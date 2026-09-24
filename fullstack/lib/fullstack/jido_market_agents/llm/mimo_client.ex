defmodule Fullstack.JidoMarketAgents.LLM.MimoClient do
  @moduledoc "Client for MIMO LLM API (OpenAI-compatible chat completions)"

  def chat_completion(messages, opts \\ []) do
    api_key = System.get_env("MIMO_API_KEY")
    base_url = System.get_env("MIMO_BASE_URL") || "https://token-plan-sgp.xiaomimimo.com/v1"
    model = Keyword.get(opts, :model, "mimo-v2.5-pro")

    url = "#{base_url}/chat/completions"

    body = %{
      "model" => model,
      "messages" => messages,
      "temperature" => Keyword.get(opts, :temperature, 0.7),
      "max_tokens" => Keyword.get(opts, :max_tokens, 1024)
    }

    body =
      if Keyword.get(opts, :json_mode, false) do
        Map.put(body, "response_format", %{type: "json_object"})
      else
        body
      end

    body = Jason.encode!(body)

    dbg(messages)

    case Req.post(url,
           headers: [
             {"authorization", "Bearer #{api_key}"},
             {"content-type", "application/json"}
           ],
           body: body,
           receive_timeout: 60_000
         ) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
        IO.inspect(content)
        {:ok, content}

      {:ok, %{status: status, body: body}} ->
        dbg(body)
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end
end
