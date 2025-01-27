defmodule Firmware.Counter do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, 0, name: __MODULE__)
  end

  def get() do
    GenServer.call(__MODULE__, :get)
  end

  @impl true
  def init(counter) do
    {:ok, counter, {:continue, :work}}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_continue(:work, state) do
    schedule_work()
    {:noreply, state}
  end

  @impl true
  def handle_info(:work, state) do
    schedule_work()

    {:noreply, state + 1}
  end

  defp schedule_work do
    IO.puts("Counter scheduling work")
    Process.send_after(self(), :work, 5_000)
  end
end
