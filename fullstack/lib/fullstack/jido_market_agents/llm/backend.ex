defmodule Fullstack.JidoMarketAgents.LLM.Backend do
  @moduledoc """
  Shared contract for pluggable LLM providers used by the market-agents pipeline.

  A backend module wraps one provider/transport (an HTTP chat-completions
  client, a local CLI binary, or a test double) and exposes exactly three
  callbacks: `chat_completion/2`, `capabilities/1`, and `validate_config/1`.

  `Fullstack.JidoMarketAgents.LLM` resolves a `{module, opts}` pair per agent
  role from application configuration and dispatches through this behaviour;
  no caller or agent branches on the concrete provider.

  ## Capabilities are configuration-scoped

  `capabilities/1` receives the backend's *configured* options (the same
  keyword list the module was configured with, e.g. `model:`, `effort:`) and
  must return only the capabilities that configured model/client combination
  actually supports. It does not describe everything the underlying provider
  could ever support in some other configuration. For example, a CLI backend
  configured for a model without structured-output support must omit
  `:json_schema` even if the same CLI binary supports it for other models.
  """

  @typedoc """
  A single chat message. Only the `"role"` and `"content"` string keys are
  part of this shared contract; adapters validate supported roles themselves.
  """
  @type message :: %{required(String.t()) => String.t()}

  @typedoc """
  A capability a configured backend can support:

    * `:json_object` — unstructured JSON-object output mode
    * `:json_schema` — schema-constrained structured output
    * `:temperature` — sampling temperature control
    * `:max_tokens` — output token limit control
    * `:effort` — provider-specific reasoning/effort level control
  """
  @type capability :: :json_object | :json_schema | :temperature | :max_tokens | :effort

  @doc """
  Sends `messages` to the configured provider and returns the assistant's
  reply as plain text.

  When the caller requested structured JSON output, the returned string is
  the JSON-encoded payload (JSON text), never a provider-specific envelope
  or an already-decoded Elixir term.
  """
  @callback chat_completion([message()], keyword()) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Returns the capabilities supported by this backend as configured with
  `opts`. `opts` is the backend's own configured keyword list (model,
  effort, and any other adapter-specific settings), not caller-supplied
  request options.
  """
  @callback capabilities(keyword()) :: [capability()]

  @doc """
  Validates that `opts` is a well-formed, internally consistent configuration
  for this backend (e.g. required keys present, values in supported ranges).

  This callback performs no network calls or subprocess execution; it is a
  structural/semantic check over the configuration term itself.
  """
  @callback validate_config(keyword()) :: :ok | {:error, term()}
end
