# bedit's agent on the BEAM.
#
# One long-lived Elixir process that bedit owns, started by `src/elixir-sandbox.blsp`
# and spoken to over stdin/stdout, one request per line. It is the editor's foothold
# inside a running VM: it evaluates, it observes, and — because it is an ordinary node
# — it can be pointed at another one.
#
# Three properties make it useful rather than a novelty:
#
#   * It is a SESSION. `binding` and `__ENV__` are threaded from request to request, so
#     `x = 41` and then `x + 1` works, and a module defined in one request is callable
#     in the next. That is what lets a playground buffer behave like a file rather than
#     like a series of unrelated one-liners.
#
#   * It runs INSIDE YOUR PROJECT. Started with `mix run`, the application is compiled
#     and started before the first request is read, so `Accounts.list_users()` and
#     `Repo.aggregate(Post, :count)` mean what they mean in `iex -S mix`.
#
#   * It TRACES. Every evaluation is run with `:erlang.trace/3` on, scoped to the
#     modules this session itself defined, so the reply carries the call/return cascade
#     that produced the answer. Scoping is the whole trick: tracing your application's
#     modules would drown the answer, and tracing nothing would make the pane empty.
#
# ## The wire
#
# Requests in, one per line:
#
#     <VERB> <id> <timeout-ms> <base64 payload>
#
# base64 because an Elixir program is full of newlines and quotes and this way the
# framing cannot be confused by its own payload. Replies out, one JSON object per line,
# written by the encoder at the bottom of this file — hand-rolled, because the agent
# must boot in ANY project and cannot assume a JSON library is on the path, and because
# what it encodes is only ever the handful of shapes below.
#
# Nothing here is bedit-specific beyond the field names; the protocol's own contract
# (`{"ready": true}` first, then one reply per request carrying its `id`) is
# `std/editor/evalsession`'s.

defmodule Bedit.Agent do
  @moduledoc false

  # How many trace entries one evaluation collects before the tracer stands down. Past
  # this a cascade has made its point, and the alternative is a tight recursion posting
  # two messages per call for as long as it runs. Mirrors Brood's own
  # `eval-server/*spy-entry-cap*` so the two playgrounds truncate alike.
  @spy_cap 200

  # Caps on what one reply may carry. A reply is one line that the editor reads whole,
  # so a program printing a megabyte must not put a megabyte on it.
  #
  # They also keep the whole line comfortably inside the 64 KiB read buffer the `proc`
  # mechanism delivers stdout in. A multi-byte character split across that boundary is
  # decoded lossily, which would make the line fail to parse — and a reply that fails to
  # parse is dropped, which leaves its form waiting on an answer that has already been
  # given until the watchdog kills and respawns the whole VM over it. The worst case here
  # is 200 spy entries at ~160 characters plus the output and value caps: ~44 KB.
  @value_cap 4_000
  @output_cap 8_000
  @spy_text_cap 120

  # How many of a freshly defined module's functions the type hint names before it says
  # "+N more" — enough to see the shape of what you just defined, short enough for one row.
  @functions_listed 6

  # A type hint is ghost text on one line beside a form; a `@spec` with a large union in
  # it is not. Clipped to something that still says what the function takes and returns.
  @spec_cap 150

  # `env` is the SCRIPT's `__ENV__`, captured at the bottom of this file rather than
  # anywhere inside this module — and that is load-bearing. An `__ENV__` taken inside
  # `defmodule Bedit.Agent` carries `Bedit.Agent` as its module, so a `defmodule Fac`
  # evaluated against it defines `Bedit.Agent.Fac`, and the very next request's
  # `Fac.f(4)` is an undefined function. The session must see what a script sees.
  def main(env) do
    # Everything the session carries between requests. `binding` and `env` are the
    # session; `modules` is what it has defined, which is what the tracer is scoped to.
    {:ok, capture} = StringIO.open("")
    install_dbg()

    state = %{
      binding: [],
      env: env,
      modules: MapSet.new(),
      # the node this session's requests are routed to, or nil for "this one" — see the
      # ATTACH handler
      attached: nil,
      test_task: nil,
      # one capture device for the whole session — see `run/3` for why it is not per
      # evaluation
      capture: capture
    }

    # The banner says whether the project's application is actually RUNNING, which the
    # editor cannot work out for itself: it asked `mix run` to start it, but an
    # application is entitled to refuse — a pending migration, a database that is down, a
    # startup task that raises — and the retry that follows deliberately uses `--no-start`.
    # A playground where `Repo` works and one where it does not are different tools, and a
    # reader should be told which one they have.
    # The versions ride the banner because they are the versions that ACTUALLY ran. The
    # editor cannot ask for them cheaply — `elixir --version` is a whole VM boot — and it
    # must not guess: `mix` may resolve to a different install than `elixir`, an asdf/mise
    # shim may pick a per-project version, and the one that matters is the one that just
    # started. Below bedit's floor, a feature says so instead of failing three times and
    # calling the session dead.
    emit(%{
      ready: true,
      app: project_app(),
      elixir: System.version(),
      otp: System.otp_release()
    })

    loop(state)
  end

  # The project's application name when it is started, else nil. Nil for a projectless
  # session too, which is honest: there is no application there either.
  #
  # `Mix.Project.config/0` is a GenServer call into `Mix.ProjectStack`, and that process
  # only exists when Mix's own application is running — under `mix run`, not under a bare
  # `elixir`. Called there it **exits**; it does not raise, so `rescue` alone does not save
  # you, and the agent died at boot in every projectless session. Hence both the `whereis`
  # guard and the `catch`.
  defp project_app do
    with true <- Code.ensure_loaded?(Mix.Project),
         pid when is_pid(pid) <- Process.whereis(Mix.ProjectStack),
         config when is_list(config) <- Mix.Project.config(),
         app when is_atom(app) and not is_nil(app) <- config[:app],
         true <- List.keymember?(Application.started_applications(), app, 0) do
      Atom.to_string(app)
    else
      _ -> nil
    end
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  # ---- dbg, routed to its own stream ------------------------------------------------
  #
  # `dbg/2` is the best thing in Elixir's debugging toolbox and it writes to stdout, so it
  # arrived mixed into whatever the form had printed — a pipeline's step-by-step trace
  # sitting inside `printed:` on one line of ghost text, next to an `IO.puts` that had
  # nothing to do with it. It belongs where the spy cascade goes: the pane, which has room
  # for it and is already the place you look to see how an answer happened.
  #
  # `dbg` cannot be pointed at a device (the `:device` option is not one), so it is
  # intercepted at the hook Elixir provides for exactly this and IEx already uses: a
  # `:dbg_callback` runs at macro-expansion and returns the code to run in its place. Ours
  # is `Macro.dbg`'s own expansion — so the formatting stays Elixir's, step decomposition
  # and all — wrapped in a group-leader swap so its printing lands on a stream of its own.
  @dbg_device :bedit_dbg_device

  defp install_dbg do
    {:ok, device} = StringIO.open("")
    Process.register(device, @dbg_device)
    Application.put_env(:elixir, :dbg_callback, {__MODULE__, :dbg_callback, []})
  rescue
    # an Elixir without the hook still gets dbg — just in `printed:`, where it used to be
    _ -> :ok
  end

  @doc false
  def dbg_callback(code, options, env) do
    inner = Macro.dbg(code, options, env)

    quote do
      unquote(__MODULE__).capturing_dbg(fn -> unquote(inner) end)
    end
  end

  @doc false
  def capturing_dbg(fun) do
    case Process.whereis(@dbg_device) do
      nil ->
        fun.()

      device ->
        previous = Process.group_leader()
        Process.group_leader(self(), device)

        try do
          fun.()
        after
          Process.group_leader(self(), previous)
        end
    end
  end

  # What `dbg` printed since the last drain, minus the `[file:line: context]` header line
  # `Macro.dbg` opens each block with — which names the agent's own temp script and a line
  # number in it, and so is worse than nothing to a reader.
  defp drain_dbg do
    case Process.whereis(@dbg_device) do
      nil ->
        ""

      device ->
        device
        |> StringIO.flush()
        |> String.split("\n")
        |> Enum.reject(&Regex.match?(~r/^\[.*:\d+: .*\]$/, &1))
        |> Enum.join("\n")
        |> String.trim()
    end
  end

  defp loop(state) do
    case IO.read(:stdio, :line) do
      :eof ->
        :ok

      {:error, _} ->
        :ok

      line ->
        state =
          case parse(line) do
            {:ok, verb, id, timeout, payload} -> handle(verb, id, timeout, payload, state)
            :error -> state
          end

        loop(state)
    end
  end

  # ---- the wire ------------------------------------------------------------------

  # A verb may carry NO payload — `DETACH`, `TESTSTOP` — and then the line's fourth field is
  # an empty string, which `trim_trailing` takes away along with the newline. Read as three
  # fields the request was silently dropped, and the editor sat waiting out the full
  # timeout for an answer nobody was ever going to give: eleven and a half seconds and a
  # respawn to detach from a node.
  defp parse(line) do
    case String.split(String.trim_trailing(line), " ", parts: 4) do
      [verb, id, timeout, payload] -> parsed(verb, id, timeout, payload)
      [verb, id, timeout] -> parsed(verb, id, timeout, "")
      _ -> :error
    end
  end

  defp parsed(verb, id, timeout, payload) do
    with {id, ""} <- Integer.parse(id),
         {timeout, ""} <- Integer.parse(timeout),
         {:ok, decoded} <- Base.decode64(payload) do
      {:ok, verb, id, timeout, decoded}
    else
      _ -> :error
    end
  end

  # ---- the requests ---------------------------------------------------------------

  defp handle("EVAL", id, timeout, source, state) do
    {reply, state} = eval(source, timeout, state)
    emit(Map.put(reply, :id, id))
    state
  end

  # What is actually running in this VM. The editor's own `M-x list-processes` shows the
  # same columns for Brood's processes; this answers them for the BEAM, so one buffer and
  # one set of keys serve both.
  #
  # Reductions are the useful number and the reason this is worth a request rather than a
  # guess: they are the scheduler's own measure of work done, so the DIFFERENCE between two
  # snapshots is who is busy right now — which is the question you open a process list to
  # ask, and the one a static listing cannot answer.
  defp handle("OBSERVE", id, _timeout, what, state) do
    reply =
      case what do
        "processes" -> observe_processes(Map.get(state, :attached))
        other -> %{ok: false, error: "unknown observation: " <> other}
      end

    emit(Map.put(reply, :id, id))
    state
  end

  # Run this project's tests IN THIS NODE. The payload is one spec per line, each a test
  # file or a `file:line`, and the verdicts stream back as they land rather than arriving
  # as one reply at the end — which is the whole point of a warm node: you watch the suite
  # go by instead of waiting for a VM boot and a compile before the first row appears.
  #
  # Run in a Task so this loop keeps reading stdin: a suite is the one request that can
  # legitimately take minutes, and a session that could not be asked anything while one ran
  # could not be asked to STOP one either.
  defp handle("TEST", id, _timeout, spec, state) do
    task =
      Task.async(fn ->
        Process.flag(:trap_exit, false)
        run_tests(id, spec)
      end)

    Map.put(state, :test_task, task)
  end

  defp handle("TESTSTOP", id, _timeout, _payload, state) do
    case Map.get(state, :test_task) do
      %Task{} = task ->
        Task.shutdown(task, :brutal_kill)
        emit(%{id: id, ok: true, stopped: true})

      _ ->
        emit(%{id: id, ok: true, stopped: false})
    end

    Map.put(state, :test_task, nil)
  end

  # ---- attaching to somebody else's node ---------------------------------------------
  #
  # The agent is an ordinary BEAM node, so the thing that makes bedit an editor for a
  # RUNNING system rather than for a project is a `Node.connect/1`. Attached, `EVAL` and
  # `OBSERVE` are routed to the target with `:erpc`, and everything above them — the
  # playground, the process list, the spy pane — is pointed at your dev server or, over an
  # SSH tunnel, at a release.
  #
  # The payload is two lines: the cookie, then the node. Both are needed and neither is
  # guessed: a cookie read from somewhere the user did not name is a credential used
  # without being asked for.
  defp handle("ATTACH", id, _timeout, payload, state) do
    reply =
      case String.split(payload, "\n", parts: 2) do
        [cookie, node] -> attach(String.trim(cookie), String.trim(node))
        _ -> %{ok: false, error: "attach wants a cookie and a node"}
      end

    emit(Map.put(reply, :id, id))
    Map.put(state, :attached, reply[:node])
  end

  defp handle("DETACH", id, _timeout, _payload, state) do
    emit(%{id: id, ok: true, node: nil})
    Map.put(state, :attached, nil)
  end

  defp handle(_unknown, id, _timeout, _payload, state) do
    emit(%{id: id, ok: false, error: "unknown request"})
    state
  end

  defp attach(cookie, name) do
    node = String.to_atom(name)

    with :ok <- start_distribution(name),
         :ok <- set_cookie(node, cookie),
         true <- Node.connect(node) do
      %{ok: true, node: name, otp: :erpc.call(node, :erlang, :system_info, [:otp_release], 5_000)}
    else
      false -> %{ok: false, error: "could not connect to " <> name}
      :ignored -> %{ok: false, error: "could not connect to " <> name <> " (distribution refused)"}
      {:error, why} -> %{ok: false, error: why}
    end
  rescue
    error -> %{ok: false, error: Exception.message(error)}
  catch
    _, reason -> %{ok: false, error: "attach failed: " <> Exception.format_exit(reason)}
  end

  # Our own node has to be named before it can talk to anybody, and it is not named at
  # boot: an unnamed VM costs nothing and cannot be reached, which is the right default for
  # a child that usually only talks to its editor. The name type has to MATCH the target's
  # — a short-named node cannot see a long-named one — so it is taken from the name asked
  # for rather than chosen here.
  defp start_distribution(name) do
    if Node.alive?() do
      :ok
    else
      type = if String.contains?(name, "."), do: :longnames, else: :shortnames
      self_name = String.to_atom("bedit_#{System.system_time(:second)}")

      case Node.start(self_name, type) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
        {:error, reason} -> {:error, "could not start distribution: " <> inspect(reason)}
      end
    end
  end

  defp set_cookie(node, ""), do: {:error, "no cookie for #{node}"}

  defp set_cookie(node, cookie) do
    Node.set_cookie(node, String.to_atom(cookie))
    Node.set_cookie(Node.self(), String.to_atom(cookie))
    :ok
  end

  # The helper the process snapshot runs INSIDE the target. A closure cannot be sent —
  # its module would have to exist over there — so the module is compiled here and loaded
  # there, which is what `:observer` does for the same reason. It is fifteen lines and it
  # defines nothing the target could already be using.
  @remote_module Bedit.Remote

  defp remote_source do
    quote do
      defmodule Bedit.Remote do
        @moduledoc false
        def processes(fields) do
          Process.list()
          |> Enum.map(fn pid ->
            case Process.info(pid, fields) do
              nil ->
                nil

              info ->
                started =
                  case Process.info(pid, :dictionary) do
                    {:dictionary, dict} when is_list(dict) -> Keyword.get(dict, :"$initial_call")
                    _ -> nil
                  end

                {inspect(pid), Keyword.put(info, :started_as, started)}
            end
          end)
          |> Enum.reject(&is_nil/1)
        end
      end
    end
  end

  defp ensure_remote(node) do
    [{module, binary} | _] = Code.compile_quoted(remote_source())
    {:module, ^module} = :erpc.call(node, :code, :load_binary, [module, ~c"bedit_remote.ex", binary], 10_000)
    :ok
  rescue
    error -> {:error, Exception.message(error)}
  catch
    _, reason -> {:error, "could not load the helper on the node: " <> Exception.format_exit(reason)}
  end

  # ---- running the suite --------------------------------------------------------------

  defp run_tests(id, spec) do
    specs = spec |> String.split("\n", trim: true) |> Enum.reject(&(&1 == ""))
    files = specs |> Enum.map(&spec_file/1) |> Enum.uniq()
    lines = Enum.flat_map(specs, &spec_line/1)

    # Pick up `lib/` BEFORE loading the test files, so a test compiled now sees the
    # application as it is on disk rather than as it was when this node booted.
    recompiled = recompile()

    case prepare(files) do
      {:error, why} ->
        emit(%{id: id, ok: false, error: why})

      {:ok, modules} ->
        Application.put_env(:ex_unit, :bedit_run_id, id)

        # Only our formatter: ExUnit's own writes a progress report for a terminal, and
        # nothing here is one. `exclude: [:test] / include: [line: N]` is exactly how
        # `mix test file:line` narrows a run to the test under your cursor.
        ExUnit.configure(
          formatters: [Bedit.TestFormatter],
          autorun: false,
          colors: [enabled: false],
          exclude: if(lines == [], do: [], else: [:test]),
          include: Enum.map(lines, &{:line, &1})
        )

        started = System.monotonic_time(:millisecond)

        # The modules are named EXPLICITLY rather than left to ExUnit's own registry, and
        # that is what makes a second run work at all. `ExUnit.Server` collects the modules
        # a `use ExUnit.Case` registers, but only until the first run takes them; a warm
        # node's second `C-c t` re-requires the same file, redefines the same module, and
        # finds an empty registry — a green "0 tests" for a suite that has three.
        result =
          try do
            # `ExUnit.run/1` is what makes a second run possible, and it is not in every
            # Elixir this agent may land in. Where it is missing the registry path still
            # works for the FIRST run of a file, which is the whole of what an older
            # Elixir gets — said out loud rather than silently answering "0 tests".
            if function_exported?(ExUnit, :run, 1),
              do: ExUnit.run(modules),
              else: ExUnit.run()
          rescue
            error -> %{failed: error}
          end

        case result do
          %{failed: error} ->
            emit(%{id: id, ok: false, error: Exception.message(error)})

          summary ->
            emit(%{
              id: id,
              ok: true,
              summary: %{
                total: Map.get(summary, :total, 0),
                failed: Map.get(summary, :failures, 0),
                skipped: Map.get(summary, :skipped, 0) + Map.get(summary, :excluded, 0),
                ms: System.monotonic_time(:millisecond) - started,
                # whether this run had to pick the project up first — what lets the editor
                # say "warm · recompiled" instead of leaving the reader to wonder whether
                # the answer is about the code in front of them
                reloaded: recompiled
              }
            })
        end
    end
  end

  # Recompile the project IN THIS NODE, answering 1 when something was picked up and 0
  # when the node was already current. What `recompile` does in `iex -S mix`, and the
  # reason a warm test node is not a trap: without it the node tests the code it booted
  # with, so a function you have already fixed keeps failing and one you have already
  # broken keeps passing.
  #
  # The re-enabling is the whole trick and it is why `Mix.Task.rerun("compile", [])` is
  # not enough on its own: `rerun` re-enables the task you name, but the work is done by
  # `compile.all` and the per-compiler tasks under it, which stay marked as run — so it
  # answers `:noop` and nothing happens. Measured before the re-enables were added:
  # `:noop` in 11ms and the old code still loaded. With them: `:ok` in 28ms and the new
  # code live, 14ms when there was nothing to do.
  defp recompile do
    config = Mix.Project.config()
    Mix.Task.reenable("compile")
    Mix.Task.reenable("compile.all")
    Enum.each(config[:compilers] || Mix.compilers(), &Mix.Task.reenable("compile.#{&1}"))

    case Mix.Task.run("compile", ["--no-deps-check"]) do
      {:noop, _} -> 0
      _ -> 1
    end
  rescue
    # No Mix (a projectless session), or a compile error in your own code: the second is
    # the interesting one, and it must not cost you the run. ExUnit is about to load the
    # test files, and whatever is broken will be reported there — as a test failure with a
    # location, which is far more use than a reply saying the agent gave up.
    _ -> 0
  catch
    _, _ -> 0
  end

  defp spec_file(spec), do: spec |> String.split(":") |> hd()

  defp spec_line(spec) do
    case String.split(spec, ":") do
      [_file, line] ->
        case Integer.parse(line) do
          {n, ""} -> [n]
          _ -> []
        end

      _ ->
        []
    end
  end

  # Load the helper once and the test files EVERY time — the files are the thing you just
  # edited, and a warm node that kept the first version of them would answer questions
  # about code that is no longer there. `unrequire` first, because `require_file` on a file
  # already required is a no-op; recompiling redefines the test module, which is a warning
  # we turn off rather than a problem.
  defp prepare(specs) do
    missing = Enum.reject(specs, &File.exists?/1)

    cond do
      missing != [] ->
        {:error, "no such test file: " <> Enum.join(missing, ", ")}

      true ->
        files = Enum.flat_map(specs, &expand/1)

        if files == [] do
          {:error, "no test files under: " <> Enum.join(specs, ", ")}
        else
          Code.put_compiler_option(:ignore_module_conflict, true)
          ensure_exunit()
          Code.unrequire_files(files)
          Enum.each(files, &Code.require_file/1)
          {:ok, test_modules(files)}
        end
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  # `test` — the whole suite — is a directory, and `Code.require_file` on one is `:eisdir`.
  # ExUnit's own default pattern, so "run everything" means the same set of files here as
  # it does to `mix test`.
  defp expand(spec) do
    if File.dir?(spec), do: Path.wildcard(Path.join(spec, "**/*_test.exs")), else: [spec]
  end

  # Every loaded `ExUnit.Case` module DECLARED IN one of these files — asked of the modules
  # themselves rather than remembered from the require, because a re-require redefines a
  # module that is already loaded and so shows up in no before/after diff.
  defp test_modules(files) do
    wanted = MapSet.new(files, &Path.expand/1)

    :code.all_loaded()
    |> Enum.map(fn {module, _} -> module end)
    |> Enum.filter(&function_exported?(&1, :__ex_unit__, 0))
    |> Enum.filter(fn module ->
      case module.__ex_unit__() do
        %{file: file} -> MapSet.member?(wanted, Path.expand(to_string(file)))
        _ -> false
      end
    end)
  rescue
    _ -> []
  end

  # `test/test_helper.exs` is where a project starts ExUnit and sets up whatever its tests
  # need (the Ecto sandbox, above all), so it is required first and only once — running it
  # twice would start what it starts twice. A project without one still gets an ExUnit.
  defp ensure_exunit do
    helper = Path.join("test", "test_helper.exs")

    if File.exists?(helper) do
      Code.require_file(helper)
    else
      ExUnit.start(autorun: false)
    end

    # …and whatever the helper asked for, this run is not autorun: the suite runs when the
    # editor says so, not when the VM exits.
    ExUnit.configure(autorun: false)
  end

  # ---- observing ---------------------------------------------------------------------

  @process_fields [
    :registered_name,
    :status,
    :message_queue_len,
    :memory,
    :reductions,
    :monitored_by,
    :current_function,
    :initial_call
  ]

  # Locally it is `Process.list/0`; attached it is one `:erpc` into the target, through the
  # helper module pushed there — one round trip for the whole snapshot rather than one per
  # process, which over a tunnel is the difference between a list and a stall.
  defp observe_processes(nil), do: %{ok: true, processes: processes(), node: nil}

  defp observe_processes(name) do
    node = String.to_atom(name)

    case ensure_remote(node) do
      {:error, why} ->
        %{ok: false, error: why}

      :ok ->
        rows =
          node
          |> :erpc.call(@remote_module, :processes, [@process_fields], 15_000)
          |> Enum.map(fn {pid, info} -> row_of(pid, info) end)

        %{ok: true, processes: rows, node: name}
    end
  rescue
    error -> %{ok: false, error: Exception.message(error)}
  catch
    _, reason -> %{ok: false, error: "the node did not answer: " <> Exception.format_exit(reason)}
  end

  defp processes do
    Process.list()
    |> Enum.map(&process_row/1)
    |> Enum.reject(&is_nil/1)
  end

  defp process_row(pid) do
    # A process can die between `Process.list/0` and this call, and `Process.info/2`
    # answers nil rather than raising when it does — which is the whole reason a snapshot
    # is taken this way instead of asserted.
    case Process.info(pid, @process_fields) do
      nil -> nil
      info -> row_of(inspect(pid), Keyword.put(info, :started_as, started_as(pid)))
    end
  end

  # OTP's true initial call, out of the process dictionary. Read here — and, for an
  # attached node, inside the helper over there — rather than from the row, so the
  # dictionary itself never crosses the wire: some processes keep a lot in it, and this is
  # one atom-and-arity of it.
  defp started_as(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dict} when is_list(dict) -> Keyword.get(dict, :"$initial_call")
      _ -> nil
    end
  end

  # One row from an info keyword list. Shared by the local snapshot and the attached one,
  # so a remote node's process list is the same list with the same columns — which is the
  # whole promise of attaching rather than a second, lesser view.
  defp row_of(pid, info) do
    %{
      pid: pid,
      name: process_name(info),
      status: to_string(info[:status]),
      mailbox: info[:message_queue_len] || 0,
      memory: info[:memory] || 0,
      reductions: info[:reductions] || 0,
      monitored_by: length(info[:monitored_by] || []),
      current: mfa(info[:current_function] || info[:initial_call])
    }
  end

  # A registered name when it has one, else what the process was STARTED as — which for a
  # supervised process is its own module, and is far more use than a bare pid.
  #
  # `:initial_call` is NOT that answer for anything OTP started: every `gen_server`,
  # `gen_statem` and `Task` is spawned by `:proc_lib`, so a list built on it reads
  # `:proc_lib` for most of a real application — the rows you most want to identify are
  # exactly the ones it cannot. OTP stores the true one in the process dictionary under
  # `$initial_call` for this reason, and that is what `:observer` reads.
  defp process_name(info) do
    case info[:registered_name] do
      name when is_atom(name) and not is_nil(name) -> inspect(name)
      _ -> inspect_module(info[:started_as] || info[:initial_call])
    end
  end

  defp inspect_module({module, _f, _a}), do: inspect(module)
  defp inspect_module(_), do: "-"

  defp mfa({m, f, a}), do: "#{inspect(m)}.#{f}/#{a}"
  defp mfa(_), do: "-"

  # ---- evaluation ------------------------------------------------------------------

  defp eval(source, timeout, state) do
    timeout = if timeout > 0, do: timeout, else: 5_000
    before_pids = MapSet.new(Process.list())

    parent = self()

    task =
      spawn_monitor(fn ->
        # The leak count is taken INSIDE the evaluation, at its end, where the three
        # processes the agent itself created for it — this one, its collector, its output
        # capture — are known and can be excluded by name. Counted out here instead, they
        # are merely "new since the snapshot", and whether they have finished exiting by
        # the time the reply is folded is a race: the same expression would report
        # "1 process still running" or nothing depending on scheduling.
        send(parent, {:result, self(), run(source, state, before_pids)})
      end)

    {pid, ref} = task

    receive do
      {:result, ^pid, result} ->
        Process.demonitor(ref, [:flush])
        settle(result, state)

      {:DOWN, ^ref, :process, ^pid, reason} ->
        {%{ok: false, error: "the evaluation died: " <> Exception.format_exit(reason)}, state}
    after
      timeout ->
        Process.exit(pid, :kill)
        Process.demonitor(ref, [:flush])
        {%{ok: false, timeout: true}, state}
    end
  end

  # Runs in the child process, so a timeout can kill it without taking the agent with
  # it — and so the captured group leader and the tracer are scoped to this evaluation
  # and cannot leak into the next one.
  defp run(source, state, before_pids) do
    # The session's ONE capture device, not a fresh one per evaluation.
    #
    # A process the evaluated code spawns inherits its spawner's group leader, and keeps
    # it for life. With a per-evaluation `StringIO` that gets closed at the end, that
    # process's next `IO.puts` raised `** (ErlangError) :terminated — the device has
    # terminated` and killed it: a plain `spawn(fn -> :timer.sleep(300); IO.puts("hi") end)`
    # in a playground buffer died three hundred milliseconds later, for a reason having
    # nothing to do with the code. Changing what the program DOES is the one thing a
    # capture must not do.
    #
    # A long-lived device outlives every such process, so they all keep working. The cost
    # is that a late print lands in whichever evaluation happens to be draining next
    # rather than in its own — output attributed a form too late, which is a cosmetic
    # wrong answer where the other was a behavioural one.
    capture = state.capture
    original_leader = Process.group_leader()
    Process.group_leader(self(), capture)

    collector = spawn_collector()
    trace_on(collector, state.modules)

    # The three this evaluation is owed, and must not be charged for.
    ours = MapSet.new([self(), collector, capture])
    modules_before = loaded_modules()

    started = System.monotonic_time(:millisecond)

    outcome =
      try do
        {value, binding} = eval_string(source, state)
        {:ok, value, binding}
      rescue
        error -> {:raised, Exception.format_banner(:error, error, __STACKTRACE__)}
      catch
        kind, thrown -> {:raised, Exception.format_banner(kind, thrown, __STACKTRACE__)}
      end

    elapsed = System.monotonic_time(:millisecond) - started

    trace_off()
    spy = collect(collector)
    left_running = leaked(before_pids, ours)

    Process.group_leader(self(), original_leader)
    # Drain rather than close — the device is the session's and outlives this evaluation
    # (see above). `StringIO.flush/1` takes what has accumulated and leaves it empty.
    printed = StringIO.flush(capture)

    %{
      outcome: outcome,
      printed: printed,
      ms: elapsed,
      spy: spy,
      procs: left_running,
      dbg: cap(drain_dbg(), @output_cap),
      defined: defined_modules(modules_before)
    }
  end

  # Unattached this is a plain local evaluation. ATTACHED it runs on the target, and the
  # binding comes back so the session keeps working the way it does locally: `x = 41` then
  # `x + 1` means the same thing whichever node it ran on.
  #
  # `Code.eval_string/3` with a keyword LOCATION rather than this agent's `__ENV__`: an env
  # is a struct that names modules, aliases and imports from here, none of which the target
  # has to have, and sending one is how a remote eval fails with an error about the editor
  # rather than about your code.
  defp eval_string(source, %{attached: node} = state) when is_binary(node) do
    :erpc.call(String.to_atom(node), Code, :eval_string, [source, state.binding, [file: "bedit"]], 30_000)
  end

  defp eval_string(source, state), do: Code.eval_string(source, state.binding, state.env)

  # Back in the agent process: turn what the child produced into a reply, and fold the
  # session forward. Only a successful evaluation advances the session — a raise leaves
  # the binding where it was, which is what makes a typo in the middle of a buffer cost
  # nothing.
  defp settle(%{outcome: {:ok, value, binding}} = result, state) do
    modules = MapSet.union(state.modules, result.defined)

    reply = %{
      ok: true,
      value: render(value),
      type: type_of(value),
      output: cap(result.printed, @output_cap),
      ms: result.ms,
      spy: result.spy,
      procs: %{alive: result.procs},
      dbg: result.dbg
    }

    {reply, %{state | binding: binding, modules: modules}}
  end

  defp settle(%{outcome: {:raised, banner}} = result, state) do
    {%{ok: false, error: banner, output: cap(result.printed, @output_cap), ms: result.ms,
       spy: result.spy, dbg: result.dbg}, state}
  end

  # Which modules this evaluation defined — by DIFFING what is loaded, not by reading the
  # value it returned.
  #
  # `defmodule` evaluates to `{:module, Name, binary, _}`, and reading that was enough
  # until a form held two of them: `Code.eval_string` answers with the LAST one, so
  #
  #     defmodule Ay do def go, do: Bee.go() end
  #     defmodule Bee do def go, do: :from_bee end
  #
  # tracked `Bee` and not `Ay` — and the cascade for `Ay.go()` showed the inner call
  # while silently omitting the outer one, which is worse than showing nothing. The same
  # hole swallowed a module defined inside an `if` or a `for`. What is loaded is the fact;
  # the return value was a proxy for it.
  defp defined_modules(before_modules) do
    loaded_modules()
    |> MapSet.difference(before_modules)
    |> Enum.filter(&defined_here?/1)
    |> MapSet.new()
  end

  # Defined by evaluated source, as opposed to merely LOADED while it ran.
  #
  # The difference matters because the diff alone is far too generous: evaluating almost
  # anything lazily loads modules from disk — `survivor = :yes` pulls in
  # `List.Chars.to_charlist` — and every one of them then became a tracing target, so the
  # cascade for a one-line form opened with protocol implementations instead of the call
  # you asked about. That is the "tracing your application would drown the answer" failure,
  # arrived at from the other direction.
  #
  # A module compiled in memory has no beam file: `:code.which/1` answers `[]` where a
  # module loaded from disk — the standard library's, and your project's under `mix run` —
  # answers its path.
  defp defined_here?(module), do: :code.which(module) == []

  defp loaded_modules do
    :code.all_loaded() |> Enum.map(&elem(&1, 0)) |> MapSet.new()
  end

  # Processes this evaluation started that are still running. Concurrency has no return
  # value to look at, so this is the only thing that reports it — and it is silent when
  # nothing was left behind, so it only speaks up where processes are the point.
  #
  # `ours` is the evaluation's own scaffolding: the evaluating process, its trace collector
  # and its output capture. They are new since the snapshot and they are not yours.
  defp leaked(before_pids, ours) do
    Process.list()
    |> Enum.count(fn pid ->
      not MapSet.member?(before_pids, pid) and not MapSet.member?(ours, pid)
    end)
  end

  # ---- tracing ----------------------------------------------------------------------
  # The cascade the editor paints beside the code: which calls happened, nested, and
  # what each one returned. Scoped to the modules this SESSION defined — never to the
  # project's — because a single `Repo.all` inside a Phoenix app traces thousands of
  # calls and the one you asked about is not findable among them.

  # LINKED to the evaluation, and that is the whole point. A timeout kills the evaluating
  # process, which never gets to send `{:dump, …}` — so an unlinked collector sits in its
  # receive forever, and the node leaks one process per timed-out evaluation. Measured: a
  # session's process count went 58 → 61 across three timeouts. Linked, it dies with the
  # evaluation it was collecting for.
  defp spawn_collector do
    spawn_link(fn -> collecting([], 0) end)
  end

  defp collecting(acc, count) do
    receive do
      {:trace, _pid, :call, {module, function, args}} when count < @spy_cap ->
        collecting([{:call, module, function, args} | acc], count + 1)

      {:trace, _pid, :return_from, {module, function, arity}, value} when count < @spy_cap ->
        collecting([{:return, module, function, arity, value} | acc], count + 1)

      {:dump, to} ->
        send(to, {:spy, Enum.reverse(acc), count >= @spy_cap})

      # Past the cap the tracer is still on — turning it off from here would race the
      # evaluation — so entries are read and dropped. The cost is a message per call,
      # which is what the cap is protecting against in the first place; it is bounded
      # by the evaluation's own timeout.
      _ ->
        collecting(acc, count)
    end
  end

  defp trace_on(collector, modules) do
    :erlang.trace(self(), true, [:call, {:tracer, collector}])

    Enum.each(modules, fn module ->
      # `:local` so private functions are traced too: a helper you did not export is
      # exactly the thing a cascade exists to reveal.
      :erlang.trace_pattern({module, :_, :_}, [{:_, [], [{:return_trace}]}], [:local])
    end)
  rescue
    # Tracing is a nicety. A VM that refuses it (another tracer already attached, a
    # restricted node) should still evaluate.
    _ -> :ok
  end

  defp trace_off do
    :erlang.trace(self(), false, [:call])
  rescue
    _ -> :ok
  end

  defp collect(collector) do
    # Wait for the trace messages to actually ARRIVE before asking for them.
    #
    # `:erlang.trace/3` returning false only means no further calls will be traced; the
    # messages already emitted are in flight, sent by the VM rather than by us, so nothing
    # orders them against the `{:dump, …}` we send next. Without this the collector
    # regularly answered with the first few entries and the last returns were simply
    # missing — a cascade that stopped mid-way for no reason the reader could see, on
    # maybe one call in three.
    #
    # `trace_delivered/1` is the primitive for exactly this question: it answers once every
    # trace message emitted for this process has reached its tracer.
    ref = :erlang.trace_delivered(self())

    receive do
      {:trace_delivered, _tracee, ^ref} -> :ok
    after
      1_000 -> :ok
    end

    send(collector, {:dump, self()})

    receive do
      {:spy, entries, _capped} -> Enum.flat_map(entries, &spy_entry/1)
    after
      1_000 -> []
    end
  end

  # `__info__` is the compiler's, not yours: every call into a freshly defined module
  # begins with one, and a cascade that opens with it reads as noise.
  defp spy_entry({:call, _module, :__info__, _args}), do: []
  defp spy_entry({:return, _module, :__info__, _arity, _value}), do: []

  defp spy_entry({:call, module, function, args}) do
    [
      %{
        kind: "call",
        fn: "#{inspect(module)}.#{function}",
        args: args |> Enum.map(&inspect_bounded(&1, @spy_text_cap)) |> Enum.join(", ")
      }
    ]
  end

  defp spy_entry({:return, _module, _function, _arity, value}) do
    [%{kind: "return", value: inspect_bounded(value, @spy_text_cap)}]
  end

  # ---- describing a value ------------------------------------------------------------

  # What the editor paints after `=>`. Almost always `inspect`, with one exception: a
  # `defmodule` evaluates to `{:module, Foo, <<the whole BEAM binary>>, _}`, and a
  # thousand bytes of compiled module is not what anybody typing `defmodule` wants to
  # read back. The name is the answer; how much it defined is the type hint's job.
  defp render({:module, module, binary, _}) when is_atom(module) and is_binary(binary),
    do: inspect(module)

  defp render(value), do: inspect_bounded(value)

  defp inspect_bounded(value, limit \\ @value_cap) do
    value
    |> inspect(limit: 50, printable_limit: limit, pretty: false)
    |> cap(limit)
  end

  defp cap(string, limit) when is_binary(string) do
    if String.length(string) > limit, do: String.slice(string, 0, limit) <> "…", else: string
  end

  defp cap(other, _limit), do: to_string(other)

  # The `: Integer` hint the editor paints at the form — Elixir's answer to a type. A
  # struct names itself, because `%User{}` says far more than "a map".
  defp type_of(value) do
    cond do
      is_integer(value) -> "Integer"
      is_float(value) -> "Float"
      is_boolean(value) -> "Boolean"
      is_nil(value) -> "nil"
      # every Elixir string is a binary and not every binary is a string — `<<0, 1, 255>>`
      # calling itself a String is a small lie that sends you looking for an encoding bug
      is_binary(value) -> if String.valid?(value), do: "String", else: "Binary"
      is_atom(value) -> "Atom"
      is_list(value) -> "List"
      is_tuple(value) -> module_tuple(value)
      is_function(value) -> function_type(value)
      is_pid(value) -> "PID"
      is_reference(value) -> "Reference"
      is_map(value) -> map_type(value)
      true -> nil
    end
  end

  # A `defmodule` answers with what it DEFINED, which is the only useful thing to say
  # about `{:module, Foo, <<the whole BEAM binary>>, ...}` — and `2 functions` was a poor
  # version of it. The names and arities are what you want to see after defining a module:
  # they tell you at a glance whether the clause you just typed landed where you meant it,
  # and what you can call next.
  defp module_tuple({:module, module, binary, _}) when is_atom(module) and is_binary(binary) do
    functions = apply(module, :__info__, [:functions])
    listed = functions |> Enum.take(@functions_listed) |> Enum.map_join(", ", fn {f, a} -> "#{f}/#{a}" end)

    more =
      case length(functions) - @functions_listed do
        n when n > 0 -> ", +#{n} more"
        _ -> ""
      end

    case listed do
      "" -> inspect(module)
      _ -> "#{inspect(module)} · #{listed}#{more}"
    end
  rescue
    _ -> "Tuple"
  end

  defp module_tuple(_), do: "Tuple"

  # A function value says WHICH function it is, and its `@spec` when one can be had.
  #
  # `Function` told you nothing — every function looked alike. A captured named function
  # knows its module, name and arity, and for anything compiled to disk (your project, its
  # dependencies, the standard library) the declared spec is readable too. That is the
  # per-function type information Elixir actually has: a module this session defined in
  # memory carries no spec chunk, so there is nothing to show for one, and saying its
  # name and arity is the honest most.
  defp function_type(value) do
    info = Function.info(value)

    case {info[:type], info[:module], info[:name], info[:arity]} do
      {:external, module, name, arity} when is_atom(module) and is_atom(name) ->
        case spec_of(module, name, arity) do
          # `spec_to_quoted` already renders the name and its argument types, so the spec
          # IS the signature — prefixing it with `&Mod.fun/2 ::` would say the name twice.
          # `Enum.map(t(), (element() -> any())) :: list()` is what hover shows.
          nil -> "&#{inspect(module)}.#{name}/#{arity}"
          spec -> "#{inspect(module)}.#{spec}"
        end

      {_, _, _, arity} when is_integer(arity) ->
        "fn/#{arity}"

      _ ->
        "Function"
    end
  rescue
    _ -> "Function"
  end

  # The declared `@spec` for `module.name/arity`, rendered, or nil. Only a module with a
  # beam file has the chunk this reads, which is exactly the modules worth asking about.
  defp spec_of(module, name, arity) do
    with {:ok, specs} <- Code.Typespec.fetch_specs(module),
         {_, [form | _]} <- List.keyfind(specs, {name, arity}, 0) do
      name |> Code.Typespec.spec_to_quoted(form) |> Macro.to_string() |> cap(@spec_cap)
    else
      _ -> nil
    end
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  defp map_type(%module{}), do: inspect(module)
  defp map_type(_), do: "Map"

  # ---- the reply encoder --------------------------------------------------------------
  # Hand-rolled, and deliberately: the agent has to boot inside whatever project it is
  # pointed at, where no JSON library is guaranteed to be on the path and adding one is
  # not the editor's business. It only ever encodes the shapes above.

  # Public because the test formatter is a separate module (ExUnit starts it, so it cannot
  # be a closure) and every line it streams is a reply on this same wire.
  def emit(map) do
    IO.puts(encode(map))
  end

  defp encode(value) when is_map(value) and not is_struct(value) do
    "{" <>
      (value
       |> Enum.map(fn {k, v} -> encode(to_string(k)) <> ":" <> encode(v) end)
       |> Enum.join(",")) <> "}"
  end

  defp encode(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &encode/1) <> "]"

  defp encode(value) when is_binary(value), do: escape(value)
  defp encode(value) when is_integer(value), do: Integer.to_string(value)
  defp encode(value) when is_float(value), do: Float.to_string(value)
  defp encode(true), do: "true"
  defp encode(false), do: "false"
  defp encode(nil), do: "null"
  defp encode(value) when is_atom(value), do: escape(Atom.to_string(value))
  defp encode(value), do: escape(inspect(value))

  defp escape(string) do
    escaped =
      string
      |> String.to_charlist()
      |> Enum.map(&escape_char/1)
      |> IO.iodata_to_binary()

    "\"" <> escaped <> "\""
  end

  defp escape_char(?"), do: "\\\""
  defp escape_char(?\\), do: "\\\\"
  defp escape_char(?\n), do: "\\n"
  defp escape_char(?\r), do: "\\r"
  defp escape_char(?\t), do: "\\t"
  defp escape_char(c) when c < 0x20, do: "\\u" <> String.pad_leading(Integer.to_string(c, 16), 4, "0")
  defp escape_char(c), do: <<c::utf8>>
end

# An ExUnit formatter that writes bedit's wire instead of a terminal.
#
# ExUnit reports a suite by casting to formatter processes, so this is where a test's
# verdict is known first — and every one of them goes out the moment it lands, tagged
# `more: true`, so the *Tests* buffer fills as the suite runs. The shape is the editor's
# own `testadapter` vocabulary (group, name, passed, ms, where, failures), which is what
# lets `C-c t` mean the same thing here as it does for a Brood project or a cold
# `mix test`.
defmodule Bedit.TestFormatter do
  @moduledoc false
  use GenServer

  # Enough of a failure to know what broke without opening the file; the rest is what the
  # jump on RET is for.
  @detail_cap 400
  @details_per_failure 6

  def init(_opts) do
    {:ok, %{id: Application.get_env(:ex_unit, :bedit_run_id), root: File.cwd!()}}
  end

  def handle_cast({:test_finished, %ExUnit.Test{} = test}, state) do
    Bedit.Agent.emit(%{id: state.id, more: true, test: row(test, state.root)})
    {:noreply, state}
  end

  # Every other event — suite/module/case started and finished — is either noise or is
  # said better by the summary the TEST request answers with.
  def handle_cast(_event, state), do: {:noreply, state}

  defp row(test, root) do
    tags = test.tags || %{}

    %{
      group: group(test, tags),
      name: name(test, tags),
      passed: test.state == nil,
      skipped: skipped?(test.state),
      ms: div(test.time || 0, 1000),
      where: where(tags, root),
      failures: failures(test, tags, root)
    }
  end

  # A `describe` block is the group a reader recognises; without one it is the test module,
  # which is what ExUnit's own `--trace` output uses as the heading.
  defp group(test, tags) do
    case tags[:describe] do
      nil -> inspect(test.module)
      "" -> inspect(test.module)
      describe -> describe
    end
  end

  # ExUnit names a test `:"test <describe> <name>"`; the describe part is already the
  # group, so showing it again in every row under it is noise.
  defp name(test, tags) do
    full = test.name |> Atom.to_string() |> strip_prefix("test ")

    case tags[:describe] do
      nil -> full
      "" -> full
      describe -> strip_prefix(full, describe <> " ")
    end
  end

  defp strip_prefix(string, prefix) do
    if String.starts_with?(string, prefix),
      do: String.slice(string, String.length(prefix)..-1//1),
      else: string
  end

  defp skipped?({:skipped, _}), do: true
  defp skipped?({:excluded, _}), do: true
  defp skipped?(_), do: false

  defp where(tags, root) do
    case tags[:file] do
      nil -> ""
      file -> relative(file, root) <> ":" <> Integer.to_string(tags[:line] || 0)
    end
  end

  defp relative(path, root) do
    case Path.relative_to(path, root) do
      ^path -> Path.basename(path)
      relative -> relative
    end
  end

  defp failures(%ExUnit.Test{state: {:failed, failures}} = test, tags, root) do
    Enum.map(failures, fn {kind, reason, stack} ->
      %{loc: loc(test, tags, stack, root), details: details(kind, reason)}
    end)
  end

  defp failures(_test, _tags, _root), do: []

  # The line the failure is ON, which is rarely the line the test is declared on — the
  # first stack frame inside the test's own file, falling back to the declaration.
  defp loc(_test, tags, stack, root) do
    file = tags[:file]

    hit =
      Enum.find(stack || [], fn
        {_m, _f, _a, opts} -> opts[:file] && to_string(opts[:file]) |> String.ends_with?(Path.basename(file || ""))
        _ -> false
      end)

    case hit do
      {_m, _f, _a, opts} -> [relative(file || "", root), opts[:line] || tags[:line] || 0, 0]
      _ -> [relative(file || "", root), tags[:line] || 0, 0]
    end
  end

  # An `assert` failure knows what it compared, and saying so is most of the value of
  # reading a failure at all. Anything else is the exception's own banner.
  defp details(_kind, %ExUnit.AssertionError{} = error) do
    no_value = ExUnit.AssertionError.no_value()

    [clip(error.message || "assertion failed")]
    |> maybe(error.left, no_value, "left:  ")
    |> maybe(error.right, no_value, "right: ")
    |> Enum.take(@details_per_failure)
  end

  defp details(kind, reason) do
    kind
    |> Exception.format_banner(reason)
    |> String.split("\n")
    |> Enum.map(&clip/1)
    |> Enum.take(@details_per_failure)
  end

  defp maybe(details, value, no_value, label) do
    if value == no_value, do: details, else: details ++ [clip(label <> inspect(value))]
  end

  defp clip(string) do
    if String.length(string) > @detail_cap,
      do: String.slice(string, 0, @detail_cap - 1) <> "…",
      else: string
  end
end

Bedit.Agent.main(__ENV__)
