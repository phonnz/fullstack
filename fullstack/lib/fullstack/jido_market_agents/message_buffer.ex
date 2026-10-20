defmodule Fullstack.JidoMarketAgents.MessageBuffer do
  @moduledoc """
  Debounces a user's rapid-fire messages before they reach `RateLimiter`,
  so three messages sent seconds apart become one merged batch instead of
  three separate LLM calls.

  One process per `user_id` (design D6) — the OPPOSITE shape from
  `RateLimiter`'s single named GenServer. A shared debounce window has no
  meaning here: each user's timer must reset independently on every new
  message they send, and isolating each user's pending state in its own
  process means one user's crash never loses another user's buffer.
  Processes are started on demand under `MessageBufferSupervisor` (a
  `DynamicSupervisor`) and found again via
  `Fullstack.JidoMarketAgents.ConversationRegistry`, namespaced with a
  `{:message_buffer, user_id}` key so it can never collide with a
  conversation id (always a UUID or legacy plain string, never a tuple).

  `append/3` replies `{:ok, :buffered, conversation_id}` immediately (spec
  S6.4) and cancels/restarts the debounce timer (spec S6.2) — a user who
  keeps sending messages keeps pushing the flush later, so the flush lands
  `debounce_ms` after the LAST message, not the first.

  On flush, pending messages are grouped by `conversation_id` (never mixed
  across conversations, spec S6.3) and forwarded to
  `RateLimiter.check_and_process/3`. A group containing a map message is
  never string-joined with `"\\n\\n"`: `Enum.join/2` has no `String.Chars`
  implementation for maps, and a map is already a complete extraction call
  in its own right (see `RateLimiter`'s moduledoc, spec R8) — merging two
  maps, or a map with a string, would not mean anything sensible. So any
  group containing a map message forwards each of its messages
  individually, in order, instead of being joined into a single string.
  Groups made entirely of strings are joined with `"\\n\\n"` as usual
  (spec S6.1).

  Durations are read at runtime via `Application.get_env/3` (design D5),
  matching `RateLimiter`'s `config/0` pattern, so test config
  (`debounce_ms: 50`) takes effect.
  """
  use GenServer
  require Logger

  alias Fullstack.JidoMarketAgents.{Conversation, MessageBufferSupervisor, RateLimiter}
  alias Fullstack.JidoMarketAgents.Telemetry, as: AgentTelemetry

  @registry Fullstack.JidoMarketAgents.ConversationRegistry

  defstruct [:user_id, pending: [], debounce_timer: nil]

  # Client API

  def start_link(opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(user_id))
  end

  @doc """
  Buffers `message` for `conversation_id` under `user_id`'s debounce
  window, (re)starting that user's process on first use.

  Returns `{:ok, :buffered, conversation_id}` immediately — the message is
  forwarded to `RateLimiter.check_and_process/3` only once the debounce
  window elapses with no further append for this user (spec S6.4).
  """
  @spec append(term(), term(), map() | String.t()) :: {:ok, :buffered, term()}
  def append(user_id, conversation_id, message) do
    {:ok, pid} = find_or_start(user_id)
    GenServer.call(pid, {:append, conversation_id, message})
  end

  # Registry helpers

  defp via_tuple(user_id), do: {:via, Registry, {@registry, {:message_buffer, user_id}}}

  defp lookup(user_id) do
    case Registry.lookup(@registry, {:message_buffer, user_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> :not_found
    end
  end

  defp find_or_start(user_id) do
    case lookup(user_id) do
      {:ok, pid} ->
        {:ok, pid}

      :not_found ->
        case DynamicSupervisor.start_child(
               MessageBufferSupervisor,
               {__MODULE__, user_id: user_id}
             ) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # Server callbacks

  @impl true
  def init(opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    {:ok, %__MODULE__{user_id: user_id}}
  end

  @impl true
  def handle_call({:append, conversation_id, message}, _from, state) do
    entry = %{conversation_id: conversation_id, message: message, queued_at: DateTime.utc_now()}
    state = %{state | pending: state.pending ++ [entry]}

    # First probe in the pipeline: the message is now in the system. Every
    # later stage is expected to produce its own line for this
    # conversation_id; the first one missing localizes the stall.
    AgentTelemetry.emit(
      [:fullstack, :jido_market_agents, :message, :received],
      %{pending_count: length(state.pending)},
      %{conversation_id: conversation_id, user_id: state.user_id, message: message}
    )

    broadcast_buffered(state, conversation_id)

    state = reset_debounce_timer(state)

    {:reply, {:ok, :buffered, conversation_id}, state}
  end

  @impl true
  def handle_info(:flush, state) do
    state.pending
    |> Enum.group_by(& &1.conversation_id, & &1.message)
    |> Enum.each(fn {conversation_id, messages} ->
      # The debounce window elapsed and this batch is moving on. A
      # `message.received` with no `buffer.flushed` for the same
      # conversation means the message is still sitting in this window.
      # The window is `debounce_ms` (45s in dev config), long enough to
      # look like a hang to anyone watching the UI — the emitted
      # measurement reports the real value for this environment.
      AgentTelemetry.emit(
        [:fullstack, :jido_market_agents, :buffer, :flushed],
        %{batch_size: length(messages)},
        %{
          conversation_id: conversation_id,
          user_id: state.user_id,
          debounce_ms: debounce_ms()
        }
      )

      forward_batch(state.user_id, conversation_id, messages)
    end)

    {:noreply, %{state | pending: [], debounce_timer: nil}}
  end

  # Internal helpers

  defp reset_debounce_timer(state) do
    if state.debounce_timer, do: Process.cancel_timer(state.debounce_timer)
    timer_ref = Process.send_after(self(), :flush, debounce_ms())
    %{state | debounce_timer: timer_ref}
  end

  defp broadcast_buffered(state, conversation_id) do
    count =
      Enum.count(state.pending, &(&1.conversation_id == conversation_id))

    payload = %{
      conversation_id: conversation_id,
      message_count: count,
      debounce_ms: debounce_ms()
    }

    Phoenix.PubSub.broadcast(
      Fullstack.PubSub,
      Conversation.topic(conversation_id),
      {:buffered, payload}
    )
  end

  # A group containing any map message is forwarded message-by-message
  # (see moduledoc for why); an all-string group is joined into one batch.
  defp forward_batch(user_id, conversation_id, messages) do
    if Enum.any?(messages, &is_map/1) do
      Enum.each(messages, &RateLimiter.check_and_process(user_id, conversation_id, &1))
    else
      merged = Enum.join(messages, "\n\n")
      RateLimiter.check_and_process(user_id, conversation_id, merged)
    end
  end

  defp config, do: Application.get_env(:fullstack, Fullstack.JidoMarketAgents, [])
  defp debounce_ms, do: Keyword.fetch!(config(), :debounce_ms)
end
