defmodule Fullstack.JidoMarketAgents.TelemetryTest do
  @moduledoc """
  Behavior tests for the market-agents telemetry vocabulary and its
  development-time logging handler.

  These tests assert on the CONTRACT the pipeline depends on — that every
  stage emits a named event carrying the correlation id, and that a stage
  which produces no response still leaves a trace — not on log formatting.
  """
  use ExUnit.Case, async: false

  alias Fullstack.JidoMarketAgents.Telemetry, as: AgentTelemetry

  setup do
    # Each test attaches its own handler under a unique id and detaches on
    # exit, so a failing test can never leak a handler into another test.
    handler_id = "test-#{System.unique_integer([:positive])}"
    test_pid = self()

    :telemetry.attach_many(
      handler_id,
      AgentTelemetry.events(),
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok
  end

  describe "events/0" do
    test "events/0 advertises analysis systems and tech_strategy spans" do
      for stage <- [:analysis, :systems, :tech_strategy], suffix <- [:start, :stop, :exception] do
        assert [:fullstack, :jido_market_agents, stage, suffix] in AgentTelemetry.events()
      end
    end

    test "new stage reporter details omit result bodies and private error contents" do
      level = Logger.level()
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: level) end)

      log =
        ExUnit.CaptureLog.capture_log([level: :info], fn ->
          Fullstack.JidoMarketAgents.Telemetry.Reporter.handle_event(
            [:fullstack, :jido_market_agents, :analysis, :stop],
            %{duration: 1_000_000},
            %{
              conversation_id: "abc",
              run_ref: "run-1",
              mode: :manual,
              status: :active,
              result: :error,
              reason: {:parse_failed, "private customer facts"}
            },
            nil
          )
        end)

      assert log =~ "run=run-1"
      assert log =~ "mode=manual"
      assert log =~ "status=active"
      assert log =~ "parse_failed"
      refute log =~ "private customer facts"
    end

    test "every advertised event is a non-empty list of atoms under the agents prefix" do
      events = AgentTelemetry.events()

      assert events != []

      for event <- events do
        assert [:fullstack, :jido_market_agents | rest] = event
        assert rest != []
        assert Enum.all?(event, &is_atom/1)
      end
    end

    test "advertised events are unique" do
      events = AgentTelemetry.events()
      assert length(Enum.uniq(events)) == length(events)
    end

    test "the stages that can silently drop a response are all covered" do
      events = AgentTelemetry.events()

      # Each of these corresponds to a point the investigation identified as
      # able to swallow a response with no trace. If a stage is removed from
      # the vocabulary, this test fails rather than the gap going unnoticed.
      for required <- [
            [:fullstack, :jido_market_agents, :message, :received],
            [:fullstack, :jido_market_agents, :buffer, :flushed],
            [:fullstack, :jido_market_agents, :validation, :stop],
            [:fullstack, :jido_market_agents, :validation, :incomplete],
            [:fullstack, :jido_market_agents, :research, :stop],
            [:fullstack, :jido_market_agents, :broadcast, :emitted],
            [:fullstack, :jido_market_agents, :liveview, :dropped]
          ] do
        assert required in events, "missing telemetry event: #{inspect(required)}"
      end
    end
  end

  describe "emit/3" do
    test "emits an advertised event with its measurements and metadata" do
      AgentTelemetry.emit(
        [:fullstack, :jido_market_agents, :message, :received],
        %{count: 1},
        %{conversation_id: "abc"}
      )

      assert_receive {:telemetry_event, [:fullstack, :jido_market_agents, :message, :received],
                      %{count: 1}, metadata}

      assert metadata.conversation_id == "abc"
    end

    test "stamps a monotonic system_time measurement so events can be ordered" do
      AgentTelemetry.emit(
        [:fullstack, :jido_market_agents, :message, :received],
        %{},
        %{conversation_id: "abc"}
      )

      assert_receive {:telemetry_event, _event, measurements, _metadata}
      assert is_integer(measurements.system_time)
    end

    test "raises on an event outside the advertised vocabulary" do
      # A typo'd event name would otherwise emit into the void — no handler
      # is attached to it, so it would look exactly like a working probe.
      assert_raise ArgumentError, ~r/not an advertised/, fn ->
        AgentTelemetry.emit([:fullstack, :jido_market_agents, :nope], %{}, %{})
      end
    end
  end

  describe "span/3" do
    test "emits a start and a stop event around a successful function" do
      result =
        AgentTelemetry.span(:validation, %{conversation_id: "abc"}, fn ->
          {:ok, :extracted}
        end)

      assert result == {:ok, :extracted}

      assert_receive {:telemetry_event, [:fullstack, :jido_market_agents, :validation, :start], _,
                      %{conversation_id: "abc"}}

      assert_receive {:telemetry_event, [:fullstack, :jido_market_agents, :validation, :stop],
                      measurements, metadata}

      assert is_integer(measurements.duration)
      assert metadata.result == :ok
    end

    test "tags the stop event as an error when the function returns an error tuple" do
      # This is the case the user is chasing: the stage RAN but produced no
      # usable response. It must be distinguishable from success in the
      # trace, not merely absent.
      result =
        AgentTelemetry.span(:validation, %{conversation_id: "abc"}, fn ->
          {:error, :llm_failed}
        end)

      assert result == {:error, :llm_failed}

      assert_receive {:telemetry_event, [:fullstack, :jido_market_agents, :validation, :stop], _,
                      metadata}

      assert metadata.result == :error
      assert metadata.reason == :llm_failed
    end

    test "emits an exception event and re-raises when the function raises" do
      assert_raise RuntimeError, "boom", fn ->
        AgentTelemetry.span(:research, %{conversation_id: "abc"}, fn ->
          raise "boom"
        end)
      end

      assert_receive {:telemetry_event, [:fullstack, :jido_market_agents, :research, :exception],
                      measurements, metadata}

      assert is_integer(measurements.duration)
      assert metadata.kind == :error
      assert %RuntimeError{} = metadata.reason
      assert is_list(metadata.stacktrace)
    end

    test "a raise does not swallow the original stacktrace" do
      # Re-raising with the captured stacktrace keeps the real origin, so a
      # crash inside an LLM call is still debuggable from the log.
      try do
        AgentTelemetry.span(:research, %{conversation_id: "abc"}, fn -> raise "boom" end)
      rescue
        _ ->
          [{mod, fun, _arity, _loc} | _] = __STACKTRACE__
          refute {mod, fun} == {AgentTelemetry, :span}
      end
    end
  end

  describe "Reporter.attach/0" do
    test "is idempotent — attaching twice does not error" do
      assert :ok = Fullstack.JidoMarketAgents.Telemetry.Reporter.attach()
      assert :ok = Fullstack.JidoMarketAgents.Telemetry.Reporter.attach()

      on_exit(fn -> Fullstack.JidoMarketAgents.Telemetry.Reporter.detach() end)
    end
  end
end
