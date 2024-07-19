defmodule Fullstack.Servers.NumberGenerator do
  alias Hex.API.Key
  use GenServer

  def start_link(max) when is_integer(max) do
    GenServer.start_link(__MODULE__, max)
  end

  def start_link(args \\ []) do
    max = Keyword.get(args, :max, 10000)
    GenServer.start_link(__MODULE__, max)
  end

  def rand(pid) do
    GenServer.call(pid, :rand, 30_000)
  end

  def rand() do
    GenServer.call(__MODULE__, :rand)
  end

  @impl true
  def init(val) do
    {:ok, val}
  end

  @impl true
  def handle_call(:rand, _from, state) do
    {:reply, :rand.uniform(state), state}
  end
end
