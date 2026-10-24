defmodule Fullstack.JidoMarketAgents.ConversationsStepTest do
  use Fullstack.DataCase, async: false
  import Fullstack.AccountsFixtures

  alias Fullstack.JidoMarketAgents.{Conversation, Conversations}
  alias Fullstack.JidoMarketAgents.Conversations.Step

  defmodule BlockingBackend do
    @behaviour Fullstack.JidoMarketAgents.LLM.Backend
    def capabilities(_), do: [:json_object]
    def validate_config(_), do: :ok

    def chat_completion(_messages, opts) do
      send(opts[:owner], {:provider, self()})

      receive do
        {:reply, result} -> {:ok, Jason.encode!(result)}
      end
    end
  end

  test "open/3 with nil creates an owned idle manual session token" do
    user = user_fixture()
    assert {:ok, session} = Step.open(user.id, nil, [])
    assert session.user_id == user.id
    assert session.mode == :manual
    assert is_pid(session.pid) and Process.alive?(session.pid)
    assert is_pid(session.observer) and session.observer != self()
    assert is_reference(session.monitor_ref)
    assert is_reference(session.lease_ref)
    assert {:ok, _} = Ecto.UUID.cast(session.run_ref)
    assert session.topic == Conversation.topic(session.conversation_id)
    assert session.stage_versions == %{}
    assert [record] = Conversations.list_for_user(user.id)
    assert record.id == session.conversation_id
    assert record.status == :idle
    assert record.validated_data["_pipeline"]["run_ref"] == session.run_ref
    refute inspect(record.validated_data) =~ "#Reference"
    state = :sys.get_state(session.pid)
    assert state.user_id == user.id
    assert state.mode == :manual
    assert state.task == nil and state.queue == []
    assert Conversations.list_messages(record.id) == []
    stop_runtime(session)
  end

  test "open/3 returns not_found for missing and foreign-owned ids without leakage" do
    user = user_fixture()
    other = user_fixture()
    {:ok, foreign} = Conversations.create(other.id)
    {:ok, owned} = Conversations.create(user.id)
    missing = Ecto.UUID.generate()

    for id <- [missing, foreign.id, "not-a-uuid"] do
      assert {:error, :not_found} = Step.open(user.id, id, [])
      assert Registry.lookup(Fullstack.JidoMarketAgents.ConversationRegistry, id) == []
    end

    assert {:ok, session} = Step.open(user.id, owned.id, [])
    assert session.conversation_id == owned.id
    assert :sys.get_state(session.pid).user_id == user.id
    assert length(Conversations.list_for_user(user.id)) == 1
    stop_runtime(session)
  end

  test "open/3 returns already_running while any stage or manual lease is active" do
    user = user_fixture()
    {:ok, session} = Step.open(user.id, nil, [])
    assert {:error, :already_running} = Step.open(user.id, session.conversation_id, [])

    assert {:error, :already_running} =
             Conversation.send_message(session.conversation_id, "automatic")

    stop_runtime(session)

    {:ok, record} = Conversations.create(user.id)
    parent = self()

    callers =
      for _ <- 1..2 do
        spawn(fn ->
          receive do
            :open -> send(parent, {:opened, self(), Step.open(user.id, record.id, [])})
          end

          receive do
            :stop -> :ok
          end
        end)
      end

    Enum.each(callers, &send(&1, :open))
    assert_receive {:opened, a, first}, 1_000
    assert_receive {:opened, b, second}, 1_000
    assert Enum.count([first, second], &match?({:ok, _}, &1)) == 1
    assert Enum.count([first, second], &(&1 == {:error, :already_running})) == 1
    {:ok, winner} = Enum.find([first, second], &match?({:ok, _}, &1))
    send(a, :stop)
    send(b, :stop)
    stop_runtime(winner)

    {:ok, unbound} = Conversations.create(user.id)
    {:ok, pid} = Conversation.ensure_started(unbound.id)
    assert {:error, :not_found} = Step.open(user.id, unbound.id, [])
    assert :sys.get_state(pid).user_id == nil
    DynamicSupervisor.terminate_child(Fullstack.JidoMarketAgents.ConversationSupervisor, pid)
  end

  test "abandoned lease is released but an accepted stage must settle before another grant" do
    user = user_fixture()
    parent = self()

    owner =
      spawn(fn ->
        {:ok, session} = Step.open(user.id, nil, [])
        send(parent, {:owned_session, session})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:owned_session, session}, 1_000
    monitor = Process.monitor(owner)
    send(owner, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
    eventually(fn -> :sys.get_state(session.pid).manual_lease == nil end)
    assert :sys.get_state(session.pid).mode == :automatic
    assert {:ok, reopened} = Step.open(user.id, session.conversation_id, [])
    stop_runtime(reopened)
  end

  test "automatic work and abandoned in-flight manual work exclude new leases" do
    config = Application.get_env(:fullstack, Fullstack.JidoMarketAgents, [])

    Application.put_env(
      :fullstack,
      Fullstack.JidoMarketAgents,
      Keyword.put(config, :validator_backend, {BlockingBackend, owner: self()})
    )

    on_exit(fn -> Application.put_env(:fullstack, Fullstack.JidoMarketAgents, config) end)
    user = user_fixture()
    {:ok, record} = Conversations.create(user.id)
    {:ok, pid} = Conversation.ensure_started(record.id, user.id)
    assert {:ok, :accepted, _} = Conversation.send_message(record.id, "automatic input")
    assert_receive {:provider, worker}, 1_000
    assert {:error, :already_running} = Step.open(user.id, record.id, [])
    send(worker, {:reply, %{country: "Spain"}})
    eventually(fn -> :sys.get_state(pid).task == nil end)
    DynamicSupervisor.terminate_child(Fullstack.JidoMarketAgents.ConversationSupervisor, pid)

    parent = self()

    owner =
      spawn(fn ->
        {:ok, session} = Step.open(user.id, nil, [])

        envelope = %{
          __pipeline_request__: true,
          mode: :manual,
          message: "manual input",
          run_ref: session.run_ref,
          request_ref: session.request_ref,
          lease_ref: session.lease_ref
        }

        {:ok, :accepted, _} = Conversation.send_message(session.conversation_id, envelope)
        send(parent, {:running_session, session})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:running_session, session}, 1_000
    assert_receive {:provider, worker}, 1_000
    send(owner, :stop)
    eventually(fn -> :sys.get_state(session.pid).manual_lease == nil end)
    assert :sys.get_state(session.pid).mode == :manual
    assert {:error, :already_running} = Step.open(user.id, session.conversation_id, [])
    send(worker, {:reply, %{country: "Spain"}})
    eventually(fn -> :sys.get_state(session.pid).task == nil end)
    assert :sys.get_state(session.pid).mode == :automatic
    assert {:ok, reopened} = Step.open(user.id, session.conversation_id, [])
    stop_runtime(reopened)
  end

  test "close/1 releases manual mode demonitor flushes and unsubscribes" do
    user = user_fixture()
    {:ok, session} = Step.open(user.id, nil, [])
    Conversation.subscribe(session.conversation_id)
    send(self(), :unrelated_message)
    Phoenix.PubSub.broadcast(Fullstack.PubSub, session.topic, {:caller_event, %{keep: true}})
    assert :ok = Step.close(session)
    refute Process.alive?(session.observer)
    assert :sys.get_state(session.pid).manual_lease == nil
    assert :sys.get_state(session.pid).mode == :automatic

    assert Conversations.get_for_user(session.conversation_id, user.id).validated_data[
             "_pipeline"
           ]["mode"] == "automatic"

    assert_receive :unrelated_message
    assert_receive {:caller_event, %{keep: true}}
    Phoenix.PubSub.broadcast(Fullstack.PubSub, session.topic, :still_subscribed)
    assert_receive :still_subscribed
    refute_receive {:DOWN, _, :process, _, _}, 10

    assert {:ok, newer} = Step.open(user.id, session.conversation_id, [])
    assert :ok = Step.close(%{session | run_ref: "older-returned-token"})
    assert :sys.get_state(newer.pid).manual_lease.ref == newer.lease_ref
    assert Process.alive?(newer.observer)
    assert :ok = Step.close(newer)
    assert :ok = Step.close(newer)
    stop_runtime(newer)
  end

  test "close does not kill accepted manual work or generate its descendants" do
    config = Application.get_env(:fullstack, Fullstack.JidoMarketAgents, [])

    Application.put_env(
      :fullstack,
      Fullstack.JidoMarketAgents,
      Keyword.put(config, :validator_backend, {BlockingBackend, owner: self()})
    )

    on_exit(fn -> Application.put_env(:fullstack, Fullstack.JidoMarketAgents, config) end)
    user = user_fixture()
    {:ok, session} = Step.open(user.id, nil, [])

    envelope = %{
      __pipeline_request__: true,
      mode: :manual,
      message: "manual input",
      run_ref: session.run_ref,
      request_ref: session.request_ref,
      lease_ref: session.lease_ref
    }

    assert {:ok, :accepted, _} = Conversation.send_message(session.conversation_id, envelope)
    assert_receive {:provider, worker}, 1_000
    assert :ok = Step.close(session)
    assert Process.alive?(worker)
    assert {:error, :already_running} = Step.open(user.id, session.conversation_id, [])

    send(
      worker,
      {:reply,
       %{
         country: "Spain",
         business_market: "retail",
         initial_budget: "1000 EUR",
         final_product_proposal: "Shop",
         product_price: "10 EUR",
         team_size: %{status: "unknown", count: nil, notes: nil},
         current_tools_systems: %{status: "unknown", items: []},
         repetitive_processes_pain_points: %{status: "unknown", items: []},
         digital_maturity: %{level: "unknown", evidence: nil},
         metrics_baselines: %{status: "unknown", items: []}
       }}
    )

    eventually(fn -> :sys.get_state(session.pid).task == nil end)
    assert :sys.get_state(session.pid).mode == :automatic
    assert :sys.get_state(session.pid).pending_stage == :research
    refute_receive {:provider, _}, 20
    stop_runtime(session)
  end

  test "wait ignores stale run_ref wrong stage and foreign conversation events" do
    user = user_fixture()
    {:ok, session} = Step.open(user.id, nil, [])

    current = %{
      conversation_id: session.conversation_id,
      run_ref: session.run_ref,
      request_ref: session.request_ref,
      stage: :analysis,
      boundary_version: 1,
      status: :running
    }

    parent = self()

    producer =
      spawn(fn ->
        for payload <- [
              Map.put(current, :run_ref, Ecto.UUID.generate()),
              Map.put(current, :stage, :systems),
              Map.put(current, :conversation_id, Ecto.UUID.generate()),
              Map.put(current, :request_ref, Ecto.UUID.generate()),
              Map.put(current, :boundary_version, 0)
            ] do
          Phoenix.PubSub.broadcast(Fullstack.PubSub, session.topic, {:analysis_complete, payload})
        end

        Process.sleep(40)
        persist_analysis(session, 1)
        Phoenix.PubSub.broadcast(Fullstack.PubSub, session.topic, {:analysis_complete, current})
        send(parent, :valid_boundary_committed)
      end)

    start = System.monotonic_time(:millisecond)
    assert {:ok, payload, updated} = Step.wait(session, :analysis)
    assert payload.business_analysis["summary"] == "durable"
    assert updated.stage_versions[:analysis] == 1
    assert updated.boundary_version == 1
    assert System.monotonic_time(:millisecond) - start >= 30
    assert_receive :valid_boundary_committed
    refute Process.alive?(producer)
    Step.close(updated)
    stop_runtime(updated)
  end

  test "wait reconciles a committed boundary even when PubSub delivery was dropped" do
    user = user_fixture()
    {:ok, session} = Step.open(user.id, nil, [])

    :sys.replace_state(session.observer, fn state ->
      Phoenix.PubSub.unsubscribe(Fullstack.PubSub, session.topic)
      state
    end)

    spawn(fn ->
      Process.sleep(30)
      persist_analysis(session, 1)
    end)

    assert {:ok, %{business_analysis: %{"summary" => "durable"}}, updated} =
             Step.wait(session, :analysis)

    Step.close(updated)
    stop_runtime(updated)
  end

  test "wait distinguishes a durable incomplete validation from enqueue acceptance" do
    user = user_fixture()
    {:ok, session} = Step.open(user.id, nil, [])

    envelope = %{
      __pipeline_request__: true,
      mode: :manual,
      message: %{country: "Spain"},
      run_ref: session.run_ref,
      request_ref: session.request_ref,
      lease_ref: session.lease_ref
    }

    assert {:ok, :accepted, _} = Conversation.send_message(session.conversation_id, envelope)

    assert {:waiting, %{status: :idle, lifecycle_stage: :validating, validated_data: data},
            updated} =
             Step.wait(session, :validator)

    assert data["country"] == "Spain"
    assert updated.stage_versions[:validator] == 1
    Step.close(updated)
    stop_runtime(updated)
  end

  test "stage wait returns tagged timeout without killing conversation" do
    user = user_fixture()
    assert {:error, :invalid_timeout} = Step.open(user.id, nil, timeout_ms: 0)
    config = Application.get_env(:fullstack, Fullstack.JidoMarketAgents, [])

    Application.put_env(
      :fullstack,
      Fullstack.JidoMarketAgents,
      Keyword.put(config, :validator_backend, {BlockingBackend, owner: self()})
    )

    on_exit(fn -> Application.put_env(:fullstack, Fullstack.JidoMarketAgents, config) end)
    {:ok, session} = Step.open(user.id, nil, timeout_ms: 300)

    envelope = %{
      __pipeline_request__: true,
      mode: :manual,
      message: "blocked",
      run_ref: session.run_ref,
      request_ref: session.request_ref,
      lease_ref: session.lease_ref
    }

    assert {:ok, :accepted, _} = Conversation.send_message(session.conversation_id, envelope)
    assert_receive {:provider, worker}, 1_000
    Process.sleep(180)
    observer = session.observer

    flood =
      spawn(fn ->
        for _ <- 1..15 do
          send(observer, {:extraction_complete, %{run_ref: "stale"}})
          Process.sleep(5)
        end
      end)

    start = System.monotonic_time(:millisecond)
    assert {:error, {:timeout, :validator}} = Step.wait(session, :validator)
    assert System.monotonic_time(:millisecond) - start < 180
    eventually(fn -> not Process.alive?(session.observer) end)
    assert Process.alive?(session.pid) and Process.alive?(worker)
    assert :sys.get_state(session.pid).manual_lease == nil
    send(worker, {:reply, %{country: "Spain"}})
    eventually(fn -> :sys.get_state(session.pid).task == nil end)
    eventually(fn -> not Process.alive?(flood) end)

    assert Conversations.get_for_user(session.conversation_id, user.id).validated_data["country"] ==
             "Spain"

    stop_runtime(session)
  end

  test "finite positive timeout is validated before any record is created" do
    user = user_fixture()

    for timeout <- [0, -1, :infinity, nil, 1.5, "100"] do
      assert {:error, :invalid_timeout} = Step.open(user.id, nil, timeout_ms: timeout)
    end

    assert Conversations.list_for_user(user.id) == []
  end

  test "the session deadline includes think time and does not renew after a completion" do
    user = user_fixture()
    {:ok, session} = Step.open(user.id, nil, timeout_ms: 120)
    persist_analysis(session, 1)
    assert {:ok, _, updated} = Step.wait(session, :analysis)
    assert updated.deadline == session.deadline
    Process.sleep(130)
    start = System.monotonic_time(:millisecond)
    assert {:error, {:timeout, :systems}} = Step.wait(updated, :systems)
    assert System.monotonic_time(:millisecond) - start < 50
    refute Process.alive?(session.observer)
    assert :sys.get_state(session.pid).manual_lease == nil
    stop_runtime(session)
  end

  test "manual admission uses the same deadline and cannot leave a late orphan grant" do
    user = user_fixture()
    {:ok, record} = Conversations.create(user.id)
    {:ok, pid} = Conversation.ensure_started(record.id, user.id)
    :ok = :sys.suspend(pid)
    assert {:error, {:timeout, :open}} = Step.open(user.id, record.id, timeout_ms: 30)
    :ok = :sys.resume(pid)
    eventually(fn -> :sys.get_state(pid).manual_lease == nil end)
    assert :sys.get_state(pid).mode == :automatic
    DynamicSupervisor.terminate_child(Fullstack.JidoMarketAgents.ConversationSupervisor, pid)
  end

  test "monitored process death returns tagged stage error and cleans observer state" do
    user = user_fixture()
    {:ok, session} = Step.open(user.id, nil, [])
    Conversation.subscribe(session.conversation_id)

    killer =
      spawn(fn ->
        eventually(fn -> :sys.get_state(session.observer).waiting != nil end)
        Process.exit(session.pid, :kill)
      end)

    assert {:error, {:process_down, :analysis, :killed}} = Step.wait(session, :analysis)
    eventually(fn -> not Process.alive?(session.observer) end)
    refute Process.alive?(session.pid)
    eventually(fn -> not Process.alive?(killer) end)
    Phoenix.PubSub.broadcast(Fullstack.PubSub, session.topic, :caller_subscription_survives)
    assert_receive :caller_subscription_survives
    refute_receive {:DOWN, _, :process, _, _}, 10
    assert :ok = Step.close(session)

    eventually(fn ->
      Registry.lookup(Fullstack.JidoMarketAgents.ConversationRegistry, session.conversation_id) !=
        []
    end)

    [{restarted, _}] =
      Registry.lookup(Fullstack.JidoMarketAgents.ConversationRegistry, session.conversation_id)

    assert restarted != session.pid
    assert :sys.get_state(restarted).manual_lease == nil

    DynamicSupervisor.terminate_child(
      Fullstack.JidoMarketAgents.ConversationSupervisor,
      restarted
    )
  end

  test "runtime death before waiting retains its tagged reason without reattaching" do
    user = user_fixture()
    {:ok, session} = Step.open(user.id, nil, [])

    :ok =
      DynamicSupervisor.terminate_child(
        Fullstack.JidoMarketAgents.ConversationSupervisor,
        session.pid
      )

    assert {:error, {:process_down, :research, :shutdown}} = Step.wait(session, :research)
    refute Process.alive?(session.observer)

    assert Registry.lookup(
             Fullstack.JidoMarketAgents.ConversationRegistry,
             session.conversation_id
           ) == []
  end

  test "unexpected observer death uses the same non-destructive cleanup" do
    user = user_fixture()
    {:ok, session} = Step.open(user.id, nil, [])
    Process.exit(session.observer, :kill)
    eventually(fn -> not Process.alive?(session.observer) end)
    assert {:error, {:observer_down, :systems}} = Step.wait(session, :systems)
    eventually(fn -> :sys.get_state(session.pid).manual_lease == nil end)
    assert Process.alive?(session.pid)
    stop_runtime(session)
  end

  test "an idle durable automatic pending stage can be claimed without automatic resume" do
    user = user_fixture()

    {:ok, record} =
      Conversations.create(user.id, %{
        validated_data: %{
          "_pipeline" => %{
            "mode" => "automatic",
            "run_ref" => Ecto.UUID.generate(),
            "request_ref" => Ecto.UUID.generate(),
            "boundary_version" => 1,
            "pending_stage" => "research"
          },
          "country" => "Spain",
          "business_market" => "retail",
          "initial_budget" => "1000 EUR",
          "final_product_proposal" => "Shop",
          "product_price" => "10 EUR",
          "team_size" => %{"status" => "unknown", "count" => nil, "notes" => nil},
          "current_tools_systems" => %{"status" => "unknown", "items" => []},
          "repetitive_processes_pain_points" => %{"status" => "unknown", "items" => []},
          "digital_maturity" => %{"level" => "unknown", "evidence" => nil},
          "metrics_baselines" => %{"status" => "unknown", "items" => []}
        }
      })

    assert {:ok, session} = Step.open(user.id, record.id, [])
    assert :sys.get_state(session.pid).task == nil
    assert :sys.get_state(session.pid).mode == :manual
    Step.close(session)
    assert {:ok, reopened} = Step.open(user.id, record.id, [])
    Step.close(reopened)
    stop_runtime(reopened)
  end

  test "a correlated persistence failure at the unadvanced boundary terminates the wait" do
    user = user_fixture()
    {:ok, session} = Step.open(user.id, nil, timeout_ms: 150)

    spawn(fn ->
      eventually(fn -> :sys.get_state(session.observer).waiting != nil end)

      Phoenix.PubSub.broadcast(
        Fullstack.PubSub,
        session.topic,
        {:error,
         %{
           conversation_id: session.conversation_id,
           run_ref: session.run_ref,
           request_ref: session.request_ref,
           stage: :extraction,
           boundary_version: session.boundary_version,
           durability: :failed,
           reason: {:stage_failed, :persistence_failed}
         }}
      )
    end)

    assert {:error, {:stage_failed, :validator, :persistence_failed}} =
             Step.wait(session, :validator)

    refute Process.alive?(session.observer)
    assert :sys.get_state(session.pid).manual_lease == nil
    stop_runtime(session)
  end

  test "manual startup suppression is one-shot so closing preserves automatic crash recovery" do
    config = Application.get_env(:fullstack, Fullstack.JidoMarketAgents, [])

    Application.put_env(
      :fullstack,
      Fullstack.JidoMarketAgents,
      Keyword.put(config, :researcher_backend, {BlockingBackend, owner: self()})
    )

    on_exit(fn -> Application.put_env(:fullstack, Fullstack.JidoMarketAgents, config) end)
    user = user_fixture()
    {:ok, session} = Step.open(user.id, nil, [])
    pid = session.pid

    on_exit(fn ->
      for {runtime, _} <-
            Registry.lookup(
              Fullstack.JidoMarketAgents.ConversationRegistry,
              session.conversation_id
            ),
          do:
            DynamicSupervisor.terminate_child(
              Fullstack.JidoMarketAgents.ConversationSupervisor,
              runtime
            )
    end)

    :sys.replace_state(pid, fn state ->
      %{
        state
        | pending_stage: :research,
          validated_data: %{
            country: "Spain",
            business_market: "retail",
            initial_budget: "1000 EUR",
            final_product_proposal: "Shop",
            product_price: "10 EUR",
            team_size: %{status: "unknown", count: nil, notes: nil},
            current_tools_systems: %{status: "unknown", items: []},
            repetitive_processes_pain_points: %{status: "unknown", items: []},
            digital_maturity: %{level: "unknown", evidence: nil},
            metrics_baselines: %{status: "unknown", items: []}
          }
      }
    end)

    assert :ok = Step.close(session)
    Process.exit(pid, :kill)
    assert_receive {:provider, worker}, 1_000
    assert Process.alive?(worker)

    [{restarted, _}] =
      Registry.lookup(Fullstack.JidoMarketAgents.ConversationRegistry, session.conversation_id)

    assert restarted != pid
    assert :sys.get_state(restarted).task_stage == :research

    DynamicSupervisor.terminate_child(
      Fullstack.JidoMarketAgents.ConversationSupervisor,
      restarted
    )
  end

  defp persist_analysis(session, version) do
    record = Conversations.get_for_user(session.conversation_id, session.user_id)

    control =
      Map.merge(record.validated_data["_pipeline"], %{
        "boundary_version" => version,
        "run_ref" => session.run_ref,
        "request_ref" => session.request_ref,
        "pending_stage" => "systems"
      })

    result = %{
      "summary" => "durable",
      "_meta" => %{
        "stage" => "analysis",
        "boundary_version" => version,
        "run_ref" => session.run_ref,
        "request_ref" => session.request_ref
      }
    }

    assert {:ok, _} =
             Conversations.update_state(record, %{
               business_analysis: result,
               validated_data: Map.put(record.validated_data, "_pipeline", control)
             })
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, attempts) do
    if fun.(),
      do: :ok,
      else:
        (
          Process.sleep(5)
          eventually(fun, attempts - 1)
        )
  end

  defp stop_runtime(session) do
    if Process.alive?(session.observer), do: GenServer.stop(session.observer)

    if Process.alive?(session.pid),
      do:
        DynamicSupervisor.terminate_child(
          Fullstack.JidoMarketAgents.ConversationSupervisor,
          session.pid
        )
  end
end
