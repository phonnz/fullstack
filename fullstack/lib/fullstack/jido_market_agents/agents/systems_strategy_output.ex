defmodule Fullstack.JidoMarketAgents.Agents.SystemsStrategyOutput do
  @moduledoc "Closed, canonically ordered six-systems strategy contract."

  @fields [:systems, :sequencing, :quarterly_focus]
  @order [:acquisition, :authority, :conversion, :delivery_retention, :referrals, :information]
  @layers [:personal_discourse, :third_party_endorsement, :success_cases]
  @phases [:qualification, :education_nurturing, :proposal, :close]
  @flow [:channel, :incentive, :review_cadence]

  def fields, do: @fields
  def system_order, do: @order

  @doc "Projects normalized keyed systems in canonical rendering order."
  def ordered_systems(%{systems: systems}), do: Enum.map(@order, &{&1, Map.fetch!(systems, &1)})

  def normalize_map(raw) when is_map(raw) do
    with :ok <- reject_reserved(raw),
         {:ok, systems} <- normalize_systems(get(raw, :systems)),
         {:ok, sequence} <- normalize_sequence(get(raw, :sequencing)),
         {:ok, focus} <- required_text(:quarterly_focus, get(raw, :quarterly_focus)) do
      %{systems: systems, sequencing: sequence, quarterly_focus: focus}
    end
  end

  def normalize_map(_raw), do: error(:output, :invalid_shape)

  defp reject_reserved(raw) do
    Enum.find_value([:_pipeline, :_meta], :ok, fn key ->
      if Map.has_key?(raw, key) or Map.has_key?(raw, to_string(key)),
        do: {:error, {:reserved_key, key}}
    end)
  end

  defp normalize_systems(raw) when is_map(raw) do
    allowed = @order ++ Enum.map(@order, &to_string/1)

    if Enum.any?(Map.keys(raw), &(&1 not in allowed)) do
      error(:systems, :unexpected_system)
    else
      Enum.reduce_while(@order, {:ok, %{}}, fn name, {:ok, acc} ->
        case normalize_system(name, get(raw, name)) do
          {:ok, system} -> {:cont, {:ok, Map.put(acc, name, system)}}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp normalize_systems(_raw), do: error(:systems, :invalid_shape)

  defp normalize_system(name, nil), do: error(name, :missing_system)

  defp normalize_system(name, raw) when is_map(raw) do
    with {:ok, state} <- required_text(name, get(raw, :current_state)),
         {:ok, priority} <- normalize_priority(name, get(raw, :priority)),
         {:ok, actions} <- text_items(name, get(raw, :actions)),
         {:ok, kpis} <- text_items(name, get(raw, :kpis)),
         :ok <- information_kpis(name, kpis),
         {:ok, pitfall} <- required_text(name, get(raw, :pitfall)),
         {:ok, special} <- special_fields(name, raw) do
      {:ok,
       Map.merge(
         %{
           current_state: state,
           priority: priority,
           actions: actions,
           kpis: kpis,
           pitfall: pitfall
         },
         special
       )}
    end
  end

  defp normalize_system(name, _raw), do: error(name, :invalid_shape)

  defp special_fields(:authority, raw), do: nested_fields(:authority, raw, :layers, @layers)
  defp special_fields(:conversion, raw), do: nested_fields(:conversion, raw, :phases, @phases)

  defp special_fields(:information, raw),
    do: nested_fields(:information, raw, :upward_information_flow, @flow)

  defp special_fields(_name, _raw), do: {:ok, %{}}

  defp nested_fields(name, raw, key, fields) do
    value = get(raw, key)

    code =
      case key do
        :layers -> :invalid_layers
        :phases -> :invalid_phases
        :upward_information_flow -> :invalid_upward_information_flow
      end

    if is_map(value) do
      normalized = Map.new(fields, &{&1, scalar(get(value, &1))})

      if Enum.any?(normalized, fn {_key, text} -> is_nil(text) end),
        do: error(name, code),
        else: {:ok, %{key => normalized}}
    else
      error(name, code)
    end
  end

  defp normalize_priority(name, value) do
    case scalar(value) do
      priority when priority in ["high", "medium", "low"] -> {:ok, priority}
      _ -> error(name, :invalid_priority)
    end
  end

  defp information_kpis(:information, kpis) do
    if length(kpis) == 3 and length(Enum.uniq(kpis)) == 3,
      do: :ok,
      else: error(:information, :three_kpis_required)
  end

  defp information_kpis(_name, _kpis), do: :ok

  defp normalize_sequence(sequence) when is_list(sequence) do
    canonical = Enum.map(@order, &to_string/1)

    if Enum.map(sequence, &scalar/1) == canonical,
      do: {:ok, canonical},
      else: error(:sequencing, :invalid_order)
  end

  defp normalize_sequence(_sequence), do: error(:sequencing, :invalid_order)

  defp text_items(name, items) when is_list(items) do
    values = Enum.map(items, &scalar/1)
    if Enum.any?(values, &is_nil/1), do: error(name, :invalid_items), else: {:ok, values}
  end

  defp text_items(name, _items), do: error(name, :invalid_items)

  defp required_text(name, value) do
    case scalar(value) do
      nil -> error(name, :invalid_text)
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
  defp error(field, code), do: {:error, {:invalid_systems_strategy, field, code}}

  def schema do
    closed_object(
      %{
        "systems" => closed_object(Map.new(@order, &{to_string(&1), system_schema(&1)}), @order),
        "sequencing" => %{
          "type" => "array",
          "minItems" => 6,
          "maxItems" => 6,
          "items" => %{"type" => "string", "enum" => Enum.map(@order, &to_string/1)}
        },
        "quarterly_focus" => text()
      },
      @fields
    )
  end

  defp system_schema(name) do
    common = %{
      "current_state" => text(),
      "priority" => %{"type" => "string", "enum" => ["high", "medium", "low"]},
      "actions" => items(text()),
      "kpis" => items(text()),
      "pitfall" => text()
    }

    properties =
      case name do
        :authority ->
          Map.put(common, "layers", text_object(@layers))

        :conversion ->
          Map.put(common, "phases", text_object(@phases))

        :information ->
          common
          |> Map.put("kpis", Map.merge(items(text()), %{"minItems" => 3, "maxItems" => 3}))
          |> Map.put("upward_information_flow", text_object(@flow))

        _ ->
          common
      end

    closed_object(properties)
  end

  defp text_object(fields), do: closed_object(Map.new(fields, &{to_string(&1), text()}), fields)
  defp text, do: %{"type" => "string"}
  defp items(item), do: %{"type" => "array", "items" => item}

  defp closed_object(properties, required \\ nil) do
    %{
      "type" => "object",
      "properties" => properties,
      "required" =>
        if(required, do: Enum.map(required, &to_string/1), else: Map.keys(properties)),
      "additionalProperties" => false
    }
  end
end
