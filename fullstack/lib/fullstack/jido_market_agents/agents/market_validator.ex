defmodule Fullstack.JidoMarketAgents.Agents.MarketValidator do
  @moduledoc """
  Jido agent that validates and extracts market entry data from natural language.
  Uses MIMO LLM to extract fields from free-text messages and accumulates
  state across multiple conversation turns.
  Required fields: country, business_market, initial_budget, final_product_proposal, product_price
  Optional: city
  """

  use Jido.Agent,
    name: "market_validator",
    description: "Validates and extracts market entry data from natural language",
    schema: [
      country: [type: :string, required: false],
      city: [type: :string, required: false],
      business_market: [type: :string, required: false],
      initial_budget: [type: :string, required: false],
      final_product_proposal: [type: :string, required: false],
      product_price: [type: :string, required: false],
      team_size: [type: :map, required: false, default: nil],
      current_tools_systems: [type: :map, required: false, default: nil],
      repetitive_processes_pain_points: [type: :map, required: false, default: nil],
      digital_maturity: [type: :map, required: false, default: nil],
      metrics_baselines: [type: :map, required: false, default: nil],
      output_language: [type: :string, required: false, default: nil],
      extraction_history: [type: :list, required: false, default: []]
    ]

  alias Fullstack.JidoMarketAgents.LLM
  alias Fullstack.JidoMarketAgents.Agents.ExtractionOutput

  @required_fields [
    :country,
    :business_market,
    :initial_budget,
    :final_product_proposal,
    :product_price
  ]

  @extractable_fields ExtractionOutput.fields()

  @doc """
  Pure extraction prompt shared by the text extraction path.

  Explains all eleven fields, requests explicit `"unknown"` states for
  structured diagnosis answers, and forbids inventing data.
  """
  @spec extraction_prompt() :: String.t()
  def extraction_prompt do
    """
    You are a data extraction assistant. Extract the following fields from the user's message.
    Return ONLY a JSON object with the extracted fields. If a field is not found in the message, omit it entirely.

    Commercial fields:
    - country: The target country for market entry
    - city: The target city (optional)
    - business_market: The industry or market sector
    - initial_budget: The starting budget amount (include currency if mentioned)
    - final_product_proposal: Description of the product or service to launch
    - product_price: The planned price for the product

    Diagnosis fields (structured objects):
    - team_size: {"status": "known"|"unknown", "count": integer|null, "notes": string|null}
    - current_tools_systems: {"status": "known"|"none"|"unknown", "items": [{"name", "category", "purpose", "integration_notes"}]}
    - repetitive_processes_pain_points: {"status": "known"|"none"|"unknown", "items": [{"process", "pain_point", "frequency", "time_cost", "error_cost"}]}
    - digital_maturity: {"level": "unknown"|"manual"|"digitized"|"integrated"|"optimized", "evidence": string|null}
    - metrics_baselines: {"status": "measured"|"estimated"|"none"|"unknown", "items": [{"metric", "value", "unit", "period", "source"}]}

    Explicit unknown states:
    - When the user does not provide a diagnosis answer, set its "status" to "unknown" (or "level": "unknown" for digital_maturity) instead of guessing.
    - Use "none" only when the user explicitly says there is nothing to report.

    Do not invent values. Never fabricate data that is not stated by the user.

    Return ONLY valid JSON, no other text.
    """
  end

  @doc """
  Extracts field values from a user message.

  If the message is a map, uses it directly (fast path, no LLM call).
  If the message is a string, calls the MIMO LLM to extract fields.

  Returns {:ok, updated_agent} on success.
  Returns {:error, reason} if the LLM call or JSON parsing fails for string messages.
  """
  def extract_fields(agent, message) when is_binary(message) do
    system_prompt = extraction_prompt()

    messages = [
      %{"role" => "system", "content" => system_prompt},
      %{"role" => "user", "content" => message}
    ]

    case LLM.chat_completion(:validator, messages,
           response_format: {:json_object, ExtractionOutput.schema()}
         ) do
      {:ok, content} ->
        case parse_llm_json(content) do
          {:ok, extracted, meta} ->
            merge_extracted(agent, extracted, meta, meta.language_switch_requested, message)

          {:error, {:invalid_diagnosis, _field, _code}} = error ->
            error

          {:error, reason} ->
            {:error, {:parse_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:llm_failed, reason}}
    end
  end

  def extract_fields(agent, message) when is_map(message) do
    # Fast path: map input — extract directly without LLM. Normalization
    # validates the domain data explicitly (generated `set/2` deep-merges
    # without validation), so a malformed diagnosis is rejected before any
    # merge and prior data stays unchanged.
    case normalize_map(message) do
      {:error, _reason} = error ->
        error

      extracted ->
        meta = ExtractionOutput.language_metadata(message)
        switch? = explicit_language_key?(message) or meta.language_switch_requested
        merge_extracted(agent, extracted, meta, switch?, "map_input")
    end
  end

  @doc """
  Checks which required fields are still nil/empty.

  Required: the five commercial scalars (city stays optional) plus an
  explicit answer for every diagnosis field. A normalized diagnosis map
  with an explicit `"unknown"` state counts as answered; a top-level
  `nil` diagnosis value stays missing.

  Returns:
  - {:complete, data_map} if all required fields present
  - {:incomplete, missing_fields_list} if some are missing
  """
  def check_completeness(agent) do
    required = @required_fields ++ ExtractionOutput.diagnosis_fields()

    missing =
      Enum.filter(required, fn field ->
        missing?(agent.state, field)
      end)

    case missing do
      [] -> {:complete, extract_data(agent)}
      fields -> {:incomplete, fields}
    end
  end

  @doc """
  Returns a specific prompt asking ONLY for the missing fields.
  """
  def format_missing_prompt(missing_fields) do
    field_names = Enum.map_join(missing_fields, ", ", &humanize/1)
    "Thanks! I still need: #{field_names}. Please provide these details."
  end

  @doc """
  Returns a summary of what has been extracted so far.
  """
  def format_extraction_summary(agent) do
    lines =
      @extractable_fields
      |> Enum.map(fn field ->
        value = Map.get(agent.state, field)
        label = capitalize_humanize(field)

        case value do
          nil -> "  - #{label}: (not provided)"
          "" -> "  - #{label}: (not provided)"
          v when is_map(v) -> "  - #{label}: #{format_diagnosis_value(field, v)}"
          v -> "  - #{label}: #{v}"
        end
      end)

    missing =
      @required_fields
      |> Enum.filter(fn field ->
        value = Map.get(agent.state, field)
        is_nil(value) or value == ""
      end)

    missing_text =
      case missing do
        [] -> "  - None — all required fields collected!"
        fields -> "  - Missing: #{Enum.map_join(fields, ", ", &humanize/1)}"
      end

    """
    Here's what I have so far:
    #{Enum.join(lines, "\n")}
    #{missing_text}
    """
    |> String.trim()
  end

  # Backward-compatible alias for existing code (Conversation GenServer uses this)
  def validate_data(agent) do
    case check_completeness(agent) do
      {:complete, data} -> {:complete, data}
      {:incomplete, fields} -> {:missing, fields}
    end
  end

  # Private helpers

  defp missing?(state, field) do
    value = Map.get(state, field)
    is_nil(value) or value == ""
  end

  # Pure merge selection: which extracted values may update state. Omitted
  # values (normalized to nil) and empty strings never erase prior state.
  @spec select_updates(map()) :: %{atom() => term()}
  def select_updates(extracted_map) do
    extracted_map
    |> Enum.filter(fn {_k, v} -> not is_nil(v) and v != "" end)
    |> Map.new(fn {k, v} ->
      key = if is_binary(k), do: String.to_existing_atom(k), else: k
      {key, v}
    end)
  end

  defp merge_extracted(agent, extracted_map, meta, switch?, source_message) do
    # Only non-nil extracted values update state, using ATOM keys
    updates = select_updates(extracted_map)

    history_entry = %{
      source: source_message,
      extracted: updates,
      status: :ok
    }

    history = Map.get(agent.state, :extraction_history, []) ++ [history_entry]

    # Normalize-and-replace (design (d)): updates carry COMPLETE normalized
    # field maps, and the shallow top-level merge replaces each affected
    # field wholesale. Rebuilding a fresh validator from that replacement
    # map keeps Jido set/2 deep-merge from preserving stale nested keys.
    replacement =
      agent.state
      |> Map.merge(updates)
      |> Map.put(:output_language, resolve_output_language(agent, meta, switch?))
      |> Map.put(:extraction_history, history)

    rebuild(agent, replacement)
  end

  # Pure language update policy (design (c)), isolated from field merging:
  # the first valid hint sets the language (falling back to the system
  # default when none arrives); later hints apply only on an explicit
  # switch request, so the language never drifts silently. Invalid hints
  # normalize to nil upstream and behave exactly like missing ones.
  defp resolve_output_language(agent, %{output_language: hint}, switch?) do
    prior = Map.get(agent.state, :output_language)

    cond do
      not is_nil(hint) and (is_nil(prior) or switch?) -> hint
      is_nil(prior) -> ExtractionOutput.default_language()
      true -> prior
    end
  end

  defp explicit_language_key?(message) do
    Map.has_key?(message, :output_language) or Map.has_key?(message, "output_language")
  end

  defp rebuild(agent, replacement) do
    with {:ok, fresh} <- __MODULE__.set(__MODULE__.new(), replacement) do
      {:ok, %{fresh | id: agent.id}}
    end
  end

  defp parse_llm_json(content) when is_binary(content) do
    # Decode the final answer once, accepting an optional enclosing JSON fence.
    content = String.trim(content)

    json_str =
      case Regex.run(~r/\A```(?:json)?\s*(.*?)\s*```\z/s, content, capture: :all_but_first) do
        [json] -> json
        nil -> content
      end

    case Jason.decode(json_str) do
      {:ok, map} when is_map(map) ->
        case normalize_map(map) do
          {:error, _reason} = error -> error
          normalized -> {:ok, normalized, ExtractionOutput.language_metadata(map)}
        end

      {:ok, _other} ->
        {:error, :not_a_map}

      {:error, reason} ->
        {:error, {:json_parse, reason}}
    end
  end

  defp parse_llm_json(_content), do: {:error, :invalid_content}

  defp normalize_map(map), do: ExtractionOutput.normalize_map(map)

  defp extract_data(agent) do
    base = %{
      country: agent.state.country,
      city: Map.get(agent.state, :city),
      business_market: agent.state.business_market,
      initial_budget: agent.state.initial_budget,
      final_product_proposal: agent.state.final_product_proposal,
      product_price: agent.state.product_price
    }

    Enum.reduce(ExtractionOutput.diagnosis_fields(), base, fn field, acc ->
      Map.put(acc, field, Map.get(agent.state, field))
    end)
  end

  defp humanize(:business_market), do: "business market"
  defp humanize(:initial_budget), do: "initial budget"
  defp humanize(:final_product_proposal), do: "final product proposal"
  defp humanize(:product_price), do: "product price"
  defp humanize(:team_size), do: "team size"
  defp humanize(:current_tools_systems), do: "current tools and systems"
  defp humanize(:repetitive_processes_pain_points), do: "repetitive processes and pain points"
  defp humanize(:digital_maturity), do: "digital maturity"
  defp humanize(:metrics_baselines), do: "baseline metrics"
  defp humanize(field), do: field |> to_string() |> String.replace("_", " ")

  # Status-aware display for normalized diagnosis maps: stable,
  # human-readable summaries instead of raw `inspect/1` output.
  defp format_diagnosis_value(:team_size, %{status: "known", count: count}), do: "#{count}"
  defp format_diagnosis_value(:team_size, %{status: status}), do: status
  defp format_diagnosis_value(:digital_maturity, %{level: level}), do: level

  defp format_diagnosis_value(field, %{items: items}) when is_list(items) and items != [] do
    noun = if length(items) == 1, do: "item", else: "items"
    labels = Enum.map_join(items, ", ", &item_label(field, &1))
    "#{length(items)} #{noun} (#{labels})"
  end

  defp format_diagnosis_value(_field, %{status: status}), do: status

  defp item_label(:current_tools_systems, %{name: name}), do: name
  defp item_label(:repetitive_processes_pain_points, %{process: process}), do: process
  defp item_label(:metrics_baselines, %{metric: metric}), do: metric
  defp item_label(_field, _item), do: "item"

  defp capitalize_humanize(field) do
    case humanize(field) do
      <<first::utf8, rest::binary>> -> String.upcase(<<first::utf8>>) <> rest
      other -> other
    end
  end
end
