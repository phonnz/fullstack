defmodule Fullstack.JidoMarketAgents.Agents.BusinessAnalyzerTest do
  use ExUnit.Case, async: false
  alias Fullstack.JidoMarketAgents.Agents.{BusinessAnalyzer, BusinessAnalysisOutput}

  defmodule Backend do
    @behaviour Fullstack.JidoMarketAgents.LLM.Backend
    def capabilities(_), do: [:json_object]
    def validate_config(_), do: :ok

    def chat_completion(messages, opts) do
      send(self(), {:analysis_dispatch, messages, opts})
      Process.get(:analysis_reply, {:ok, "{}"})
    end
  end

  setup do
    config = Application.get_env(:fullstack, Fullstack.JidoMarketAgents, [])

    Application.put_env(
      :fullstack,
      Fullstack.JidoMarketAgents,
      Keyword.put(config, :analyzer_backend, {Backend, model: "analyzer-test"})
    )

    on_exit(fn -> Application.put_env(:fullstack, Fullstack.JidoMarketAgents, config) end)
    :ok
  end

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

  test "analyze/1 normalizes structured output and tags failures" do
    agent = BusinessAnalyzer.new()

    raw = %{
      viable_offer: %{
        name: "Booking",
        target_customer: "Shops",
        value_proposition: "Faster booking",
        price: 100,
        evidence_refs: ["e1"]
      },
      evidence: [
        %{
          id: "e1",
          claim: "Needs faster booking",
          source_kind: "user_input",
          source_ref: "validated_data.pain_points"
        }
      ],
      blocker: nil,
      experiment: nil
    }

    Process.put(:analysis_reply, {:ok, Jason.encode!(raw)})
    assert {:ok, result} = BusinessAnalyzer.analyze(agent)
    assert result == BusinessAnalysisOutput.normalize_map(raw)
    assert result.viable_offer.price == "100"
    assert_received {:analysis_dispatch, messages, opts}
    assert List.last(messages)["content"] == BusinessAnalyzer.prompt(agent)
    assert opts[:response_format] == {:json_object, BusinessAnalysisOutput.schema()}
    assert opts[:model] == "analyzer-test"

    Process.put(
      :analysis_reply,
      {:ok, ~s({"viable_offer":null,"blocker":"Demand unknown","experiment":"Interview buyers"})}
    )

    assert {:ok, %{viable_offer: nil, blocker: "Demand unknown"}} =
             BusinessAnalyzer.analyze(agent)

    Process.put(:analysis_reply, {:error, :offline})
    assert {:error, {:analysis_failed, :offline}} = BusinessAnalyzer.analyze(agent)
    Process.put(:analysis_reply, {:ok, "not JSON"})

    assert {:error, {:parse_failed, {:json_parse, %Jason.DecodeError{}}}} =
             BusinessAnalyzer.analyze(agent)

    Process.put(:analysis_reply, {:ok, "[]"})
    assert {:error, {:parse_failed, :not_a_map}} = BusinessAnalyzer.analyze(agent)
    Process.put(:analysis_reply, {:ok, nil})
    assert {:error, {:parse_failed, :invalid_content}} = BusinessAnalyzer.analyze(agent)
    Process.put(:analysis_reply, {:ok, "{}"})

    assert {:error, {:invalid_business_analysis, :viable_offer, :blocker_experiment_required}} =
             BusinessAnalyzer.analyze(agent)
  end
end
