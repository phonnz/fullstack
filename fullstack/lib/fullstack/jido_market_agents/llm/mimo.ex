defmodule Fullstack.JidoMarketAgents.LLM.Mimo do
  @moduledoc """
  `Backend` adapter wrapping the existing `Fullstack.JidoMarketAgents.LLM.MimoClient`
  HTTP transport.

  This adapter is intentionally thin: it validates and translates the
  configured/request options into `MimoClient.chat_completion/2`'s existing
  option shape and returns its `{:ok, content} | {:error, reason}` result
  unchanged.

  ## Supported capabilities

  Mimo supports `:json_object` (via `json_mode: true`), `:temperature` and
  `:max_tokens`. It does NOT support `:json_schema` — the underlying API has
  no schema-constrained-output parameter — nor `:effort`, which is not
  implemented by this transport.

  ## `response_format` translation

    * `:text` — no `json_mode` set.
    * `{:json_object, _schema}` — translates to `json_mode: true`. The
      schema itself is discarded: Mimo has no schema API parameter, so
      structure is enforced by the caller's existing extraction prompt and
      parser, not by this adapter.
  """

  @behaviour Fullstack.JidoMarketAgents.LLM.Backend

  alias Fullstack.JidoMarketAgents.LLM.MimoClient

  @configured_keys [:model, :temperature, :max_tokens]

  @impl true
  def chat_completion(messages, opts) do
    {response_format, opts} = Keyword.pop(opts, :response_format, :text)

    client_opts =
      opts
      |> Keyword.take(@configured_keys)
      |> put_json_mode(response_format)

    MimoClient.chat_completion(messages, client_opts)
  end

  defp put_json_mode(client_opts, :text), do: client_opts

  defp put_json_mode(client_opts, {:json_object, _schema}),
    do: Keyword.put(client_opts, :json_mode, true)

  @impl true
  def capabilities(_opts), do: [:json_object, :temperature, :max_tokens]

  @impl true
  def validate_config(opts) do
    with :ok <- reject_unsupported(opts) do
      reject_unknown(opts)
    end
  end

  defp reject_unsupported(opts) do
    if Keyword.has_key?(opts, :effort) do
      {:error, {:unsupported_option, :effort}}
    else
      :ok
    end
  end

  defp reject_unknown(opts) do
    case Enum.find(opts, fn {key, _value} -> key not in @configured_keys end) do
      nil -> :ok
      {key, _value} -> {:error, {:unknown_option, key}}
    end
  end
end
