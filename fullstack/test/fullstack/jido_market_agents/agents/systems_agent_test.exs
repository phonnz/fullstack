defmodule Fullstack.JidoMarketAgents.Agents.SystemsAgentTest do
  use ExUnit.Case, async: false
  alias Fullstack.JidoMarketAgents.Agents.SystemsAgent

  defmodule Guide do
    def fetch(:six_systems), do: {:ok, "SIX_SYSTEMS_GUIDE_MARKER: sequence before optimization"}
    def fetch(:tech_adoption), do: {:ok, "TECH_GUIDE_MUST_NOT_APPEAR"}
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

  test "systems prompt includes only six-systems guide rules refinements and output_language" do
    agent =
      SystemsAgent.new(
        state: %{
          validated_data: %{country: "Spain", output_language: "es"},
          analysis_output: %{
            viable_offer: nil,
            blocker: "Demand unknown",
            experiment: "Interview buyers"
          },
          refinements: %{quarter: "Focus on retention"}
        }
      )

    assert %Jido.Agent{} = agent
    assert {:ok, prompt} = SystemsAgent.prompt(agent)
    assert {:ok, ^prompt} = SystemsAgent.prompt(agent)

    for instruction <- [
          "SIX_SYSTEMS_GUIDE_MARKER",
          "acquisition",
          "authority",
          "conversion",
          "delivery_retention",
          "referrals",
          "information",
          "personal_discourse",
          "qualification",
          "three KPIs",
          "upward_information_flow",
          "pitfall",
          "quarterly_focus",
          "Focus on retention",
          "USER's input language: es"
        ] do
      assert prompt =~ instruction
    end

    refute prompt =~ "TECH_GUIDE_MUST_NOT_APPEAR"

    assert {:ok, corrected} =
             SystemsAgent.set(agent, %{
               validated_data: %{team_size: %{status: "unknown"}},
               refinements: %{scope: "Only acquisition"}
             })

    assert corrected.state.validated_data.country == nil
    assert corrected.state.refinements == %{scope: "Only acquisition"}
    config = Application.get_env(:fullstack, Fullstack.JidoMarketAgents, [])

    Application.put_env(
      :fullstack,
      Fullstack.JidoMarketAgents,
      Keyword.put(config, :systems_knowledge_max_chars, 10)
    )

    assert {:ok, truncated} = SystemsAgent.prompt(agent)
    assert truncated =~ "SIX_SYSTEM"
    assert truncated =~ "[GROUNDING TRUNCATED]"
    refute truncated =~ "sequence before optimization"
  end
end
