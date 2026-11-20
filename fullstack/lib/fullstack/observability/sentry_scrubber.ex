defmodule Fullstack.Observability.SentryScrubber do
  @moduledoc """
  `before_send` callback for Sentry. Removes credentials and personal data
  from request context before an event leaves the node.
  """

  @filtered "[FILTERED]"
  @sensitive_headers ~w(authorization cookie set-cookie x-api-key x-csrf-token)
  @sensitive_keys ~w(password password_confirmation current_password token api_key
                     secret authorization access_token refresh_token _csrf_token)

  @spec before_send(Sentry.Event.t()) :: Sentry.Event.t()
  def before_send(%Sentry.Event{request: request} = event) when is_map(request) do
    %{event | request: scrub_request(request)}
  end

  def before_send(event), do: event

  defp scrub_request(request) do
    request
    |> update_if_present(:headers, &scrub_headers/1)
    |> update_if_present(:data, &scrub_data/1)
    |> update_if_present(:cookies, fn _ -> @filtered end)
    |> update_if_present(:query_string, fn _ -> @filtered end)
  end

  defp update_if_present(map, key, fun) do
    case map do
      %{^key => value} when not is_nil(value) -> Map.put(map, key, fun.(value))
      _ -> map
    end
  end

  defp scrub_headers(headers) when is_map(headers) do
    Map.new(headers, fn {k, v} ->
      if String.downcase(to_string(k)) in @sensitive_headers, do: {k, @filtered}, else: {k, v}
    end)
  end

  defp scrub_data(data) when is_map(data) do
    Map.new(data, fn {k, v} ->
      if String.downcase(to_string(k)) in @sensitive_keys,
        do: {k, @filtered},
        else: {k, scrub_data(v)}
    end)
  end

  defp scrub_data(data) when is_list(data), do: Enum.map(data, &scrub_data/1)
  defp scrub_data(data), do: data
end
