defmodule Fullstack.JidoMarketAgents do
  @moduledoc """
  Public API for the Jido Market Agents system.

  ## Usage

      # Subscribe to conversation events (BEFORE sending)
      Fullstack.JidoMarketAgents.subscribe("my-analysis")

      # Send initial market data (name becomes conversation id)
      # Returns immediately with {:ok, :accepted, id}
      Fullstack.JidoMarketAgents.send_message("my-analysis", %{
        country: "Spain",
        business_market: "fintech",
        initial_budget: "50000 EUR",
        final_product_proposal: "Mobile payment app",
        product_price: "9.99 EUR"
      })

      # Receive results via PubSub (or poll with resume/list_messages)
      receive do
        {:extraction_complete, %{status: :needs_data, messages: msgs}} ->
          # Ask for more data
        {:extraction_complete, %{status: :researching}} ->
          # Research is in progress
        {:research_complete, %{status: :completed, messages: msgs}} ->
          # Done!
        {:error, %{status: :error, reason: reason}} ->
          # Handle error
      end

      # Polling fallback (still works, returns current state)
      Fullstack.JidoMarketAgents.resume("my-analysis")
      Fullstack.JidoMarketAgents.list_messages("my-analysis")
  """

  alias Fullstack.JidoMarketAgents.Conversation

  @doc """
  Send a message to a conversation. If no conversation exists with that id, creates one.
  The id is the user-provided name or identifier.

  Returns `{:ok, :accepted, conversation_id}` immediately. Results arrive via PubSub
  on `topic(id)`. The timeout covers only enqueueing the message, not LLM processing.

  Subscribe to `topic(id)` **before** calling this to avoid missing broadcasts.
  """
  def send_message(id, message, timeout \\ 15_000) when is_binary(id) do
    Conversation.send_message(id, message, timeout)
  end

  @doc """
  Resume a conversation by id. Returns current status and all messages.
  Returns `{:error, :conversation_not_found}` if no conversation exists.
  """
  def resume(id) when is_binary(id) do
    Conversation.resume(id)
  end

  @doc """
  List all messages in a conversation.
  Returns `{:error, :conversation_not_found}` if no conversation exists.
  """
  def list_messages(id) when is_binary(id) do
    Conversation.list_messages(id)
  end

  @doc "PubSub topic for a conversation. Subscribe before calling send_message/3."
  defdelegate topic(id), to: Conversation

  @doc "Convenience: subscribe the calling process to this conversation's topic."
  defdelegate subscribe(id), to: Conversation
end
