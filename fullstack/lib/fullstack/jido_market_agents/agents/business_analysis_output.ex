defmodule Fullstack.JidoMarketAgents.Agents.BusinessAnalysisOutput do
  @moduledoc "Closed business analysis contract; an unsupported offer remains blocked."

  @fields [:viable_offer, :evidence, :blocker, :experiment]
  @source_kinds ["user_input", "market_research", "assumption"]
  @offer_fields [:name, :target_customer, :value_proposition, :price, :evidence_refs]

  def fields, do: @fields

  def schema do
    properties = %{
      "viable_offer" => offer_schema(),
      "evidence" => items(evidence_schema()),
      "blocker" => nullable_string(),
      "experiment" => nullable_string()
    }

    Map.put(closed_object(properties), "required", Enum.map(@fields, &to_string/1))
  end

  defp offer_schema do
    @offer_fields
    |> Map.new(fn field -> {to_string(field), %{"type" => "string"}} end)
    |> Map.put("evidence_refs", Map.put(items(%{"type" => "string"}), "minItems", 1))
    |> closed_object()
    |> Map.put("type", ["object", "null"])
  end

  defp evidence_schema do
    closed_object(%{
      "id" => %{"type" => "string"},
      "claim" => %{"type" => "string"},
      "source_kind" => source_enum_schema(),
      "source_ref" => nullable_string()
    })
  end

  defp source_enum_schema, do: %{"type" => "string", "enum" => @source_kinds}
  defp nullable_string, do: %{"type" => ["string", "null"]}
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
