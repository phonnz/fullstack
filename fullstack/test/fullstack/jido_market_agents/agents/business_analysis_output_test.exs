defmodule Fullstack.JidoMarketAgents.Agents.BusinessAnalysisOutputTest do
  use ExUnit.Case, async: true

  alias Fullstack.JidoMarketAgents.Agents.BusinessAnalysisOutput

  test "normalize_map/1 accepts only approved evidence source kinds" do
    evidence = %{
      id: "e1",
      claim: "Customer needs faster booking",
      source_kind: "user_input",
      source_ref: "diagnosis.pain_points"
    }

    offer = %{
      name: "Booking service",
      target_customer: "Local businesses",
      value_proposition: "Faster booking",
      price: 100,
      evidence_refs: ["e1"]
    }

    raw = %{viable_offer: offer, evidence: [evidence], blocker: nil, experiment: nil}

    result = BusinessAnalysisOutput.normalize_map(Map.put(raw, :unknown, true))
    assert result.viable_offer.price == "100"
    assert result.evidence == [evidence]
    assert Map.keys(result) |> Enum.sort() == Enum.sort(BusinessAnalysisOutput.fields())
    assert BusinessAnalysisOutput.normalize_map(Jason.decode!(Jason.encode!(raw))) == result

    for kind <- ["user_input", "market_research"] do
      assert %{viable_offer: %{name: "Booking service"}} =
               BusinessAnalysisOutput.normalize_map(%{
                 raw
                 | evidence: [%{evidence | source_kind: kind}]
               })
    end

    assert {:error, {:invalid_business_analysis, :evidence, :invalid_source_kind}} =
             BusinessAnalysisOutput.normalize_map(%{
               raw
               | evidence: [%{evidence | source_kind: "web_search"}]
             })

    assert {:error, {:invalid_business_analysis, :viable_offer, :unsupported_offer}} =
             BusinessAnalysisOutput.normalize_map(%{
               raw
               | evidence: [%{evidence | source_kind: "assumption", source_ref: nil}]
             })

    assert {:error, {:invalid_business_analysis, :viable_offer, :unresolved_evidence_refs}} =
             BusinessAnalysisOutput.normalize_map(%{
               raw
               | viable_offer: %{offer | evidence_refs: ["missing"]}
             })

    assert {:error, {:invalid_business_analysis, :evidence, :duplicate_ids}} =
             BusinessAnalysisOutput.normalize_map(%{raw | evidence: [evidence, evidence]})

    assert {:error, {:invalid_business_analysis, :evidence, :source_ref_required}} =
             BusinessAnalysisOutput.normalize_map(%{
               raw
               | evidence: [%{evidence | source_ref: nil}]
             })

    blocked = %{
      raw
      | viable_offer: nil,
        blocker: "Demand is not established",
        experiment: "Interview five prospective customers",
        evidence: [%{evidence | source_kind: "assumption", source_ref: nil}]
    }

    assert %{viable_offer: nil, blocker: "Demand is not established"} =
             BusinessAnalysisOutput.normalize_map(blocked)

    assert {:error, {:invalid_business_analysis, :viable_offer, :blocker_experiment_required}} =
             BusinessAnalysisOutput.normalize_map(%{blocked | experiment: nil})

    assert {:error, {:invalid_business_analysis, :viable_offer, :invalid_shape}} =
             BusinessAnalysisOutput.normalize_map(%{raw | viable_offer: [offer]})

    for key <- [:_pipeline, "_pipeline", :_meta, "_meta"] do
      assert {:error, {:reserved_key, _}} = BusinessAnalysisOutput.normalize_map(%{key => %{}})
    end
  end

  test "schema/0 models one viable offer and sourced evidence" do
    schema = BusinessAnalysisOutput.schema()

    assert BusinessAnalysisOutput.fields() == [:viable_offer, :evidence, :blocker, :experiment]
    assert schema["additionalProperties"] == false
    assert schema["required"] == Enum.map(BusinessAnalysisOutput.fields(), &to_string/1)
    offer = schema["properties"]["viable_offer"]
    assert offer["type"] == ["object", "null"]
    assert offer["additionalProperties"] == false
    assert "evidence_refs" in offer["required"]
    evidence = schema["properties"]["evidence"]["items"]
    assert evidence["additionalProperties"] == false

    assert evidence["properties"]["source_kind"]["enum"] ==
             ["user_input", "market_research", "assumption"]

    refute Map.has_key?(schema["properties"], "_pipeline")
    refute Map.has_key?(schema["properties"], "_meta")
  end
end
