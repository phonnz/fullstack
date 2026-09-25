defmodule Fullstack.JidoMarketAgents.Conversation do
  @moduledoc """
  GenServer that manages a single conversation lifecycle.
  Each conversation holds message history and orchestrates agent interactions.
  Supports multi-turn data accumulation via the MarketValidator agent.
  Identified by a user-provided name/id.

  `send_message/3` is fully asynchronous: it returns `{:ok, :accepted, id}`
  immediately and processes the message (LLM extraction, research) in the
  background. Subscribe to `topic(id)` **before** calling `send_message/3`
  to receive stage broadcasts via Phoenix PubSub.
  """
  use GenServer
  require Logger

  alias Fullstack.JidoMarketAgents.Agents.{MarketValidator, MarketResearcher}
  alias Fullstack.JidoMarketAgents.Conversations

  @pubsub Fullstack.PubSub
  @default_timeout 15_000

  # The six flat fields extracted by `MarketValidator` (its schema, minus
  # `extraction_history` — excluded per design D3). Shared by the T4
  # partial-persistence fix (`partial_validated_data/1`) and rehydration
  # (`normalize_validated_data_map/1`).
  @validator_fields [
    :country,
    :city,
    :business_market,
    :initial_budget,
    :final_product_proposal,
    :product_price
  ]

  defstruct [
    :id,
    :messages,
    :validator_agent,
    :researcher_agent,
    :status,
    :validated_data,
    :user_id,
    :record_id,
    persisted_count: 0
  ]

  # Client API

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(id))
  end

  @doc """
  Send a message to a conversation. If no conversation exists with that id, creates one.
  The id is the user-provided name or identifier.

  Returns `{:ok, :accepted, conversation_id}` immediately. Results arrive via
  PubSub on `topic(id)`. The timeout covers only enqueueing, not LLM processing.

  Subscribe to `topic(id)` **before** calling this to avoid missing broadcasts.
  """
  def send_message(id, message, timeout \\ @default_timeout) do
    case find_or_start(id) do
      {:ok, pid} -> GenServer.call(pid, {:send_message, message}, timeout)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Ensures a conversation GenServer is running for `id`, optionally binding
  it to `user_id` for persistence.

  If the conversation already exists (started previously with or without a
  `user_id`), this returns its pid unchanged — it never migrates an
  already-running conversation onto a different `user_id`.
  """
  def ensure_started(id, user_id \\ nil) do
    find_or_start(id, user_id)
  end

  def resume(id) do
    case lookup(id) do
      {:ok, pid} -> GenServer.call(pid, :resume)
      :not_found -> {:error, :conversation_not_found}
    end
  end

  def list_messages(id) do
    case lookup(id) do
      {:ok, pid} -> GenServer.call(pid, :list_messages)
      :not_found -> {:error, :conversation_not_found}
    end
  end

  @doc "PubSub topic for a conversation. Subscribe before calling send_message/3."
  def topic(id), do: "conversation:#{id}"

  @doc "Convenience: subscribe the calling process to this conversation's topic."
  def subscribe(id), do: Phoenix.PubSub.subscribe(@pubsub, topic(id))

  # Registry helpers

  defp via_tuple(id) do
    {:via, Registry, {Fullstack.JidoMarketAgents.ConversationRegistry, id}}
  end

  defp lookup(id) do
    case Registry.lookup(Fullstack.JidoMarketAgents.ConversationRegistry, id) do
      [{pid, _}] -> {:ok, pid}
      [] -> :not_found
    end
  end

  # Id scheme (design D4/D8, decided in T4): rehydration needs a way to
  # find the specific persisted `Conversations.Record` for this GenServer
  # `id`, scoped to `user_id`. Nothing in the current schema stores the
  # GenServer's string id on a `Record` (`record.ex` has no such column,
  # and adding one is out of T4's scope — `conversation.ex` only). So the
  # chosen scheme is: for a persisted (user-bound) conversation, the
  # GenServer `id` *is* the `Record`'s own `binary_id`. This needs no
  # schema change, is exactly what S2.2 describes ("the Registry key is
  # that UUID string"), and makes `Conversations.get_for_user(id,
  # user_id)` directly the rehydration lookup — reusing the existing
  # user-scoped query (D8) with no new unscoped getter. Callers that want
  # a rehydratable conversation create the `Record` first
  # (`Conversations.create/1`) and pass `record.id` as `id` here.
  defp find_or_start(id, user_id \\ nil) do
    case lookup(id) do
      {:ok, pid} ->
        {:ok, pid}

      :not_found ->
        opts = if user_id, do: [id: id, user_id: user_id], else: [id: id]

        DynamicSupervisor.start_child(
          Fullstack.JidoMarketAgents.ConversationSupervisor,
          {__MODULE__, opts}
        )
    end
  end

  # Under the chosen id scheme, `id` is only ever a hit if it is itself a
  # `Record`'s `binary_id` (a UUID) — `Conversations.create/1` never
  # produces anything else. Callers that pick an arbitrary non-UUID
  # string as their conversation id (the legacy 3-arity `send_message/3`
  # path, and any caller with no `Record` to rehydrate from) can never
  # have a matching row, so treat that as an ordinary miss rather than
  # letting `Ecto.Query.CastError` reach `init/1`.
  defp load_persisted_conversation(id, user_id) do
    if uuid?(id) do
      case Conversations.get_for_user(id, user_id) do
        nil ->
          :not_found

        %Conversations.Record{} = record ->
          {:ok,
           %{
             record_id: record.id,
             status: restored_status(record.status),
             validated_data: record.validated_data,
             messages: Enum.map(Conversations.list_messages(record.id), &restored_message/1)
           }}
      end
    else
      :not_found
    end
  end

  # `Ecto.UUID.cast/1` is lenient: it also accepts any raw 16-byte binary
  # and hex-encodes it, so a plain string of the right length (e.g.
  # `"test-persist-324"`, 17 bytes) can spuriously "cast" successfully
  # without ever being canonical UUID text. Match the canonical
  # `8-4-4-4-12` hex string form instead, since that is the only form
  # `Ecto.UUID`'s own `dump/1` (what the `:binary_id` column actually
  # requires) accepts as text input.
  @uuid_text_regex ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

  defp uuid?(id) when is_binary(id), do: Regex.match?(@uuid_text_regex, id)
  defp uuid?(_), do: false

  # Only these 4 known values are ever persisted (`Record`'s
  # `@statuses`/changeset validation) — an explicit mapping, never
  # `String.to_atom/1` on a value that came out of the database.
  defp restored_status("active"), do: :active
  defp restored_status("researching"), do: :researching
  defp restored_status("completed"), do: :completed
  defp restored_status("error"), do: :error

  defp restored_message(%Conversations.Message{} = message) do
    %{
      role: restored_role(message.role),
      content: message.content,
      timestamp: message.inserted_at,
      metadata: message.metadata || %{}
    }
  end

  # `role` is constrained by `Message`'s changeset to exactly these two
  # values — explicit mapping, not dynamic atom creation.
  defp restored_role("user"), do: :user
  defp restored_role("assistant"), do: :assistant

  # Server callbacks

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    user_id = Keyword.get(opts, :user_id)

    # Rehydration (D4) is attempted here, inside `init/1`, rather than in
    # `find_or_start/2` (the caller process that decides whether to spawn
    # a child at all). The `Conversation` child spec is the `use
    # GenServer` default (`restart: :permanent`), so `ConversationSupervisor`
    # (`:one_for_one`) restarts a killed conversation automatically by
    # calling `start_link/1` with the *original* `start_child` opts —
    # bypassing `find_or_start/2` entirely. `init/1` is the only code path
    # both a manual miss (via `find_or_start/2`) and that automatic
    # restart share, so it is the one place a load can't be raced or
    # skipped. If `user_id` is nil there is nothing to scope the lookup by
    # (design D8: no unscoped getter exists) — start fresh empty, same as
    # today (S5.3).
    restored = user_id && load_persisted_conversation(id, user_id)

    # The researcher agent has no persisted state (untouched by this
    # feature) — always starts fresh, restored or not.
    researcher = MarketResearcher.new(id: "#{id}_researcher")

    state =
      case restored do
        {:ok, restored} -> restored_state(id, user_id, researcher, restored)
        _ -> fresh_state(id, user_id, researcher)
      end

    Logger.info("Conversation started: #{id}")
    {:ok, state}
  end

  defp fresh_state(id, user_id, researcher) do
    %__MODULE__{
      id: id,
      messages: [],
      validator_agent: MarketValidator.new(id: "#{id}_validator"),
      researcher_agent: researcher,
      status: :active,
      validated_data: nil,
      user_id: user_id,
      record_id: nil,
      persisted_count: 0
    }
  end

  # Rehydration (R5/D3/D4): rebuilds the validator agent only through its
  # public `new/1` + `set/2` API — never by deserializing a stored struct.
  # `extraction_history` does not survive (D3, accepted: `check_completeness/1`
  # never reads it).
  defp restored_state(id, user_id, researcher, restored) do
    validator = rebuild_validator(id, restored.validated_data)

    %__MODULE__{
      id: id,
      messages: restored.messages,
      validator_agent: validator,
      researcher_agent: researcher,
      status: restored.status,
      validated_data: restored.validated_data,
      user_id: user_id,
      record_id: restored.record_id,
      persisted_count: length(restored.messages)
    }
  end

  defp rebuild_validator(id, nil) do
    MarketValidator.new(id: "#{id}_validator")
  end

  defp rebuild_validator(id, validated_data) when is_map(validated_data) do
    validator = MarketValidator.new(id: "#{id}_validator")

    case normalize_validated_data_map(validated_data) do
      empty when map_size(empty) == 0 ->
        validator

      normalized ->
        {:ok, validator} = MarketValidator.set(validator, normalized)
        validator
    end
  end

  # `validated_data` round-trips through a `:map` (jsonb-like) column, so
  # its keys may come back as strings or already as atoms — never assume
  # either. Only the six known validator fields are accepted, mapped via
  # `String.to_existing_atom/1` (safe: these atoms already exist, defined
  # in `MarketValidator`'s schema) rather than `String.to_atom/1` on
  # arbitrary database content. Nil values are dropped so `set/2` only
  # receives fields that actually have data.
  defp normalize_validated_data_map(data) do
    Map.new(
      for {key, value} <- data,
          not is_nil(value),
          field = validator_field_key(key),
          not is_nil(field) do
        {field, value}
      end
    )
  end

  defp validator_field_key(key) when is_atom(key) do
    if key in @validator_fields, do: key, else: nil
  end

  defp validator_field_key(key) when is_binary(key) do
    if key in Enum.map(@validator_fields, &Atom.to_string/1) do
      String.to_existing_atom(key)
    else
      nil
    end
  end

  @impl true
  def handle_call({:send_message, message}, _from, state) do
    # Record user message
    user_msg = %{role: :user, content: message, timestamp: DateTime.utc_now()}
    state = %{state | messages: state.messages ++ [user_msg]}

    # Enqueue async processing — no I/O in this call
    send(self(), {:process_message, message})
    {:reply, {:ok, :accepted, state.id}, state}
  end

  def handle_call(:resume, _from, state) do
    {:reply, {:ok, state.status, state.messages}, state}
  end

  def handle_call(:list_messages, _from, state) do
    {:reply, {:ok, state.messages}, state}
  end

  # Async message processing (moved out of handle_call)

  @impl true
  def handle_info({:process_message, message}, state) do
    state = persist_new_messages(state)

    case MarketValidator.extract_fields(state.validator_agent, message) do
      {:ok, updated_validator} ->
        state = %{state | validator_agent: updated_validator}
        process_extraction(state)

      {:error, reason} ->
        error_msg = %{
          role: :assistant,
          content: "Sorry, I had trouble processing your message. Please try again.",
          timestamp: DateTime.utc_now(),
          metadata: %{type: :error, reason: inspect(reason)}
        }

        state = %{state | messages: state.messages ++ [error_msg], status: :error}

        state =
          broadcast(state, :error, %{status: :error, stage: :extraction, reason: reason})

        {:noreply, state}
    end
  end

  def handle_info(:run_research, state) do
    case MarketResearcher.research(state.researcher_agent) do
      {:ok, result} ->
        research_msg = %{
          role: :assistant,
          content: result.research_result,
          timestamp: DateTime.utc_now(),
          metadata: %{type: :research_result}
        }

        state = %{
          state
          | messages: state.messages ++ [research_msg],
            status: :completed
        }

        state = broadcast(state, :research_complete, %{status: :completed})
        Logger.info("Research completed for conversation #{state.id}")
        {:noreply, state}

      {:error, reason} ->
        error_msg = %{
          role: :assistant,
          content: "Market research failed: #{inspect(reason)}. Please try again.",
          timestamp: DateTime.utc_now(),
          metadata: %{type: :error}
        }

        state = %{
          state
          | messages: state.messages ++ [error_msg],
            status: :error
        }

        state =
          broadcast(state, :error, %{status: :error, stage: :research, reason: reason})

        Logger.error("Research failed for conversation #{state.id}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  # Private helpers

  defp process_extraction(state) do
    case MarketValidator.check_completeness(state.validator_agent) do
      {:complete, data} ->
        # Data is complete - delegate to researcher
        assistant_msg = %{
          role: :assistant,
          content:
            "Data is complete. Researching market for #{data.final_product_proposal} in #{data.country}...",
          timestamp: DateTime.utc_now()
        }

        {:ok, updated_researcher} =
          MarketResearcher.set(state.researcher_agent, %{
            country: data.country,
            city: Map.get(data, :city),
            business_market: data.business_market,
            final_product_proposal: data.final_product_proposal
          })

        state = %{
          state
          | messages: state.messages ++ [assistant_msg],
            researcher_agent: updated_researcher,
            status: :researching,
            validated_data: data
        }

        state = broadcast(state, :extraction_complete, %{status: :researching})

        # Run research asynchronously
        send(self(), :run_research)
        {:noreply, state}

      {:incomplete, fields} ->
        prompt = MarketValidator.format_missing_prompt(fields)
        Logger.debug("Extraction prompt: #{prompt}")

        summary = MarketValidator.format_extraction_summary(state.validator_agent)
        Logger.debug("Extraction summary: #{summary}")

        content = "#{summary}\n\n#{prompt}"

        assistant_msg = %{role: :assistant, content: content, timestamp: DateTime.utc_now()}

        state = %{
          state
          | messages: state.messages ++ [assistant_msg],
            validated_data: partial_validated_data(state.validator_agent)
        }

        state = broadcast(state, :extraction_complete, %{status: :needs_data})
        {:noreply, state}
    end
  end

  # Bug fix (T4, Part 1): the `{:complete, data}` branch above sets
  # `validated_data` from the validator's `extract_data/1`, but the
  # `{:incomplete, fields}` branch never did — so a conversation killed
  # after a partial turn (e.g. country given, business_market still
  # missing) had nothing to rehydrate from, silently discarding whatever
  # the user already provided. This mirrors `extract_data/1`
  # (`market_validator.ex:232-240`) but is built directly from
  # `agent.state` rather than by calling `check_completeness/1` again
  # (which would just return `{:incomplete, ...}`, not a data map).
  #
  # `extraction_history` is deliberately excluded (design D3) — it is
  # diagnostic only and `check_completeness/1` never reads it.
  #
  # Shape choice: fields are included even when nil/empty (not filtered
  # out), the same shape `extract_data/1` returns for the complete case.
  # This keeps `validated_data` a fixed 6-key map in both branches, so
  # rehydration (`normalize_validated_data_map/1` below) has one shape to
  # handle rather than two.
  defp partial_validated_data(validator_agent) do
    Map.new(@validator_fields, fn field -> {field, Map.get(validator_agent.state, field)} end)
  end

  defp broadcast(state, event, extra) do
    status = Map.get(extra, :status, state.status)

    state =
      state
      |> persist_new_messages()
      |> persist_status(status)

    payload =
      extra
      |> Map.put(:conversation_id, state.id)
      |> Map.put(:messages, state.messages)

    Phoenix.PubSub.broadcast(@pubsub, topic(state.id), {event, payload})
    state
  end

  # ── Persistence (design D2: never crash, never block the broadcast) ────────

  # Persists every message accumulated since the last persist, appending only
  # the new slice (`state.messages` from `persisted_count` onward) so that
  # `broadcast/3`, which fires on every transition, does not re-insert
  # already-persisted history on every call.
  defp persist_new_messages(state) do
    new_messages = Enum.drop(state.messages, state.persisted_count)

    case new_messages do
      [] ->
        state

      _ ->
        case ensure_record(state) do
          {:ok, state} ->
            Enum.reduce(new_messages, state, &persist_message(&2, &1))

          {:error, state} ->
            state
        end
    end
  end

  defp persist_message(state, message) do
    attrs = %{
      role: to_string(message.role),
      content: to_content_string(message.content),
      metadata: Map.get(message, :metadata) || %{}
    }

    case safe_call(fn -> Conversations.append_message(state.record_id, attrs) end) do
      {:ok, {:ok, _record}} ->
        %{state | persisted_count: state.persisted_count + 1}

      {:ok, {:error, reason}} ->
        Logger.error("Conversation #{state.id}: failed to persist message (#{inspect(reason)})")

        %{state | persisted_count: state.persisted_count + 1}

      {:error, reason} ->
        Logger.error(
          "Conversation #{state.id}: raised while persisting message (#{inspect(reason)})"
        )

        %{state | persisted_count: state.persisted_count + 1}
    end
  end

  defp to_content_string(content) when is_binary(content), do: content
  defp to_content_string(content), do: inspect(content)

  defp persist_status(state, status) do
    case ensure_record(state) do
      {:ok, state} ->
        do_persist_status(state, status)

      {:error, state} ->
        state
    end
  end

  # `:needs_data` is an internal substate of an otherwise still-active
  # conversation, not one of `Record`'s persisted statuses
  # (`active/researching/completed/error`) — map it down to `"active"`.
  defp persisted_status(:needs_data), do: "active"
  defp persisted_status(status), do: to_string(status)

  defp do_persist_status(state, status) do
    attrs = %{status: persisted_status(status), validated_data: normalize_validated_data(state)}

    case safe_call(fn ->
           Conversations.get_for_user(state.record_id, state.user_id)
         end) do
      {:ok, %Fullstack.JidoMarketAgents.Conversations.Record{} = record} ->
        case safe_call(fn -> Conversations.update_state(record, attrs) end) do
          {:ok, {:ok, _updated}} ->
            :ok

          {:ok, {:error, reason}} ->
            Logger.error(
              "Conversation #{state.id}: failed to persist status (#{inspect(reason)})"
            )

          {:error, reason} ->
            Logger.error(
              "Conversation #{state.id}: raised while persisting status (#{inspect(reason)})"
            )
        end

      {:ok, nil} ->
        Logger.error("Conversation #{state.id}: could not reload record to persist status")

      {:error, reason} ->
        Logger.error(
          "Conversation #{state.id}: raised while reloading record (#{inspect(reason)})"
        )
    end

    state
  end

  defp normalize_validated_data(%{validated_data: nil}), do: nil
  defp normalize_validated_data(%{validated_data: data}) when is_map(data), do: data
  defp normalize_validated_data(_state), do: nil

  # Lazily creates the conversation row on first persist. Degrades
  # gracefully (logs and skips) when no `user_id` is set or creation fails —
  # it never invents a fake `user_id` and never crashes the GenServer.
  defp ensure_record(%{record_id: record_id} = state) when is_binary(record_id) do
    {:ok, state}
  end

  defp ensure_record(%{user_id: nil} = state) do
    Logger.debug("Conversation #{state.id}: no user_id set, skipping persistence")

    {:error, state}
  end

  defp ensure_record(%{user_id: user_id} = state) do
    case safe_call(fn -> Conversations.create(user_id) end) do
      {:ok, {:ok, record}} ->
        {:ok, %{state | record_id: record.id}}

      {:ok, {:error, reason}} ->
        Logger.error(
          "Conversation #{state.id}: failed to create conversation row (#{inspect(reason)})"
        )

        {:error, state}

      {:error, reason} ->
        Logger.error(
          "Conversation #{state.id}: raised while creating conversation row (#{inspect(reason)})"
        )

        {:error, state}
    end
  end

  # Wraps a persistence call so an unexpected raise degrades to `{:error,
  # reason}` instead of crashing the conversation GenServer (design D2).
  defp safe_call(fun) do
    {:ok, fun.()}
  rescue
    error -> {:error, error}
  end
end
