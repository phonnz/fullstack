defmodule Fullstack.JidoMarketAgents.Agents.SystemsStrategyOutput do
  @moduledoc "Closed, canonically ordered six-systems strategy contract."

  @fields [:systems, :sequencing, :quarterly_focus]
  @order [:acquisition, :authority, :conversion, :delivery_retention, :referrals, :information]
  @layers [:personal_discourse, :third_party_endorsement, :success_cases]
  @phases [:qualification, :education_nurturing, :proposal, :close]
  @flow [:channel, :incentive, :review_cadence]

  def fields, do: @fields
  def system_order, do: @order

  def schema do
    closed_object(
      %{
        "systems" => closed_object(Map.new(@order, &{to_string(&1), system_schema(&1)}), @order),
        "sequencing" => %{
          "type" => "array",
          "minItems" => 6,
          "maxItems" => 6,
          "items" => %{"type" => "string", "enum" => Enum.map(@order, &to_string/1)}
        },
        "quarterly_focus" => text()
      },
      @fields
    )
  end

  defp system_schema(name) do
    common = %{
      "current_state" => text(),
      "priority" => %{"type" => "string", "enum" => ["high", "medium", "low"]},
      "actions" => items(text()),
      "kpis" => items(text()),
      "pitfall" => text()
    }

    properties =
      case name do
        :authority ->
          Map.put(common, "layers", text_object(@layers))

        :conversion ->
          Map.put(common, "phases", text_object(@phases))

        :information ->
          common
          |> Map.put("kpis", Map.merge(items(text()), %{"minItems" => 3, "maxItems" => 3}))
          |> Map.put("upward_information_flow", text_object(@flow))

        _ ->
          common
      end

    closed_object(properties)
  end

  defp text_object(fields), do: closed_object(Map.new(fields, &{to_string(&1), text()}), fields)
  defp text, do: %{"type" => "string"}
  defp items(item), do: %{"type" => "array", "items" => item}

  defp closed_object(properties, required \\ nil) do
    %{
      "type" => "object",
      "properties" => properties,
      "required" =>
        if(required, do: Enum.map(required, &to_string/1), else: Map.keys(properties)),
      "additionalProperties" => false
    }
  end
end
