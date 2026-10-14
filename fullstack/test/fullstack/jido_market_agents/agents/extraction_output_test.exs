defmodule Fullstack.JidoMarketAgents.Agents.ExtractionOutputTest do
  use ExUnit.Case, async: true

  alias Fullstack.JidoMarketAgents.Agents.ExtractionOutput

  @fields [
    :country,
    :city,
    :business_market,
    :initial_budget,
    :final_product_proposal,
    :product_price
  ]

  describe "schema/0" do
    test "declares all six extraction fields in both properties and required" do
      schema = ExtractionOutput.schema()

      for field <- @fields do
        key = to_string(field)
        assert Map.has_key?(schema["properties"], key)
        assert key in schema["required"]
      end
    end

    test "is a closed object schema (additionalProperties: false)" do
      schema = ExtractionOutput.schema()
      assert schema["type"] == "object"
      assert schema["additionalProperties"] == false
    end

    test "each property accepts either a string or null" do
      schema = ExtractionOutput.schema()

      for field <- @fields do
        property = schema["properties"][to_string(field)]
        assert property["type"] == ["string", "null"]
      end
    end

    test "schema/0 defines closed team_size status count and notes" do
      team_size = ExtractionOutput.schema()["properties"]["team_size"]

      assert team_size["type"] == ["object", "null"]

      assert team_size["properties"]["status"] == %{
               "type" => "string",
               "enum" => ["known", "unknown"]
             }

      assert team_size["properties"]["count"] == %{
               "type" => ["integer", "null"],
               "minimum" => 0
             }

      assert team_size["properties"]["notes"] == %{"type" => ["string", "null"]}
      assert team_size["required"] == ["status", "count", "notes"]
      assert team_size["additionalProperties"] == false
    end

    test "declares exactly the canonical field keys, no more, no fewer" do
      schema = ExtractionOutput.schema()
      expected_keys = ExtractionOutput.fields() |> Enum.map(&to_string/1) |> Enum.sort()

      assert Map.keys(schema["properties"]) |> Enum.sort() == expected_keys
      assert Enum.sort(schema["required"]) == expected_keys
    end

    test "round-trips through Jason.encode/1" do
      schema = ExtractionOutput.schema()
      assert {:ok, encoded} = Jason.encode(schema)
      assert {:ok, decoded} = Jason.decode(encoded)
      assert decoded == schema
    end

    test "an all-null extraction payload is structurally valid against the schema shape" do
      schema = ExtractionOutput.schema()

      all_null =
        Map.new(ExtractionOutput.fields(), fn field -> {to_string(field), nil} end)

      # Every required key is present; every value is one of the schema's
      # declared types (null); no keys outside `properties`.
      assert Enum.sort(Map.keys(all_null)) == Enum.sort(schema["required"])

      for {key, value} <- all_null do
        allowed_types = schema["properties"][key]["type"]

        assert (is_nil(value) and "null" in allowed_types) or
                 (is_binary(value) and "string" in allowed_types)
      end
    end
  end

  describe "fields/0" do
    test "fields/0 returns commercial and diagnosis fields in canonical order" do
      assert ExtractionOutput.fields() == [
               :country,
               :city,
               :business_market,
               :initial_budget,
               :final_product_proposal,
               :product_price,
               :team_size,
               :current_tools_systems,
               :repetitive_processes_pain_points,
               :digital_maturity,
               :metrics_baselines
             ]
    end

    test "keeps the six commercial field atoms in canonical relative order" do
      fields = ExtractionOutput.fields()

      commercial = [
        :country,
        :city,
        :business_market,
        :initial_budget,
        :final_product_proposal,
        :product_price
      ]

      assert Enum.filter(fields, &(&1 in commercial)) == commercial
    end
  end

  describe "normalize_map/1" do
    test "normalizes known keys from either string or atom map, ignores unknown keys" do
      normalized =
        ExtractionOutput.normalize_map(%{
          "country" => "Spain",
          "city" => "Madrid",
          "business_market" => "fintech",
          "initial_budget" => 50_000,
          "final_product_proposal" => "Payment app",
          "product_price" => 9.99,
          "unknown_field" => "ignored"
        })

      assert normalized == %{
               country: "Spain",
               city: "Madrid",
               business_market: "fintech",
               initial_budget: "50000",
               final_product_proposal: "Payment app",
               product_price: "9.99",
               team_size: nil,
               current_tools_systems: nil,
               repetitive_processes_pain_points: nil,
               digital_maturity: nil,
               metrics_baselines: nil
             }
    end

    test "missing keys normalize to nil" do
      normalized = ExtractionOutput.normalize_map(%{"country" => "Spain"})

      assert normalized.country == "Spain"
      assert normalized.city == nil
      assert normalized.business_market == nil
    end

    test "nested/non-scalar values normalize to nil" do
      normalized =
        ExtractionOutput.normalize_map(%{
          "country" => ["Spain"],
          "city" => %{"name" => "Madrid"}
        })

      assert normalized.country == nil
      assert normalized.city == nil
    end

    test "boolean values coerce to their string representation" do
      normalized = ExtractionOutput.normalize_map(%{"business_market" => false})
      assert normalized.business_market == "false"
    end
  end
end
