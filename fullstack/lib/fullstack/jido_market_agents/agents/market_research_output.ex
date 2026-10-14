defmodule Fullstack.JidoMarketAgents.Agents.MarketResearchOutput do
  @moduledoc "Closed market investigation contract for the no-retrieval research stage."

  @fields [:market_evidence, :market_gaps, :demand_signals, :sources, :limitations]

  def fields, do: @fields

  @doc "Normalizes unverified evidence without inventing retrieval provenance."
  def normalize_map(raw) when is_map(raw) do
    with :ok <- reject_reserved(raw),
         :ok <- no_sources(get(raw, :sources)),
         {:ok, evidence} <- normalize_items(:market_evidence, get(raw, :market_evidence)),
         {:ok, gaps} <- normalize_items(:market_gaps, get(raw, :market_gaps)),
         {:ok, signals} <- normalize_items(:demand_signals, get(raw, :demand_signals)),
         {:ok, limitations} <- normalize_limitations(get(raw, :limitations)) do
      %{
        market_evidence: evidence,
        market_gaps: gaps,
        demand_signals: signals,
        sources: [],
        limitations: limitations
      }
    end
  end

  def normalize_map(_raw), do: error(:output, :invalid_shape)

  defp reject_reserved(raw) do
    Enum.find_value([:_pipeline, :_meta], :ok, fn key ->
      if Map.has_key?(raw, key) or Map.has_key?(raw, to_string(key)),
        do: {:error, {:reserved_key, key}}
    end)
  end

  defp no_sources(value) when value in [nil, []], do: :ok
  defp no_sources(_value), do: error(:sources, :retrieval_unavailable)

  defp normalize_items(_field, nil), do: {:ok, []}

  defp normalize_items(field, items) when is_list(items) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case normalize_evidence(field, item) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp normalize_items(field, _items), do: error(field, :invalid_items)

  defp normalize_evidence(field, item) when is_map(item) do
    status = scalar(get(item, :verification_status))

    cond do
      get(item, :verified) not in [nil, false] or status == "verified" ->
        error(field, :verified_claim)

      status not in [nil, "unverified"] ->
        error(field, :invalid_verification_status)

      get(item, :evidence_refs) not in [nil, []] ->
        error(field, :unresolved_evidence_refs)

      is_nil(scalar(get(item, :claim))) ->
        error(field, :invalid_claim)

      true ->
        with {:ok, confidence} <- normalize_confidence(field, get(item, :confidence)) do
          {:ok,
           %{
             claim: scalar(get(item, :claim)),
             confidence: confidence,
             verification_status: "unverified",
             evidence_refs: []
           }}
        end
    end
  end

  defp normalize_evidence(field, _item), do: error(field, :invalid_item)

  defp normalize_confidence(_field, nil), do: {:ok, "low"}

  defp normalize_confidence(field, value) do
    case scalar(value) do
      confidence when confidence in ["low", "medium", "high"] -> {:ok, confidence}
      _ -> error(field, :invalid_confidence)
    end
  end

  defp normalize_limitations(nil), do: {:ok, []}

  defp normalize_limitations(items) when is_list(items) do
    values = Enum.map(items, &scalar/1)

    if Enum.any?(values, &is_nil/1),
      do: error(:limitations, :invalid_items),
      else: {:ok, values}
  end

  defp normalize_limitations(_items), do: error(:limitations, :invalid_items)

  defp get(raw, key), do: Map.get(raw, key, Map.get(raw, to_string(key)))
  defp scalar(nil), do: nil

  defp scalar(value) when is_binary(value) or is_number(value) or is_atom(value) do
    case String.trim(to_string(value)) do
      "" -> nil
      text -> text
    end
  end

  defp scalar(_value), do: nil
  defp error(field, code), do: {:error, {:invalid_market_research, field, code}}

  def schema do
    properties = %{
      "market_evidence" => items(evidence_schema()),
      "market_gaps" => items(evidence_schema()),
      "demand_signals" => items(evidence_schema()),
      "sources" => Map.put(items(%{"type" => "string"}), "maxItems", 0),
      "limitations" => items(%{"type" => "string"})
    }

    Map.put(closed_object(properties), "required", Enum.map(@fields, &to_string/1))
  end

  defp evidence_schema do
    closed_object(%{
      "claim" => %{"type" => "string"},
      "confidence" => %{"type" => "string", "enum" => ["low", "medium", "high"]},
      "verification_status" => %{"type" => "string", "enum" => ["unverified"]},
      "evidence_refs" => Map.put(items(%{"type" => "string"}), "maxItems", 0)
    })
  end

  defp items(item), do: %{"type" => "array", "items" => item}

  defp closed_object(properties) do
    %{
      "type" => "object",
      "properties" => properties,
      "required" => Map.keys(properties),
      "additionalProperties" => false
    }
  end
end
