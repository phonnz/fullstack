defmodule Fullstack.JidoMarketAgents.Agents.TechAdoptionOutputTest do
  use ExUnit.Case, async: true

  alias Fullstack.JidoMarketAgents.Agents.TechAdoptionOutput

  test "normalize_map/1 enforces KPI pilot budget and baseline-safe ROI rules" do
    raw = valid_adoption()
    result = TechAdoptionOutput.normalize_map(raw)

    assert result.budget_roi.roi == %{
             status: "calculated",
             percentage: 20.0,
             payback_months: 10.0,
             reason: nil
           }

    assert result.pilot.end_day == 48
    assert result.pilot.end_day > 30
    assert TechAdoptionOutput.normalize_map(Jason.decode!(Jason.encode!(raw))) == result
    assert TechAdoptionOutput.normalize_map(Map.put(raw, :ignored, true)) == result
    assert TechAdoptionOutput.normalize_map(result) == result

    for count <- [0, 2, 6] do
      assert {:error, {:invalid_tech_adoption, :kpis, :invalid_cardinality}} =
               TechAdoptionOutput.normalize_map(%{
                 raw
                 | kpis: List.duplicate(hd(raw.kpis), count)
               })
    end

    for weeks <- [3, 9] do
      assert {:error, {:invalid_tech_adoption, :pilot, :out_of_range}} =
               TechAdoptionOutput.normalize_map(put_in(raw, [:pilot, :duration_weeks], weeks))
    end

    eight_weeks =
      raw |> put_in([:pilot, :duration_weeks], 8) |> put_in([:scaling, :review_day], 76)

    assert %{pilot: %{end_day: 76}} = TechAdoptionOutput.normalize_map(eight_weeks)

    assert {:error, {:invalid_tech_adoption, :scaling, :review_after_pilot_required}} =
             TechAdoptionOutput.normalize_map(put_in(raw, [:scaling, :review_day], 30))

    for component <- [:subscriptions, :development, :training, :integration, :maintenance] do
      broken = update_in(raw, [:budget_roi, :components], &Map.delete(&1, component))

      assert {:error, {:invalid_tech_adoption, :budget_roi, :missing_field}} =
               TechAdoptionOutput.normalize_map(broken)
    end

    assert {:error, {:invalid_tech_adoption, :budget_roi, :out_of_range}} =
             TechAdoptionOutput.normalize_map(
               put_in(raw, [:budget_roi, :components, :training, :amount], -1)
             )

    assert {:error, {:invalid_tech_adoption, :budget_roi, :invalid_number}} =
             TechAdoptionOutput.normalize_map(
               put_in(raw, [:budget_roi, :components, :training, :amount], "200")
             )

    missing =
      raw
      |> put_in([:budget_roi, :assumptions, :baseline_status], "missing")
      |> put_in([:budget_roi, :assumptions, :baseline_value], nil)

    estimated = put_in(raw, [:budget_roi, :assumptions, :baseline_status], "estimated")

    for {input, reason} <- [
          {missing, "missing_baseline"},
          {estimated, "estimated_baseline"},
          {put_in(raw, [:budget_roi, :assumptions, :baseline_value], nil), "missing_baseline"},
          {put_in(raw, [:budget_roi, :assumptions, :baseline_source], nil),
           "missing_baseline_source"},
          {put_in(raw, [:budget_roi, :assumptions, :monthly_benefit], nil), "missing_benefit"},
          {put_in(raw, [:diagnosis, :baseline_status], "estimated"), "estimated_baseline"}
        ] do
      assert_not_calculable(input, reason)
    end

    missing_kpi =
      update_in(raw, [:kpis], fn [first | rest] ->
        [%{first | baseline: nil, baseline_status: "missing", source: nil} | rest]
      end)

    assert_not_calculable(missing_kpi, "missing_baseline")

    zero =
      update_in(raw, [:budget_roi, :components], fn costs ->
        Map.new(costs, fn {key, cost} ->
          {key, if(cost.period == "one_time", do: %{cost | amount: 0}, else: cost)}
        end)
      end)

    assert_not_calculable(zero, "zero_investment")

    for benefit <- [0, 49, 50] do
      assert_not_calculable(
        put_in(raw, [:budget_roi, :assumptions, :monthly_benefit], benefit),
        "nonpositive_net_benefit"
      )
    end

    assert %{
             budget_roi: %{
               roi: %{status: "calculated", percentage: negative, payback_months: 1500.0}
             }
           } =
             TechAdoptionOutput.normalize_map(
               put_in(raw, [:budget_roi, :assumptions, :monthly_benefit], 51)
             )

    assert negative < 0

    for {path, value, reason} <- [
          {[:budget_roi, :assumptions, :benefit_currency], "USD", "currency_mismatch"},
          {[:budget_roi, :components, :training, :currency], "USD", "currency_mismatch"},
          {[:budget_roi, :assumptions, :benefit_unit], "hours", "unit_mismatch"},
          {[:budget_roi, :components, :training, :unit], "hours", "unit_mismatch"},
          {[:budget_roi, :assumptions, :benefit_period], "yearly", "period_mismatch"},
          {[:budget_roi, :components, :maintenance, :period], "yearly", "period_mismatch"}
        ] do
      assert_not_calculable(put_in(raw, path, value), reason)
    end

    assert_not_calculable(
      put_in(raw, [:budget_roi, :assumptions, :monthly_benefit], 1.0e308),
      "arithmetic_overflow"
    )

    reversed = %{raw | action_plan_30_days: Enum.reverse(raw.action_plan_30_days)}

    assert {:error, {:invalid_tech_adoption, :action_plan_30_days, :invalid_day_ranges}} =
             TechAdoptionOutput.normalize_map(reversed)

    assert {:error, {:invalid_tech_adoption, :smart_objectives, :area_objectives_required}} =
             TechAdoptionOutput.normalize_map(
               put_in(raw, [:smart_objectives, Access.at(0), :area], "Other")
             )

    for key <- [:_pipeline, "_pipeline", :_meta, "_meta"] do
      assert {:error, {:reserved_key, _}} = TechAdoptionOutput.normalize_map(%{key => %{}})
    end

    assert {:error, {:invalid_tech_adoption, :output, :invalid_shape}} =
             TechAdoptionOutput.normalize_map([])
  end

  defp assert_not_calculable(raw, reason) do
    assert %{
             budget_roi: %{
               roi: %{
                 status: "not_calculable",
                 percentage: nil,
                 payback_months: nil,
                 reason: ^reason
               }
             }
           } =
             TechAdoptionOutput.normalize_map(raw)
  end

  defp valid_adoption do
    objective = %{
      specific: "Automate one repeated task",
      measurable: "Reduce time by 20%",
      achievable: "Use existing resources",
      relevant: "Reduce operating cost",
      time_bound: "Within 8 weeks"
    }

    cost = %{amount: 0, currency: "EUR", unit: "currency", period: "one_time"}

    components =
      Map.new([:subscriptions, :development, :training, :integration, :maintenance], &{&1, cost})
      |> Map.put(:subscriptions, %{cost | amount: 20, period: "monthly"})
      |> Map.put(:maintenance, %{cost | amount: 30, period: "monthly"})
      |> Map.put(:development, %{cost | amount: 1000})
      |> Map.put(:training, %{cost | amount: 200})
      |> Map.put(:integration, %{cost | amount: 300})

    %{
      diagnosis: %{
        prioritized_areas: ["Support", "Operations"],
        baseline_status: "measured",
        notes: "Measured current work"
      },
      smart_objectives: Enum.map(["Support", "Operations"], &Map.put(objective, :area, &1)),
      kpis:
        Enum.map(["Cycle time", "Errors", "Cost"], fn name ->
          %{
            name: name,
            baseline: 20,
            baseline_status: "measured",
            unit: "count",
            period: "monthly",
            source: "Operations log",
            target: 16
          }
        end),
      tool_selection: %{
        tool: "Workflow automation",
        criteria:
          Map.new(
            [
              :implementation_ease,
              :scalability,
              :integration,
              :total_cost,
              :support_community,
              :compliance_security
            ],
            &{&1, "Evaluate this criterion against current systems"}
          )
      },
      budget_roi: %{
        currency: "EUR",
        components: components,
        assumptions: %{
          baseline_status: "measured",
          baseline_value: 100,
          baseline_source: "Operations log",
          monthly_benefit: 200,
          benefit_currency: "EUR",
          benefit_unit: "currency",
          benefit_period: "monthly",
          horizon_months: 12
        },
        roi: %{status: "calculated", percentage: 9999, payback_months: 0, reason: nil}
      },
      pilot: %{
        process: "Support triage",
        team: "Two team members",
        start_day: 21,
        duration_weeks: 4,
        end_day: 30,
        success_metrics: ["Cycle time"],
        feedback: "Weekly team feedback"
      },
      scaling: %{
        decision: "pending",
        approach: "phased",
        review_day: 48,
        lessons_learned: [],
        expansion_plan: "Scale only after pilot evidence"
      },
      action_plan_30_days:
        Enum.map([{1, 5}, {6, 10}, {11, 20}, {21, 30}], fn {first, last} ->
          %{
            start_day: first,
            end_day: last,
            phase: "Prepare and launch",
            actions: ["Complete this phase"]
          }
        end)
    }
  end

  test "schema/0 defines seven-step adoption deliverables" do
    schema = TechAdoptionOutput.schema()

    assert TechAdoptionOutput.fields() == [
             :diagnosis,
             :smart_objectives,
             :kpis,
             :tool_selection,
             :budget_roi,
             :pilot,
             :scaling,
             :action_plan_30_days
           ]

    assert schema["required"] == Enum.map(TechAdoptionOutput.fields(), &to_string/1)
    assert schema["additionalProperties"] == false
    properties = schema["properties"]
    assert properties["kpis"]["minItems"] == 3
    assert properties["kpis"]["maxItems"] == 5
    assert properties["kpis"]["items"]["additionalProperties"] == false

    assert properties["tool_selection"]["properties"]["criteria"]["required"] ==
             ~w(implementation_ease scalability integration total_cost support_community compliance_security)

    assert properties["budget_roi"]["properties"]["components"]["required"] ==
             ~w(subscriptions development training integration maintenance)

    assert properties["budget_roi"]["properties"]["roi"]["properties"]["status"]["enum"] ==
             ["calculated", "not_calculable"]

    assert properties["pilot"]["properties"]["duration_weeks"]["minimum"] == 4
    assert properties["pilot"]["properties"]["duration_weeks"]["maximum"] == 8
    assert properties["action_plan_30_days"]["minItems"] == 4
    assert properties["action_plan_30_days"]["maxItems"] == 4
    refute Map.has_key?(properties, "_pipeline")
    refute Map.has_key?(properties, "_meta")
  end
end
