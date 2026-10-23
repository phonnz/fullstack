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

  alias Fullstack.JidoMarketAgents.Agents.{MarketValidator, MarketResearcher, ExtractionOutput}
  alias Fullstack.JidoMarketAgents.Conversations
  alias Fullstack.JidoMarketAgents.Conversations.Lifecycle
  alias Fullstack.JidoMarketAgents.Agents.{BusinessAnalyzer, SystemsAgent, StrategyAgent}

  alias Fullstack.JidoMarketAgents.Agents.{
    MarketResearchOutput,
    BusinessAnalysisOutput,
    SystemsStrategyOutput,
    TechAdoptionOutput
  }

  alias Fullstack.JidoMarketAgents.Knowledge
  alias Fullstack.JidoMarketAgents.Telemetry, as: AgentTelemetry

  @pubsub Fullstack.PubSub
  @default_timeout 15_000
  @stages [:research, :analysis, :systems, :tech_strategy]
  @chat_only_type :chat_only

  # Rehydration/persistence field allow-list, sourced from
  # `ExtractionOutput.fields/0` (six commercial scalars + five diagnosis
  # fields — never `extraction_history`, excluded per design D3). Shared by
  # the T4 partial-persistence fix (`partial_validated_data/1`) and
  # rehydration (`normalize_validated_data_map/1`).

  defstruct [
    :id,
    :messages,
    :validator_agent,
    :researcher_agent,
    :analyzer_agent,
    :systems_agent,
    :strategy_agent,
    :status,
    :validated_data,
    :user_id,
    :record_id,
    :mode,
    :pending_stage,
    :manual_lease,
    manual_release_pending: false,
    stage: :inserted,
    validation_provider_free: false,
    last_commit_failed: false,
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

  @doc false
  def ensure_step_started(id, user_id),
    do: find_or_start(id, user_id, manual_open: :atomics.new(1, []))

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
  defp find_or_start(id, user_id \\ nil, start_opts \\ []) do
    case lookup(id) do
      {:ok, pid} ->
        {:ok, pid}

      :not_found ->
        opts =
          Keyword.merge(start_opts, if(user_id, do: [id: id, user_id: user_id], else: [id: id]))

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
             stage: record.stage,
             mode: restored_record_mode(record),
             pending_stage: restored_stage(pipeline_control(record)["pending_stage"]),
             validated_data: record.validated_data,
             result_maps: %{
               analysis: record.business_analysis,
               systems: record.systems_strategy,
               tech_strategy: record.tech_strategy
             },
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

  defp pipeline_control_from_data(data), do: (data || %{})["_pipeline"] || %{}

  # Downstream stages are durable in the record's nullable result columns
  # ("persisted result maps"); only research is durable in a typed message.
  # A cleared column means the boundary was invalidated, so columns win
  # unconditionally over any surviving history message.
  defp restored_results(research, result_maps) do
    %{
      research: research,
      analysis: result_maps.analysis,
      systems: result_maps.systems,
      tech_strategy: result_maps.tech_strategy
    }
    |> Enum.reject(fn {_stage, result} -> is_nil(result) end)
    |> Map.new()
  end

  @doc false
  # Pure, isolated selection of the durable research boundary from typed
  # `market_research` messages (metadata read string-keyed after the JSON
  # roundtrip). Superseded (stale input fingerprint), foreign (wrong type
  # or stage) and unsupported-version messages are never eligible; among
  # eligible messages the latest timestamp wins, with tied timestamps
  # resolved by the durable boundary sequence rather than list insertion
  # order.
  def select_research_message(messages, expected_fingerprint) do
    messages
    |> Enum.filter(&eligible_research?(&1, expected_fingerprint))
    |> Enum.max_by(&research_order/1, fn -> nil end)
    |> case do
      nil -> nil
      message -> (message.metadata || %{})["result"] || message.metadata[:result]
    end
  end

  defp eligible_research?(message, expected_fingerprint) do
    with true <- is_binary(expected_fingerprint),
         metadata when is_map(metadata) <- Map.get(message, :metadata, %{}),
         true <- (metadata["type"] || metadata[:type]) == "market_research",
         result when is_map(result) <- metadata["result"] || metadata[:result],
         meta when is_map(meta) <- result["_meta"] || result[:_meta] do
      (meta["stage"] || meta[:stage]) in [nil, "research"] and
        (meta["contract_version"] || meta[:contract_version]) == contract_version(:research) and
        (meta["input_fingerprint"] || meta[:input_fingerprint]) == expected_fingerprint
    else
      _ -> false
    end
  end

  defp research_order(message) do
    metadata = Map.get(message, :metadata, %{})
    result = metadata["result"] || metadata[:result]
    meta = (is_map(result) && (result["_meta"] || result[:_meta])) || %{}

    {to_string(Map.get(message, :timestamp)),
     meta["boundary_version"] || meta[:boundary_version] || 0}
  end

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
    # Supervisor retains the original start arguments on restart. Suppress
    # resume only for the opening attempt, not for subsequent automatic crash
    # recovery after the caller closes its lease. This flag is never persisted.
    opening = Keyword.get(opts, :manual_open)

    unless is_reference(opening) and :atomics.exchange(opening, 1, 1) == 0,
      do: maybe_enqueue_resume(state)

    {:ok, state}
  end

  # Commit-before-broadcast crash recovery (P58): initialization inspects
  # the durable boundaries and enqueues ONLY the next stage — never a
  # committed one (no regeneration) and never a successor behind a missing
  # prerequisite. The durable `pending_stage` claim must name the same
  # stage (it is written atomically with the boundary), so inconsistent or
  # legacy evidence fails closed instead of scheduling work. Automatic
  # mode only: manual and legacy rows expose idle pending work without
  # generating a successor, and error rows never auto-retry. A stage whose
  # lifecycle phase is behind the persisted `stage` is never resumed: the
  # lifecycle only moves forward.
  defp maybe_enqueue_resume(state) do
    with {:run, stage} <- resume_point(state),
         true <- state.mode == :automatic,
         true <- state.pending_stage == stage,
         true <- not Lifecycle.before?(stage_phase(stage), state.stage) do
      send(self(), {:run_stage, stage})
    end

    state
  end

  defp fresh_state(id, user_id, researcher) do
    state = %__MODULE__{
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

    rebuild_analysis_agents(state)
  end

  # Rehydration (R5/D3/D4): rebuilds the validator agent only through its
  # public `new/1` + `set/2` API — never by deserializing a stored struct.
  # `extraction_history` does not survive (D3, accepted: `check_completeness/1`
  # never reads it).
  defp restored_state(id, user_id, researcher, restored) do
    validator = rebuild_validator(id, restored.validated_data)

    state = %__MODULE__{
      id: id,
      messages: restored.messages,
      validator_agent: validator,
      researcher_agent: researcher,
      status: restored.status,
      stage: restored.stage,
      mode: restored.mode,
      pending_stage: restored.pending_stage,
      run_ref: pipeline_control_from_data(restored.validated_data)["run_ref"],
      request_ref: pipeline_control_from_data(restored.validated_data)["request_ref"],
      boundary_version:
        pipeline_control_from_data(restored.validated_data)["boundary_version"] || 0,
      input_fingerprint: pipeline_control_from_data(restored.validated_data)["input_fingerprint"],
      results: %{},
      validated_data: restored.validated_data,
      user_id: user_id,
      record_id: restored.record_id,
      persisted_count: length(restored.messages)
    }

    research = select_research_message(state.messages, stage_input_fingerprint(state, :research))
    rebuild_analysis_agents(%{state | results: restored_results(research, restored.result_maps)})
  end

  defp rebuild_validator(id, nil) do
    MarketValidator.new(id: "#{id}_validator")
  end

  defp rebuild_validator(id, validated_data) when is_map(validated_data) do
    validator = MarketValidator.new(id: "#{id}_validator")

    replacement =
      case restored_output_language(validated_data) do
        nil ->
          normalize_validated_data_map(validated_data)

        language ->
          Map.put(normalize_validated_data_map(validated_data), :output_language, language)
      end

    case replacement do
      empty when map_size(empty) == 0 ->
        validator

      replacement ->
        {:ok, validator} = MarketValidator.set(validator, replacement)
        validator
    end
  end

  # Rehydration (P54): every downstream agent is rebuilt from the persisted
  # result maps with `new/1` plus one `set/2` of each COMPLETE normalized
  # map. Jido's generated `set/2` deep-merges nested maps, so partial
  # updates would preserve stale nested keys — always replace, never merge,
  # and never serialize a Jido struct into or out of persistence.
  defp rebuild_analysis_agents(state) do
    %{
      state
      | analyzer_agent:
          build_downstream(
            BusinessAnalyzer,
            downstream_inputs(state, [
              {:research_output, MarketResearchOutput, state.results[:research]}
            ])
          ),
        systems_agent:
          build_downstream(
            SystemsAgent,
            downstream_inputs(state, [
              {:research_output, MarketResearchOutput, state.results[:research]},
              {:analysis_output, BusinessAnalysisOutput, state.results[:analysis]}
            ])
          ),
        strategy_agent:
          build_downstream(
            StrategyAgent,
            downstream_inputs(state, [
              {:research_output, MarketResearchOutput, state.results[:research]},
              {:analysis_output, BusinessAnalysisOutput, state.results[:analysis]},
              {:systems_output, SystemsStrategyOutput, state.results[:systems]}
            ])
          )
    }
  end

  defp downstream_inputs(state, upstreams) do
    base = %{
      validated_data: business_data(state),
      refinements: %{},
      output_language: state.validator_agent.state.output_language
    }

    Enum.reduce(upstreams, base, fn {key, module, raw}, inputs ->
      result_input(inputs, key, module, raw)
    end)
  end

  # A persisted result map carries its `"_meta"` envelope and JSON-roundtrip
  # string keys; the closed output contracts reject reserved keys outright,
  # so clean and normalize first and skip absent or invalid maps rather than
  # letting `new/1` raise during initialization.
  defp result_input(inputs, key, module, raw) do
    case module.normalize_map(clean_result(raw)) do
      {:error, _} -> inputs
      normalized -> Map.put(inputs, key, normalized)
    end
  end

  defp build_downstream(module, inputs) do
    module.new(state: inputs)
  rescue
    ArgumentError -> module.new(state: %{refinements: %{}})
  end

  @doc false
  # Pure ordered decision over the restored durable boundaries (P56):
  # resume at the highest contiguous VALID boundary. Fingerprint gaps are
  # stale — a result map whose `_meta` input fingerprint is missing or no
  # longer compatible is treated as absent, and the pipeline resumes at the
  # earliest invalid boundary. Error rows never auto-retry; manual and
  # legacy rows never auto-advance; incomplete validation waits for the
  # user. Complete means a matching research boundary plus all three
  # compatible result maps.
  def resume_point(state) do
    cond do
      state.status == :error -> :halt
      state.mode != :automatic -> :idle
      true -> resume_stage(state)
    end
  end

  defp resume_stage(state) do
    case MarketValidator.check_completeness(state.validator_agent) do
      {:incomplete, _fields} -> :wait
      {:complete, _data} -> earliest_missing_boundary(state)
    end
  end

  defp earliest_missing_boundary(state) do
    Enum.find_value(@stages, :complete, fn stage ->
      if boundary_compatible?(state, stage), do: nil, else: {:run, stage}
    end)
  end

  defp boundary_compatible?(state, stage) do
    case state.results[stage] do
      result when is_map(result) ->
        meta = result["_meta"] || result[:_meta] || %{}
        stored = meta["input_fingerprint"] || meta[:input_fingerprint]
        is_binary(stored) and stored == stage_input_fingerprint(state, stage)

      _ ->
        false
    end
  end

  # The language is system-owned control metadata (`validated_data["_pipeline"]`),
  # restored through `set/2` like any other validated state. Missing or
  # invalid values leave it unset so the next turn re-derives it.
  defp restored_output_language(data) do
    control = Map.get(data, "_pipeline") || Map.get(data, :_pipeline)

    hint =
      if is_map(control),
        do: Map.get(control, "output_language") || Map.get(control, :output_language)

    if ExtractionOutput.valid_language?(hint), do: hint, else: nil
  end

  # `validated_data` round-trips through a `:map` (jsonb-like) column, so
  # its keys may come back as strings or already as atoms — never assume
  # either. Only the fields in `ExtractionOutput.fields/0` are accepted,
  # mapped via `String.to_existing_atom/1` (safe: these atoms already
  # exist, defined in `MarketValidator`'s schema) rather than
  # `String.to_atom/1` on arbitrary database content. Nil values are
  # dropped so `set/2` only receives fields that actually have data.
  #
  # Diagnosis values are re-normalized through `ExtractionOutput`
  # (jsonb round-trips turn nested atom keys into strings, and a
  # pre-existing six-field row has no diagnosis keys at all): missing
  # diagnosis keys normalize to `nil`, so the rebuilt validator always
  # receives the complete normalized diagnosis map (design (d)) and a
  # legacy row simply requalifies by waiting for the missing answers.
  defp normalize_validated_data_map(data) do
    scalars =
      Map.new(
        for {key, value} <- data,
            not is_nil(value),
            field = validator_field_key(key),
            not is_nil(field),
            field in ExtractionOutput.commercial_fields() do
          {field, value}
        end
      )

    Map.merge(scalars, rehydrated_diagnosis(data))
  end

  defp rehydrated_diagnosis(data) do
    case ExtractionOutput.validate_diagnosis(data) do
      {:ok, diagnosis} ->
        diagnosis

      {:error, _reason} ->
        # A malformed legacy diagnosis payload never blocks display: it
        # rehydrates as unanswered and is re-asked on explicit execution.
        Map.new(ExtractionOutput.diagnosis_fields(), fn field -> {field, nil} end)
    end
  end

  defp validator_field_key(key) when is_atom(key) do
    if key in ExtractionOutput.fields(), do: key, else: nil
  end

  defp validator_field_key(key) when is_binary(key) do
    if key in Enum.map(ExtractionOutput.fields(), &Atom.to_string/1) do
      String.to_existing_atom(key)
    else
      nil
    end
  end

  @impl true
  # The Registry is the single ordering authority on ONE node. Multi-node
  # manual leases would need a distributed ownership mechanism instead.
  def handle_call({:claim_step, user_id, owner, observer, lease}, {caller, _}, state) do
    cond do
      state.user_id != user_id or is_nil(state.record_id) or caller != owner ->
        {:reply, {:error, :not_found}, state}

      state.task != nil or state.manual_lease != nil or state.queue != [] ->
        {:reply, {:error, :already_running}, state}

      true ->
        claimed = %{
          state
          | mode: :manual,
            run_ref: state.run_ref || Ecto.UUID.generate(),
            request_ref: state.request_ref || Ecto.UUID.generate(),
            manual_lease: %{
              ref: lease,
              owner: owner,
              observer: observer,
              owner_monitor: Process.monitor(owner),
              observer_monitor: Process.monitor(observer)
            }
        }

        case persist_owned_boundary(claimed, %{}) do
          {:ok, admitted} ->
            binding = Map.take(admitted, [:run_ref, :request_ref, :boundary_version])
            {:reply, {:ok, binding}, admitted}

          {:error, _} ->
            demonitor_lease(claimed.manual_lease)
            {:reply, {:error, :persistence_failed}, state}
        end
    end
  end

  def handle_call({:release_step, ref}, {caller, _}, %{manual_lease: lease} = state)
      when not is_nil(lease) and ref == lease.ref and
             (caller == lease.owner or caller == lease.observer) do
    {:reply, :ok, release_manual_lease(state)}
  end

  # Old tokens cannot release a newer grant, even on the same run.
  def handle_call({:release_step, _ref}, _from, state), do: {:reply, :ok, state}

  def handle_call({:send_message, message}, {caller, _}, state) do
    if state.manual_lease != nil and not manual_request?(state, caller, message) do
      {:reply, {:error, :already_running}, state}
    else
      request = request_envelope(message)

      if Lifecycle.accepts_messages?(state.stage) do
        state = %{state | queue: state.queue ++ [request]}
        send(self(), :drain_queue)
        {:reply, {:ok, :accepted, state.id}, state}
      else
        # Past `:research` a message is chat only. It is stored at once, even
        # while a stage task runs, because it never waits on the pipeline.
        {:reply, {:ok, :accepted, state.id}, store_chat_message(state, request)}
      end
    end
  end

  def handle_call(:snapshot, _from, state) do
    snapshot =
      if state.record_id && state.user_id do
        %{
          record: Conversations.get_for_user(state.record_id, state.user_id),
          messages: Conversations.list_messages(state.record_id)
        }
      else
        %{record: nil, messages: state.messages}
      end

    {:reply, {:ok, snapshot}, state}
  end

  def handle_call({:run_stage, stage, run, request}, {caller, _}, state) do
    cond do
      state.manual_lease != nil and state.manual_lease.owner != caller ->
        {:reply, {:error, :already_running}, state}

      run != state.run_ref or request != state.request_ref ->
        {:reply, {:error, :stale_binding}, state}

      state.task != nil and state.task_stage == stage ->
        {:reply, :accepted, state}

      state.task != nil ->
        {:reply, {:error, :busy}, state}

      stage not in @stages ->
        {:reply, {:error, :invalid_stage}, state}

      true ->
        case cached_stage(state, stage) do
          {:ok, result, state} ->
            {:reply, {:ok, result}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}

          :miss ->
            if stage == state.pending_stage do
              {:noreply, state} = run_stage(%{state | mode: :manual}, stage)
              {:reply, :accepted, state}
            else
              {:reply, {:error, :missing_prerequisite}, state}
            end
        end
    end
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
  def handle_info(:drain_queue, %{task: nil, queue: [request | rest]} = state) do
    state = %{state | queue: rest}

    if Lifecycle.accepts_messages?(state.stage) do
      admit_user_message(state, request)
    else
      # The stage moved past `:research` while the message was queued.
      if rest != [], do: send(self(), :drain_queue)
      {:noreply, store_chat_message(state, request)}
    end
  end

  def handle_info(:drain_queue, state), do: {:noreply, state}

  def handle_info({:run_stage, stage}, %{task: nil, mode: :automatic, manual_lease: nil} = state)
      when stage in @stages do
    if state.pending_stage == stage, do: run_stage(state, stage), else: {:noreply, state}
  end

  def handle_info({:run_stage, _stage}, state), do: {:noreply, state}

  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    Process.cancel_timer(state.task_timer)
    stage = state.task_stage
    state = %{state | task: nil, task_stage: nil, task_timer: nil}

    outcome =
      case {stage, result} do
        {:validator, {:ok, validator}} ->
          process_extraction(%{state | validator_agent: validator})

        {stage, {:ok, result}} ->
          stage_success(state, stage, result)

        {stage, {:error, _reason}} ->
          stage_failure(state, stage, :provider_failed)

        {stage, _} ->
          stage_failure(state, stage, :invalid_result)
      end

    settle_manual_release(outcome)
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{task: %Task{ref: ref}} = state) do
    Process.cancel_timer(state.task_timer)

    settle_manual_release(
      stage_failure(%{state | task: nil, task_timer: nil}, state.task_stage, :worker_failed)
    )
  end

  def handle_info({:stage_timeout, ref}, %{task: %Task{ref: ref} = task} = state) do
    Task.shutdown(task, :brutal_kill)

    settle_manual_release(
      stage_failure(%{state | task: nil, task_timer: nil}, state.task_stage, :timeout)
    )
  end

  # Results and DOWNs from completed/obsolete tasks never cross the boundary.
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{manual_lease: lease} = state)
      when not is_nil(lease) and (ref == lease.owner_monitor or ref == lease.observer_monitor) do
    {:noreply, release_manual_lease(state)}
  end

  def handle_info({_ref, _result}, state), do: {:noreply, state}
  def handle_info({:DOWN, _, :process, _, _}, state), do: {:noreply, state}
  def handle_info({:EXIT, _, _}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{task: %Task{} = task}), do: Task.shutdown(task, :brutal_kill)
  def terminate(_reason, _state), do: :ok

  defp admit_user_message(state, request) do
    user_msg = %{
      role: :user,
      content: request.message,
      timestamp: DateTime.utc_now(),
      metadata: %{run_ref: request.run_ref, request_ref: request.request_ref}
    }

    state = %{
      state
      | messages: state.messages ++ [user_msg],
        run_ref: request.run_ref,
        request_ref: request.request_ref,
        validation_provider_free: is_map(request.message),
        status: :active,
        mode: request.mode,
        pending_stage: nil
    }

    # Only the owner writes. The transaction admits input plus correlation
    # before any paid provider task exists.
    admitted =
      with {:ok, state} <- ensure_record(state),
           do: persist_owned_boundary(state, %{}, :validating)

    case admitted do
      {:ok, state} ->
        start_validation(state, request.message)

      {:error, _} when is_nil(state.user_id) ->
        start_validation(state, request.message)

      {:error, _} when is_map(request.message) ->
        # Legacy provider-free maps retain the display-only degraded path.
        case MarketValidator.extract_fields(state.validator_agent, request.message) do
          {:ok, validator} -> process_extraction(%{state | validator_agent: validator})
          {:error, _} -> stage_failure(state, :validator, :invalid_input)
        end

      {:error, _} ->
        stage_failure(state, :validator, :persistence_failed)
    end
  end

  # Stores a user message as chat and nothing else: no validation, no status,
  # `pending_stage`, result or stage change. The `chat_only` type keeps it out
  # of every pipeline reader, which all select messages by their own type.
  defp store_chat_message(state, request) do
    message = %{
      role: :user,
      content: request.message,
      timestamp: DateTime.utc_now(),
      metadata: %{type: @chat_only_type}
    }

    state = %{state | messages: state.messages ++ [message]}

    state =
      case persist_owned_boundary(state, %{}) do
        {:ok, persisted} ->
          persisted

        {:error, reason} ->
          Logger.warning(
            "Conversation #{state.id}: chat message not persisted (#{inspect(reason)})"
          )

          state
      end

    broadcast(state, :message_received, %{})
  end

  defp start_validation(state, message) do
    {:noreply,
     launch(state, :validator, fn ->
       AgentTelemetry.span(:validation, %{conversation_id: state.id}, fn ->
         MarketValidator.extract_fields(state.validator_agent, message)
       end)
     end)}
  end

  defp manual_request?(%{manual_lease: lease}, caller, message) do
    is_map(message) and message[:__pipeline_request__] == true and
      message[:mode] == :manual and message[:lease_ref] == lease.ref and caller == lease.owner
  end

  defp demonitor_lease(lease) do
    Process.demonitor(lease.owner_monitor, [:flush])
    Process.demonitor(lease.observer_monitor, [:flush])
  end

  defp release_manual_lease(state) do
    demonitor_lease(state.manual_lease)
    state = %{state | manual_lease: nil, manual_release_pending: true}
    if state.task == nil and state.queue == [], do: restore_scheduling(state), else: state
  end

  defp restore_scheduling(state) do
    state = %{state | mode: :automatic, manual_release_pending: false}

    case persist_owned_boundary(state, %{}) do
      {:ok, persisted} -> persisted
      {:error, _} -> state
    end
  end

  defp settle_manual_release({:noreply, %{manual_release_pending: true} = state}),
    do: {:noreply, restore_scheduling(state)}

  defp settle_manual_release(outcome), do: outcome

  defp request_envelope(
         %{__pipeline_request__: true, message: message, run_ref: run, request_ref: request} =
           envelope
       ) do
    mode = if envelope[:mode] == :manual, do: :manual, else: :automatic
    %{message: message, run_ref: run, request_ref: request, mode: mode}
  end

  defp request_envelope(message),
    do: %{
      message: message,
      run_ref: Ecto.UUID.generate(),
      request_ref: Ecto.UUID.generate(),
      mode: :automatic
    }

  defp launch(state, stage, fun) do
    task = Task.async(fun)

    configured =
      Application.get_env(:fullstack, Fullstack.JidoMarketAgents, [])[:stage_timeout_ms]

    timeout = if is_integer(configured) and configured > 0, do: configured, else: 120_000
    timer = Process.send_after(self(), {:stage_timeout, task.ref}, timeout)
    %{state | task: task, task_stage: stage, task_timer: timer}
  end

  defp start_stage(state, stage, fun) do
    state = %{state | input_fingerprint: stage_input_fingerprint(state, stage)}

    case persist_owned_boundary(state, %{}, stage_phase(stage)) do
      {:ok, admitted} -> {:noreply, launch(admitted, stage, fun)}
      {:error, _} -> stage_failure(state, stage, :persistence_failed)
    end
  end

  defp cached_stage(%{user_id: nil}, _stage), do: :miss

  defp cached_stage(state, stage) do
    binding = %{run_ref: state.run_ref, request_ref: state.request_ref}

    case Conversations.cached_stage_result(
           state.user_id,
           state.record_id,
           state.boundary_version,
           binding,
           stage,
           stage_input_fingerprint(state, stage),
           contract_version(stage)
         ) do
      {:ok, %{result: nil}} ->
        :miss

      {:ok, snapshot} ->
        messages = Enum.map(snapshot.messages, &restored_message/1)
        {:ok, snapshot.result, %{state | messages: messages, persisted_count: length(messages)}}

      {:error, reason} ->
        {:error, reason}
    end
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

    start_stage(state, :research, fn ->
      AgentTelemetry.span(:research, %{conversation_id: state.id}, fn ->
        MarketResearcher.research(agent)
      end)
    end)
  end

  defp run_stage(state, :analysis) do
    agent = state.analyzer_agent

    start_stage(state, :analysis, fn ->
      AgentTelemetry.span(:analysis, %{conversation_id: state.id}, fn ->
        BusinessAnalyzer.analyze(agent)
      end)
    end)
  end

  defp run_stage(state, :systems) do
    agent = state.systems_agent

    start_stage(state, :systems, fn ->
      AgentTelemetry.span(:systems, %{conversation_id: state.id}, fn ->
        SystemsAgent.build(agent)
      end)
    end)
  end

  defp run_stage(state, :tech_strategy) do
    agent = state.strategy_agent

    start_stage(state, :tech_strategy, fn ->
      AgentTelemetry.span(:tech_strategy, %{conversation_id: state.id}, fn ->
        StrategyAgent.build(agent)
      end)
    end)
  end

  defp business_data(state),
    do: Map.drop(state.validated_data || %{}, ["_pipeline", :_pipeline, "_meta", :_meta])

  defp clean_result(result), do: Map.drop(result || %{}, ["_meta", :_meta])

  defp stage_success(state, stage, result) do
    next = Enum.at(@stages, Enum.find_index(@stages, &(&1 == stage)) + 1)

    status =
      case stage do
        :research -> :analyzing
        :analysis -> :building_strategy
        :systems -> :building_strategy
        :tech_strategy -> :completed
      end

    status = if state.mode == :manual and next, do: :active, else: status
    fingerprint = state.input_fingerprint

    transition = %{
      stage: stage,
      run_ref: state.run_ref,
      request_ref: state.request_ref,
      input_fingerprint: fingerprint,
      contract_version: contract_version(stage),
      guide_digest: guide_digest(stage),
      result_digest: digest(result),
      completed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      result: result,
      status: status,
      mode: state.mode,
      pending_stage: next,
      lifecycle_stage: if(stage == :tech_strategy, do: :delivered)
    }

    case commit_stage(state, transition) do
      {:ok, outcome, state} ->
        state =
          rebuild_analysis_agents(%{
            state
            | status: status,
              pending_stage: next,
              results: Map.put(state.results, stage, result)
          })

        commit_gated_advance(state, stage, next, outcome)

      {:error, _} ->
        stage_failure(state, stage, :persistence_failed)
    end
  end

  # Shared commit gate (P57): a success event is broadcast only behind a
  # fresh durable commit, and a successor stage is scheduled only behind a
  # durable commit (:committed now, or :replayed from an earlier commit of
  # the same transition). Nothing here may run before the boundary is
  # durable.
  defp commit_gated_advance(state, stage, next, outcome) do
    state =
      if outcome == :committed,
        do:
          broadcast(
            state,
            stage_event(stage),
            Map.put(
              %{status: state.status, stage: stage},
              result_key(stage),
              durable_result(state, stage)
            )
          ),
        else: state

    if not is_nil(next) and state.mode == :automatic and outcome in [:committed, :replayed],
      do: send(self(), {:run_stage, next})

    send(self(), :drain_queue)
    {:noreply, state}
  end

  defp commit_stage(%{user_id: nil} = state, transition) do
    meta =
      transition
      |> Map.take([
        :stage,
        :contract_version,
        :input_fingerprint,
        :result_digest,
        :completed_at,
        :run_ref,
        :request_ref,
        :guide_digest
      ])
      |> Map.put(:boundary_version, state.boundary_version + 1)

    result = Map.put(transition.result, :_meta, meta)

    message = %{
      role: :assistant,
      content: Jason.encode!(result),
      timestamp: DateTime.utc_now(),
      metadata: %{type: result_key(transition.stage), result: result, _meta: meta}
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
             stage: snapshot.record.stage,
             boundary_version: pipeline_control(snapshot.record)["boundary_version"]
         }}

      error ->
        error
    end
  end

  # Lifecycle phase a pipeline stage runs in.
  defp stage_phase(:research), do: :research
  defp stage_phase(:analysis), do: :proposal
  defp stage_phase(:systems), do: :strategy
  defp stage_phase(:tech_strategy), do: :strategy

  defp result_key(:research), do: :market_research
  defp result_key(:analysis), do: :business_analysis
  defp result_key(:systems), do: :systems_strategy
  defp result_key(:tech_strategy), do: :tech_strategy

  defp durable_result(state, stage) do
    type = to_string(result_key(stage))

    state.messages
    |> Enum.reverse()
    |> Enum.find_value(fn message ->
      metadata = Map.get(message, :metadata, %{})

      if to_string(metadata["type"] || metadata[:type]) == type,
        do: metadata["result"] || metadata[:result]
    end)
  end

  defp stage_event(:tech_strategy), do: :tech_strategy_complete
  defp stage_event(:systems), do: :systems_complete
  defp stage_event(:analysis), do: :analysis_complete
  defp stage_event(:research), do: :research_complete

  @doc """
  Computes a canonical stage eligibility key from owner-supplied inputs.

  Owner metadata is excluded before closed contract normalization. Version
  overrides are owner configuration, never extracted user instructions.
  """
  def fingerprint(stage, inputs) when stage in @stages do
    facts = input_value(inputs, :validated_data, %{}) |> clean_facts()
    facts = ExtractionOutput.normalize_map(facts)

    upstream =
      @stages
      |> Enum.take_while(&(&1 != stage))
      |> Map.new(fn upstream ->
        key =
          case upstream do
            :research -> :research_output
            :analysis -> :analysis_output
            :systems -> :systems_output
          end

        raw = input_value(inputs, key, %{}) |> clean_result()
        normalized = output_module(upstream).normalize_map(raw)
        {upstream, digest(normalized)}
      end)

    digest(%{
      stage: stage,
      validated_data: facts,
      output_language: input_value(inputs, :output_language, nil),
      upstream: upstream,
      refinements: input_value(inputs, :refinements, []),
      contract_version: input_value(inputs, :contract_version, contract_version(stage)),
      contract_schema: digest(output_module(stage).schema()),
      prompt_version: input_value(inputs, :prompt_version, "1"),
      guide_version: input_value(inputs, :guide_version, "1"),
      guide_digest: guide_digest(stage)
    })
  end

  defp input_value(map, key, default),
    do: Map.get(map, key, Map.get(map, to_string(key), default))

  defp clean_facts(map), do: Map.drop(map, ["_pipeline", :_pipeline, "_meta", :_meta])
  defp output_module(:research), do: MarketResearchOutput
  defp output_module(:analysis), do: BusinessAnalysisOutput
  defp output_module(:systems), do: SystemsStrategyOutput
  defp output_module(:tech_strategy), do: TechAdoptionOutput
  defp contract_version(:research), do: "market-research/1"
  defp contract_version(:analysis), do: "business-analysis/1"
  defp contract_version(:systems), do: "systems-strategy/1"
  defp contract_version(:tech_strategy), do: "tech-adoption/1"

  defp guide_digest(stage) when stage in [:systems, :tech_strategy] do
    guide = if stage == :systems, do: :six_systems, else: :tech_adoption

    case Knowledge.fetch(guide) do
      {:ok, content} -> digest(content)
      {:error, _} -> nil
    end
  end

  defp guide_digest(_), do: nil

  defp stage_input_fingerprint(state, stage) do
    fingerprint(stage, %{
      validated_data: business_data(state),
      research_output: state.results[:research] || %{},
      analysis_output: state.results[:analysis] || %{},
      systems_output: state.results[:systems] || %{},
      refinements: stage_refinements(state, stage),
      output_language: state.validator_agent.state.output_language
    })
  end

  defp stage_refinements(state, stage) do
    targets = [:validator | Enum.take_while(@stages, &(&1 != stage))] ++ [stage]

    for message <- state.messages,
        metadata = Map.get(message, :metadata, %{}),
        to_string(metadata[:type] || metadata["type"]) == "stage_refinement",
        to_string(metadata[:target] || metadata["target"]) in Enum.map(targets, &to_string/1),
        do: %{target: metadata[:target] || metadata["target"], content: message.content}
  end

  defp digest(value),
    do:
      :crypto.hash(:sha256, :erlang.term_to_binary(canonical(value)))
      |> Base.encode16(case: :lower)

  defp canonical(map) when is_map(map),
    do:
      {:map,
       map |> Enum.map(fn {key, value} -> {to_string(key), canonical(value)} end) |> Enum.sort()}

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)

  defp canonical(value) when is_atom(value) and value not in [nil, true, false],
    do: to_string(value)

  defp canonical(value), do: value

  # Shared terminal-error construction (P59): the persisted typed message
  # and the wire event derive from one sanitized envelope. `reason` is an
  # internal tag only — raw provider payloads, credentials and stacktraces
  # never leave this module.
  defp stage_error_message(stage, reason) do
    %{
      role: :assistant,
      content: "Stage failed. Please try again.",
      timestamp: DateTime.utc_now(),
      metadata: %{type: :error, stage: stage, reason: reason}
    }
  end

  defp stage_error_reason(reason), do: {:stage_failed, reason}

  defp stage_failure(state, stage, reason) do
    message = stage_error_message(stage, reason)

    candidate = %{
      state
      | messages: state.messages ++ [message],
        status: :error,
        pending_stage: nil,
        task_stage: nil,
        boundary_version: state.boundary_version + 1
    }

    {state, durability} =
      case persist_owned_boundary(candidate, %{}) do
        {:ok, committed} -> {committed, :committed}
        {:error, _} -> {%{state | pending_stage: nil, task_stage: nil}, :failed}
      end

    state =
      broadcast(state, :error, %{
        status: :error,
        stage: if(stage == :validator, do: :extraction, else: stage),
        reason: stage_error_reason(reason),
        durability: durability
      })

    send(self(), :drain_queue)
    {:noreply, state}
  end

  # Private helpers

  defp process_extraction(state) do
    last_durable = state
    completeness = MarketValidator.check_completeness(state.validator_agent)

    # The fork the whole feature turns on. `:incomplete` is a SUCCESSFUL
    # terminal state — the pipeline is now waiting on the user, not stuck —
    # and distinguishing it in the trace from a stall is the main reason
    # these probes exist.
    case completeness do
      {:incomplete, fields} ->
        AgentTelemetry.emit(
          [:fullstack, :jido_market_agents, :validation, :incomplete],
          %{missing_count: length(fields)},
          %{conversation_id: state.id, missing_fields: fields}
        )

      {:complete, _data} ->
        AgentTelemetry.emit(
          [:fullstack, :jido_market_agents, :validation, :complete],
          %{},
          %{conversation_id: state.id}
        )
    end

    assessment = MarketValidator.assessment(state.validator_agent)

    case completeness do
      {:complete, data} ->
        # Data is complete - delegate to researcher
        assistant_msg = %{
          role: :assistant,
          content:
            "Data is complete. Researching market for #{data.final_product_proposal} in #{data.country}...",
          metadata: validator_metadata(state, assessment),
          timestamp: DateTime.utc_now()
        }

        changed = facts_changed?(state, data)
        status = if state.mode == :manual, do: :active, else: :researching

        state = %{
          state
          | messages: state.messages ++ [assistant_msg],
            status: status,
            validated_data: data,
            boundary_version: state.boundary_version + 1,
            pending_stage: :research
        }

        state = commit_validation(state, changed, :ready)

        if state.last_commit_failed do
          stage_failure(last_durable, :validator, :persistence_failed)
        else
          state =
            broadcast(state, :extraction_complete, %{
              status: status,
              stage: :validator,
              validated_data: state.validated_data,
              assessment: assessment
            })

          if state.mode == :automatic, do: send(self(), {:run_stage, :research})
          send(self(), :drain_queue)
          {:noreply, state}
        end

      {:incomplete, fields} ->
        prompt = MarketValidator.format_missing_prompt(fields)
        Logger.debug("Extraction prompt: #{prompt}")

        summary = MarketValidator.format_extraction_summary(state.validator_agent)
        Logger.debug("Extraction summary: #{summary}")

        content = "#{summary}\n\n#{prompt}"

        assistant_msg = %{
          role: :assistant,
          content: content,
          metadata: validator_metadata(state, assessment),
          timestamp: DateTime.utc_now()
        }

        data = partial_validated_data(state.validator_agent)
        changed = facts_changed?(state, data)

        state = %{
          state
          | messages: state.messages ++ [assistant_msg],
            validated_data: data,
            boundary_version: state.boundary_version + 1,
            status: :active,
            pending_stage: nil
        }

        state = commit_validation(state, changed, nil)

        if state.last_commit_failed and not state.validation_provider_free do
          stage_failure(last_durable, :validator, :persistence_failed)
        else
          payload = %{
            status: :needs_data,
            stage: :validator,
            validated_data: state.validated_data,
            missing_fields: fields,
            assessment: assessment
          }

          # Preserve the historical provider-free display fallback without
          # claiming that its undurable answer is a committed boundary.
          payload =
            if state.last_commit_failed, do: Map.put(payload, :durability, :failed), else: payload

          state = broadcast(state, :extraction_complete, payload)
          send(self(), :drain_queue)
          {:noreply, state}
        end
    end
  end

  # The raw reply belongs to the extraction that `process_extraction/1` was
  # just handed, because every successful `extract_fields/2` appends its own
  # history entry. Map input records none, so only LLM turns carry it. It is
  # persisted on the message metadata for diagnosis; no broadcast payload key
  # carries it.
  defp validator_metadata(state, assessment) do
    case MarketValidator.last_raw_response(state.validator_agent) do
      nil -> %{assessment: assessment}
      raw_response -> %{assessment: assessment, raw_response: raw_response}
    end
  end

  defp facts_changed?(state, data) do
    map_size(state.results) > 0 and
      digest(business_data(state)) != digest(data)
  end

  defp commit_validation(state, changed, target_stage) do
    attrs =
      if changed,
        do: %{business_analysis: nil, systems_strategy: nil, tech_strategy: nil},
        else: %{}

    case persist_owned_boundary(state, attrs, target_stage) do
      {:ok, state} ->
        state =
          if changed,
            do: rebuild_analysis_agents(%{state | results: %{}}),
            else: state

        if changed and state.record_id do
          broadcast(state, :stage_invalidated, %{
            invalidated: @stages,
            stage: :validator,
            record: Conversations.get_for_user(state.record_id, state.user_id)
          })
        else
          state
        end

      {:error, _} ->
        %{state | last_commit_failed: true, boundary_version: max(state.boundary_version - 1, 0)}
    end
  end

  # `target_stage` is the lifecycle stage this boundary moves toward. It is
  # applied in the same transaction, and only when it is the next adjacent
  # stage (`Conversations.advance_stage/3`); at or behind the stored stage it
  # is a no-op.
  defp persist_owned_boundary(state, extra_attrs, target_stage \\ nil)

  defp persist_owned_boundary(%{user_id: nil} = state, _attrs, _target_stage), do: {:ok, state}

  defp persist_owned_boundary(state, extra_attrs, target_stage) do
    result =
      safe_call(fn ->
        Fullstack.Repo.transaction(fn ->
          record = Conversations.get_for_user(state.record_id, state.user_id)
          if is_nil(record), do: Fullstack.Repo.rollback(:not_found)

          for message <- Enum.drop(state.messages, state.persisted_count) do
            attrs = %{
              role: to_string(message.role),
              content: to_content_string(message.content),
              metadata: Map.get(message, :metadata, %{})
            }

            case Conversations.append_message(record.id, attrs) do
              {:ok, _} -> :ok
              {:error, _} -> Fullstack.Repo.rollback(:message_failed)
            end
          end

          attrs =
            Map.merge(
              %{
                status: persisted_status(state.status),
                validated_data: normalize_validated_data(state)
              },
              extra_attrs
            )

          case Conversations.update_state(record, attrs) do
            {:ok, record} -> record
            {:error, _} -> Fullstack.Repo.rollback(:state_failed)
          end
          |> then(&Conversations.advance_stage(Fullstack.Repo, &1, target_stage))
          |> case do
            {:ok, record} -> %{record: record, messages: Conversations.list_messages(record.id)}
            {:error, _} -> Fullstack.Repo.rollback(:stage_failed)
          end
        end)
      end)

    case result do
      {:ok, {:ok, snapshot}} ->
        messages = Enum.map(snapshot.messages, &restored_message/1)

        {:ok,
         %{
           state
           | messages: messages,
             persisted_count: length(messages),
             validated_data: snapshot.record.validated_data,
             stage: snapshot.record.stage,
             last_commit_failed: false
         }}

      _ ->
        {:error, :persistence_failed}
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
  # This keeps `validated_data` a fixed 11-key map in both branches (the
  # `ExtractionOutput.fields/0` shape), so rehydration
  # (`normalize_validated_data_map/1` below) has one shape to handle
  # rather than two.
  defp partial_validated_data(validator_agent) do
    Map.new(ExtractionOutput.fields(), fn field ->
      {field, Map.get(validator_agent.state, field)}
    end)
  end

  defp broadcast(state, event, extra) do
    status = Map.get(extra, :status, state.status)

    payload =
      extra
      |> Map.put(:boundary_version, state.boundary_version)
      |> Map.put(:mode, state.mode)
      |> Map.put(:run_ref, state.run_ref)
      |> Map.put(:request_ref, state.request_ref)
      |> Map.put(:conversation_id, state.id)
      |> Map.put(:messages, state.messages)
      |> Map.put(:output_language, state.validator_agent.state.output_language)

    # Last thing the backend does for this turn. A `broadcast.emitted`
    # with no matching `liveview.handled` means the response was produced
    # and the UI dropped it — which was entirely invisible before, since
    # the LiveView's catch-all `handle_info/2` returns `{:noreply, socket}`
    # without a trace.
    AgentTelemetry.emit(
      [:fullstack, :jido_market_agents, :broadcast, :emitted],
      %{message_count: length(state.messages)},
      %{conversation_id: state.id, event: event, status: status}
    )

    Phoenix.PubSub.broadcast(@pubsub, topic(state.id), {event, payload})
    state
  end

  defp to_content_string(content) when is_binary(content), do: content
  defp to_content_string(content), do: inspect(content)

  # Waiting is a UI event; the durable conversation remains active.
  defp persisted_status(:needs_data), do: "active"
  defp persisted_status(status), do: to_string(status)

  defp normalize_validated_data(%{validated_data: nil} = state),
    do: normalize_validated_data(%{state | validated_data: %{}})

  defp normalize_validated_data(%{validated_data: data} = state) when is_map(data) do
    # Owner-attached control metadata: system-owned JSON-safe state lives
    # under the reserved `validated_data["_pipeline"]` area — outside the
    # user-editable business fields. `output_language` is restored from
    # here after a process death.
    control = %{
      "output_language" => state.validator_agent.state.output_language,
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
