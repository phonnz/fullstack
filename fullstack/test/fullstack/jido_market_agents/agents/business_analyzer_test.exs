defmodule Fullstack.JidoMarketAgents.Agents.BusinessAnalyzerTest do
  use ExUnit.Case, async: false
  alias Fullstack.JidoMarketAgents.Agents.BusinessAnalyzer

  test "new/1 and set/2 accept validated data research and refinements" do
    agent =
      BusinessAnalyzer.new(
        state: %{
          validated_data: %{
            "country" => "Spain",
            "team_size" => %{"status" => "known", "count" => 3}
          },
          research_output: %{"limitations" => ["No retrieval"]},
          refinements: %{offer: "Service first"}
        }
      )

    assert %Jido.Agent{} = agent
    assert agent.state.validated_data.country == "Spain"
    assert agent.state.validated_data.team_size.count == 3
    assert agent.state.research_output.limitations == ["No retrieval"]

    assert {:ok, corrected} =
             BusinessAnalyzer.set(agent, %{
               validated_data: %{"team_size" => %{"status" => "unknown"}},
               research_output: %{},
               refinements: %{price: "Lower"}
             })

    assert corrected.state.validated_data.country == nil
    assert corrected.state.validated_data.team_size.count == nil
    assert corrected.state.research_output.limitations == []
    assert corrected.state.refinements == %{price: "Lower"}

    assert {:error, {:invalid_diagnosis, :team_size, _}} =
             BusinessAnalyzer.set(agent, %{
               validated_data: %{team_size: %{status: "known", count: -1}}
             })

    assert agent.state.validated_data.team_size.count == 3
    assert BusinessAnalyzer.new().state.validated_data == %{}
  end

  test "analysis prompt labels user facts market hypotheses and inference" do
    agent =
      BusinessAnalyzer.new(
        state: %{
          validated_data: %{
            country: "Spain",
            initial_budget: "100 EUR",
            final_product_proposal: "Booking service",
            output_language: "es"
          },
          research_output: %{limitations: ["No retrieval"]},
          refinements: %{offer: "No new staff"}
        }
      )

    prompt = BusinessAnalyzer.prompt(agent)

    for instruction <- [
          "user facts",
          "market hypotheses",
          "inference",
          "one viable offer",
          "user_input",
          "market_research",
          "assumption",
          "blocker",
          "experiment",
          "100 EUR",
          "No new staff",
          "Output language: es"
        ] do
      assert prompt =~ instruction
    end

    envelope = BusinessAnalyzer.input_envelope(agent)
    assert envelope.user_facts == agent.state.validated_data
    assert envelope.market_hypotheses == agent.state.research_output
    assert envelope.refinements == %{offer: "No new staff"}
    assert envelope.output_language == "es"
  end
end
