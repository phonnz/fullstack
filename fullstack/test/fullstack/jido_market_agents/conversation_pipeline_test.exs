defmodule Fullstack.JidoMarketAgents.ConversationPipelineTest do
  use Fullstack.DataCase, async: false
  import Fullstack.AccountsFixtures
  alias Fullstack.JidoMarketAgents.{Conversation, Conversations, MessageBuffer, RateLimiter}

  defmodule Backend do
    @behaviour Fullstack.JidoMarketAgents.LLM.Backend
    def capabilities(_), do: [:json_object]
    def validate_config(_), do: :ok

    def chat_completion(messages, opts) do
      send(opts[:owner], {:provider, self(), opts[:model], messages})

      receive do
        {:reply, result} -> result
        :crash -> exit(:provider_crash)
      end
    end
  end

  setup do
    config = Application.get_env(:fullstack, Fullstack.JidoMarketAgents, [])

    updated =
      Enum.reduce([:validator, :researcher, :analyzer, :systems, :strategy], config, fn role,
                                                                                        acc ->
        Keyword.put(acc, :"#{role}_backend", {Backend, owner: self(), model: to_string(role)})
      end)

    Application.put_env(:fullstack, Fullstack.JidoMarketAgents, updated)
    on_exit(fn -> Application.put_env(:fullstack, Fullstack.JidoMarketAgents, config) end)
    user = user_fixture()
    {:ok, record} = Conversations.create(user.id)
    {:ok, pid} = Conversation.ensure_started(record.id, user.id)
    Conversation.subscribe(record.id)

    on_exit(fn ->
      if Process.alive?(pid),
        do:
          DynamicSupervisor.terminate_child(
            Fullstack.JidoMarketAgents.ConversationSupervisor,
            pid
          )
    end)

    %{id: record.id, pid: pid, user: user}
  end

  def data do
    %{
      country: "Spain",
      business_market: "fintech",
      initial_budget: "50000 EUR",
      final_product_proposal: "Payment app",
      product_price: "10 EUR",
      team_size: %{status: "unknown", count: nil, notes: nil},
      current_tools_systems: %{status: "unknown", items: []},
      repetitive_processes_pain_points: %{status: "unknown", items: []},
      digital_maturity: %{level: "unknown", evidence: nil},
      metrics_baselines: %{status: "unknown", items: []}
    }
  end

  def research,
    do: %{
      market_evidence: [],
      market_gaps: [],
      demand_signals: [],
      sources: [],
      limitations: ["No retrieval"]
    }

  defp reply(worker, result), do: send(worker, {:reply, {:ok, Jason.encode!(result)}})

  test "complete validation enqueues run_stage research", %{id: id, pid: pid} do
    :erlang.trace(pid, true, [:receive])
    Conversation.send_message(id, data())
    assert_receive {:extraction_complete, %{assessment: assessment}}, 1_000
    assert assessment.sufficient
    assert assessment.next_question == nil
    assert assessment.data.country == "Spain"
    assistant = Enum.find(Conversations.list_messages(id), &(&1.role == "assistant"))
    assert assistant.metadata["assessment"]["sufficient"] == true
    assert_receive {:trace, ^pid, :receive, {:run_stage, :research}}, 1_000
    assert_receive {:provider, worker, "researcher", _}, 1_000
    refute worker == pid
    assert {:ok, _, _} = Conversation.resume(id)
    reply(worker, research())
    assert_receive {:research_complete, %{conversation_id: ^id}}, 1_000
  end

  test "incomplete extraction publishes and persists a reusable assessment", %{id: id} do
    Conversation.send_message(id, %{country: "Spain"})
    assert_receive {:extraction_complete, %{status: :needs_data, assessment: report}}, 1_000
    refute report.sufficient
    assert :team_size in report.missing_fields
    assert report.data.country == "Spain"
    assert report.next_question =~ "team size"
    message = List.last(Conversations.list_messages(id))
    assert message.metadata["assessment"]["data"]["country"] == "Spain"
    assert message.metadata["assessment"]["sufficient"] == false
  end

  test "blocked provider keeps reads admission and close responsive and preserves queued turns",
       %{id: id, pid: pid, user: user} do
    Conversation.send_message(id, data())
    assert_receive {:provider, worker, "researcher", _}, 1_000
    assert length(Conversations.list_messages(id)) >= 1
    control = Conversations.get_for_user(id, user.id).validated_data["_pipeline"]
    assert is_binary(control["input_fingerprint"])
    assert control["run_ref"] == :sys.get_state(pid).run_ref
    assert control["request_ref"] == :sys.get_state(pid).request_ref
    assert {:ok, _, _} = Conversation.resume(id)
    assert {:ok, _} = Conversation.list_messages(id)
    assert :ok = GenServer.call(pid, :close)
    assert {:ok, :accepted, ^id} = Conversation.send_message(id, %{country: "France"})
    reply(worker, research())
    assert_receive {:provider, next, "researcher", _}, 1_000
    assert Conversations.get_for_user(id, user.id).validated_data["country"] == "France"
    reply(next, research())
  end

  test "worker failure is contained and terminal", %{id: id, pid: pid} do
    Conversation.send_message(id, data())
    assert_receive {:provider, worker, "researcher", _}, 1_000
    send(worker, :crash)

    assert_receive {:error, %{stage: :research, durability: :committed, boundary_version: 2}},
                   1_000

    assert List.last(Conversations.list_messages(id)).metadata["type"] == "error"
    assert Process.alive?(pid)
  end

  test "owner death terminates linked provider", %{id: id, pid: pid} do
    Conversation.send_message(id, data())
    assert_receive {:provider, worker, "researcher", _}, 1_000
    monitor = Process.monitor(worker)
    DynamicSupervisor.terminate_child(Fullstack.JidoMarketAgents.ConversationSupervisor, pid)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
  end

  test "duplicate result DOWN and stale binding cannot commit twice", %{id: id, pid: pid} do
    Conversation.send_message(id, data())
    assert_receive {:provider, worker, "researcher", _}, 1_000
    task = :sys.get_state(pid).task
    send(pid, {make_ref(), {:ok, research()}})
    reply(worker, research())
    assert_receive {:research_complete, _}, 1_000
    send(pid, {task.ref, {:ok, research()}})
    send(pid, {:DOWN, task.ref, :process, worker, :normal})
    assert {:ok, _, _} = Conversation.resume(id)

    assert Enum.count(
             Conversations.list_messages(id),
             &(&1.metadata["type"] == "market_research")
           ) == 1

    refute_receive {:research_complete, _}, 50
  end

  test "stage timeout cancels worker", %{id: id} do
    config = Application.get_env(:fullstack, Fullstack.JidoMarketAgents)

    Application.put_env(
      :fullstack,
      Fullstack.JidoMarketAgents,
      Keyword.put(config, :stage_timeout_ms, 40)
    )

    Conversation.send_message(id, data())
    assert_receive {:provider, worker, "researcher", _}, 1_000
    monitor = Process.monitor(worker)
    assert_receive {:error, %{stage: :research}}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
  end

  test "concurrent startup returns a single owner" do
    id = Ecto.UUID.generate()

    results =
      1..12
      |> Task.async_stream(fn _ -> Conversation.ensure_started(id) end)
      |> Enum.map(fn {:ok, value} -> value end)

    assert Enum.all?(results, &match?({:ok, _}, &1))
    assert results |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == 1
    {:ok, pid} = hd(results)
    DynamicSupervisor.terminate_child(Fullstack.JidoMarketAgents.ConversationSupervisor, pid)
  end

  test "correlated text envelopes remain paid and retain identity through buffering", %{
    id: id,
    user: user
  } do
    run = Ecto.UUID.generate()
    request = Ecto.UUID.generate()

    assert {:ok, :buffered, ^id} =
             Fullstack.JidoMarketAgents.send_message(user.id, id, "Spain",
               run_ref: run,
               request_ref: request
             )

    assert_receive {:provider, worker, "validator", _}, 1_000
    assert RateLimiter.user_status(user.id) == :active
    entries = :ets.lookup(:rate_limiter, user.id)
    assert length(entries) == 1
    reply(worker, %{country: "Spain"})
    assert_receive {:extraction_complete, %{run_ref: ^run, request_ref: ^request}}, 1_000
    refute MessageBuffer == nil
  end

  def analysis,
    do: %{
      viable_offer: nil,
      evidence: [],
      blocker: "Demand unknown",
      experiment: "Interview buyers"
    }

  test "research success persists then schedules analysis", %{id: id, user: user} do
    Conversation.send_message(id, data())
    assert_receive {:provider, research_worker, "researcher", _}, 1_000
    reply(research_worker, research())
    assert_receive {:research_complete, %{status: :analyzing}}, 1_000
    record = Conversations.get_for_user(id, user.id)
    assert record.status == "analyzing"
    assert Enum.any?(Conversations.list_messages(id), &(&1.metadata["type"] == "market_research"))
    assert_receive {:provider, analysis_worker, "analyzer", messages}, 1_000
    assert List.last(messages)["content"] =~ "No retrieval"
    reply(analysis_worker, analysis())
    assert_receive {:analysis_complete, _}, 1_000

    assert Conversations.get_for_user(id, user.id).business_analysis["blocker"] ==
             "Demand unknown"
  end

  def systems do
    system = %{
      current_state: "Needs improvement",
      priority: "high",
      actions: ["Run an experiment"],
      kpis: ["Leads"],
      pitfall: "Do not skip foundational work"
    }

    systems =
      Map.new(
        [:acquisition, :authority, :conversion, :delivery_retention, :referrals, :information],
        &{&1, system}
      )
      |> Map.update!(
        :authority,
        &Map.put(&1, :layers, %{
          personal_discourse: "Explain proven capabilities",
          third_party_endorsement: "Collect endorsements",
          success_cases: "Collect customer outcomes"
        })
      )
      |> Map.update!(
        :conversion,
        &Map.put(&1, :phases, %{
          qualification: "Identify suitable buyers",
          education_nurturing: "Explain the problem",
          proposal: "Present the offer",
          close: "Agree on the next step"
        })
      )
      |> Map.update!(
        :information,
        &Map.merge(&1, %{
          kpis: ["Leads", "Conversion", "Retention"],
          upward_information_flow: %{
            channel: "Weekly frontline feedback",
            incentive: "Recognize actionable feedback",
            review_cadence: "Weekly"
          }
        })
      )

    %{
      systems: systems,
      sequencing:
        Enum.map(
          [:acquisition, :authority, :conversion, :delivery_retention, :referrals, :information],
          &to_string/1
        ),
      quarterly_focus: "Improve acquisition"
    }
  end

  test "analysis success persists then schedules systems", %{id: id, user: user} do
    Conversation.send_message(id, data())
    assert_receive {:provider, worker, "researcher", _}, 1_000
    reply(worker, research())
    assert_receive {:provider, worker, "analyzer", _}, 1_000
    reply(worker, analysis())
    assert_receive {:analysis_complete, %{status: :building_strategy}}, 1_000

    assert Conversations.get_for_user(id, user.id).business_analysis["blocker"] ==
             "Demand unknown"

    assert_receive {:provider, worker, "systems", messages}, 1_000
    assert List.last(messages)["content"] =~ "Demand unknown"
    reply(worker, systems())
    assert_receive {:systems_complete, _}, 1_000

    assert Conversations.get_for_user(id, user.id).systems_strategy["quarterly_focus"] ==
             "Improve acquisition"
  end

  def tech do
    objective = %{
      specific: "Automate one repeated task",
      measurable: "Reduce time by 20%",
      achievable: "Use existing resources",
      relevant: "Reduce operating cost",
      time_bound: "Within 8 weeks"
    }

    cost = %{amount: 0, currency: "EUR", unit: "currency", period: "one_time"}

    components =
      Map.new([:subscriptions, :development, :training, :integration, :maintenance], &{&1, cost})
      |> Map.put(:subscriptions, %{cost | amount: 20, period: "monthly"})
      |> Map.put(:maintenance, %{cost | amount: 30, period: "monthly"})
      |> Map.put(:development, %{cost | amount: 1000})
      |> Map.put(:training, %{cost | amount: 200})
      |> Map.put(:integration, %{cost | amount: 300})

    %{
      diagnosis: %{
        prioritized_areas: ["Support", "Operations"],
        baseline_status: "measured",
        notes: "Measured current work"
      },
      smart_objectives: Enum.map(["Support", "Operations"], &Map.put(objective, :area, &1)),
      kpis:
        Enum.map(["Cycle time", "Errors", "Cost"], fn name ->
          %{
            name: name,
            baseline: 20,
            baseline_status: "measured",
            unit: "count",
            period: "monthly",
            source: "Operations log",
            target: 16
          }
        end),
      tool_selection: %{
        tool: "Workflow automation",
        criteria:
          Map.new(
            [
              :implementation_ease,
              :scalability,
              :integration,
              :total_cost,
              :support_community,
              :compliance_security
            ],
            &{&1, "Evaluate this criterion against current systems"}
          )
      },
      budget_roi: %{
        currency: "EUR",
        components: components,
        assumptions: %{
          baseline_status: "measured",
          baseline_value: 100,
          baseline_source: "Operations log",
          monthly_benefit: 200,
          benefit_currency: "EUR",
          benefit_unit: "currency",
          benefit_period: "monthly",
          horizon_months: 12
        },
        roi: %{status: "calculated", percentage: 9999, payback_months: 0, reason: nil}
      },
      pilot: %{
        process: "Support triage",
        team: "Two team members",
        start_day: 21,
        duration_weeks: 4,
        end_day: 30,
        success_metrics: ["Cycle time"],
        feedback: "Weekly team feedback"
      },
      scaling: %{
        decision: "pending",
        approach: "phased",
        review_day: 48,
        lessons_learned: [],
        expansion_plan: "Scale only after pilot evidence"
      },
      action_plan_30_days:
        Enum.map([{1, 5}, {6, 10}, {11, 20}, {21, 30}], fn {first, last} ->
          %{
            start_day: first,
            end_day: last,
            phase: "Prepare and launch",
            actions: ["Complete this phase"]
          }
        end)
    }
  end

  test "systems success persists then completes tech strategy", %{id: id, user: user} do
    Conversation.send_message(id, data())

    for {role, output} <- [
          {"researcher", research()},
          {"analyzer", analysis()},
          {"systems", systems()}
        ] do
      assert_receive {:provider, worker, ^role, _}, 1_000
      reply(worker, output)
    end

    assert_receive {:systems_complete, %{status: :building_strategy}}, 1_000
    assert_receive {:provider, worker, "strategy", messages}, 1_000
    assert List.last(messages)["content"] =~ "Improve acquisition"
    reply(worker, tech())
    assert_receive {:tech_strategy_complete, %{status: :completed}}, 1_000
    record = Conversations.get_for_user(id, user.id)
    assert record.status == "completed"
    assert record.tech_strategy["budget_roi"]["roi"]["percentage"] != 9999
  end

  test "successful pipeline emits the five adopted events with durable payloads in order", %{
    id: id,
    user: user
  } do
    Conversation.send_message(id, data())

    expected = [
      {:extraction_complete, :validator, :validated_data, :researching},
      {:research_complete, :research, :market_research, :analyzing},
      {:analysis_complete, :analysis, :business_analysis, :building_strategy},
      {:systems_complete, :systems, :systems_strategy, :building_strategy},
      {:tech_strategy_complete, :tech_strategy, :tech_strategy, :completed}
    ]

    outputs = [
      {"researcher", research()},
      {"analyzer", analysis()},
      {"systems", systems()},
      {"strategy", tech()}
    ]

    {run, request} =
      Enum.reduce(Enum.with_index(expected, 1), {nil, nil}, fn {{event, stage, field, status},
                                                                version},
                                                               {run, request} ->
        assert_receive {^event, payload}, 1_000
        assert payload.stage == stage
        assert payload.status == status
        assert payload.boundary_version == version
        assert payload.mode == :automatic
        assert is_binary(payload.run_ref) and is_binary(payload.request_ref)
        if run, do: assert(payload.run_ref == run and payload.request_ref == request)
        record = Conversations.get_for_user(id, user.id)
        assert record.status == to_string(status)
        assert length(payload.messages) == length(Conversations.list_messages(id))
        assert record.validated_data["_pipeline"]["boundary_version"] == version
        assert Map.has_key?(payload, field)

        if stage != :validator do
          message = List.last(Conversations.list_messages(id))
          assert message.metadata["result"] == Jason.decode!(Jason.encode!(payload[field]))
        end

        if version <= 4 do
          {role, output} = Enum.at(outputs, version - 1)
          assert_receive {:provider, worker, ^role, _}, 1_000
          reply(worker, output)
        end

        {payload.run_ref, payload.request_ref}
      end)

    assert is_binary(run) and is_binary(request)
    refute_receive {_event, %{conversation_id: ^id}}, 30
  end

  test "manual validation and stage park durably without automatic descendants", %{
    id: id,
    pid: pid,
    user: user
  } do
    run = Ecto.UUID.generate()
    request = Ecto.UUID.generate()

    Conversation.send_message(id, %{
      __pipeline_request__: true,
      message: data(),
      run_ref: run,
      request_ref: request,
      mode: :manual
    })

    assert_receive {:extraction_complete, %{status: :active, mode: :manual}}, 1_000
    refute_receive {:provider, _, _, _}, 30
    assert :accepted = GenServer.call(pid, {:run_stage, :research, run, request})
    assert :accepted = GenServer.call(pid, {:run_stage, :research, run, request})
    assert_receive {:provider, worker, "researcher", _}, 1_000
    reply(worker, research())
    assert_receive {:research_complete, %{status: :active, mode: :manual}}, 1_000
    record = Conversations.get_for_user(id, user.id)
    assert record.status == "active"
    assert record.validated_data["_pipeline"]["pending_stage"] == "analysis"
    refute_receive {:provider, _, _, _}, 30
    send(pid, {:run_stage, :research})
    refute_receive {:research_complete, _}, 30
  end

  test "waiting validation is durably active with needs_data event only", %{id: id, user: user} do
    Conversation.send_message(id, %{country: "Spain"})

    assert_receive {:extraction_complete,
                    %{status: :needs_data, stage: :validator, missing_fields: fields}},
                   1_000

    assert fields != []
    assert Conversations.get_for_user(id, user.id).status == "active"
  end

  test "changed facts publish committed invalidation before replacement results", %{
    id: id,
    pid: pid,
    user: user
  } do
    Conversation.send_message(id, data())

    for {role, output} <- [
          {"researcher", research()},
          {"analyzer", analysis()},
          {"systems", systems()},
          {"strategy", tech()}
        ] do
      assert_receive {:provider, worker, ^role, _}, 1_000
      reply(worker, output)
    end

    assert_receive {:tech_strategy_complete, _}, 1_000
    Conversation.send_message(id, %{country: "France"})

    assert_receive {:stage_invalidated,
                    %{invalidated: [:research, :analysis, :systems, :tech_strategy]}},
                   1_000

    record = Conversations.get_for_user(id, user.id)

    assert record.business_analysis == nil and record.systems_strategy == nil and
             record.tech_strategy == nil

    assert {:ok, snapshot} = GenServer.call(pid, :snapshot)
    assert snapshot.record.validated_data["country"] == "France"
  end

  test "an isolated observer reconciles a durable result without any broadcast", %{
    id: id,
    pid: pid
  } do
    Conversation.send_message(id, data())
    assert_receive {:provider, worker, "researcher", _}, 1_000
    Phoenix.PubSub.unsubscribe(Fullstack.PubSub, Conversation.topic(id))
    reply(worker, research())
    assert_receive {:provider, _, "analyzer", _}, 1_000
    assert {:ok, snapshot} = GenServer.call(pid, :snapshot)
    assert Enum.any?(snapshot.messages, &(&1.metadata["type"] == "market_research"))
    refute_receive {:research_complete, _}, 30
  end

  test "failed durable text admission never launches provider work", %{id: id, user: user} do
    record = Conversations.get_for_user(id, user.id)
    Fullstack.Repo.delete!(record)
    Conversation.send_message(id, "This input cannot be durably admitted")
    assert_receive {:error, %{durability: :failed}}, 1_000
    refute_receive {:provider, _, _, _}, 50
  end

  for shape <- [:complete, :incomplete] do
    test "failed #{shape} validation commit emits no success or descendant work", %{
      id: id,
      pid: pid,
      user: user
    } do
      Conversation.send_message(id, "Paid validation whose durable record will disappear")
      assert_receive {:provider, worker, "validator", _}, 1_000
      assert length(Conversations.list_messages(id)) == 1
      Fullstack.Repo.delete!(Conversations.get_for_user(id, user.id))
      output = if unquote(shape) == :complete, do: data(), else: %{country: "Spain"}
      reply(worker, output)
      refute_receive {:extraction_complete, _}, 100

      assert_receive {:error,
                      %{
                        stage: :extraction,
                        durability: :failed,
                        boundary_version: 0,
                        reason: {:stage_failed, :persistence_failed}
                      }},
                     1_000

      refute_receive {:provider, _, _, _}, 50
      assert Conversations.get_for_user(id, user.id) == nil
      state = :sys.get_state(pid)
      assert state.task == nil and state.pending_stage == nil
    end
  end

  test "stage error persists and broadcasts once without retry or descendant scheduling", %{
    id: id,
    pid: pid,
    user: user
  } do
    Conversation.send_message(id, "Paid text whose extraction will crash")
    assert_receive {:provider, worker, "validator", _}, 1_000
    send(worker, :crash)

    assert_receive {:error, %{status: :error, reason: {:stage_failed, :worker_failed}} = payload},
                   1_000

    # Exactly one terminal event: no retry, no second error, and no
    # descendant stage work is ever scheduled.
    refute_receive {:error, _}, 100
    refute_receive {:extraction_complete, _}, 100
    refute_receive {:research_complete, _}, 100
    refute_receive {:provider, _, _, _}, 100

    # A stale successor message after the terminal error stays inert.
    send(pid, {:run_stage, :research})
    refute_receive {:provider, _, _, _}, 100

    # Persisted atomically: one typed error message, stage :validator (the
    # durable vocabulary — never :extraction), and the terminal status.
    error_message = List.last(Conversations.list_messages(id))
    assert error_message.metadata["type"] == "error"
    assert error_message.metadata["stage"] == "validator"
    assert error_message.metadata["reason"] == "worker_failed"
    assert Conversations.get_for_user(id, user.id).status == "error"

    # Sanitized: raw provider payloads, credentials and stacktraces never
    # reach the wire.
    assert payload.reason == {:stage_failed, :worker_failed}
    refute inspect(payload) =~ "provider_crash"
  end

  test "manual complete validation drains an accepted competing automatic turn", %{
    id: id,
    user: user
  } do
    run = Ecto.UUID.generate()
    request = Ecto.UUID.generate()

    Conversation.send_message(id, %{
      __pipeline_request__: true,
      message: "Manual paid validation",
      run_ref: run,
      request_ref: request,
      mode: :manual
    })

    assert_receive {:provider, validator, "validator", _}, 1_000
    assert {:ok, :accepted, ^id} = Conversation.send_message(id, %{country: "France"})
    reply(validator, data())
    assert_receive {:extraction_complete, %{run_ref: ^run, mode: :manual, status: :active}}, 1_000
    assert_receive {:extraction_complete, %{mode: :automatic, validated_data: facts}}, 1_000
    assert (facts[:country] || facts["country"]) == "France"
    assert Conversations.get_for_user(id, user.id).validated_data["country"] == "France"
    assert_receive {:provider, researcher, "researcher", messages}, 1_000
    assert List.last(messages)["content"] =~ "France"
    refute List.last(messages)["content"] =~ "Spain"
    reply(researcher, research())
  end
end
