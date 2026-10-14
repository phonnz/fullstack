defmodule Fullstack.JidoMarketAgents.LLM do
  @moduledoc """
  Role-based dispatch to a configured `Fullstack.JidoMarketAgents.LLM.Backend`.

  Each agent role (`:validator`, `:researcher`) is independently mapped to a
  `{module, opts}` pair through application configuration:

      config :fullstack, Fullstack.JidoMarketAgents,
        validator_backend: {SomeModule, model: "...", ...},
        researcher_backend: {SomeModule, model: "...", ...}

  Configuration is read at runtime via `Application.get_env/3` (never
  `Application.compile_env/2`), so runtime/test overrides take effect.

  ## Option ownership

  `response_format` is the *only* option a caller may pass to
  `chat_completion/3`. Every other setting (model, effort, sampling,
  execution/runner options) is owned by the role's configured `opts` and is
  never accepted from the caller — passing any other key is a tagged error.
  This keeps provider/model selection a deployment concern, not a call-site
  concern, and prevents a caller from silently overriding trusted
  configuration.

  `response_format` is one of:

    * `:text` — plain text reply, no particular capability required
    * `{:json_object, schema}` — JSON-object output; requires the resolved
      backend to advertise the `:json_object` capability for its configured
      opts

  ## Role selection is capability-generic

  Both `:validator` and `:researcher` may be configured with any backend
  module. There is no role-specific restriction on which backend a role may
  use: whichever capability `response_format` implies is checked against
  `capabilities/1` for the *configured* backend, and any role/backend pair
  that satisfies it is accepted. A validator does not need "the JSON-capable
  backend" specifically — it needs *some* backend whose configured opts
  advertise `:json_object` when the caller asks for `{:json_object, _}`.

  ## Validation performed on every dispatch

  Every call to `chat_completion/3` repeats the same semantic validation
  performed by `validate_config/0`, so a runtime configuration override
  cannot bypass boot-time checks by only being validated once:

    1. the role atom is recognized;
    2. the configured entry is a well-formed `{module, keyword_list}` tuple;
    3. the module is loaded and exports all three `Backend` callbacks;
    4. `module.validate_config(opts)` returns `:ok`;
    5. `module.capabilities(opts)` covers the capability implied by the
       caller's `response_format`.

  Only after all of the above succeeds is `module.chat_completion/2`
  actually invoked, with the fully configured `opts` (plus `response_format`
  merged in so the adapter knows the requested format) — never a
  caller-controlled keyword list.

  ## Interpretation note on "unknown config keys"

  The plan asks to "reject unknown call/config keys". For the *call* side
  this is direct: any caller opt key other than `response_format` is
  rejected. For the *config* side, this module does not maintain a
  whitelist of every possible backend option (those are adapter-specific
  and opaque to this dispatcher by design — see moduledoc above on option
  ownership). Instead, "unknown config" is validated structurally: the
  `validator_backend`/`researcher_backend` entries must each resolve to a
  loaded module that implements the full `Backend` behaviour, and that
  module's own `validate_config/1` is authoritative over whether its opts
  are well-formed. This matches the design's intent that adapters own their
  own option validation, while this module owns role/format/capability
  policy.
  """

  alias Fullstack.JidoMarketAgents.LLM.Backend

  @typedoc "Supported agent roles."
  @type role :: :validator | :researcher | :analyzer | :systems | :strategy

  @typedoc "Caller-supplied response format request."
  @type response_format :: :text | {:json_object, term()}

  @app :fullstack
  @scope Fullstack.JidoMarketAgents
  @roles [:validator, :researcher, :analyzer, :systems, :strategy]
  @required_callbacks [chat_completion: 2, capabilities: 1, validate_config: 1]

  @doc """
  Dispatches a chat completion request for `role` through its configured
  backend.

  `opts` MUST include `response_format:` and must contain no other key.
  All other backend settings (model, effort, sampling, execution options)
  come exclusively from the role's configured `opts`.

  Returns `{:ok, text}` on success, or a tagged `{:error, reason}` on any
  validation failure or backend error.
  """
  @spec chat_completion(role(), [Backend.message()], keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def chat_completion(role, messages, opts) do
    with {:ok, response_format} <- validate_call_opts(opts),
         {:ok, {module, backend_opts}} <- resolve_and_validate(role),
         :ok <- check_capability(module, backend_opts, response_format) do
      module.chat_completion(
        messages,
        Keyword.put(backend_opts, :response_format, response_format)
      )
    end
  end

  @doc """
  Resolves the configured `{module, opts}` pair for `role`.

  Performs the same structural/semantic validation as `chat_completion/3`
  (role recognition, config shape, callback presence, `validate_config/1`),
  but does not check any `response_format`-implied capability and never
  calls the backend. Primarily useful for tests and introspection.
  """
  @spec backend(role()) :: {:ok, {module(), keyword()}} | {:error, term()}
  def backend(role), do: resolve_and_validate(role)

  @doc """
  Validates both `:validator` and `:researcher` role configuration at boot
  (or on demand).

  For each role, this confirms: the configured entry is a well-formed
  `{module, keyword_list}` tuple; the module is loaded and exports the full
  `Backend` behaviour; and `module.validate_config(opts)` returns `:ok`.

  This function makes no network calls and requires no CLI binaries or
  credentials to exist — it is a purely structural/semantic check. It does
  NOT check any particular `response_format`-implied capability, because
  there is no caller-provided `response_format` at boot time; capability
  checks happen per-call in `chat_completion/3`.

  Returns `:ok` if both roles are structurally valid, or
  `{:error, {role, reason}}` naming the first role that failed.
  """
  @spec validate_config() :: :ok | {:error, {role(), term()}}
  def validate_config do
    Enum.reduce_while([:validator, :researcher], :ok, fn role, :ok ->
      case resolve_and_validate(role) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {role, reason}}}
      end
    end)
  end

  # -- Caller option policy -------------------------------------------------

  defp validate_call_opts(opts) do
    case Keyword.pop(opts, :response_format, :__missing__) do
      {:__missing__, _rest} ->
        {:error, {:missing_option, :response_format}}

      {response_format, rest} ->
        with :ok <- validate_response_format(response_format),
             :ok <- validate_no_extra_keys(rest) do
          {:ok, response_format}
        end
    end
  end

  defp validate_response_format(:text), do: :ok
  defp validate_response_format({:json_object, _schema}), do: :ok
  defp validate_response_format(other), do: {:error, {:invalid_response_format, other}}

  defp validate_no_extra_keys([]), do: :ok

  defp validate_no_extra_keys([{key, _value} | _rest]),
    do: {:error, {:unknown_option, key}}

  # -- Role/config resolution -------------------------------------------------

  defp resolve_and_validate(role) when role in @roles do
    with {:ok, entry} <- fetch_config_entry(role),
         {:ok, {module, backend_opts}} <- validate_config_shape(role, entry),
         :ok <- validate_backend_module(module),
         :ok <- validate_backend_config(module, backend_opts) do
      {:ok, {module, backend_opts}}
    end
  end

  defp resolve_and_validate(role), do: {:error, {:unknown_role, role}}

  defp fetch_config_entry(role) do
    key = config_key(role)
    config = Application.get_env(@app, @scope, [])
    {:ok, Keyword.get(config, key)}
  end

  defp config_key(:validator), do: :validator_backend
  defp config_key(:researcher), do: :researcher_backend
  defp config_key(:analyzer), do: :analyzer_backend
  defp config_key(:systems), do: :systems_backend
  defp config_key(:strategy), do: :strategy_backend

  defp validate_config_shape(role, {module, opts} = entry)
       when is_atom(module) and is_list(opts) do
    if Keyword.keyword?(opts) do
      {:ok, entry}
    else
      {:error, {:invalid_backend_config, role, entry}}
    end
  end

  defp validate_config_shape(role, entry), do: {:error, {:invalid_backend_config, role, entry}}

  defp validate_backend_module(module) do
    if Code.ensure_loaded?(module) and exports_all_callbacks?(module) do
      :ok
    else
      {:error, {:invalid_backend_module, module}}
    end
  end

  defp exports_all_callbacks?(module) do
    Enum.all?(@required_callbacks, fn {fun, arity} ->
      function_exported?(module, fun, arity)
    end)
  end

  # -- Backend.validate_config/1 propagation ------------------------------

  defp validate_backend_config(module, backend_opts) do
    case module.validate_config(backend_opts) do
      :ok -> :ok
      {:error, reason} -> {:error, {:backend_config_invalid, module, reason}}
    end
  end

  # -- Capability policy ----------------------------------------------------

  defp check_capability(module, backend_opts, :text) do
    _ = module
    _ = backend_opts
    :ok
  end

  defp check_capability(module, backend_opts, {:json_object, _schema}) do
    if :json_object in module.capabilities(backend_opts) do
      :ok
    else
      {:error, {:unsupported_capability, :json_object}}
    end
  end
end
