defmodule Fullstack.JidoMarketAgents.RateLimiter do
  @moduledoc """
  Limits how many LLM-backed batches a user can send within a sliding time
  window, queuing anything over the limit instead of dropping it.

  A single named `GenServer` owns one ETS `:bag` table of `{user_id,
  timestamp}` entries (design D6) — the window has no per-user timing, so one
  owner avoids N processes doing identical pruning. `MessageBuffer` (a
  separate, per-user process) calls `check_and_process/3` after its debounce
  window fires.

  Map messages bypass the limiter entirely: `MarketValidator.extract_fields/2`
  has an `is_map/1` clause that performs no LLM call, so limiting it would
  throttle work that costs nothing (spec R8).

  Durations are read at runtime from `Application.get_env/3` under
  `:fullstack, Fullstack.JidoMarketAgents` (design D5) so tests can configure
  short windows instead of waiting on production timers (spec N3).
  """
  use GenServer
  require Logger

  alias Fullstack.JidoMarketAgents.Conversation

  @table :rate_limiter

  defstruct cooldown_users: MapSet.new(),
            cooldown_queues: %{},
            cooldown_timers: %{}

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Bypasses the limiter for a map `message` (no LLM call, see moduledoc);
  otherwise applies the sliding-window limit and cooldown queue.

  Returns:
    * `:allow` — forwarded to `Conversation.send_message/2` immediately.
    * `:deny` — the batch that tipped the user into cooldown; queued.
    * `:queued` — the user was already in cooldown; queued behind earlier
      batches.
  """
  @spec check_and_process(term(), term(), map() | String.t()) :: :allow | :deny | :queued
  def check_and_process(user_id, conversation_id, message) when is_map(message) do
    GenServer.call(__MODULE__, {:process_map, user_id, conversation_id, message})
  end

  def check_and_process(user_id, conversation_id, message) do
    GenServer.call(__MODULE__, {:check_and_process, user_id, conversation_id, message})
  end

  @doc "Whether `user_id` is currently rate-limited (`:cooldown`) or not (`:active`)."
  @spec user_status(term()) :: :active | :cooldown
  def user_status(user_id) do
    GenServer.call(__MODULE__, {:user_status, user_id})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    :ets.new(@table, [:bag, :named_table, :protected, read_concurrency: true])
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:process_map, _user_id, conversation_id, message}, _from, state) do
    forward(conversation_id, message)
    {:reply, :allow, state}
  end

  def handle_call({:check_and_process, user_id, conversation_id, message}, _from, state) do
    if MapSet.member?(state.cooldown_users, user_id) do
      state = enqueue(state, user_id, conversation_id, message)
      broadcast(conversation_id, :queued_during_cooldown, %{conversation_id: conversation_id})
      {:reply, :queued, state}
    else
      prune(user_id)

      if count(user_id) < limit() do
        record(user_id)
        forward(conversation_id, message)
        {:reply, :allow, state}
      else
        state = enter_cooldown(state, user_id, conversation_id, message)
        {:reply, :deny, state}
      end
    end
  end

  def handle_call({:user_status, user_id}, _from, state) do
    status = if MapSet.member?(state.cooldown_users, user_id), do: :cooldown, else: :active
    {:reply, status, state}
  end

  @impl true
  def handle_info({:cooldown_complete, user_id}, state) do
    queue = Map.get(state.cooldown_queues, user_id, [])

    queue
    |> Enum.reverse()
    |> Enum.each(fn {conversation_id, message} ->
      forward(conversation_id, message)
      broadcast(conversation_id, :cooldown_complete, %{conversation_id: conversation_id})
    end)

    state = %{
      state
      | cooldown_users: MapSet.delete(state.cooldown_users, user_id),
        cooldown_queues: Map.delete(state.cooldown_queues, user_id),
        cooldown_timers: Map.delete(state.cooldown_timers, user_id)
    }

    {:noreply, state}
  end

  # Internal helpers

  defp enter_cooldown(state, user_id, conversation_id, message) do
    retry_at = DateTime.add(DateTime.utc_now(), cooldown_ms(), :millisecond)

    broadcast(conversation_id, :rate_limited, %{
      conversation_id: conversation_id,
      retry_at: retry_at,
      message: "Rate limit reached. Please wait ~15 minutes or upgrade your plan."
    })

    state
    |> Map.put(:cooldown_users, MapSet.put(state.cooldown_users, user_id))
    |> enqueue(user_id, conversation_id, message)
    |> start_cooldown_timer(user_id)
  end

  defp start_cooldown_timer(state, user_id) do
    if Map.has_key?(state.cooldown_timers, user_id) do
      state
    else
      timer_ref = Process.send_after(self(), {:cooldown_complete, user_id}, cooldown_ms())
      %{state | cooldown_timers: Map.put(state.cooldown_timers, user_id, timer_ref)}
    end
  end

  defp enqueue(state, user_id, conversation_id, message) do
    queue = Map.get(state.cooldown_queues, user_id, [])

    %{
      state
      | cooldown_queues:
          Map.put(state.cooldown_queues, user_id, [{conversation_id, message} | queue])
    }
  end

  defp forward(conversation_id, message) do
    Conversation.send_message(conversation_id, message)
  end

  defp broadcast(conversation_id, event, payload) do
    Phoenix.PubSub.broadcast(
      Fullstack.PubSub,
      Conversation.topic(conversation_id),
      {event, payload}
    )
  end

  defp prune(user_id) do
    cutoff = System.monotonic_time(:millisecond) - window_ms()

    :ets.select_delete(@table, [
      {{user_id, :"$1", :_}, [{:<, :"$1", cutoff}], [true]}
    ])
  end

  defp count(user_id), do: :ets.select_count(@table, [{{user_id, :_, :_}, [], [true]}])

  # The third element disambiguates entries recorded within the same
  # millisecond: ETS `:bag` silently drops an inserted tuple that is an exact
  # duplicate of one already present, which would otherwise undercount rapid
  # calls sharing a timestamp.
  defp record(user_id) do
    :ets.insert(
      @table,
      {user_id, System.monotonic_time(:millisecond), System.unique_integer([:monotonic])}
    )
  end

  defp config, do: Application.get_env(:fullstack, Fullstack.JidoMarketAgents, [])
  defp limit, do: Keyword.fetch!(config(), :rate_limit_count)
  defp window_ms, do: Keyword.fetch!(config(), :rate_limit_window_ms)
  defp cooldown_ms, do: Keyword.fetch!(config(), :cooldown_ms)
end
