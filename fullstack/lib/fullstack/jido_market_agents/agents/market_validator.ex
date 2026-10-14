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
  Extracts field values from a user message.

  If the message is a map, uses it directly (fast path, no LLM call).
  If the message is a string, calls the MIMO LLM to extract fields.

  Returns {:ok, updated_agent} on success.
  Returns {:error, reason} if the LLM call or JSON parsing fails for string messages.
  """
  def extract_fields(agent, message) when is_binary(message) do
    system_prompt = """
    You are a data extraction assistant. Extract the following fields from the user's message.
    Return ONLY a JSON object with the extracted fields. If a field is not found in the message, omit it entirely.

    Fields to extract:
    - country: The target country for market entry
    - city: The target city (optional)
    - business_market: The industry or market sector
    - initial_budget: The starting budget amount (include currency if mentioned)
    - final_product_proposal: Description of the product or service to launch
    - product_price: The planned price for the product

    Return ONLY valid JSON, no other text.
    """

    messages = [
      %{"role" => "system", "content" => system_prompt},
      %{"role" => "user", "content" => message}
    ]

    case LLM.chat_completion(:validator, messages,
           response_format: {:json_object, ExtractionOutput.schema()}
         ) do
      {:ok, content} ->
        case parse_llm_json(content) do
          {:ok, extracted} ->
            merge_extracted(agent, extracted, message)

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
      {:error, {:invalid_diagnosis, _field, _code}} = error -> error
      extracted -> merge_extracted(agent, extracted, "map_input")
    end
  end

  @doc """
  Checks which required fields are still nil/empty.

  Returns:
  - {:complete, data_map} if all required fields present
  - {:incomplete, missing_fields_list} if some are missing
  """
  def check_completeness(agent) do
    missing =
      @required_fields
      |> Enum.filter(fn field ->
        value = Map.get(agent.state, field)
        is_nil(value) or value == ""
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
          v when is_map(v) -> "  - #{label}: #{inspect(v)}"
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

  defp merge_extracted(agent, extracted_map, source_message) do
    # Build update map with only non-nil extracted values, using ATOM keys
    updates =
      extracted_map
      |> Enum.filter(fn {_k, v} -> not is_nil(v) and v != "" end)
      |> Map.new(fn {k, v} ->
        key = if is_binary(k), do: String.to_existing_atom(k), else: k
        {key, v}
      end)

    history_entry = %{
      source: source_message,
      extracted: updates,
      status: :ok
    }

    case append_history(agent, history_entry) do
      {:ok, agent_with_history} ->
        __MODULE__.set(agent_with_history, updates)

      error ->
        error
    end
  end

  defp append_history(agent, entry) do
    current_history = Map.get(agent.state, :extraction_history, [])
    updated_history = current_history ++ [entry]
    __MODULE__.set(agent, %{extraction_history: updated_history})
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
          {:error, {:invalid_diagnosis, _field, _code}} = error -> error
          normalized -> {:ok, normalized}
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
    %{
      country: agent.state.country,
      city: Map.get(agent.state, :city),
      business_market: agent.state.business_market,
      initial_budget: agent.state.initial_budget,
      final_product_proposal: agent.state.final_product_proposal,
      product_price: agent.state.product_price
    }
  end

  defp humanize(:business_market), do: "business market"
  defp humanize(:initial_budget), do: "initial budget"
  defp humanize(:final_product_proposal), do: "final product proposal"
  defp humanize(:product_price), do: "product price"
  defp humanize(field), do: field |> to_string() |> String.replace("_", " ")

  defp capitalize_humanize(field) do
    case humanize(field) do
      <<first::utf8, rest::binary>> -> String.upcase(<<first::utf8>>) <> rest
      other -> other
    end
  end
end
