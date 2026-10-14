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
end
