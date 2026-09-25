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

  # Server callbacks

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    user_id = Keyword.get(opts, :user_id)

    validator = MarketValidator.new(id: "#{id}_validator")
    researcher = MarketResearcher.new(id: "#{id}_researcher")

    state = %__MODULE__{
      id: id,
      messages: [],
      validator_agent: validator,
      researcher_agent: researcher,
      status: :active,
      validated_data: nil,
      user_id: user_id,
      record_id: nil,
      persisted_count: 0
    }

    Logger.info("Conversation started: #{id}")
    {:ok, state}
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

        state = %{state | messages: state.messages ++ [assistant_msg]}
        state = broadcast(state, :extraction_complete, %{status: :needs_data})
        {:noreply, state}
    end
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
