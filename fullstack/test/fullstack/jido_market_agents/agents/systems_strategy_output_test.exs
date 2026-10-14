defmodule Fullstack.JidoMarketAgents.Agents.SystemsStrategyOutputTest do
  use ExUnit.Case, async: true

  alias Fullstack.JidoMarketAgents.Agents.SystemsStrategyOutput

  @order [:acquisition, :authority, :conversion, :delivery_retention, :referrals, :information]

  test "schema/0 requires six ordered systems and strategy fields" do
    schema = SystemsStrategyOutput.schema()
    assert SystemsStrategyOutput.fields() == [:systems, :sequencing, :quarterly_focus]
    assert SystemsStrategyOutput.system_order() == @order
    assert schema["required"] == ~w(systems sequencing quarterly_focus)
    assert schema["additionalProperties"] == false
    systems = schema["properties"]["systems"]
    assert systems["required"] == Enum.map(@order, &to_string/1)
    assert systems["additionalProperties"] == false

    for name <- @order do
      item = systems["properties"][to_string(name)]
      assert item["additionalProperties"] == false

      for field <- ~w(current_state priority actions kpis pitfall),
          do: assert(field in item["required"])
    end

    authority = systems["properties"]["authority"]["properties"]["layers"]

    assert Enum.sort(authority["required"]) ==
             ~w(personal_discourse success_cases third_party_endorsement)

    conversion = systems["properties"]["conversion"]["properties"]["phases"]

    assert Enum.sort(conversion["required"]) ==
             ~w(close education_nurturing proposal qualification)

    information = systems["properties"]["information"]["properties"]
    assert information["kpis"]["minItems"] == 3
    assert information["kpis"]["maxItems"] == 3
    assert information["upward_information_flow"]["additionalProperties"] == false
  end
end
