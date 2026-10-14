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

  @commercial_fields [
    :country,
    :city,
    :business_market,
    :initial_budget,
    :final_product_proposal,
    :product_price
  ]

  @diagnosis_fields [
    :team_size,
    :current_tools_systems,
    :repetitive_processes_pain_points,
    :digital_maturity,
    :metrics_baselines
  ]

  @fields @commercial_fields ++ @diagnosis_fields

  @team_size_statuses ["known", "unknown"]

  @collection_statuses ["known", "none", "unknown"]

  @maturity_levels ["unknown", "manual", "digitized", "integrated", "optimized"]

  @doc "Returns the eleven extractable field atoms, in canonical order."
  @spec fields() :: [atom()]
  def fields, do: @fields

  @doc "Returns the six commercial scalar field atoms, in canonical order."
  @spec commercial_fields() :: [atom()]
  def commercial_fields, do: @commercial_fields

  @doc "Returns the five structured diagnosis field atoms, in canonical order."
  @spec diagnosis_fields() :: [atom()]
  def diagnosis_fields, do: @diagnosis_fields

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
      |> Map.put("digital_maturity", digital_maturity_schema())
      |> Map.put("metrics_baselines", metrics_baselines_schema())

    %{
      "type" => "object",
      "properties" => properties,
      "required" => Enum.map(@fields, &to_string/1),
      "additionalProperties" => false
    }
  end

  defp nullable_string, do: %{"type" => ["string", "null"]}

  defp enum_string(values), do: %{"type" => "string", "enum" => values}

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
        "status" => enum_string(@team_size_statuses),
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
        "status" => enum_string(@collection_statuses),
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
        "status" => enum_string(@collection_statuses),
        "items" => item_array(item)
      },
      ["status", "items"]
    )
  end

  defp digital_maturity_schema do
    closed_object(
      ["object", "null"],
      %{
        "level" => enum_string(@maturity_levels),
        "evidence" => nullable_string()
      },
      ["level", "evidence"]
    )
  end

  defp metrics_baselines_schema do
    item =
      closed_object(
        "object",
        %{
          "metric" => %{"type" => "string"},
          "value" => %{"type" => ["number", "null"]},
          "unit" => nullable_string(),
          "period" => nullable_string(),
          "source" => nullable_string()
        },
        ["metric", "value", "unit", "period", "source"]
      )

    closed_object(
      ["object", "null"],
      %{
        "status" => enum_string(["measured", "estimated", "none", "unknown"]),
        "items" => item_array(item)
      },
      ["status", "items"]
    )
  end

  @doc """
  Normalizes a raw map (string or atom keys, from LLM-parsed JSON or a
  caller-supplied map) into a map with exactly the eleven field atoms as
  keys.

  Commercial scalars keep the lenient legacy coercion:

    * a missing key normalizes to `nil`;
    * `nil` stays `nil`;
    * binary, numeric and atom scalar values coerce to strings via
      `to_string/1`;
    * any other value (list, map, tuple, ...) normalizes to `nil`;
    * keys outside `fields/0` are ignored.

  Structured diagnosis values are validated (see `validate_diagnosis/1`):
  a malformed non-null diagnosis value returns
  `{:error, {:invalid_diagnosis, field, code}}` instead of being coerced
  into a plausible answer. Valid diagnosis values normalize to complete
  nested maps with atom keys and every declared sub-key present, so a
  full-field replacement can never preserve stale nested values.
  """
  @spec normalize_map(map()) ::
          %{atom() => term()} | {:error, {:invalid_diagnosis, atom(), atom()}}
  def normalize_map(map) do
    with {:ok, diagnosis} <- validate_diagnosis(map) do
      Map.merge(commercial_values(map), diagnosis)
    end
  end

  @doc """
  Validates and normalizes the five structured diagnosis values of a raw
  map. Missing or top-level `nil` values normalize to `nil`; malformed
  non-null values return a tagged field error and leave prior data
  unchanged (the caller never merges an errored result).
  """
  @spec validate_diagnosis(map()) ::
          {:ok, %{atom() => term() | nil}} | {:error, {:invalid_diagnosis, atom(), atom()}}
  def validate_diagnosis(map) do
    Enum.reduce_while(@diagnosis_fields, {:ok, %{}}, fn field, {:ok, acc} ->
      case normalize_diagnosis_field(field, fetch_field(map, field)) do
        {:ok, normalized} -> {:cont, {:ok, Map.put(acc, field, normalized)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp commercial_values(map) do
    Map.new(@commercial_fields, fn field ->
      {field, normalize_value(fetch_field(map, field))}
    end)
  end

  defp fetch_field(map, field), do: Map.get(map, field, Map.get(map, to_string(field)))

  defp normalize_diagnosis_field(:team_size, raw), do: normalize_team_size(raw)
  defp normalize_diagnosis_field(:digital_maturity, raw), do: normalize_digital_maturity(raw)

  defp normalize_diagnosis_field(:current_tools_systems, raw),
    do: normalize_item_collection(:current_tools_systems, raw, &normalize_tool_item/1)

  defp normalize_diagnosis_field(:repetitive_processes_pain_points, raw),
    do:
      normalize_item_collection(
        :repetitive_processes_pain_points,
        raw,
        &normalize_pain_item/1
      )

  defp normalize_diagnosis_field(_field, raw), do: {:ok, normalize_value(raw)}

  defp normalize_item_collection(_field, nil, _item_fun), do: {:ok, nil}

  defp normalize_item_collection(field, raw, item_fun) when is_map(raw) do
    items = fetch_field(raw, :items)

    case enum_value(fetch_field(raw, :status)) do
      status when status in ["none", "unknown"] ->
        if is_nil(items) or items == [] do
          {:ok, %{status: status, items: []}}
        else
          {:error, {:invalid_diagnosis, field, :items_not_allowed}}
        end

      "known" ->
        normalize_known_items(field, items, item_fun)

      _other ->
        {:error, {:invalid_diagnosis, field, :invalid_status}}
    end
  end

  defp normalize_item_collection(field, _raw, _item_fun),
    do: {:error, {:invalid_diagnosis, field, :invalid_shape}}

  defp normalize_known_items(field, [], _item_fun),
    do: {:error, {:invalid_diagnosis, field, :items_required}}

  defp normalize_known_items(field, items, item_fun) when is_list(items) do
    result =
      Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
        case item_fun.(item) do
          {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)

    case result do
      {:ok, normalized} -> {:ok, %{status: "known", items: Enum.reverse(normalized)}}
      error -> error
    end
  end

  defp normalize_known_items(field, nil, _item_fun),
    do: {:error, {:invalid_diagnosis, field, :items_required}}

  defp normalize_known_items(field, _items, _item_fun),
    do: {:error, {:invalid_diagnosis, field, :invalid_items}}

  defp normalize_team_size(nil), do: {:ok, nil}

  defp normalize_team_size(raw) when is_map(raw) do
    notes = fetch_field(raw, :notes)

    case enum_value(fetch_field(raw, :status)) do
      "known" ->
        with {:ok, count} <- known_count(fetch_field(raw, :count)),
             {:ok, notes} <- nullable_text(:team_size, notes, :invalid_notes) do
          {:ok, %{status: "known", count: count, notes: notes}}
        end

      "unknown" ->
        with :ok <- cleared_count(fetch_field(raw, :count)),
             {:ok, notes} <- nullable_text(:team_size, notes, :invalid_notes) do
          {:ok, %{status: "unknown", count: nil, notes: notes}}
        end

      _other ->
        {:error, {:invalid_diagnosis, :team_size, :invalid_status}}
    end
  end

  defp normalize_team_size(_raw), do: {:error, {:invalid_diagnosis, :team_size, :invalid_shape}}

  defp normalize_digital_maturity(nil), do: {:ok, nil}

  defp normalize_digital_maturity(raw) when is_map(raw) do
    case enum_value(fetch_field(raw, :level)) do
      level when level in @maturity_levels ->
        with {:ok, evidence} <-
               nullable_text(:digital_maturity, fetch_field(raw, :evidence), :invalid_evidence) do
          {:ok, %{level: level, evidence: evidence}}
        end

      _other ->
        {:error, {:invalid_diagnosis, :digital_maturity, :invalid_level}}
    end
  end

  defp normalize_digital_maturity(_raw),
    do: {:error, {:invalid_diagnosis, :digital_maturity, :invalid_shape}}

  defp normalize_tool_item(item) when is_map(item) do
    with {:ok, name} <- required_text(fetch_field(item, :name)),
         {:ok, category} <- item_text(fetch_field(item, :category)),
         {:ok, purpose} <- item_text(fetch_field(item, :purpose)),
         {:ok, integration_notes} <- item_text(fetch_field(item, :integration_notes)) do
      {:ok,
       %{
         name: name,
         category: category,
         purpose: purpose,
         integration_notes: integration_notes
       }}
    else
      {:error, _reason} -> {:error, {:invalid_diagnosis, :current_tools_systems, :invalid_item}}
    end
  end

  defp normalize_tool_item(_item),
    do: {:error, {:invalid_diagnosis, :current_tools_systems, :invalid_item}}

  defp normalize_pain_item(item) when is_map(item) do
    with {:ok, process} <- required_text(fetch_field(item, :process)),
         {:ok, pain_point} <- required_text(fetch_field(item, :pain_point)),
         {:ok, frequency} <- item_text(fetch_field(item, :frequency)),
         {:ok, time_cost} <- item_text(fetch_field(item, :time_cost)),
         {:ok, error_cost} <- item_text(fetch_field(item, :error_cost)) do
      {:ok,
       %{
         process: process,
         pain_point: pain_point,
         frequency: frequency,
         time_cost: time_cost,
         error_cost: error_cost
       }}
    else
      {:error, _reason} ->
        {:error, {:invalid_diagnosis, :repetitive_processes_pain_points, :invalid_item}}
    end
  end

  defp normalize_pain_item(_item),
    do: {:error, {:invalid_diagnosis, :repetitive_processes_pain_points, :invalid_item}}

  defp required_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, :blank}
      _not_blank -> {:ok, value}
    end
  end

  defp required_text(_value), do: {:error, :not_text}

  defp item_text(nil), do: {:ok, nil}
  defp item_text(value) when is_binary(value), do: {:ok, value}
  defp item_text(_value), do: {:error, :not_text}

  defp known_count(count) when is_integer(count) and count >= 0, do: {:ok, count}
  defp known_count(_count), do: {:error, {:invalid_diagnosis, :team_size, :invalid_count}}

  defp cleared_count(nil), do: :ok
  defp cleared_count(_count), do: {:error, {:invalid_diagnosis, :team_size, :invalid_count}}

  defp enum_value(value) when is_binary(value) or is_atom(value), do: to_string(value)
  defp enum_value(_value), do: nil

  defp nullable_text(_field, nil, _code), do: {:ok, nil}
  defp nullable_text(_field, value, _code) when is_binary(value), do: {:ok, value}

  defp nullable_text(field, _value, code),
    do: {:error, {:invalid_diagnosis, field, code}}

  defp normalize_value(nil), do: nil

  defp normalize_value(value) when is_binary(value) or is_number(value) or is_atom(value),
    do: to_string(value)

  defp normalize_value(_value), do: nil
end
