defmodule Fullstack.Agents.AgentServer do
  use GenServer
  require Logger

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def ask_question(question, pid) do
    GenServer.cast(__MODULE__, {:ask_question, question, pid})
  end

  # Server Callbacks

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

  # Private functions

  defp process_question(question, live_view_pid) do
    Logger.info("Processing question: #{question}")

    # Simulate connecting to a local server that streams responses
    # In a real implementation, you would connect to your actual server
    stream_response(question, live_view_pid)
  end

  defp stream_response(question, live_view_pid) do
    # This is a mock implementation that simulates streaming a response
    # In a real app, you'd connect to your streaming server here

    # Generate a mock response based on the question
    response =
      case question do
        "hello" ->
          "Hello there! How can I help you today?"

        "time" ->
          "The current time is #{Time.utc_now() |> Time.to_string()}"

        _ ->
          "I received your question about '#{question}'. This is a simulated response that would normally come from your local server. It demonstrates how words can be streamed back to the LiveView one by one."
      end

    # Stream each word with a slight delay to simulate streaming
    response
    |> String.split(" ")
    |> Enum.with_index()
    |> Enum.each(fn {word, _index} ->
      # Send the word to the LiveView process
      send(live_view_pid, {:stream_word, word <> " "})
      # Add a small delay to simulate streaming
      Process.sleep(100)
    end)

    # Signal that the streaming is complete
    send(live_view_pid, {:stream_complete})
  end
end
