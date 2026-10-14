defmodule Fullstack.JidoMarketAgents.Agents.StrategyAgentTest do
  use ExUnit.Case, async: false
  alias Fullstack.JidoMarketAgents.Agents.StrategyAgent

  defmodule Guide do
    def fetch(:tech_adoption), do: {:ok, "TECH_ADOPTION_GUIDE_MARKER: pilot before scaling"}
    def fetch(:six_systems), do: {:ok, "SIX_SYSTEMS_MUST_NOT_APPEAR"}
  end

  setup do
    previous = Application.get_env(:fullstack, :knowledge_module)
    config = Application.get_env(:fullstack, Fullstack.JidoMarketAgents, [])
    Application.put_env(:fullstack, :knowledge_module, Guide)

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
end
