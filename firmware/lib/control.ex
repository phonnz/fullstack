defmodule Firmware.Control do
  require Logger
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def exec(payload) do
    GenServer.cast(__MODULE__, {:exec, payload})
  end

  @impl true
  def init(counter) do
    {:ok, counter, {:continue, :loop}}
  end

  @impl true
  def handle_cast({:exec, payload}, _from, state) do
    Logger.info("Execute #{inspect(payload)}")
    ## Show display 
    #

    {:noreply, state}
  end

  @impl true
  def handle_continue(:loop, state) do
    schedule_work()
    {:noreply, state}
  end

  @impl true
  def handle_info(:loop, state) do
    Logger.info("work")
    schedule_work()

    {:noreply, state}
  end

  defp schedule_work do
    Process.send_after(self(), :work, 1_000)
  end
end
