defmodule Fullstack.JidoMarketAgents.Agents.BusinessAnalysisOutputTest do
  use ExUnit.Case, async: true

  alias Fullstack.JidoMarketAgents.Agents.BusinessAnalysisOutput

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
