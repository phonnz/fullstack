defmodule Fullstack.JidoMarketAgents.Telemetry.Reporter do
  @moduledoc """
  Renders the market-agents telemetry events as readable log lines.

  This is the "show us the process" half of the instrumentation: the
  probes in `Fullstack.JidoMarketAgents.Telemetry` carry the data, and
  this handler turns it into a trace a human can read while clicking
  through the LiveView.

  Each line is prefixed with a short correlation tag so one conversation
  can be followed with a plain `grep`:

      [agents abc12345] message.received      user_id=7 bytes=42
      [agents abc12345] buffer.flushed        batch=1 debounce_ms=45000
      [agents abc12345] rate_limit.decided    verdict=allow
      [agents abc12345] message.forwarded
      [agents abc12345] validation.start
      [agents abc12345] validation.stop       ok 1284ms
      [agents abc12345] validation.incomplete missing=initial_budget,product_price
      [agents abc12345] broadcast.emitted     extraction_complete stage=validating status=idle msgs=2
      [agents abc12345] liveview.handled      extraction_complete phase=idle

  Reading a trace: each stage should appear once per turn, in that order.
  A missing line localizes the stall to the hop before it — a
  `message.received` with no `buffer.flushed` 45s later means the debounce
  window swallowed it; a `broadcast.emitted` with no `liveview.handled`
  means the UI never matched the payload.

  Deliberately a `Logger` handler and not a metrics store: the immediate
  need is seeing the process, and the events are reusable later for
  storage without touching any call site.
  """

  require Logger

  alias Fullstack.JidoMarketAgents.Telemetry, as: AgentTelemetry

  @handler_id "fullstack-jido-market-agents-reporter"

  @doc """
  Attaches the handler to every advertised event.

  Idempotent: attaching when already attached is a no-op, so this is safe
  to call from application start and again from an IEx session.
  """
  @spec attach() :: :ok
  def attach do
    case :telemetry.attach_many(
           @handler_id,
           AgentTelemetry.events(),
           &__MODULE__.handle_event/4,
           nil
         ) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @doc "Detaches the handler. Safe to call when not attached."
  @spec detach() :: :ok
  def detach do
    _ = :telemetry.detach(@handler_id)
    :ok
  end

  @doc false
  # A telemetry handler runs INSIDE the process that emitted the event, so
  # a crash here would take down a Conversation GenServer mid-turn and
  # :telemetry would detach the handler. Observability must never be able
  # to break the thing it observes, so the whole body is wrapped: a
  # formatting bug degrades to one warning instead of a lost conversation.
  def handle_event(event, measurements, metadata, _config) do
    stage = event |> Enum.drop(2) |> Enum.join(".")

    Logger.info([
      "[agents ",
      correlation(metadata),
      "] ",
      String.pad_trailing(stage, 22),
      " ",
      details(stage, measurements, metadata)
    ])
  rescue
    error ->
      Logger.warning(
        "market-agents telemetry reporter failed to format #{inspect(event)}: " <>
          Exception.message(error)
      )
  end

  # Only the id's leading segment is shown. A UUID is too wide to scan down
  # a column of log lines, and the prefix is already unique enough to
  # follow one conversation among the handful a dev session produces.
  defp correlation(%{conversation_id: id}) when is_binary(id), do: String.slice(id, 0, 8)
  defp correlation(%{conversation_id: id}), do: id |> inspect() |> String.slice(0, 8)
  defp correlation(_metadata), do: "--------"

  # Per-stage detail. Each clause reports the facts that make THAT hop's
  # outcome diagnosable, rather than dumping the whole metadata map, so the
  # trace stays scannable.

  defp details("message.received", _measurements, metadata) do
    ["user_id=", to_text(metadata[:user_id]), " ", message_shape(metadata[:message])]
  end

  defp details("buffer.flushed", measurements, metadata) do
    [
      "batch=",
      to_text(measurements[:batch_size]),
      " debounce_ms=",
      to_text(metadata[:debounce_ms])
    ]
  end

  defp details("rate_limit.decided", _measurements, metadata) do
    ["verdict=", to_text(metadata[:verdict])]
  end

  defp details("validation.incomplete", _measurements, metadata) do
    ["missing=", metadata[:missing_fields] |> List.wrap() |> Enum.map_join(",", &to_text/1)]
  end

  defp details("broadcast.emitted", _measurements, metadata) do
    [
      to_text(metadata[:event]),
      " stage=",
      to_text(metadata[:lifecycle_stage]),
      " status=",
      to_text(metadata[:status]),
      " msgs=",
      to_text(metadata[:message_count])
    ]
  end

  defp details("liveview.handled", _measurements, metadata) do
    [to_text(metadata[:event]), " phase=", to_text(metadata[:phase])]
  end

  # The silent-drop probe. Logged at :warning because, unlike every other
  # line here, it means a response WAS produced and the UI threw it away.
  defp details("liveview.dropped", _measurements, metadata) do
    Logger.warning(
      "[agents #{correlation(metadata)}] liveview DROPPED an unmatched broadcast: " <>
        inspect(metadata[:payload], limit: 5)
    )

    ["unmatched=", to_text(metadata[:event])]
  end

  # New stage traces expose only control data, never model bodies or exception text.
  defp details(stage, measurements, metadata)
       when stage in ~w(analysis.start analysis.stop analysis.exception systems.start systems.stop systems.exception tech_strategy.start tech_strategy.stop tech_strategy.exception) do
    [
      "run=",
      to_text(metadata[:run_ref]),
      " mode=",
      to_text(metadata[:mode]),
      " status=",
      to_text(metadata[:status]),
      " ",
      to_text(metadata[:result] || metadata[:kind]),
      " ",
      safe_reason(metadata[:reason]),
      " ",
      duration_text(measurements)
    ]
  end

  # Timed stages: *.stop carries the outcome, which is where an error that
  # produced no response becomes visible.
  defp details(stage, measurements, metadata) do
    cond do
      String.ends_with?(stage, ".stop") ->
        [outcome_text(metadata), " ", duration_text(measurements)]

      String.ends_with?(stage, ".exception") ->
        [
          "EXCEPTION ",
          duration_text(measurements),
          " ",
          inspect(metadata[:reason], limit: 3)
        ]

      true ->
        []
    end
  end

  defp safe_reason(reason) when is_atom(reason), do: to_text(reason)
  defp safe_reason(reason) when is_tuple(reason), do: safe_reason(elem(reason, 0))
  defp safe_reason(_reason), do: "redacted"

  defp outcome_text(%{result: :error, reason: reason}), do: ["ERROR ", inspect(reason, limit: 3)]
  defp outcome_text(%{result: :error}), do: "ERROR"
  defp outcome_text(_metadata), do: "ok"

  defp duration_text(%{duration: duration}) when is_integer(duration) do
    ms = System.convert_time_unit(duration, :native, :millisecond)
    [to_text(ms), "ms"]
  end

  defp duration_text(_measurements), do: ""

  # The pipeline accepts a string message (LLM extraction) or a map (fast
  # path, no LLM call). Which one it is changes the expected trace, so the
  # shape is reported instead of the content — message bodies are user
  # data and do not belong in logs.
  defp message_shape(message) when is_binary(message), do: "bytes=#{byte_size(message)}"
  defp message_shape(message) when is_map(message), do: "map_keys=#{map_size(message)}"
  defp message_shape(_message), do: "shape=unknown"

  defp to_text(nil), do: "-"
  defp to_text(value) when is_binary(value), do: value
  defp to_text(value) when is_atom(value), do: Atom.to_string(value)
  defp to_text(value) when is_integer(value), do: Integer.to_string(value)
  defp to_text(value), do: inspect(value)
end
