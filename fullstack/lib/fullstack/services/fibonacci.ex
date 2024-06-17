defmodule Fullstack.Services.Fibonacci.Server do
  use GenServer

  def start_link(default \\ []) when is_list(default) do
    GenServer.start_link(__MODULE__, default)
  end

  def push(pid, element) do
    GenServer.cast(pid, {:push, element})
  end

  def pop(pid) do
    GenServer.call(pid, :pop)
  end

  # Server (callbacks)

  @impl true
  def init(elements) do
    initial_state = String.split(elements, ",", trim: true)
    {:ok, initial_state}
  end

  @impl true
  def handle_call(:pop, _from, state) do
    [to_caller | new_state] = state
    {:reply, to_caller, new_state}
  end

  @impl true
  def handle_cast({:push, element}, state) do
    new_state = [element | state]
    {:noreply, new_state}
  end

  defp get_randon_feature do
    features =
      [
        "HTTP server",
        "Request processing",
        "Long-running requests",
        "Server-wide state",
        "Persistable data",
        "Background jobs",
        "Service crash recovery"
      ]
      |> Enum.random()
  end
end
