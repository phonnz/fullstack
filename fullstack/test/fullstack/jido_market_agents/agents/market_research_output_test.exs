defmodule Fullstack.JidoMarketAgents.Agents.MarketResearchOutputTest do
  use ExUnit.Case, async: true

  alias Fullstack.JidoMarketAgents.Agents.MarketResearchOutput

  test "normalize_map/1 preserves unverified evidence and explicit limitations" do
    item = %{"claim" => "Possible local demand", "confidence" => "medium"}

    raw = %{
      "market_evidence" => [item],
      "market_gaps" => [Map.put(item, "confidence", nil)],
      "demand_signals" => [item],
      "sources" => [],
      "limitations" => ["No retrieval was performed"],
      "unknown" => "ignored"
    }

    result = MarketResearchOutput.normalize_map(raw)
    assert Map.keys(result) |> Enum.sort() == Enum.sort(MarketResearchOutput.fields())
    assert result.limitations == ["No retrieval was performed"]

    for field <- [:market_evidence, :market_gaps, :demand_signals] do
      [evidence] = result[field]
      assert evidence.verification_status == "unverified"
      assert evidence.evidence_refs == []
      assert evidence.claim == "Possible local demand"

      for fabricated <- [
            Map.put(item, "verification_status", "verified"),
            Map.put(item, "verified", true)
          ] do
        assert {:error, {:invalid_market_research, ^field, :verified_claim}} =
                 MarketResearchOutput.normalize_map(Map.put(raw, field, [fabricated]))
      end

      assert {:error, {:invalid_market_research, ^field, :unresolved_evidence_refs}} =
               MarketResearchOutput.normalize_map(
                 Map.put(raw, field, [Map.put(item, "evidence_refs", ["made-up"])])
               )
    end

    assert hd(result.market_gaps).confidence == "low"

    assert {:error, {:invalid_market_research, :sources, :retrieval_unavailable}} =
             MarketResearchOutput.normalize_map(Map.put(raw, "sources", ["https://example.com"]))

    assert {:error, {:invalid_market_research, :market_evidence, :invalid_confidence}} =
             MarketResearchOutput.normalize_map(
               Map.put(raw, "market_evidence", [Map.put(item, "confidence", "certain")])
             )

    assert {:error, {:invalid_market_research, :limitations, :invalid_items}} =
             MarketResearchOutput.normalize_map(Map.put(raw, "limitations", [nil]))

    for key <- [:_pipeline, "_pipeline", :_meta, "_meta"] do
      assert {:error, {:reserved_key, _}} = MarketResearchOutput.normalize_map(%{key => %{}})
    end

    assert {:error, {:invalid_market_research, :output, :invalid_shape}} =
             MarketResearchOutput.normalize_map([])
  end

  test "schema/0 defines closed market evidence fields" do
    schema = MarketResearchOutput.schema()

    assert MarketResearchOutput.fields() ==
             [:market_evidence, :market_gaps, :demand_signals, :sources, :limitations]

    assert schema["additionalProperties"] == false
    assert schema["required"] == Enum.map(MarketResearchOutput.fields(), &to_string/1)
    assert Map.keys(schema["properties"]) |> Enum.sort() == Enum.sort(schema["required"])

    for field <- ~w(market_evidence market_gaps demand_signals) do
      item = schema["properties"][field]["items"]
      assert item["additionalProperties"] == false
      assert item["properties"]["verification_status"]["enum"] == ["unverified"]
      assert item["properties"]["evidence_refs"]["maxItems"] == 0
    end

    assert schema["properties"]["sources"]["maxItems"] == 0
    refute Map.has_key?(schema["properties"], "_pipeline")
    refute Map.has_key?(schema["properties"], "_meta")
  end
end
