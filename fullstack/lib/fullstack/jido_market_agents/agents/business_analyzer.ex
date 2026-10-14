defmodule Fullstack.JidoMarketAgents.Agents.BusinessAnalyzer do
  @moduledoc "Jido agent aligning validated user capabilities with market investigation."
  use Jido.Agent,
    name: "business_analyzer",
    description: "Analyzes one viable business offer",
    schema: [
      validated_data: [type: :map, default: %{}],
      research_output: [type: :map, default: %{}],
      refinements: [type: :map, default: %{}],
      output_language: [type: :string, required: false, default: nil]
    ]

  alias Fullstack.JidoMarketAgents.Agents.{ExtractionOutput, MarketResearchOutput}

  defoverridable new: 1, set: 2

  def new(opts) do
    agent = super(opts)
    opts = Map.new(opts)

    case set(agent, opts[:state] || %{}) do
      {:ok, normalized} -> normalized
      {:error, reason} -> raise ArgumentError, "Invalid analyzer inputs: #{inspect(reason)}"
    end
  end

  @doc "Normalizes supplied maps and replaces each input, never deep-merging corrections."
  def set(agent, attrs) do
    Enum.reduce_while(Map.new(attrs), {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case normalize_input(key, value) do
        {:error, _} = error -> {:halt, error}
        result -> {:cont, {:ok, Map.put(acc, key, result)}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, %{agent | state: Map.merge(agent.state, normalized)}}
      error -> error
    end
  end

  defp normalize_input(:validated_data, value) when is_map(value) do
    case ExtractionOutput.normalize_map(value) do
      {:error, _} = error ->
        error

      data ->
        language = Map.get(value, :output_language, Map.get(value, "output_language"))

        if ExtractionOutput.valid_language?(language),
          do: Map.put(data, :output_language, language),
          else: data
    end
  end

  defp normalize_input(:research_output, value) when is_map(value),
    do: MarketResearchOutput.normalize_map(value)

  defp normalize_input(:refinements, value) when is_map(value), do: value
  defp normalize_input(:output_language, nil), do: nil

  defp normalize_input(:output_language, value) do
    if ExtractionOutput.valid_language?(value),
      do: value,
      else: {:error, {:invalid_input, :output_language}}
  end

  defp normalize_input(key, _value), do: {:error, {:invalid_input, key}}
end
