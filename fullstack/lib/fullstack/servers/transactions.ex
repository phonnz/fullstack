defmodule Fullstack.Servers.Generators.Transactions do
  use GenServer

  alias Fullstack.Financial
  @generate_every_default Enum.random(1..5) * 1_000

  def start_link(_args) do
    time_to_generate = Keyword.get(get_env(), :time_to_generate, @generate_every_default)
    GenServer.start_link(__MODULE__, %{generate_after: time_to_generate}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_work(state.generate_after)

    {:ok, state}
  end

  @impl true
  def handle_info(:work, state) do
    Financial.trx_gen()

    schedule_work(state.generate_after)

    {:noreply, state}
  end

  defp schedule_work(generate_after) do
    Process.send_after(self(), :work, generate_after)
  end

  defp get_env(),
    do: Application.get_env(:fullstack, :transactions)
end
