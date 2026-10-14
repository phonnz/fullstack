defmodule Fullstack.JidoMarketAgents.Telemetry do
  @moduledoc """
  The observability vocabulary for the market-agents conversation pipeline.

  ## Why this module exists

  The pipeline crosses asynchronous process hand-offs and then runs
  five ordered agent stages:

      LiveView ──call──▶ MessageBuffer ──timer──▶ RateLimiter ──call──▶
      Conversation ──self-send──▶ Validator (LLM) ──▶ Researcher (LLM)
               └──▶ Analyzer (LLM) ──▶ Systems (LLM) ──▶ Tech Strategy (LLM)
               └──────────────── PubSub ───────────────▶ LiveView

  Every arrow is a place a message can stop moving without anything
  crashing. A debounce timer that never fires, a cooldown queue that holds
  a message, an LLM that returns an unparseable body, a broadcast whose
  shape no `handle_info` clause matches — in all of these the system stays
  up, no exception is raised, and the user simply never sees a reply. The
  logs before this module could not distinguish them: there was no log
  line at all between "user pressed send" and "research completed", so a
  missing response looked identical regardless of which hop lost it.

  This module gives every hop a name. The point is not metrics — it is
  being able to read a single conversation's trace and see which arrow the
  message did not come out of.

  ## Design

  `:telemetry` is used rather than bare `Logger` calls for three reasons:

    1. emission is decoupled from presentation — the same probes feed the
       dev-time log (`#{inspect(__MODULE__)}.Reporter`) now and a metrics
       or storage backend later, with no changes at the call sites;
    2. a probe with no handler attached costs almost nothing, so these can
       stay in the production path;
    3. handlers are attached per-event, so a test can observe exactly the
       stage it cares about.

  `events/0` is the closed vocabulary, and `emit/3` refuses anything
  outside it. That check is deliberate: a mistyped event name is silently
  inert — it emits to no handler and looks exactly like a working probe —
  which is the same class of invisible failure this module exists to
  eliminate.

  ## Correlation

  Every event carries `:conversation_id` in its metadata. That is the join
  key across all five processes; filtering a log by one id yields the
  complete ordered story of one conversation.
  """

  @prefix [:fullstack, :jido_market_agents]

  # Stages that are timed with span/3. Each contributes :start, :stop and
  # :exception events, following the convention :telemetry.span/3 uses, so
  # standard tooling can consume them without special-casing.
  @span_stages [:validation, :research, :extraction, :analysis, :systems, :tech_strategy]

  # Discrete points that mark a hand-off rather than a timed operation.
  # These are the arrows in the diagram above.
  @discrete_events [
    # A user message entered the pipeline at the LiveView boundary.
    [:message, :received],
    # The per-user debounce window elapsed and the batch moved on. A
    # :received with no matching :flushed means the message died in the
    # debounce window.
    [:buffer, :flushed],
    # The rate limiter's verdict: allowed, queued during cooldown, or
    # denied. A :flushed with no :forwarded means the limiter is holding it.
    [:rate_limit, :decided],
    # The message reached the Conversation GenServer.
    [:message, :forwarded],
    # The validator found required fields missing and is asking the user.
    # This is a TERMINAL, SUCCESSFUL state — not a failure — and the most
    # commonly misread one, because the pipeline legitimately stops here
    # until the user replies.
    [:validation, :incomplete],
    # The validator found every required field and handed off to research.
    [:validation, :complete],
    # A PubSub broadcast left the Conversation GenServer.
    [:broadcast, :emitted],
    # A LiveView received and matched a broadcast.
    [:liveview, :handled],
    # A LiveView received a broadcast that NO clause matched, and dropped
    # it. Before this probe existed, this path was completely silent — it
    # is the single most likely explanation for a response that is produced
    # but never rendered.
    [:liveview, :dropped]
  ]

  @doc """
  The closed list of events this pipeline emits.

  Attach to these to observe the pipeline; `emit/3` rejects anything not
  in this list.
  """
  @spec events() :: [[atom()]]
  def events do
    span_events =
      for stage <- @span_stages,
          suffix <- [:start, :stop, :exception],
          do: @prefix ++ [stage, suffix]

    discrete = for event <- @discrete_events, do: @prefix ++ event

    Enum.uniq(span_events ++ discrete)
  end

  @doc """
  Emits one advertised event.

  A `:system_time` measurement is always added so events from different
  processes can be ordered against each other — the hand-offs cross
  process boundaries, so wall-clock order is the only thing that relates
  them.

  Raises `ArgumentError` if `event` is outside `events/0`, because an
  unadvertised event would be silently inert.
  """
  @spec emit([atom()], map(), map()) :: :ok
  def emit(event, measurements \\ %{}, metadata \\ %{}) do
    unless event in events() do
      raise ArgumentError,
            "#{inspect(event)} is not an advertised telemetry event. " <>
              "Add it to #{inspect(__MODULE__)} or fix the call site."
    end

    :telemetry.execute(
      event,
      Map.put_new(measurements, :system_time, System.system_time()),
      metadata
    )
  end

  @doc """
  Times `fun` as `stage`, emitting `:start`, then `:stop` or `:exception`.

  The `:stop` metadata distinguishes three outcomes, which is the whole
  point of wrapping these calls:

    * `result: :ok` — the stage produced a usable value;
    * `result: :error` with a `:reason` — the stage RAN TO COMPLETION but
      produced nothing usable. This is the case that previously vanished:
      an LLM returning an unparseable body is not a crash, so nothing was
      logged, yet no response ever reached the user;
    * `:exception` — the stage raised.

  An exception is re-raised with its original stacktrace, so instrumenting
  a call never costs the debuggability of a crash inside it.
  """
  @spec span(atom(), map(), (-> result)) :: result when result: term()
  def span(stage, metadata, fun) when stage in @span_stages and is_function(fun, 0) do
    start_time = System.monotonic_time()
    emit(@prefix ++ [stage, :start], %{}, metadata)

    try do
      fun.()
    catch
      kind, reason ->
        stacktrace = __STACKTRACE__

        emit(
          @prefix ++ [stage, :exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, %{kind: kind, reason: reason, stacktrace: stacktrace})
        )

        # Preserve the original stacktrace rather than re-raising from here.
        :erlang.raise(kind, reason, stacktrace)
    else
      result ->
        emit(
          @prefix ++ [stage, :stop],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, outcome(result))
        )

        result
    end
  end

  # A stage's outcome is read from its return shape. Only the two tuple
  # forms the pipeline actually uses are interpreted; anything else is
  # reported as :ok rather than guessed at, so this never misreports a
  # shape it does not know.
  defp outcome({:error, reason}), do: %{result: :error, reason: reason}
  defp outcome({:ok, _value}), do: %{result: :ok}
  defp outcome(:ok), do: %{result: :ok}
  defp outcome({:incomplete, fields}), do: %{result: :ok, missing_fields: fields}
  defp outcome({:complete, _data}), do: %{result: :ok}
  defp outcome(_other), do: %{result: :ok}
end
