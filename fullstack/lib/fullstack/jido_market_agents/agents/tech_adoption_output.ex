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

  @doc "Validates deliverables and replaces model projections with deterministic calculations."
  def normalize_map(raw) when is_map(raw) do
    with :ok <- reject_reserved(raw),
         {:ok, normalized} <- normalize_fields(prepare_computed(raw)),
         :ok <- validate_objectives(normalized),
         :ok <- validate_kpis(normalized.kpis),
         :ok <- validate_day_ranges(normalized.action_plan_30_days),
         {:ok, pilot} <- finalize_pilot(normalized.pilot, normalized.scaling) do
      normalized
      |> Map.put(:pilot, pilot)
      |> put_in([:budget_roi, :roi], calculate_roi(normalized))
    end
  end

  def normalize_map(_raw), do: error(:output, :invalid_shape)

  defp reject_reserved(raw) do
    Enum.find_value([:_pipeline, :_meta], :ok, fn key ->
      if Map.has_key?(raw, key) or Map.has_key?(raw, to_string(key)),
        do: {:error, {:reserved_key, key}}
    end)
  end

  # These fields are system-owned, not trustworthy model inputs, even when they are well-typed.
  defp prepare_computed(raw) do
    raw
    |> replace_computed(:budget_roi, :roi, not_calculable("pending"))
    |> replace_computed(:pilot, :end_day, 1)
  end

  defp replace_computed(raw, field, key, value) do
    case get(raw, field) do
      nested when is_map(nested) ->
        Map.put(raw, field, nested |> Map.delete(to_string(key)) |> Map.put(key, value))

      _ ->
        raw
    end
  end

  defp normalize_fields(raw) do
    properties = contract()["properties"]

    Enum.reduce_while(@fields, {:ok, %{}}, fn field, {:ok, acc} ->
      result =
        if has_key?(raw, field),
          do: normalize_node(get(raw, field), properties[field], field),
          else: error(field, :missing_field)

      case result do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, field, value)}}
        error -> {:halt, error}
      end
    end)
  end

  defp normalize_node(raw, %{"type" => types} = schema, field) when is_list(types) do
    if is_nil(raw) and "null" in types do
      {:ok, nil}
    else
      normalize_node(raw, Map.put(schema, "type", hd(types)), field)
    end
  end

  defp normalize_node(raw, %{"type" => "object"} = schema, field) when is_map(raw) do
    Enum.reduce_while(schema["required"], {:ok, %{}}, fn key, {:ok, acc} ->
      result =
        if has_key?(raw, key),
          do: normalize_node(get(raw, key), schema["properties"][key], field),
          else: error(field, :missing_field)

      case result do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        error -> {:halt, error}
      end
    end)
  end

  defp normalize_node(raw, %{"type" => "array"} = schema, field) when is_list(raw) do
    count = length(raw)

    if count < Map.get(schema, "minItems", 0) or count > Map.get(schema, "maxItems", count) do
      error(field, :invalid_cardinality)
    else
      Enum.reduce_while(raw, {:ok, []}, fn item, {:ok, acc} ->
        case normalize_node(item, schema["items"], field) do
          {:ok, value} -> {:cont, {:ok, [value | acc]}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, values} -> {:ok, Enum.reverse(values)}
        error -> error
      end
    end
  end

  defp normalize_node(raw, %{"type" => "string"} = schema, field) do
    value = scalar(raw)

    cond do
      is_nil(value) -> error(field, :invalid_text)
      Map.has_key?(schema, "enum") and value not in schema["enum"] -> error(field, :invalid_enum)
      true -> {:ok, value}
    end
  end

  defp normalize_node(raw, %{"type" => type} = schema, field)
       when type in ["number", "integer"] do
    cond do
      not is_number(raw) -> error(field, :invalid_number)
      type == "integer" and not is_integer(raw) -> error(field, :invalid_integer)
      raw * 0 != 0 -> error(field, :invalid_number)
      Map.has_key?(schema, "minimum") and raw < schema["minimum"] -> error(field, :out_of_range)
      Map.has_key?(schema, "maximum") and raw > schema["maximum"] -> error(field, :out_of_range)
      true -> {:ok, raw}
    end
  end

  defp normalize_node(_raw, _schema, field), do: error(field, :invalid_shape)

  defp validate_objectives(normalized) do
    areas = normalized.diagnosis.prioritized_areas
    objectives = Enum.map(normalized.smart_objectives, & &1.area)

    if length(Enum.uniq(areas)) == length(areas) and Enum.sort(areas) == Enum.sort(objectives),
      do: :ok,
      else: error(:smart_objectives, :area_objectives_required)
  end

  defp validate_kpis(kpis) do
    valid_baselines? =
      Enum.all?(kpis, fn kpi ->
        case kpi.baseline_status do
          "missing" -> is_nil(kpi.baseline)
          _ -> not is_nil(kpi.baseline) and not is_nil(kpi.source)
        end
      end)

    names = Enum.map(kpis, & &1.name)

    cond do
      length(Enum.uniq(names)) != length(names) -> error(:kpis, :duplicate_kpis)
      not valid_baselines? -> error(:kpis, :invalid_baseline)
      true -> :ok
    end
  end

  defp validate_day_ranges(plan) do
    if Enum.map(plan, &{&1.start_day, &1.end_day}) == @day_ranges,
      do: :ok,
      else: error(:action_plan_30_days, :invalid_day_ranges)
  end

  defp finalize_pilot(pilot, scaling) do
    end_day = pilot.start_day + pilot.duration_weeks * 7 - 1

    if scaling.review_day >= end_day,
      do: {:ok, %{pilot | end_day: end_day}},
      else: error(:scaling, :review_after_pilot_required)
  end

  defp calculate_roi(normalized) do
    budget = normalized.budget_roi
    assumptions = budget.assumptions
    costs = Map.values(budget.components)

    statuses = [
      normalized.diagnosis.baseline_status,
      assumptions.baseline_status
      | Enum.map(normalized.kpis, & &1.baseline_status)
    ]

    cond do
      "missing" in statuses or is_nil(assumptions.baseline_value) ->
        not_calculable("missing_baseline")

      "estimated" in statuses ->
        not_calculable("estimated_baseline")

      is_nil(assumptions.baseline_source) ->
        not_calculable("missing_baseline_source")

      is_nil(assumptions.monthly_benefit) ->
        not_calculable("missing_benefit")

      assumptions.benefit_currency != budget.currency or
          Enum.any?(costs, &(&1.currency != budget.currency)) ->
        not_calculable("currency_mismatch")

      assumptions.benefit_unit != "currency" or Enum.any?(costs, &(&1.unit != "currency")) ->
        not_calculable("unit_mismatch")

      assumptions.benefit_period != "monthly" or
          Enum.any?(costs, &(&1.period not in ["one_time", "monthly"])) ->
        not_calculable("period_mismatch")

      true ->
        compute_financials(costs, assumptions)
    end
  end

  defp compute_financials(costs, assumptions) do
    investment =
      costs |> Enum.filter(&(&1.period == "one_time")) |> Enum.map(& &1.amount) |> Enum.sum()

    recurring =
      costs |> Enum.filter(&(&1.period == "monthly")) |> Enum.map(& &1.amount) |> Enum.sum()

    net = assumptions.monthly_benefit - recurring

    cond do
      investment <= 0 ->
        not_calculable("zero_investment")

      net <= 0 ->
        not_calculable("nonpositive_net_benefit")

      true ->
        %{
          status: "calculated",
          percentage: (net * assumptions.horizon_months - investment) / investment * 100,
          payback_months: investment / net,
          reason: nil
        }
    end
  rescue
    ArithmeticError -> not_calculable("arithmetic_overflow")
  end

  defp not_calculable(reason),
    do: %{status: "not_calculable", percentage: nil, payback_months: nil, reason: reason}

  defp get(raw, key), do: Map.get(raw, key, Map.get(raw, to_string(key)))
  defp has_key?(raw, key), do: Map.has_key?(raw, key) or Map.has_key?(raw, to_string(key))
  defp scalar(nil), do: nil

  defp scalar(value) when is_binary(value) or is_number(value) or is_atom(value) do
    case String.trim(to_string(value)) do
      "" -> nil
      text -> text
    end
  end

  defp scalar(_value), do: nil
  defp error(field, code), do: {:error, {:invalid_tech_adoption, field, code}}

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
