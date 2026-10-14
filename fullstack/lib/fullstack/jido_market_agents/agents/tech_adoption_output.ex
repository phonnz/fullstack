defmodule Fullstack.JidoMarketAgents.Agents.TechAdoptionOutput do
  @moduledoc "Seven-step adoption contract with baseline-safe, deterministic financial projections."

  @fields [
    :diagnosis,
    :smart_objectives,
    :kpis,
    :tool_selection,
    :budget_roi,
    :pilot,
    :scaling,
    :action_plan_30_days
  ]
  @criteria [
    :implementation_ease,
    :scalability,
    :integration,
    :total_cost,
    :support_community,
    :compliance_security
  ]
  @components [:subscriptions, :development, :training, :integration, :maintenance]
  @baseline_statuses ["measured", "estimated", "missing"]
  @day_ranges [{1, 5}, {6, 10}, {11, 20}, {21, 30}]

  def fields, do: @fields
  def schema, do: wire_schema(contract())

  defp contract do
    object(
      diagnosis:
        object(
          prioritized_areas: array(text(), 2, 3),
          baseline_status: enum(@baseline_statuses),
          notes: text()
        ),
      smart_objectives:
        array(
          object(
            area: text(),
            specific: text(),
            measurable: text(),
            achievable: text(),
            relevant: text(),
            time_bound: text()
          ),
          2,
          3
        ),
      kpis: array(kpi_schema(), 3, 5),
      tool_selection: object(tool: text(), criteria: text_object(@criteria)),
      budget_roi: budget_schema(),
      pilot:
        object(
          process: text(),
          team: text(),
          start_day: integer(21, 30),
          duration_weeks: integer(4, 8),
          end_day: integer(1),
          success_metrics: array(text(), 1),
          feedback: text()
        ),
      scaling:
        object(
          decision: enum(["pending", "scale", "do_not_scale"]),
          approach: enum(["horizontal", "vertical", "phased"]),
          review_day: integer(1),
          lessons_learned: array(text()),
          expansion_plan: text()
        ),
      action_plan_30_days: array(day_range_schema(), 4, 4)
    )
  end

  defp kpi_schema do
    object(
      name: text(),
      baseline: nullable("number"),
      baseline_status: enum(@baseline_statuses),
      unit: text(),
      period: text(),
      source: nullable("string"),
      target: number()
    )
  end

  defp budget_schema do
    cost = object(amount: number(0), currency: text(), unit: text(), period: text())

    object(
      currency: text(),
      components: object(Enum.map(@components, &{&1, cost})),
      assumptions:
        object(
          baseline_status: enum(@baseline_statuses),
          baseline_value: nullable("number"),
          baseline_source: nullable("string"),
          monthly_benefit: nullable("number"),
          benefit_currency: text(),
          benefit_unit: text(),
          benefit_period: text(),
          horizon_months: integer(1)
        ),
      roi:
        object(
          status: enum(["calculated", "not_calculable"]),
          percentage: nullable("number"),
          payback_months: nullable("number"),
          reason: nullable("string")
        )
    )
  end

  defp day_range_schema do
    object(
      start_day: integer(1, 30),
      end_day: integer(1, 30),
      phase: text(),
      actions: array(text(), 1)
    )
  end

  defp text_object(fields), do: object(Enum.map(fields, &{&1, text()}))
  defp text, do: %{"type" => "string"}
  defp enum(values), do: %{"type" => "string", "enum" => values}
  defp nullable(type), do: %{"type" => [type, "null"]}
  defp number, do: %{"type" => "number"}
  defp number(minimum), do: %{"type" => "number", "minimum" => minimum}
  defp integer(minimum), do: %{"type" => "integer", "minimum" => minimum}
  defp integer(minimum, maximum), do: Map.put(integer(minimum), "maximum", maximum)
  defp array(item), do: %{"type" => "array", "items" => item}
  defp array(item, minimum), do: Map.put(array(item), "minItems", minimum)
  defp array(item, minimum, maximum), do: Map.put(array(item, minimum), "maxItems", maximum)

  # Atom property keys are the normalization allow-list; only the wire projection stringifies them.
  defp object(properties) do
    %{
      "type" => "object",
      "properties" => Map.new(properties),
      "required" => Keyword.keys(properties),
      "additionalProperties" => false
    }
  end

  defp wire_schema(%{"properties" => properties} = schema) do
    schema
    |> Map.put(
      "properties",
      Map.new(properties, fn {key, value} -> {to_string(key), wire_schema(value)} end)
    )
    |> Map.update!("required", &Enum.map(&1, fn key -> to_string(key) end))
  end

  defp wire_schema(%{"items" => item} = schema), do: Map.put(schema, "items", wire_schema(item))
  defp wire_schema(schema), do: schema
end
