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
  alias Fullstack.JidoMarketAgents.Agents.{BusinessAnalyzer, SystemsAgent}
  alias Fullstack.JidoMarketAgents.Telemetry, as: AgentTelemetry

  @pubsub Fullstack.PubSub
  @default_timeout 15_000
  @stages [:research, :analysis, :systems, :tech_strategy]

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
    :mode,
    :pending_stage,
    task: nil,
    task_stage: nil,
    task_timer: nil,
    run_ref: nil,
    request_ref: nil,
    boundary_version: 0,
    input_fingerprint: nil,
    results: %{},
    queue: [],
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

        case DynamicSupervisor.start_child(
               Fullstack.JidoMarketAgents.ConversationSupervisor,
               {__MODULE__, opts}
             ) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          error -> error
        end
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
             status: restored_record_status(record),
             mode: restored_record_mode(record),
             pending_stage: restored_stage(pipeline_control(record)["pending_stage"]),
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

  # Only these 6 known values are ever persisted (`Record`'s
  # `@statuses`/changeset validation) — an explicit mapping, never
  # `String.to_atom/1` on a value that came out of the database.
  defp restored_status("active"), do: :active
  defp restored_status("researching"), do: :researching
  defp restored_status("analyzing"), do: :analyzing
  defp restored_status("building_strategy"), do: :building_strategy
  defp restored_status("completed"), do: :completed
  defp restored_status("error"), do: :error
  defp restored_status(_unknown), do: :active

  defp pipeline_control(record) do
    case record.validated_data do
      %{"_pipeline" => control} when is_map(control) -> control
      _ -> %{}
    end
  end

  # Terminal outcomes precede manual idling; legacy completed reports remain
  # display-only. Unknown control values fail closed without creating atoms.
  defp restored_record_status(%{status: "error"}), do: :error
  defp restored_record_status(%{status: "completed"}), do: :completed

  defp restored_record_status(record) do
    if restored_record_mode(record) == :manual,
      do: :active,
      else: restored_status(record.status)
  end

  defp restored_record_mode(%{status: "completed"} = record) do
    if map_size(pipeline_control(record)) == 0,
      do: :legacy,
      else: restored_mode(pipeline_control(record)["mode"])
  end

  defp restored_record_mode(record), do: restored_mode(pipeline_control(record)["mode"])
  defp restored_mode("automatic"), do: :automatic
  defp restored_mode(nil), do: :automatic
  defp restored_mode(_manual_or_unknown), do: :manual

  defp restored_stage("validator"), do: :validator
  defp restored_stage("research"), do: :research
  defp restored_stage("analysis"), do: :analysis
  defp restored_stage("systems"), do: :systems
  defp restored_stage("tech_strategy"), do: :tech_strategy
  defp restored_stage(_unknown), do: nil

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
    Process.flag(:trap_exit, true)
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
      mode: :automatic,
      pending_stage: nil,
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
      mode: restored.mode,
      pending_stage: restored.pending_stage,
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
    request = request_envelope(message)
    state = %{state | queue: state.queue ++ [request]}
    send(self(), :drain_queue)
    {:reply, {:ok, :accepted, state.id}, state}
  end

  def handle_call(:close, _from, state) do
    # Closing an observer never cancels an already accepted stage.
    {:reply, :ok, %{state | mode: :manual}}
  end

  def handle_call(:resume, _from, state),
    do: {:reply, {:ok, state.status, state.messages}, state}

  def handle_call(:list_messages, _from, state),
    do: {:reply, {:ok, state.messages}, state}

  @impl true
  def handle_info(:drain_queue, %{task: nil, queue: [request | rest]} = state)
      when state.pending_stage == nil or state.mode == :manual do
    user_msg = %{
      role: :user,
      content: request.message,
      timestamp: DateTime.utc_now(),
      metadata: %{run_ref: request.run_ref, request_ref: request.request_ref}
    }

    state = %{
      state
      | messages: state.messages ++ [user_msg],
        queue: rest,
        run_ref: request.run_ref,
        request_ref: request.request_ref,
        status: :active,
        mode: :automatic,
        pending_stage: nil
    }

    # Only the owner writes. Accepted input and identity precede provider launch.
    state = persist_new_messages(state)
    state = persist_status(state, :active)

    {:noreply,
     launch(state, :validator, fn ->
       AgentTelemetry.span(:validation, %{conversation_id: state.id}, fn ->
         MarketValidator.extract_fields(state.validator_agent, request.message)
       end)
     end)}
  end

  def handle_info(:drain_queue, state), do: {:noreply, state}

  def handle_info({:run_stage, stage}, %{task: nil} = state) when stage in @stages do
    if state.pending_stage == stage, do: run_stage(state, stage), else: {:noreply, state}
  end

  def handle_info({:run_stage, _stage}, state), do: {:noreply, state}

  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    Process.cancel_timer(state.task_timer)
    stage = state.task_stage
    state = %{state | task: nil, task_stage: nil, task_timer: nil}

    case {stage, result} do
      {:validator, {:ok, validator}} -> process_extraction(%{state | validator_agent: validator})
      {stage, {:ok, result}} -> stage_success(state, stage, result)
      {stage, {:error, _reason}} -> stage_failure(state, stage, :provider_failed)
      {stage, _} -> stage_failure(state, stage, :invalid_result)
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{task: %Task{ref: ref}} = state) do
    Process.cancel_timer(state.task_timer)
    stage_failure(%{state | task: nil, task_timer: nil}, state.task_stage, :worker_failed)
  end

  def handle_info({:stage_timeout, ref}, %{task: %Task{ref: ref} = task} = state) do
    Task.shutdown(task, :brutal_kill)
    stage_failure(%{state | task: nil, task_timer: nil}, state.task_stage, :timeout)
  end

  # Results and DOWNs from completed/obsolete tasks never cross the boundary.
  def handle_info({_ref, _result}, state), do: {:noreply, state}
  def handle_info({:DOWN, _, :process, _, _}, state), do: {:noreply, state}
  def handle_info({:EXIT, _, _}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{task: %Task{} = task}), do: Task.shutdown(task, :brutal_kill)
  def terminate(_reason, _state), do: :ok

  defp request_envelope(%{
         __pipeline_request__: true,
         message: message,
         run_ref: run,
         request_ref: request
       }) do
    %{message: message, run_ref: run, request_ref: request}
  end

  defp request_envelope(message),
    do: %{message: message, run_ref: Ecto.UUID.generate(), request_ref: Ecto.UUID.generate()}

  defp launch(state, stage, fun) do
    task = Task.async(fun)

    configured =
      Application.get_env(:fullstack, Fullstack.JidoMarketAgents, [])[:stage_timeout_ms]

    timeout = if is_integer(configured) and configured > 0, do: configured, else: 120_000
    timer = Process.send_after(self(), {:stage_timeout, task.ref}, timeout)
    %{state | task: task, task_stage: stage, task_timer: timer}
  end

  defp run_stage(state, :research) do
    data = state.validated_data

    {:ok, agent} =
      MarketResearcher.set(MarketResearcher.new(id: "#{state.id}_researcher"), %{
        country: data[:country] || data["country"],
        city: data[:city] || data["city"],
        business_market: data[:business_market] || data["business_market"],
        final_product_proposal: data[:final_product_proposal] || data["final_product_proposal"]
      })

    {:noreply,
     launch(state, :research, fn ->
       AgentTelemetry.span(:research, %{conversation_id: state.id}, fn ->
         MarketResearcher.research(agent)
       end)
     end)}
  end

  defp run_stage(state, :analysis) do
    agent =
      BusinessAnalyzer.new(
        state: %{
          validated_data: business_data(state),
          research_output: clean_result(state.results[:research]),
          refinements: %{},
          output_language: state.validator_agent.state.output_language
        }
      )

    {:noreply,
     launch(state, :analysis, fn ->
       AgentTelemetry.span(:analysis, %{conversation_id: state.id}, fn ->
         BusinessAnalyzer.analyze(agent)
       end)
     end)}
  end

  defp run_stage(state, :systems) do
    agent =
      SystemsAgent.new(
        state: %{
          validated_data: business_data(state),
          research_output: clean_result(state.results[:research]),
          analysis_output: clean_result(state.results[:analysis]),
          refinements: %{},
          output_language: state.validator_agent.state.output_language
        }
      )

    {:noreply,
     launch(state, :systems, fn ->
       AgentTelemetry.span(:systems, %{conversation_id: state.id}, fn ->
         SystemsAgent.build(agent)
       end)
     end)}
  end

  defp business_data(state),
    do: Map.drop(state.validated_data || %{}, ["_pipeline", :_pipeline, "_meta", :_meta])

  defp clean_result(result), do: Map.drop(result || %{}, ["_meta", :_meta])

  defp stage_success(state, stage, result) do
    next =
      case stage do
        :research -> :analysis
        :analysis -> :systems
        :systems -> nil
      end

    status =
      case stage do
        :research -> :analyzing
        :analysis -> :building_strategy
        :systems -> :completed
      end

    fingerprint = stage_input_fingerprint(state, stage)
    state = %{state | input_fingerprint: fingerprint}
    state = persist_status(state, state.status)

    transition = %{
      stage: stage,
      run_ref: state.run_ref,
      request_ref: state.request_ref,
      input_fingerprint: fingerprint,
      contract_version: "1",
      result_digest: digest(result),
      completed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      result: result,
      status: status,
      mode: state.mode,
      pending_stage: next
    }

    case commit_stage(state, transition) do
      {:ok, outcome, state} ->
        state = %{
          state
          | status: status,
            pending_stage: next,
            results: Map.put(state.results, stage, result)
        }

        state =
          if outcome == :committed,
            do: broadcast(state, stage_event(stage), %{status: status}),
            else: state

        if next && state.mode == :automatic, do: send(self(), {:run_stage, next})
        send(self(), :drain_queue)
        {:noreply, state}

      {:error, _} ->
        stage_failure(state, stage, :persistence_failed)
    end
  end

  defp commit_stage(%{user_id: nil} = state, transition) do
    message = %{
      role: :assistant,
      content: Jason.encode!(transition.result),
      timestamp: DateTime.utc_now(),
      metadata: %{type: :market_research, result: transition.result}
    }

    {:ok, :committed,
     %{
       state
       | messages: state.messages ++ [message],
         boundary_version: state.boundary_version + 1
     }}
  end

  defp commit_stage(state, transition) do
    case Conversations.persist_stage_transition(
           state.user_id,
           state.record_id,
           state.boundary_version,
           transition
         ) do
      {:ok, outcome, snapshot} ->
        messages = Enum.map(snapshot.messages, &restored_message/1)

        {:ok, outcome,
         %{
           state
           | messages: messages,
             persisted_count: length(messages),
             validated_data: snapshot.record.validated_data,
             boundary_version: pipeline_control(snapshot.record)["boundary_version"]
         }}

      error ->
        error
    end
  end

  defp stage_event(:systems), do: :systems_complete
  defp stage_event(:analysis), do: :analysis_complete
  defp stage_event(:research), do: :research_complete

  defp stage_input_fingerprint(state, stage),
    do: digest(%{stage: stage, data: state.validated_data})

  defp digest(value),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(value)) |> Base.encode16(case: :lower)

  defp stage_failure(state, stage, reason) do
    message = %{
      role: :assistant,
      content: "Stage failed. Please try again.",
      timestamp: DateTime.utc_now(),
      metadata: %{type: :error}
    }

    state = %{
      state
      | messages: state.messages ++ [message],
        status: :error,
        pending_stage: nil,
        task_stage: nil
    }

    state =
      broadcast(state, :error, %{
        status: :error,
        stage: if(stage == :validator, do: :extraction, else: stage),
        reason: reason
      })

    send(self(), :drain_queue)
    {:noreply, state}
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

        state = %{
          state
          | messages: state.messages ++ [assistant_msg],
            status: :researching,
            validated_data: data,
            pending_stage: :research
        }

        state = broadcast(state, :extraction_complete, %{status: :researching})
        send(self(), {:run_stage, :research})
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

        state = %{state | status: :active, pending_stage: nil}
        state = broadcast(state, :extraction_complete, %{status: :needs_data})
        send(self(), :drain_queue)
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
      |> Map.put(:run_ref, state.run_ref)
      |> Map.put(:request_ref, state.request_ref)
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

  defp normalize_validated_data(%{validated_data: data} = state) when is_map(data) do
    control = %{
      "run_ref" => state.run_ref,
      "request_ref" => state.request_ref,
      "input_fingerprint" => state.input_fingerprint,
      "boundary_version" => state.boundary_version,
      "mode" => to_string(state.mode),
      "pending_stage" => state.pending_stage && to_string(state.pending_stage)
    }

    Map.update(data, "_pipeline", control, fn existing ->
      Map.merge(if(is_map(existing), do: existing, else: %{}), control)
    end)
  end

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
