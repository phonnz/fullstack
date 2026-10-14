defmodule Fullstack.JidoMarketAgents.Agents.ExtractionOutput do
  @moduledoc """
  Shared domain contract for the market-entry extraction fields: the six
  commercial scalars (`country`, `city`, `business_market`, `initial_budget`,
  `final_product_proposal`, `product_price`) plus the five structured
  diagnosis fields (`team_size`, `current_tools_systems`,
  `repetitive_processes_pain_points`, `digital_maturity`,
  `metrics_baselines`).

  This module owns:

    * `fields/0` — the canonical list of extractable field atoms.
    * `schema/0` — a closed JSON-schema object describing the wire shape
      passed to `LLM.chat_completion/3` as
      `{:json_object, ExtractionOutput.schema()}`. It is a CLI generation
      contract only: nothing on the Mimo side reads its contents (Mimo
      translates `{:json_object, _}` to `json_mode: true` and discards the
      schema), and no CLI adapter consumes it yet.
    * `normalize_map/1` — the pure normalization step shared by
      `MarketValidator`'s LLM-parsed JSON path and its map fast path.
      Missing keys normalize to `nil`; scalar (string/number/boolean/atom)
      values coerce to strings; nested/composite values normalize to `nil`;
      unknown keys are ignored.

  ## Wire schema vs. business completeness

  `schema/0` describes what a CLI-generation backend may produce: all six
  keys are marked `required` with type `["string", "null"]`, and an
  all-null object is valid against it. This is a distinct concern from
  business completeness (five required fields, `city` optional), which
  remains owned by `MarketValidator.check_completeness/1` and is untouched
  by this module.
  """

  @fields [
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

  @doc "Returns the eleven extractable field atoms, in canonical order."
  @spec fields() :: [atom()]
  def fields, do: @fields

  @doc """
  Returns a closed JSON-schema object for CLI structured-output generation.

  All six fields from `fields/0` appear in both `"properties"` and
  `"required"`. `"additionalProperties"` is `false`. Each property has
  type `["string", "null"]`, so an all-null object (no known values yet)
  is valid against this schema. Requiring the keys does not require known
  values: prompts explicitly use `null` for absent information.
  """
  @spec schema() :: map()
  def schema do
    properties =
      @fields
      |> Map.new(fn field -> {to_string(field), nullable_string()} end)
      |> Map.put("team_size", team_size_schema())
      |> Map.put("current_tools_systems", current_tools_systems_schema())
      |> Map.put(
        "repetitive_processes_pain_points",
        repetitive_processes_pain_points_schema()
      )

    %{
      "type" => "object",
      "properties" => properties,
      "required" => Enum.map(@fields, &to_string/1),
      "additionalProperties" => false
    }
  end

  defp nullable_string, do: %{"type" => ["string", "null"]}

  defp closed_object(type, properties, required) do
    %{
      "type" => type,
      "properties" => properties,
      "required" => required,
      "additionalProperties" => false
    }
  end

  defp team_size_schema do
    closed_object(
      ["object", "null"],
      %{
        "status" => %{"type" => "string", "enum" => ["known", "unknown"]},
        "count" => %{"type" => ["integer", "null"], "minimum" => 0},
        "notes" => nullable_string()
      },
      ["status", "count", "notes"]
    )
  end

  defp item_array(item), do: %{"type" => "array", "items" => item}

  defp current_tools_systems_schema do
    item =
      closed_object(
        "object",
        %{
          "name" => %{"type" => "string"},
          "category" => nullable_string(),
          "purpose" => nullable_string(),
          "integration_notes" => nullable_string()
        },
        ["name", "category", "purpose", "integration_notes"]
      )

    closed_object(
      ["object", "null"],
      %{
        "status" => %{"type" => "string", "enum" => ["known", "none", "unknown"]},
        "items" => item_array(item)
      },
      ["status", "items"]
    )
  end

  defp repetitive_processes_pain_points_schema do
    item =
      closed_object(
        "object",
        %{
          "process" => %{"type" => "string"},
          "pain_point" => %{"type" => "string"},
          "frequency" => nullable_string(),
          "time_cost" => nullable_string(),
          "error_cost" => nullable_string()
        },
        ["process", "pain_point", "frequency", "time_cost", "error_cost"]
      )

    closed_object(
      ["object", "null"],
      %{
        "status" => %{"type" => "string", "enum" => ["known", "none", "unknown"]},
        "items" => item_array(item)
      },
      ["status", "items"]
    )
  end

  @doc """
  Normalizes a raw map (string or atom keys, from LLM-parsed JSON or a
  caller-supplied map) into a map with exactly the six field atoms as
  keys.

  Behavior, preserved verbatim from `MarketValidator`'s prior private
  implementation:

    * a missing key normalizes to `nil`;
    * `nil` stays `nil`;
    * binary, numeric and atom scalar values coerce to strings via
      `to_string/1`;
    * any other value (list, map, tuple, ...) normalizes to `nil`;
    * keys outside `fields/0` are ignored.
  """
  @spec normalize_map(map()) :: %{atom() => String.t() | nil}
  def normalize_map(map) do
    Map.new(@fields, fn field ->
      value = Map.get(map, field, Map.get(map, to_string(field)))
      {field, normalize_value(value)}
    end)
  end

  defp normalize_value(nil), do: nil

  defp normalize_value(value) when is_binary(value) or is_number(value) or is_atom(value),
    do: to_string(value)

  defp normalize_value(_value), do: nil
end
