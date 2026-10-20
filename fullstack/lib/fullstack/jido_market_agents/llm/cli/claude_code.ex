defmodule Fullstack.JidoMarketAgents.LLM.Cli.ClaudeCode do
  @moduledoc """
  `Backend` adapter for the local `claude` CLI (Claude Code) in non-interactive
  mode, via `Fullstack.JidoMarketAgents.LLM.Cli.Runner`.

  ## Non-interactive invocation

  Built argv (verified against installed `claude` 2.1.261 `--help`):

      claude -p --output-format json --restricted --no-session-persistence \\
             --model <model> [--effort <level>] --system-prompt <system> <user-prompt>

  `-p`/`--print` runs one non-interactive turn and exits; `--output-format
  json` returns a single JSON object on stdout; `--restricted` removes
  command/code-running tools and `WebFetch` unless explicitly selected;
  `--no-session-persistence` disables session persistence (both flags are
  documented as valid only alongside `--print`, which is always passed here).

  Structured output uses `--json-schema <encoded-schema>`, confirmed present
  in installed `claude --help` (`2.1.261`):

      --json-schema <schema>   JSON Schema for structured output validation.

  The plan's documented success-envelope field for the parsed structured
  payload is `structured_output`; this could not be re-verified against a
  live response in this task (no paid/authenticated CLI call is permitted by
  the test policy below), so this adapter reads exactly that field name and
  documents the assumption here rather than guessing at an alternative.

  ## Success envelope — exit status is not sufficient

  A CLI exit status of `0` is NOT sufficient proof of success: a smoke test
  observed exit status `0` with `is_error: true`, `api_error_status: 400`,
  and `result: "Credit balance is too low"` on stdout. Treating that as
  `{:ok, "Credit balance is too low"}` would store and display a billing
  error as market research. Success requires ALL of:

    * process exit status `0` (checked by `Runner`, surfaced as
      `{:nonzero_exit, status}` otherwise);
    * `is_error == false`;
    * `subtype == "success"`;
    * the field appropriate to the requested format is present and valid
      (`result` for text; `structured_output` for structured JSON).

  Any other combination — including exit `0` with an error envelope — is a
  `{:error, _}`, never `{:ok, _}`.

  ## Response format translation

    * `:text` — validates `result` is a nonempty string, returns
      `{:ok, result}`.
    * `{:json_object, schema}` — appends `--json-schema <encoded schema>`
      and `--output-format json`; validates the success envelope, extracts
      `structured_output`, validates it locally against the fixed six-key
      closed nullable-string `ExtractionOutput` schema (object root, all six
      keys present, no extra keys, each value a string or `nil`), then
      returns `{:ok, Jason.encode!(structured_output)}`. `result` is never
      required and never used as a fallback in this mode: per plan lines
      88-92, structured mode requires the structured field itself to be
      valid, independent of whether `result` happens to be empty.

  ## Effort — explicit levels are rejected as unverified

  Installed help advertises `--effort <level>` with values `low`, `medium`,
  `high`, `xhigh`, `max`, but per-model support and any org/managed policy
  cap are not derivable from the CLI alone, and this adapter makes no
  network calls. Per the plan (lines 252-256): "if it cannot be established,
  reject it as unverified rather than promise the requested level was
  applied." This adapter therefore rejects every explicitly configured
  `effort:` value with `{:unverified_effort, level}` — there is no local way
  to confirm the effective cap without a network call, so no level is
  encoded as "supported" in the descriptor below. `effort: nil` or omitted
  means no override: no `--effort` flag is emitted and the CLI's own default
  applies, which needs no verification because this adapter makes no promise
  about which level was used.

  ## Unsupported controls

  `temperature:` and `max_tokens:` are rejected by `validate_config/1`: the
  CLI has no equivalent switch, so an explicitly configured value must fail
  loudly rather than be silently dropped or approximated.
  """

  @behaviour Fullstack.JidoMarketAgents.LLM.Backend

  alias Fullstack.JidoMarketAgents.LLM.Cli.Runner

  @configured_keys [:command, :model, :effort, :timeout_ms, :env]
  @rejected_keys [:temperature, :max_tokens]

  # Small, versioned compatibility descriptor: only the model aliases this
  # adapter has been checked against installed `claude --help` (2.1.261) are
  # listed. `--model` help text gives `'fable', 'opus', or 'sonnet'` as
  # example aliases; full model name IDs are intentionally not pinned here
  # (aliases can drift server-side, but no exact full ID was verified against
  # this installation, and the plan explicitly forbids inventing a matrix).
  #
  # No effort level is listed as "supported" for any model: per plan lines
  # 252-256, an explicit effort cannot be locally verified against org/model
  # policy without a network call, so every explicit effort is rejected as
  # unverified regardless of model, independent of this table. The table
  # exists to bound which *models* are accepted, not which efforts.
  @known_models ~w(sonnet opus fable)

  @impl true
  def chat_completion(messages, opts) do
    {response_format, opts} = Keyword.pop(opts, :response_format, :text)

    with :ok <- validate_response_format(response_format),
         {:ok, system_prompt, user_prompt} <- extract_messages(messages),
         {:ok, command} <- fetch_command(opts) do
      argv = build_argv(opts, response_format, system_prompt, user_prompt)
      env = opts |> Keyword.get(:env, %{}) |> to_env_map()
      timeout_ms = Keyword.get(opts, :timeout_ms)

      command
      |> Runner.run(argv, run_opts(env, timeout_ms))
      |> handle_result(response_format)
    end
  end

  defp run_opts(env, nil), do: [env: env]
  defp run_opts(env, timeout_ms), do: [env: env, timeout_ms: timeout_ms]

  defp to_env_map(nil), do: %{}
  defp to_env_map(env) when is_map(env), do: env

  # -- Message extraction ---------------------------------------------------

  # Extracts exactly one optional system message and exactly one user
  # message. Any other role, or more than one message of either role, is
  # rejected rather than silently flattened or concatenated: Codex-style
  # prompt folding does not recreate API role priority, and this adapter
  # makes no attempt to approximate multi-turn history.
  defp extract_messages(messages) do
    case Enum.reduce_while(messages, %{system: nil, user: nil}, &collect_message/2) do
      {:error, _reason} = error -> error
      %{user: nil} -> {:error, :missing_user_message}
      %{system: system, user: user} -> {:ok, system, user}
    end
  end

  defp collect_message(%{"role" => "system", "content" => content}, %{system: nil} = acc),
    do: {:cont, %{acc | system: content}}

  defp collect_message(%{"role" => "system"}, %{system: _already_set}),
    do: {:halt, {:error, :duplicate_system_message}}

  defp collect_message(%{"role" => "user", "content" => content}, %{user: nil} = acc),
    do: {:cont, %{acc | user: content}}

  defp collect_message(%{"role" => "user"}, %{user: _already_set}),
    do: {:halt, {:error, :duplicate_user_message}}

  defp collect_message(%{"role" => role}, _acc),
    do: {:halt, {:error, {:unsupported_role, role}}}

  # -- Argv construction ------------------------------------------------

  defp build_argv(opts, response_format, system_prompt, user_prompt) do
    model = Keyword.fetch!(opts, :model)
    effort = Keyword.get(opts, :effort)

    ["-p", "--output-format", "json", "--restricted", "--no-session-persistence"]
    |> maybe_add_json_schema(response_format)
    |> Kernel.++(["--model", model])
    |> maybe_add_effort(effort)
    |> maybe_add_system_prompt(system_prompt)
    |> Kernel.++([user_prompt])
  end

  defp maybe_add_json_schema(argv, :text), do: argv

  defp maybe_add_json_schema(argv, {:json_object, schema}),
    do: argv ++ ["--json-schema", Jason.encode!(schema)]

  defp maybe_add_effort(argv, nil), do: argv
  defp maybe_add_effort(argv, effort), do: argv ++ ["--effort", effort]

  defp maybe_add_system_prompt(argv, nil), do: argv

  defp maybe_add_system_prompt(argv, system_prompt),
    do: argv ++ ["--system-prompt", system_prompt]

  # -- Command resolution -----------------------------------------------

  defp fetch_command(opts) do
    case Keyword.fetch(opts, :command) do
      {:ok, command} when is_binary(command) -> {:ok, command}
      _other -> {:error, :missing_command}
    end
  end

  # -- Result handling -------------------------------------------------

  defp handle_result({:ok, %{stdout: stdout}}, response_format) do
    with {:ok, envelope} <- decode_envelope(stdout),
         :ok <- validate_success_envelope(envelope) do
      extract_payload(envelope, response_format)
    end
  end

  defp handle_result({:error, _reason}, _response_format) do
    {:error, :cli_execution_failed}
  end

  defp decode_envelope(stdout) do
    case Jason.decode(stdout) do
      {:ok, envelope} when is_map(envelope) -> {:ok, envelope}
      {:ok, _other} -> {:error, :malformed_output}
      {:error, _reason} -> {:error, :malformed_output}
    end
  end

  # The success envelope check is the load-bearing safety property of this
  # adapter: exit status 0 alone is not proof of success (see moduledoc).
  defp validate_success_envelope(%{"is_error" => false, "subtype" => "success"}), do: :ok
  defp validate_success_envelope(_envelope), do: {:error, :provider_error_envelope}

  defp extract_payload(%{"result" => result}, :text) when is_binary(result) and result != "" do
    {:ok, result}
  end

  defp extract_payload(_envelope, :text), do: {:error, :empty_result}

  defp extract_payload(envelope, {:json_object, schema}) do
    with {:ok, structured} <- fetch_structured_output(envelope),
         :ok <- validate_structured_schema(structured, schema) do
      {:ok, Jason.encode!(structured)}
    end
  end

  defp fetch_structured_output(%{"structured_output" => structured}) when is_map(structured),
    do: {:ok, structured}

  defp fetch_structured_output(_envelope), do: {:error, :missing_structured_output}

  # Validates the structured payload against the SUPPLIED schema's root
  # rules: `required` keys must be present, `additionalProperties: false`
  # forbids any other key, and each property's `type` constrains the
  # value's JSON type. Payload keys come from the supplied schema — never
  # from any extraction field registry.
  defp validate_structured_schema(structured, schema) when is_map(schema),
    do: validate_value(structured, schema)

  defp validate_structured_schema(_structured, _schema), do: {:error, :invalid_supplied_schema}

  # Schema keywords this adapter enforces locally, plus pure annotations.
  # Anything else (pattern, oneOf, $ref, ...) would silently skip a
  # validation rule, so it is rejected BEFORE Runner.run/3.
  @supported_schema_keywords ~w(
    type properties required additionalProperties items enum
    minimum maximum minItems maxItems
    description title default examples $schema $id
  )

  defp validate_response_format(:text), do: :ok

  defp validate_response_format({:json_object, schema}), do: walk_schema_keywords(schema)

  defp validate_response_format(_other), do: {:error, :invalid_response_format}

  defp walk_schema_keywords(node) when is_map(node) do
    case Enum.find(Map.keys(node), &(&1 not in @supported_schema_keywords)) do
      nil ->
        Enum.reduce_while(schema_children(node), :ok, fn child, :ok ->
          case walk_schema_keywords(child) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
        end)

      key ->
        {:error, {:unsupported_schema_keyword, key}}
    end
  end

  defp walk_schema_keywords(_node), do: {:error, :invalid_supplied_schema}

  defp schema_children(node) do
    props =
      case Map.get(node, "properties") do
        properties when is_map(properties) -> Map.values(properties)
        _other -> []
      end

    case Map.get(node, "items") do
      nil -> props
      items -> [items | props]
    end
  end

  # Recursive value-vs-schema walk: object nodes (properties/required/
  # additionalProperties), array nodes (items/minItems/maxItems), enums,
  # scalar and nullable (type-list) nodes, and numeric bounds. Violations
  # use two standardized tags at every depth: :schema_key_mismatch for
  # key rules, :schema_type_mismatch for type/enum/bounds/count rules.
  defp validate_value(value, node) when is_map(node) do
    with :ok <- validate_enum(value, node),
         :ok <- validate_type(value, node),
         :ok <- validate_object(value, node),
         :ok <- validate_array(value, node) do
      validate_numeric_bounds(value, node)
    end
  end

  defp validate_value(_value, _node), do: {:error, :invalid_supplied_schema}

  defp validate_enum(value, %{"enum" => choices}) when is_list(choices) do
    if Enum.any?(choices, &(&1 == value)), do: :ok, else: {:error, :schema_type_mismatch}
  end

  defp validate_enum(_value, _node), do: :ok

  defp validate_type(value, node) do
    if value_matches_type?(value, Map.get(node, "type")),
      do: :ok,
      else: {:error, :schema_type_mismatch}
  end

  defp validate_object(value, node) when is_map(value) do
    case Map.get(node, "properties") do
      properties when is_map(properties) ->
        required = Map.get(node, "required", [])
        closed? = Map.get(node, "additionalProperties", true) == false

        keys_ok? =
          Enum.all?(required, &Map.has_key?(value, &1)) and
            (not closed? or Enum.all?(Map.keys(value), &Map.has_key?(properties, &1)))

        if keys_ok? do
          Enum.reduce_while(value, :ok, fn {key, child_value}, :ok ->
            case Map.get(properties, key) do
              nil ->
                {:cont, :ok}

              child_node ->
                case validate_value(child_value, child_node) do
                  :ok -> {:cont, :ok}
                  error -> {:halt, error}
                end
            end
          end)
        else
          {:error, :schema_key_mismatch}
        end

      _no_properties ->
        :ok
    end
  end

  defp validate_object(_value, _node), do: :ok

  defp validate_array(value, node) when is_list(value) do
    min = Map.get(node, "minItems")
    max = Map.get(node, "maxItems")

    cond do
      is_integer(min) and length(value) < min ->
        {:error, :schema_type_mismatch}

      is_integer(max) and length(value) > max ->
        {:error, :schema_type_mismatch}

      true ->
        case Map.get(node, "items") do
          nil -> :ok
          items_node -> Enum.reduce_while(value, :ok, &validate_item(&1, items_node, &2))
        end
    end
  end

  defp validate_array(_value, _node), do: :ok

  defp validate_item(item, items_node, :ok) do
    case validate_value(item, items_node) do
      :ok -> {:cont, :ok}
      error -> {:halt, error}
    end
  end

  defp validate_numeric_bounds(value, node) when is_number(value) do
    min = Map.get(node, "minimum")
    max = Map.get(node, "maximum")

    cond do
      is_number(min) and value < min -> {:error, :schema_type_mismatch}
      is_number(max) and value > max -> {:error, :schema_type_mismatch}
      true -> :ok
    end
  end

  defp validate_numeric_bounds(_value, _node), do: :ok

  defp value_matches_type?(_value, nil), do: true

  defp value_matches_type?(value, types) when is_list(types),
    do: Enum.any?(types, &value_matches_type?(value, &1))

  defp value_matches_type?(nil, "null"), do: true
  defp value_matches_type?(value, "string") when is_binary(value), do: true
  defp value_matches_type?(value, "number") when is_number(value), do: true
  defp value_matches_type?(value, "integer") when is_integer(value), do: true
  defp value_matches_type?(value, "boolean") when is_boolean(value), do: true
  defp value_matches_type?(value, "object") when is_map(value), do: true
  defp value_matches_type?(value, "array") when is_list(value), do: true
  defp value_matches_type?(_value, _type), do: false

  # -- Backend.capabilities/1 -------------------------------------------

  @impl true
  def capabilities(_opts), do: [:json_object, :json_schema, :effort]

  # -- Backend.validate_config/1 -----------------------------------------

  @impl true
  def validate_config(opts) do
    with :ok <- reject_keys(opts, @rejected_keys, :unsupported_option),
         :ok <- reject_unknown(opts),
         :ok <- require_command(opts),
         :ok <- require_model(opts),
         :ok <- validate_model(opts),
         :ok <- validate_effort(opts) do
      :ok
    end
  end

  defp reject_keys(opts, keys, tag) do
    case Enum.find(keys, &Keyword.has_key?(opts, &1)) do
      nil -> :ok
      key -> {:error, {tag, key}}
    end
  end

  defp reject_unknown(opts) do
    case Enum.find(opts, fn {key, _value} -> key not in @configured_keys end) do
      nil -> :ok
      {key, _value} -> {:error, {:unknown_option, key}}
    end
  end

  defp require_command(opts) do
    case Keyword.get(opts, :command) do
      command when is_binary(command) and command != "" -> :ok
      _other -> {:error, {:missing_required_option, :command}}
    end
  end

  defp require_model(opts) do
    case Keyword.get(opts, :model) do
      model when is_binary(model) and model != "" -> :ok
      _other -> {:error, {:missing_required_option, :model}}
    end
  end

  defp validate_model(opts) do
    model = Keyword.fetch!(opts, :model)

    if model in @known_models do
      :ok
    else
      {:error, {:unsupported_model_config, model}}
    end
  end

  # Every explicitly configured effort is rejected as unverified: no local
  # check can establish the effective org/model policy cap without a network
  # call (plan lines 252-256). `nil`/omitted means no override and needs no
  # verification because no level is promised.
  defp validate_effort(opts) do
    case Keyword.get(opts, :effort) do
      nil -> :ok
      "" -> {:error, {:invalid_effort, ""}}
      effort when is_binary(effort) -> {:error, {:unverified_effort, effort}}
      other -> {:error, {:invalid_effort, other}}
    end
  end
end
