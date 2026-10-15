defmodule Fullstack.JidoMarketAgents.Conversations.Step do
  @moduledoc """
  Caller-owned, non-serializable observer tokens for manual conversation stages.
  A dedicated observer owns the PubSub subscription; opening never submits input.
  """
  alias Fullstack.JidoMarketAgents.{Conversation, Conversations}
  alias __MODULE__.Observer

  @stage_fields %{
    research: :market_research,
    analysis: :business_analysis,
    systems: :systems_strategy,
    tech_strategy: :tech_strategy
  }
  @stage_events %{
    validator: :extraction_complete,
    research: :research_complete,
    analysis: :analysis_complete,
    systems: :systems_complete,
    tech_strategy: :tech_strategy_complete
  }

  defstruct [
    :owner,
    :conversation_id,
    :user_id,
    :pid,
    :observer,
    :monitor_ref,
    :topic,
    :lease_ref,
    :run_ref,
    :request_ref,
    :boundary_version,
    :deadline,
    mode: :manual,
    stage_versions: %{}
  ]

  def open(user_id, conversation_id \\ nil, opts \\ []) do
    with {:ok, timeout} <- timeout_ms(opts) do
      deadline = System.monotonic_time(:millisecond) + timeout
      do_open(user_id, conversation_id, deadline)
    end
  end

  defp timeout_ms(opts) do
    timeout =
      if is_list(opts) and Keyword.keyword?(opts), do: Keyword.get(opts, :timeout_ms, 120_000)

    if is_integer(timeout) and timeout > 0, do: {:ok, timeout}, else: {:error, :invalid_timeout}
  end

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)

  defp do_open(user_id, nil, deadline) do
    run = Ecto.UUID.generate()
    request = Ecto.UUID.generate()

    with {:ok, record} <-
           Conversations.create(user_id, %{
             validated_data: %{
               "_pipeline" => %{
                 "mode" => "manual",
                 "run_ref" => run,
                 "request_ref" => request,
                 "boundary_version" => 0
               }
             }
           }) do
      attach(record, user_id, deadline)
    end
  end

  defp do_open(user_id, id, deadline) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, user_id} <- Ecto.UUID.cast(user_id),
         %Conversations.Record{} = record <- Conversations.get_for_user(id, user_id) do
      attach(record, user_id, deadline)
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Waits for a correlated durable completion, not a stage enqueue acknowledgement."
  def wait(%__MODULE__{owner: owner} = session, stage) when owner == self() do
    if Map.has_key?(@stage_events, stage) do
      result =
        if remaining(session.deadline) == 0,
          do: {:error, {:timeout, stage}},
          else: GenServer.call(session.observer, {:wait, session, stage}, :infinity)

      case result do
        {:error, _} = error ->
          close(session)
          error

        result ->
          result
      end
    else
      {:error, :invalid_stage}
    end
  end

  def wait(%__MODULE__{}, _stage), do: {:error, :not_owner}

  @doc false
  def correlated?(session, stage, floor, event, payload) when is_map(payload) do
    wire_stage =
      if event == :error and payload[:stage] == :extraction, do: :validator, else: payload[:stage]

    version = payload[:boundary_version]

    event in [Map.get(@stage_events, stage), :error] and wire_stage == stage and
      payload[:conversation_id] == session.conversation_id and
      payload[:run_ref] == session.run_ref and payload[:request_ref] == session.request_ref and
      is_integer(version) and version > floor
  end

  def correlated?(_, _, _, _, _), do: false

  @doc false
  def reconcile(session, stage, floor) do
    case Conversations.get_for_user(session.conversation_id, session.user_id) do
      nil ->
        :pending

      record ->
        control = control(record)
        version = control["boundary_version"] || 0

        if control["run_ref"] == session.run_ref and control["request_ref"] == session.request_ref and
             version > floor do
          durable_outcome(session, stage, floor, record, control)
        else
          :pending
        end
    end
  end

  defp durable_outcome(session, stage, floor, record, control) do
    messages = Conversations.list_messages(record.id)

    error =
      Enum.find(Enum.reverse(messages), fn message ->
        meta = message.metadata || %{}
        meta["type"] == "error"
      end)

    cond do
      record.status == "error" and not is_nil(error) and
          error.metadata["stage"] == to_string(stage) ->
        {:error, {:stage_failed, stage, error.metadata["reason"]}}

      stage == :validator ->
        payload =
          durable_payload(session, stage, control["boundary_version"])
          |> Map.put(:validated_data, record.validated_data)

        if control["pending_stage"] == nil do
          {:waiting, Map.put(payload, :status, :needs_data)}
        else
          {:ok, payload}
        end

      true ->
        field = Map.fetch!(@stage_fields, stage)

        result =
          if stage == :research do
            Enum.find_value(Enum.reverse(messages), fn message ->
              metadata = message.metadata || %{}

              if metadata["type"] == "market_research" and not metadata["superseded"],
                do: metadata["result"]
            end)
          else
            Map.get(record, field)
          end

        meta = if is_map(result), do: result["_meta"] || %{}, else: %{}
        version = meta["boundary_version"]

        if meta["stage"] == to_string(stage) and meta["run_ref"] == session.run_ref and
             meta["request_ref"] == session.request_ref and is_integer(version) and
             version > floor and version <= control["boundary_version"] do
          {:ok, Map.put(durable_payload(session, stage, version), field, result)}
        else
          :pending
        end
    end
  end

  defp durable_payload(session, stage, version),
    do: %{
      conversation_id: session.conversation_id,
      run_ref: session.run_ref,
      request_ref: session.request_ref,
      stage: stage,
      boundary_version: version
    }

  defp control(record), do: (record.validated_data || %{})["_pipeline"] || %{}

  defp stage_versions(record) do
    messages = Conversations.list_messages(record.id)

    results =
      for {stage, field} <- @stage_fields, into: %{} do
        result =
          if stage == :research do
            Enum.find_value(Enum.reverse(messages), fn message ->
              metadata = message.metadata || %{}

              if metadata["type"] == "market_research" and not metadata["superseded"],
                do: metadata["result"]
            end)
          else
            Map.get(record, field)
          end

        {stage, if(is_map(result), do: get_in(result, ["_meta", "boundary_version"]))}
      end

    results = Map.reject(results, fn {_stage, version} -> not is_integer(version) end)

    if map_size(Map.delete(record.validated_data || %{}, "_pipeline")) > 0 do
      Map.put(results, :validator, control(record)["boundary_version"] || 0)
    else
      results
    end
  end

  @doc "Closes only this lease and observer, leaving accepted stage work alive."
  def close(%__MODULE__{owner: owner} = session) when owner == self() do
    try do
      GenServer.call(session.pid, {:release_step, session.lease_ref})
    catch
      :exit, _ -> :ok
    after
      stop_observer(session.observer)
    end
  end

  def close(%__MODULE__{}), do: {:error, :not_owner}

  defp stop_observer(observer) do
    if Process.alive?(observer), do: GenServer.stop(observer, :normal)
    :ok
  catch
    :exit, _ -> :ok
  end

  defp attach(record, user_id, deadline) do
    with true <- remaining(deadline) > 0,
         {:ok, pid} <- Conversation.ensure_step_started(record.id, user_id),
         true <- remaining(deadline) > 0,
         {:ok, observer} <- Observer.start(self(), pid, Conversation.topic(record.id), deadline) do
      lease = make_ref()

      try do
        case GenServer.call(
               pid,
               {:claim_step, user_id, self(), observer, lease},
               max(remaining(deadline), 1)
             ) do
          {:ok, binding} ->
            session =
              struct!(
                __MODULE__,
                Map.merge(binding, %{
                  deadline: deadline,
                  owner: self(),
                  conversation_id: record.id,
                  user_id: user_id,
                  pid: pid,
                  observer: observer,
                  monitor_ref: GenServer.call(observer, :monitor_ref),
                  topic: Conversation.topic(record.id),
                  lease_ref: lease,
                  stage_versions: stage_versions(record)
                })
              )

            if remaining(deadline) > 0 do
              {:ok, session}
            else
              close(session)
              {:error, {:timeout, :open}}
            end

          error ->
            stop_observer(observer)
            error
        end
      catch
        :exit, reason ->
          stop_observer(observer)

          if remaining(deadline) == 0,
            do: {:error, {:timeout, :open}},
            else: {:error, {:open_failed, reason}}
      end
    else
      false -> {:error, {:timeout, :open}}
      error -> error
    end
  end

  defmodule Observer do
    @moduledoc false
    use GenServer
    alias Fullstack.JidoMarketAgents.Conversations.Step

    def start(owner, pid, topic, deadline),
      do: GenServer.start(__MODULE__, {owner, pid, topic, deadline})

    @impl true
    def init({owner, pid, topic, deadline}) do
      :ok = Phoenix.PubSub.subscribe(Fullstack.PubSub, topic)

      deadline_timer =
        Process.send_after(
          self(),
          :expired,
          max(deadline - System.monotonic_time(:millisecond), 0)
        )

      {:ok,
       %{
         topic: topic,
         deadline: deadline,
         deadline_timer: deadline_timer,
         owner: owner,
         owner_ref: Process.monitor(owner),
         runtime_ref: Process.monitor(pid),
         waiting: nil,
         poll_timer: nil,
         versions: %{}
       }}
    end

    @impl true
    def handle_call(:monitor_ref, _from, state), do: {:reply, state.runtime_ref, state}

    def handle_call({:wait, session, stage}, {owner, _} = from, state) do
      if owner == state.owner and is_nil(state.waiting) do
        floor =
          Enum.max([
            session.boundary_version,
            Map.get(session.stage_versions, stage, 0),
            Map.get(state.versions, stage, 0)
          ])

        waiting = %{session: session, stage: stage, floor: floor, from: from}
        check(%{state | waiting: waiting})
      else
        {:reply, {:error, :already_waiting}, state}
      end
    end

    @impl true
    def handle_info(:expired, %{waiting: nil} = state), do: {:stop, :normal, state}

    def handle_info(:expired, state) do
      {:noreply, state} = check(state)
      {:stop, :normal, state}
    end

    def handle_info(:reconcile, state), do: check(%{state | poll_timer: nil})

    def handle_info({event, payload}, %{waiting: waiting} = state) when not is_nil(waiting) do
      if Step.correlated?(waiting.session, waiting.stage, waiting.floor, event, payload) do
        if event == :error do
          finish(state, {:error, {:stage_failed, waiting.stage, payload[:reason]}})
        else
          check(state)
        end
      else
        {:noreply, state}
      end
    end

    def handle_info({:DOWN, _, :process, _, _}, state), do: {:stop, :normal, state}
    def handle_info(_event, state), do: {:noreply, state}

    defp check(%{waiting: nil} = state), do: {:noreply, state}

    defp check(%{waiting: waiting} = state) do
      case Step.reconcile(waiting.session, waiting.stage, waiting.floor) do
        :pending ->
          if state.deadline <= System.monotonic_time(:millisecond) do
            finish(state, {:error, {:timeout, waiting.stage}})
          else
            if state.poll_timer, do: Process.cancel_timer(state.poll_timer)
            delay = min(20, state.deadline - System.monotonic_time(:millisecond)) |> max(0)
            {:noreply, %{state | poll_timer: Process.send_after(self(), :reconcile, delay)}}
          end

        result ->
          finish(state, result)
      end
    end

    defp finish(%{waiting: waiting} = state, {tag, payload}) when tag in [:ok, :waiting] do
      if state.poll_timer, do: Process.cancel_timer(state.poll_timer)
      version = payload.boundary_version
      versions = Map.put(waiting.session.stage_versions, waiting.stage, version)

      updated = %{
        waiting.session
        | stage_versions: versions,
          boundary_version: max(waiting.session.boundary_version, version)
      }

      GenServer.reply(waiting.from, {tag, payload, updated})

      {:noreply,
       %{
         state
         | waiting: nil,
           poll_timer: nil,
           versions: Map.put(state.versions, waiting.stage, version)
       }}
    end

    defp finish(%{waiting: waiting} = state, error) do
      if state.poll_timer, do: Process.cancel_timer(state.poll_timer)
      GenServer.reply(waiting.from, error)
      {:noreply, %{state | waiting: nil, poll_timer: nil}}
    end

    @impl true
    def terminate(_reason, state) do
      Process.cancel_timer(state.deadline_timer)
      if state.poll_timer, do: Process.cancel_timer(state.poll_timer)
      Process.demonitor(state.owner_ref, [:flush])
      Process.demonitor(state.runtime_ref, [:flush])
      Phoenix.PubSub.unsubscribe(Fullstack.PubSub, state.topic)
    end
  end
end
