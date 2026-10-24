defmodule Fullstack.JidoMarketAgents.LLM.MimoClient do
  @moduledoc "Client for MIMO LLM API (OpenAI-compatible chat completions)"

  require Logger

  @log_excerpt_chars 200

  def chat_completion(messages, opts \\ []) do
    api_key = System.get_env("MIMO_API_KEY")
    base_url = System.get_env("MIMO_BASE_URL") || "https://token-plan-sgp.xiaomimimo.com/v1"
    model = Keyword.get(opts, :model, "mimo-v2.6-pro")

    url = "#{base_url}/chat/completions"

    body = %{
      "model" => model,
      "messages" => messages,
      "temperature" => Keyword.get(opts, :temperature, 0.7),
      "max_completion_tokens" => Keyword.get(opts, :max_tokens, 1024)
    }

    body =
      if Keyword.get(opts, :json_mode, false) do
        Map.put(body, "response_format", %{type: "json_object"})
      else
        body
      end

    body =
      case Keyword.fetch(opts, :thinking) do
        {:ok, mode} -> Map.put(body, "thinking", %{type: Atom.to_string(mode)})
        :error -> body
      end

    body = Jason.encode!(body)

    case Req.post(url,
           headers: [
             {"authorization", "Bearer #{api_key}"},
             {"content-type", "application/json"}
           ],
           body: body,
           receive_timeout: 60_000
         ) do
      {:ok, %{status: 200, body: %{"choices" => [choice | _]} = body}} ->
        read_final_content(choice, body)

      {:ok, %{status: status, body: body}} ->
        Logger.warning(
          "MiMo request failed: :api_error status=#{status} body_excerpt=#{excerpt(body)}"
        )

        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.warning("MiMo request failed: :request_failed reason=#{excerpt(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp read_final_content(choice, body) do
    metadata = response_metadata(choice, body)

    case choice do
      %{"finish_reason" => "length"} ->
        log_invalid_response(:truncated, metadata)
        {:error, {:invalid_response, :truncated, metadata}}

      %{"message" => %{"content" => content}} when is_binary(content) ->
        if String.trim(content) == "" do
          log_invalid_response(:empty_content, metadata)
          {:error, {:invalid_response, :empty_content, metadata}}
        else
          {:ok, content}
        end

      _ ->
        log_invalid_response(:invalid_content, metadata)
        {:error, {:invalid_response, :invalid_content, metadata}}
    end
  end

  defp log_invalid_response(code, metadata) do
    Logger.warning(
      "MiMo response rejected: :invalid_response code=#{inspect(code)} finish_reason=#{metadata.finish_reason || "none"} usage=#{inspect(metadata.usage)}"
    )
  end

  defp excerpt(value) do
    value
    |> inspect(printable_limit: @log_excerpt_chars, limit: 5)
    |> String.slice(0, @log_excerpt_chars)
  end

  defp response_metadata(choice, body) do
    reason = if is_map(choice), do: Map.get(choice, "finish_reason")
    reason = if is_binary(reason) and byte_size(reason) <= 32, do: reason
    usage = if is_map(body["usage"]), do: body["usage"], else: %{}

    details =
      if is_map(usage["completion_tokens_details"]),
        do: usage["completion_tokens_details"],
        else: %{}

    tokens =
      usage
      |> Map.take(["prompt_tokens", "completion_tokens", "total_tokens"])
      |> Map.put("reasoning_tokens", details["reasoning_tokens"])
      |> Enum.filter(fn {_key, value} -> is_integer(value) and value >= 0 end)
      |> Map.new()

    %{finish_reason: reason, usage: tokens}
  end
end
