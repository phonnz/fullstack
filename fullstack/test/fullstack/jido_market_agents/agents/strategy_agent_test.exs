defmodule Fullstack.JidoMarketAgents.Agents.StrategyAgentTest do
  use ExUnit.Case, async: false
  alias Fullstack.JidoMarketAgents.Agents.{StrategyAgent, TechAdoptionOutput}

  defmodule Guide do
    def fetch(:tech_adoption), do: {:ok, "TECH_ADOPTION_GUIDE_MARKER: pilot before scaling"}
    def fetch(:six_systems), do: {:ok, "SIX_SYSTEMS_MUST_NOT_APPEAR"}
  end

  defmodule MissingGuide do
    def fetch(_), do: {:error, :not_configured}
  end

  defmodule BlankGuide do
    def fetch(_), do: {:ok, "   "}
  end

  defmodule Backend do
    @behaviour Fullstack.JidoMarketAgents.LLM.Backend
    def capabilities(_), do: [:json_object]
    def validate_config(_), do: :ok

    def chat_completion(messages, opts) do
      send(self(), {:strategy_dispatch, messages, opts})
      Process.get(:strategy_reply, {:ok, "{}"})
    end
  end

  setup do
    previous = Application.get_env(:fullstack, :knowledge_module)
    config = Application.get_env(:fullstack, Fullstack.JidoMarketAgents, [])
    Application.put_env(:fullstack, :knowledge_module, Guide)

    Application.put_env(
      :fullstack,
      Fullstack.JidoMarketAgents,
      Keyword.put(config, :strategy_backend, {Backend, model: "strategy-test"})
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:fullstack, :knowledge_module, previous),
        else: Application.delete_env(:fullstack, :knowledge_module)

      Application.put_env(:fullstack, Fullstack.JidoMarketAgents, config)
    end)

    :ok
  end

  test "strategy prompt includes only tech guide baseline rules refinements and output_language" do
    agent =
      StrategyAgent.new(
        state: %{
          validated_data: %{country: "Spain", output_language: "es"},
          analysis_output: %{
            viable_offer: nil,
            blocker: "Demand unknown",
            experiment: "Interview buyers"
          },
          refinements: %{tool: "Reuse existing CRM"}
        }
      )

    assert %Jido.Agent{} = agent
    assert {:ok, prompt} = StrategyAgent.prompt(agent)
    assert {:ok, ^prompt} = StrategyAgent.prompt(agent)

    for instruction <- [
          "TECH_ADOPTION_GUIDE_MARKER",
          "diagnosis",
          "smart_objectives",
          "3-5 KPIs",
          "tool_selection",
          "budget_roi",
          "pilot",
          "scaling",
          "action_plan_30_days",
          "measured",
          "estimated",
          "missing",
          "not_calculable",
          "subscriptions",
          "development",
          "training",
          "integration",
          "maintenance",
          "4-8 weeks",
          "days 1-5",
          "days 6-10",
          "days 11-20",
          "days 21-30",
          "Reuse existing CRM",
          "USER's input language: es"
        ] do
      assert prompt =~ instruction
    end

    refute prompt =~ "SIX_SYSTEMS_MUST_NOT_APPEAR"

    assert {:ok, corrected} =
             StrategyAgent.set(agent, %{
               validated_data: %{team_size: %{status: "unknown"}},
               refinements: %{tool: "No new software"}
             })

    assert corrected.state.validated_data.country == nil
    assert corrected.state.refinements == %{tool: "No new software"}
    config = Application.get_env(:fullstack, Fullstack.JidoMarketAgents, [])

    Application.put_env(
      :fullstack,
      Fullstack.JidoMarketAgents,
      Keyword.put(config, :strategy_knowledge_max_chars, 10)
    )

    assert {:ok, truncated} = StrategyAgent.prompt(agent)
    assert truncated =~ "TECH_ADOPT"
    assert truncated =~ "[GROUNDING TRUNCATED]"
    refute truncated =~ "pilot before scaling"
  end

  test "build/1 normalizes adoption strategy and tags failures" do
    agent = StrategyAgent.new(state: %{output_language: "pt"})
    raw = valid_adoption()
    Process.put(:strategy_reply, {:ok, Jason.encode!(raw)})
    assert {:ok, result} = StrategyAgent.build(agent)
    assert result == TechAdoptionOutput.normalize_map(raw)
    assert result.budget_roi.roi.percentage == 20.0
    assert result.pilot.end_day == 48
    assert_received {:strategy_dispatch, messages, opts}
    assert List.last(messages)["content"] =~ "USER's input language: pt"
    assert opts[:model] == "strategy-test"
    assert opts[:response_format] == {:json_object, TechAdoptionOutput.schema()}
    estimated = put_in(raw, [:diagnosis, :baseline_status], "estimated")
    Process.put(:strategy_reply, {:ok, Jason.encode!(estimated)})

    assert {:ok, %{budget_roi: %{roi: %{status: "not_calculable", reason: "estimated_baseline"}}}} =
             StrategyAgent.build(agent)

    Process.put(:strategy_reply, {:error, :offline})
    assert {:error, {:strategy_failed, :offline}} = StrategyAgent.build(agent)
    Process.put(:strategy_reply, {:ok, "not JSON"})

    assert {:error, {:parse_failed, {:json_parse, %Jason.DecodeError{}}}} =
             StrategyAgent.build(agent)

    Process.put(:strategy_reply, {:ok, "[]"})
    assert {:error, {:parse_failed, :not_a_map}} = StrategyAgent.build(agent)
    Process.put(:strategy_reply, {:ok, nil})
    assert {:error, {:parse_failed, :invalid_content}} = StrategyAgent.build(agent)
    Process.put(:strategy_reply, {:ok, "{}"})

    assert {:error, {:invalid_tech_adoption, :diagnosis, :missing_field}} =
             StrategyAgent.build(agent)

    drain_dispatch()

    for module <- [MissingGuide, BlankGuide] do
      Application.put_env(:fullstack, :knowledge_module, module)
      assert {:error, {:grounding_failed, :not_configured}} = StrategyAgent.build(agent)
      refute_receive {:strategy_dispatch, _, _}, 10
    end
  end

  defp drain_dispatch do
    receive do
      {:strategy_dispatch, _, _} -> drain_dispatch()
    after
      0 -> :ok
    end
  end

  defp valid_adoption do
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
end
