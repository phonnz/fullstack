defmodule Fullstack.JidoMarketAgents.Agents.MarketResearchOutputTest do
  use ExUnit.Case, async: true

  alias Fullstack.JidoMarketAgents.Agents.MarketResearchOutput

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
