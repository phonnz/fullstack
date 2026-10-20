defmodule Fullstack.JidoMarketAgents.Agents.SystemsAgentTest do
  use ExUnit.Case, async: false
  alias Fullstack.JidoMarketAgents.Agents.{SystemsAgent, SystemsStrategyOutput}

  defmodule Guide do
    def fetch(:six_systems), do: {:ok, "SIX_SYSTEMS_GUIDE_MARKER: sequence before optimization"}
    def fetch(:tech_adoption), do: {:ok, "TECH_GUIDE_MUST_NOT_APPEAR"}
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
      send(self(), {:systems_dispatch, messages, opts})
      Process.get(:systems_reply, {:ok, "{}"})
    end
  end

  setup do
    previous = Application.get_env(:fullstack, :knowledge_module)
    config = Application.get_env(:fullstack, Fullstack.JidoMarketAgents, [])
    Application.put_env(:fullstack, :knowledge_module, Guide)

    Application.put_env(
      :fullstack,
      Fullstack.JidoMarketAgents,
      Keyword.put(config, :systems_backend, {Backend, model: "systems-test"})
    )

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

  test "build/1 normalizes strategy and fails before dispatch when grounding is missing" do
    agent = SystemsAgent.new(state: %{output_language: "fr"})
    raw = valid_strategy()
    Process.put(:systems_reply, {:ok, Jason.encode!(raw)})
    assert {:ok, result} = SystemsAgent.build(agent)
    assert result == SystemsStrategyOutput.normalize_map(raw)
    assert_received {:systems_dispatch, messages, opts}
    assert List.last(messages)["content"] =~ "USER's input language: fr"
    assert opts[:model] == "systems-test"
    assert opts[:response_format] == {:json_object, SystemsStrategyOutput.schema()}
    Process.put(:systems_reply, {:error, :offline})
    assert {:error, {:systems_failed, :offline}} = SystemsAgent.build(agent)
    Process.put(:systems_reply, {:ok, "not JSON"})

    assert {:error, {:parse_failed, {:json_parse, %Jason.DecodeError{}}}} =
             SystemsAgent.build(agent)

    Process.put(:systems_reply, {:ok, "[]"})
    assert {:error, {:parse_failed, :not_a_map}} = SystemsAgent.build(agent)
    Process.put(:systems_reply, {:ok, nil})
    assert {:error, {:parse_failed, :invalid_content}} = SystemsAgent.build(agent)
    Process.put(:systems_reply, {:ok, "{}"})

    assert {:error, {:invalid_systems_strategy, :systems, :invalid_shape}} =
             SystemsAgent.build(agent)

    drain_dispatch()

    for module <- [MissingGuide, BlankGuide] do
      Application.put_env(:fullstack, :knowledge_module, module)
      assert {:error, {:grounding_failed, :not_configured}} = SystemsAgent.build(agent)
      refute_receive {:systems_dispatch, _, _}, 10
    end
  end

  defp drain_dispatch do
    receive do
      {:systems_dispatch, _, _} -> drain_dispatch()
    after
      0 -> :ok
    end
  end

  defp valid_strategy do
    systems =
      Map.new(SystemsStrategyOutput.system_order(), fn key ->
        base = %{
          current_state: "Manual",
          priority: "high",
          actions: ["Improve"],
          kpis: ["Revenue"],
          pitfall: "Do not skip sequencing"
        }

        details =
          case key do
            :authority ->
              %{
                layers: %{
                  personal_discourse: "Clear message",
                  third_party_endorsement: "Partners",
                  success_cases: "Case study"
                }
              }

            :conversion ->
              %{
                phases: %{
                  qualification: "Fit",
                  education_nurturing: "Teach",
                  proposal: "Offer",
                  close: "Agree"
                }
              }

            :information ->
              %{
                kpis: ["Revenue", "Margin", "Retention"],
                upward_information_flow: %{
                  channel: "Weekly report",
                  incentive: "Learning",
                  review_cadence: "Weekly"
                }
              }

            _ ->
              %{}
          end

        {key, Map.merge(base, details)}
      end)

    %{
      systems: systems,
      sequencing: Enum.map(SystemsStrategyOutput.system_order(), &to_string/1),
      quarterly_focus: "Acquisition"
    }
  end
end
