defmodule Fullstack.JidoMarketAgents.Agents.SystemsStrategyOutputTest do
  use ExUnit.Case, async: true

  alias Fullstack.JidoMarketAgents.Agents.SystemsStrategyOutput

  @order [:acquisition, :authority, :conversion, :delivery_retention, :referrals, :information]

  test "normalize_map/1 rejects missing systems and non-three information KPIs" do
    raw = valid_strategy()
    result = SystemsStrategyOutput.normalize_map(raw)
    assert Enum.map(SystemsStrategyOutput.ordered_systems(result), &elem(&1, 0)) == @order
    assert result.systems.information.kpis == ["Leads", "Conversion", "Retention"]
    assert result.systems.authority.layers.success_cases == "Collect customer outcomes"
    assert SystemsStrategyOutput.normalize_map(Jason.decode!(Jason.encode!(raw))) == result
    assert SystemsStrategyOutput.normalize_map(Map.put(raw, :ignored, true)) == result

    for name <- @order do
      assert {:error, {:invalid_systems_strategy, ^name, :missing_system}} =
               SystemsStrategyOutput.normalize_map(%{
                 raw
                 | systems: Map.delete(raw.systems, name)
               })
    end

    for kpis <- [
          [],
          ["Leads"],
          ["Leads", "Conversion"],
          ["A", "B", "C", "D"],
          ["Leads", "Leads", "Retention"]
        ] do
      assert {:error, {:invalid_systems_strategy, :information, :three_kpis_required}} =
               SystemsStrategyOutput.normalize_map(
                 put_in(raw, [:systems, :information, :kpis], kpis)
               )
    end

    for layer <- [:personal_discourse, :third_party_endorsement, :success_cases] do
      broken = update_in(raw, [:systems, :authority, :layers], &Map.delete(&1, layer))

      assert {:error, {:invalid_systems_strategy, :authority, :invalid_layers}} =
               SystemsStrategyOutput.normalize_map(broken)
    end

    for phase <- [:qualification, :education_nurturing, :proposal, :close] do
      broken = update_in(raw, [:systems, :conversion, :phases], &Map.delete(&1, phase))

      assert {:error, {:invalid_systems_strategy, :conversion, :invalid_phases}} =
               SystemsStrategyOutput.normalize_map(broken)
    end

    for part <- [:channel, :incentive, :review_cadence] do
      broken =
        update_in(raw, [:systems, :information, :upward_information_flow], &Map.delete(&1, part))

      assert {:error, {:invalid_systems_strategy, :information, :invalid_upward_information_flow}} =
               SystemsStrategyOutput.normalize_map(broken)
    end

    assert {:error, {:invalid_systems_strategy, :sequencing, :invalid_order}} =
             SystemsStrategyOutput.normalize_map(%{
               raw
               | sequencing: Enum.reverse(raw.sequencing)
             })

    assert {:error, {:invalid_systems_strategy, :systems, :unexpected_system}} =
             SystemsStrategyOutput.normalize_map(%{
               raw
               | systems: Map.put(raw.systems, :seventh, %{})
             })

    assert {:error, {:invalid_systems_strategy, :acquisition, :invalid_priority}} =
             SystemsStrategyOutput.normalize_map(
               put_in(raw, [:systems, :acquisition, :priority], "urgent")
             )

    for key <- [:_pipeline, "_pipeline", :_meta, "_meta"] do
      assert {:error, {:reserved_key, _}} = SystemsStrategyOutput.normalize_map(%{key => %{}})
    end

    assert {:error, {:invalid_systems_strategy, :output, :invalid_shape}} =
             SystemsStrategyOutput.normalize_map(nil)
  end

  defp valid_strategy do
    system = %{
      current_state: "Needs improvement",
      priority: "high",
      actions: ["Run an experiment"],
      kpis: ["Leads"],
      pitfall: "Do not skip foundational work"
    }

    systems =
      Map.new(@order, &{&1, system})
      |> Map.update!(
        :authority,
        &Map.put(&1, :layers, %{
          personal_discourse: "Explain proven capabilities",
          third_party_endorsement: "Collect endorsements",
          success_cases: "Collect customer outcomes"
        })
      )
      |> Map.update!(
        :conversion,
        &Map.put(&1, :phases, %{
          qualification: "Identify suitable buyers",
          education_nurturing: "Explain the problem",
          proposal: "Present the offer",
          close: "Agree on the next step"
        })
      )
      |> Map.update!(
        :information,
        &Map.merge(&1, %{
          kpis: ["Leads", "Conversion", "Retention"],
          upward_information_flow: %{
            channel: "Weekly frontline feedback",
            incentive: "Recognize actionable feedback",
            review_cadence: "Weekly"
          }
        })
      )

    %{
      systems: systems,
      sequencing: Enum.map(@order, &to_string/1),
      quarterly_focus: "Improve acquisition"
    }
  end

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
