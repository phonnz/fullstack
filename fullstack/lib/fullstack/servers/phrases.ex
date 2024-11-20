defmodule Fullstack.Servers.Generators.Phrases do
  use GenServer
  require Logger
  @phrases ["This", "is", "a", "random", "word"]

  def get_state() do
    GenServer.call(__MODULE__, :get_state)
  end

  def connected(pid) do
    GenServer.cast(pid, :connected)
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{phrase: Enum.random(@phrases), idle?: false},
      name: {:global, __MODULE__}
    )
  end

  @impl true
  def init(state) do
    Process.flag(:trap_exit, true)
    schedule_work()

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:work, state) do
    schedule_work()
    new_phrase = Enum.random(@phrases)
    dbg(new_phrase)
    {:noreply, %{phrase: new_phrase}}
  end

  @impl true
  def handle_info(:finish, state) do
    dbg("finishing after doing work")
    {:stop, :shutdown, state}
  end

  @impl true
  def handle_info(:connected, state) do
    dbg("renewing....")
    {:noreply, Map.put(state, :idle?, false)}
  end

  @impl true
  def handle_cast(:idle_or_connected, %{idle?: idle?} = state) do
    dbg(idle?)

    if idle? do
      {:stop, :shutdown, %{}}
    else
      Logger.info("Enable process")
      schedule_work()
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(happened, state) do
    dbg(happened)
    {:noreply, state}
  end

  @impl true
  def terminate({:shutdown, :closed}, state) do
    dbg("SHUTDOWN <==========")
    {:noreply, Map.put(state, :idle?, true)}
  end

  defp schedule_work(after_seconds \\ 2_000) do
    Process.send_after(self(), :work, after_seconds)
  end
end
