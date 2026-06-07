# A small Elixir sample for exercising elixir-mode (tree-sitter).
defmodule Greeter do
  @greeting "hello"

  def new(name) do
    %{name: name, count: 0}
  end

  def greet(%{name: name} = state, loud \\ false) do
    msg = "#{@greeting}, #{name}!"
    msg = if loud, do: String.upcase(msg), else: msg
    IO.puts(msg)
    {:ok, %{state | count: state.count + 1}}
  end
end

state = Greeter.new(:world)
Enum.each(1..3, fn _ -> Greeter.greet(state, true) end)
