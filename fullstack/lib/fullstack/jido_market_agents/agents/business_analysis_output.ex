defmodule Fullstack.JidoMarketAgents.Agents.BusinessAnalysisOutput do
  @moduledoc "Closed business analysis contract; an unsupported offer remains blocked."

  @fields [:viable_offer, :evidence, :blocker, :experiment]
  @source_kinds ["user_input", "market_research", "assumption"]
  @offer_fields [:name, :target_customer, :value_proposition, :price, :evidence_refs]

  def fields, do: @fields

  @doc "Normalizes evidence and keeps a blocked analysis distinct from a viable offer."
  def normalize_map(raw) when is_map(raw) do
    with :ok <- reject_reserved(raw),
         {:ok, evidence} <- normalize_evidence(get(raw, :evidence)),
         {:ok, offer} <- normalize_offer(get(raw, :viable_offer), evidence),
         {:ok, blocker} <- optional_text(:blocker, get(raw, :blocker)),
         {:ok, experiment} <- optional_text(:experiment, get(raw, :experiment)),
         :ok <- require_blocked_experiment(offer, blocker, experiment) do
      %{viable_offer: offer, evidence: evidence, blocker: blocker, experiment: experiment}
    end
  end

  def normalize_map(_raw), do: error(:output, :invalid_shape)

  defp reject_reserved(raw) do
    Enum.find_value([:_pipeline, :_meta], :ok, fn key ->
      if Map.has_key?(raw, key) or Map.has_key?(raw, to_string(key)),
        do: {:error, {:reserved_key, key}}
    end)
  end

  defp normalize_evidence(nil), do: {:ok, []}

  defp normalize_evidence(items) when is_list(items) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case normalize_evidence_item(item) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} ->
        ids = Enum.map(values, & &1.id)

        if length(ids) == length(Enum.uniq(ids)),
          do: {:ok, Enum.reverse(values)},
          else: error(:evidence, :duplicate_ids)

      error ->
        error
    end
  end

  defp normalize_evidence(_items), do: error(:evidence, :invalid_items)

  defp normalize_evidence_item(item) when is_map(item) do
    kind = scalar(get(item, :source_kind))
    ref = scalar(get(item, :source_ref))
    id = scalar(get(item, :id))
    claim = scalar(get(item, :claim))

    cond do
      kind not in @source_kinds -> error(:evidence, :invalid_source_kind)
      is_nil(id) or is_nil(claim) -> error(:evidence, :invalid_item)
      kind != "assumption" and is_nil(ref) -> error(:evidence, :source_ref_required)
      not is_nil(get(item, :source_ref)) and is_nil(ref) -> error(:evidence, :invalid_source_ref)
      true -> {:ok, %{id: id, claim: claim, source_kind: kind, source_ref: ref}}
    end
  end

  defp normalize_evidence_item(_item), do: error(:evidence, :invalid_item)

  defp normalize_offer(nil, _evidence), do: {:ok, nil}

  defp normalize_offer(raw, evidence) when is_map(raw) do
    values =
      Map.new(@offer_fields -- [:evidence_refs], fn key -> {key, scalar(get(raw, key))} end)

    refs = get(raw, :evidence_refs)

    cond do
      Enum.any?(values, fn {_key, value} -> is_nil(value) end) ->
        error(:viable_offer, :invalid_offer)

      not is_list(refs) or refs == [] or Enum.any?(refs, &(not is_binary(&1))) ->
        error(:viable_offer, :unsupported_offer)

      true ->
        by_id = Map.new(evidence, &{&1.id, &1})

        cond do
          Enum.any?(refs, &(not Map.has_key?(by_id, &1))) ->
            error(:viable_offer, :unresolved_evidence_refs)

          Enum.all?(refs, &(by_id[&1].source_kind == "assumption")) ->
            error(:viable_offer, :unsupported_offer)

          true ->
            {:ok, Map.put(values, :evidence_refs, Enum.uniq(refs))}
        end
    end
  end

  defp normalize_offer(_raw, _evidence), do: error(:viable_offer, :invalid_shape)

  defp require_blocked_experiment(nil, blocker, experiment)
       when is_nil(blocker) or is_nil(experiment),
       do: error(:viable_offer, :blocker_experiment_required)

  defp require_blocked_experiment(_offer, _blocker, _experiment), do: :ok

  defp optional_text(_field, nil), do: {:ok, nil}

  defp optional_text(field, value) do
    case scalar(value) do
      nil -> error(field, :invalid_text)
      text -> {:ok, text}
    end
  end

  defp get(raw, key), do: Map.get(raw, key, Map.get(raw, to_string(key)))
  defp scalar(nil), do: nil

  defp scalar(value) when is_binary(value) or is_number(value) or is_atom(value) do
    case String.trim(to_string(value)) do
      "" -> nil
      text -> text
    end
  end

  defp scalar(_value), do: nil
  defp error(field, code), do: {:error, {:invalid_business_analysis, field, code}}

  def schema do
    properties = %{
      "viable_offer" => offer_schema(),
      "evidence" => items(evidence_schema()),
      "blocker" => nullable_string(),
      "experiment" => nullable_string()
    }

    Map.put(closed_object(properties), "required", Enum.map(@fields, &to_string/1))
  end

  defp offer_schema do
    @offer_fields
    |> Map.new(fn field -> {to_string(field), %{"type" => "string"}} end)
    |> Map.put("evidence_refs", Map.put(items(%{"type" => "string"}), "minItems", 1))
    |> closed_object()
    |> Map.put("type", ["object", "null"])
  end

  defp evidence_schema do
    closed_object(%{
      "id" => %{"type" => "string"},
      "claim" => %{"type" => "string"},
      "source_kind" => source_enum_schema(),
      "source_ref" => nullable_string()
    })
  end

  defp source_enum_schema, do: %{"type" => "string", "enum" => @source_kinds}
  defp nullable_string, do: %{"type" => ["string", "null"]}
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
