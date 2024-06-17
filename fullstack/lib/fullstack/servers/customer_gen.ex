defmodule Fullstack.Servers.Generators.Customers do
  use GenServer

  alias Fullstack.Customers

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
    Customers.gen()

    schedule_work()

    {:noreply, state}
  end

  defp schedule_work do
    x = :rand.uniform(4)
    Process.send_after(self(), :work, x * 10 * 1000)
  end
end
