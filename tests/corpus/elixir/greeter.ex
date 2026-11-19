defmodule App.Ledger do
  # ^^^^^ keyword
  #       ^^^^^^^^^^ special
  @moduledoc """
  Posts entries.
  """

  use GenServer
  # ^ keyword
  require Logger

  # the public face
  # ^^^^^^^^^^^^^^^ comment
  def post(account, amount) when is_integer(amount) do
    # ^^^^ definition            ^^^^^^^^^^ function
    with {:ok, acct} <- fetch(account) do
      #   ^^^ constant
      GenServer.call(__MODULE__, {:post, acct, amount})
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  #     ^^^^ keyword
  def handle_call({:post, acct, amount}, _from, state) do
    case Map.fetch(state, acct.id) do
      #  ^^^ special
      {:ok, balance} ->
        {:reply, {:ok, balance + amount}, state}

      :error ->
        {:reply, {:error, :no_account}, state}
    end
  end

  defp validate(acct, amount) do
    acct.limits
    |> Enum.filter(fn l -> l.active end)
    #  ^^^^ special
    #              ^^ keyword
    |> Enum.all?(fn l -> amount <= l.max end)
  end
end
