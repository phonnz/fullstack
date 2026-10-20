defmodule Fullstack.Support.FutureProvider do
  @moduledoc """
  Test-only `Backend` adapter proving the plan's extension claim (see
  `odd/tasks/llm-backend-adapter.md`, "Extending providers and models"): a
  brand-new provider needs no change to agent logic, `LLM` dispatch, or any
  provider switch statement — only a module implementing this existing
  `Backend` behaviour, selected via configuration.

  Fully deterministic: no subprocess, no HTTP. Behavior is keyed entirely
  off its own configured `opts` (`:mode` / `:canned_response`) rather than
  message content, so tests can predict its output exactly.

  ## Configuration

    * `:mode` (required) — one of `:text` or `:json_object`. Determines
      which `response_format` this configured instance is prepared to
      answer. `validate_config/1` rejects any other value.
    * `:canned_response` (optional) —
        * for `:mode: :text`, a binary returned verbatim as the reply.
          Defaults to `"future-provider-canned-text"`.
        * for `:mode: :json_object`, a map merged onto an all-nil
          `ExtractionOutput.fields/0` map before being JSON-encoded.
          Defaults to `%{}` (an all-null extraction object).
    * `:notify` (optional) — a pid. When present, `chat_completion/2`
      sends `{:backend_hit, __MODULE__, opts}` to it before returning, so
      a test can assert which configured backend actually ran without
      relying on process dictionaries or global state.

  ## Capabilities

  Advertises `[:json_object, :temperature]` unconditionally: a plausible,
  internally consistent capability set for a hypothetical provider that
  supports temperature control and unstructured JSON-object mode, but not
  schema-constrained output or an effort control.
  """

  @behaviour Fullstack.JidoMarketAgents.LLM.Backend

  alias Fullstack.JidoMarketAgents.Agents.ExtractionOutput

  @impl true
  def chat_completion(_messages, opts) do
    {response_format, opts} = Keyword.pop(opts, :response_format, :text)

    case Keyword.fetch(opts, :notify) do
      {:ok, pid} when is_pid(pid) -> send(pid, {:backend_hit, __MODULE__, opts})
      _other -> :ok
    end

    render(response_format, opts)
  end

  defp render(:text, opts) do
    {:ok, Keyword.get(opts, :canned_response, "future-provider-canned-text")}
  end

  defp render({:json_object, _schema}, opts) do
    overrides = Keyword.get(opts, :canned_response, %{})

    body =
      ExtractionOutput.fields()
      |> Map.new(&{&1, nil})
      |> Map.merge(atomize_keys(overrides))
      |> Map.new(fn {key, value} -> {to_string(key), value} end)

    {:ok, Jason.encode!(body)}
  end

  defp atomize_keys(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      {key, value} -> {key, value}
    end)
  end

  @impl true
  def capabilities(_opts), do: [:json_object, :temperature]

  @impl true
  def validate_config(opts) do
    case Keyword.get(opts, :mode) do
      mode when mode in [:text, :json_object] -> :ok
      other -> {:error, {:invalid_mode, other}}
    end
  end
end
