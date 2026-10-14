defmodule Fullstack.JidoMarketAgents.Agents.MarketResearchOutput do
  @moduledoc "Closed market investigation contract for the no-retrieval research stage."

  @fields [:market_evidence, :market_gaps, :demand_signals, :sources, :limitations]

  def fields, do: @fields

  def schema do
    properties = %{
      "market_evidence" => items(evidence_schema()),
      "market_gaps" => items(evidence_schema()),
      "demand_signals" => items(evidence_schema()),
      "sources" => Map.put(items(%{"type" => "string"}), "maxItems", 0),
      "limitations" => items(%{"type" => "string"})
    }

    Map.put(closed_object(properties), "required", Enum.map(@fields, &to_string/1))
  end

  defp evidence_schema do
    closed_object(%{
      "claim" => %{"type" => "string"},
      "confidence" => %{"type" => "string", "enum" => ["low", "medium", "high"]},
      "verification_status" => %{"type" => "string", "enum" => ["unverified"]},
      "evidence_refs" => Map.put(items(%{"type" => "string"}), "maxItems", 0)
    })
  end

  defp items(item), do: %{"type" => "array", "items" => item}

  defp closed_object(properties) do
    %{
      "type" => "object",
      "properties" => properties,
      "required" => Map.keys(properties),
      "additionalProperties" => false
    }
  end
end
