defmodule Fullstack.Servers.Generators.Transactions do
  use GenServer

  alias Fullstack.Financial

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_work()

    {:ok, state}
  end

  @impl true
  def handle_info(:work, state) do
    Financial.trx_gen()

    schedule_work()

    {:noreply, state}
  end

  defp schedule_work do
    x = :rand.uniform(2)
    Process.send_after(self(), :work, x * 10 * 1000)
  end
end
