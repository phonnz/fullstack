defmodule Fullstack.JidoMarketAgents.Agents.TechAdoptionOutputTest do
  use ExUnit.Case, async: true

  alias Fullstack.JidoMarketAgents.Agents.TechAdoptionOutput

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
