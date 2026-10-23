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
        {:extraction_complete, %{status: :idle, lifecycle_stage: :validating, messages: msgs}} ->
          # Ask for more data
        {:extraction_complete, %{status: :running, lifecycle_stage: :ready}} ->
          # Research is in progress
        {:research_complete, %{status: :running, lifecycle_stage: :research}} ->
          # Analysis and strategy stages are in progress
        {:tech_strategy_complete, %{status: :idle, lifecycle_stage: :delivered, messages: msgs}} ->
          # Done!
        {:error, %{status: :error, reason: reason}} ->
          # Handle error
      end

      # Polling fallback (still works, returns current state)
      Fullstack.JidoMarketAgents.resume("my-analysis")
      Fullstack.JidoMarketAgents.list_messages("my-analysis")

  ## Status and lifecycle stage

  Every payload that carries `status:` is run health: `:idle` (nothing in
  flight), `:running` (committed automatic work is in flight), or `:error`.
  It also carries `lifecycle_stage:`, where the conversation is in its
  forward-only lifecycle (`:inserted`, `:validating`, `:ready`, `:research`,
  `:proposal`, `:strategy`, `:delivered`). The `stage:` key keeps naming the
  pipeline stage that produced the event (`:validator`, `:research`, ...).
  """

  alias Fullstack.JidoMarketAgents.{Conversation, MessageBuffer, RateLimiter}

  @registry Fullstack.JidoMarketAgents.ConversationRegistry

  @doc """
  Legacy path — send a message straight to a conversation, bypassing the
  throttling pipeline entirely. If no conversation exists with that id,
  creates one. The id is the user-provided name or identifier.

  Returns `{:ok, :accepted, conversation_id}` immediately. Results arrive via
  PubSub on `topic(id)`. The timeout covers only enqueueing the message, not
  LLM processing.

  Subscribe to `topic(id)` **before** calling this to avoid missing
  broadcasts.

  This path exists for non-UI callers (tests, scripts, anything driving a
  conversation directly by id) that have no `user_id` to throttle against.
  UI callers should use `send_message/4` instead, which debounces and rate
  limits per user (design D7).
  """
  def send_message(id, message, timeout \\ 15_000) when is_binary(id) do
    Conversation.send_message(id, message, timeout)
  end

  @doc """
  Buffered path — send a message on behalf of `user_id` for
  `conversation_id`, through `MessageBuffer`'s per-user debounce window and
  `RateLimiter`'s sliding-window limit (design D7, spec R10 S10.2).

  Returns `{:ok, :buffered, conversation_id}` immediately; the message is
  forwarded to the conversation only after the debounce window elapses with
  no further append for this user, and only if the user is not currently
  rate limited (in which case it is queued instead — see `RateLimiter`).

  This is the path UI callers should use. It is the only path that
  throttles: `send_message/3` bypasses both buffer and limiter entirely.
  """
  @spec send_message(term(), term(), map() | String.t(), keyword()) ::
          {:ok, :buffered, term()}
  def send_message(user_id, conversation_id, message, opts) do
    payload =
      if Keyword.has_key?(opts, :run_ref) or Keyword.has_key?(opts, :request_ref) do
        %{
          __pipeline_request__: true,
          message: message,
          run_ref: Keyword.get(opts, :run_ref, Ecto.UUID.generate()),
          request_ref: Keyword.get(opts, :request_ref, Ecto.UUID.generate())
        }
      else
        message
      end

    MessageBuffer.append(user_id, conversation_id, payload)
  end

  @doc "Whether `user_id` is currently rate-limited (`:cooldown`) or not (`:active`)."
  @spec user_status(term()) :: :active | :cooldown
  defdelegate user_status(user_id), to: RateLimiter

  @doc """
  Whether `user_id` currently has an active `MessageBuffer` process holding
  pending messages. Returns `:buffering` if a buffer process exists for the
  user, `:idle` otherwise.

  There is no direct API for this on `MessageBuffer` itself (out of scope
  for this task) — a buffer process's presence in `ConversationRegistry`
  under its `{:message_buffer, user_id}` key is exactly the fact this
  function reports, so it is answered via the Registry it is already
  keyed in, rather than adding a new function to `MessageBuffer`.
  """
  @spec buffer_status(term()) :: :buffering | :idle
  def buffer_status(user_id) do
    case Registry.lookup(@registry, {:message_buffer, user_id}) do
      [{_pid, _}] -> :buffering
      [] -> :idle
    end
  end

  @doc """
  Resume a conversation by id. Returns the current run health
  (`:idle | :running | :error`) and all messages.
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
