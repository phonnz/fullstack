defmodule Fullstack.Agents.AgentServer do
  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def ask_question(question, pid) do
    GenServer.cast(__MODULE__, {:ask_question, question, pid})
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:ask_question, question, live_view_pid}, state) do
    # Spawn a process to handle the streaming response
    spawn(fn -> process_question(question, live_view_pid) end)
    {:noreply, state}
  end

  defp process_question(question, live_view_pid) do
    Logger.info("Processing question: #{question}")
    Fullstack.Llms.Client.Local.call(live_view_pid, question)
  end
end
