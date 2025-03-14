defmodule FullstackWeb.Public.AgentLive do
  use FullstackWeb, :live_view
  alias Fullstack.Agents.AgentServer

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       question: "",
       answer: "",
       streaming: false
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <h1 class="text-2xl font-bold mb-4">Question Answerer</h1>

      <form phx-submit="submit_question">
        <div class="mb-4">
          <label class="block text-gray-700 mb-2" for="question">
            Ask a question:
          </label>
          <textarea
            id="question"
            name="question"
            class="w-full px-3 py-2 border border-gray-300 rounded-md"
            rows="3"
            value={@question}
            disabled={@streaming}
          ><%= @question %></textarea>
        </div>

        <button
          type="submit"
          class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded"
          disabled={@streaming}
        >
          <%= if @streaming, do: "Processing...", else: "Ask" %>
        </button>
      </form>

      <div class="mt-8">
        <h2 class="text-xl font-bold mb-2">Answer:</h2>
        <div class="p-4 bg-gray-100 rounded-md min-h-[100px]">
          <%= @answer %>
          <%= if @streaming do %>
            <span class="animate-pulse">|</span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("submit_question", %{"question" => question}, socket) do
    if String.trim(question) != "" do
      socket = assign(socket, streaming: true, answer: "")

      AgentServer.ask_question(question, self())

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:stream_word, word}, socket) do
    updated_answer = socket.assigns.answer <> word
    {:noreply, assign(socket, answer: updated_answer)}
  end

  def handle_info({:stream_complete}, socket) do
    {:noreply, assign(socket, streaming: false)}
  end
end
