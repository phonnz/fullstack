defmodule Fullstack.Counter do
  use GenServer

  def start_link(default \\ 0) when is_number(default) do
    GenServer.start_link(__MODULE__, default)
  end

  def inc(pid) do
    GenServer.cast(pid, :inc)
  end

  def dec(pid) do
    GenServer.cast(pid, :dec)
  end

  def get(pid), do: GenServer.call(pid, :get)

  @impl true
  def init(val) do
    {:ok, val}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast(:inc, state) do
    {:noreply, state + 1}
  end

  @impl true
  def handle_cast(:dec, state) do
    {:noreply, state - 1}
  end
end
