defmodule Fullstack.JidoMarketAgents.LLM.Cli.Codex do
  @moduledoc """
  `Backend` adapter for the local `codex` CLI (`codex exec ...`) run
  non-interactively via `Fullstack.JidoMarketAgents.LLM.Cli.Runner`.

  ## Success signal

  Codex has no structured success/error envelope on stdout: a successful run
  can print unrelated noise (session ids, hook logs, even a literal
  `ERROR: Reconnecting... 2/5` line) while still succeeding. This adapter
  therefore never inspects stdout to decide success or failure. Only the
  process exit status plus the contents of the `-o`/`--output-last-message`
  file matter: zero exit and a fresh, bounded, nonempty output file.

  ## Output file handling

  `Runner.run/3` sets the child's `cd:` to its private scratch directory, so
  this adapter passes a *relative* filename (`"codex_output.txt"`) to `-o`
  and reads it back via `opts[:before_cleanup]`, which runs after the process
  exits but before the scratch directory is removed. This is simpler and
  equally correct compared to resolving an absolute path ahead of spawn,
  since the scratch directory does not exist until `Runner.run/3` creates it.

  ## Schema file handling

  For `{:json_object, schema}` requests, the schema JSON must be readable by
  the child *during* its run, but `Runner` does not expose the scratch
  directory before spawn (only inside `before_cleanup`, which is too late).
  So this adapter writes the schema to its own private temp file under
  `System.tmp_dir!/0`, passes its **absolute** path to `--output-schema`,
  and removes that file itself once `Runner.run/3` returns — success or
  error — independently of the scratch-dir lifecycle Runner already owns for
  the `-o` file.

  ## Prompt folding

  Codex has no separate system-prompt argv flag. Any `"system"`-role message
  content and the `"user"`-role message content(s) are folded into a single
  positional prompt string (text concatenation, newline-joined). This does
  **not** recreate API-level role priority or isolation between system and
  user text — it is plain text concatenation passed as one CLI argument.
  Only `"system"` and `"user"` roles are supported; any other role
  (`"assistant"`, etc.) is rejected before any subprocess is spawned.

  ## Isolation

  Base argv always includes `--skip-git-repo-check`, `--ephemeral`,
  `--sandbox read-only`, `--ignore-user-config`, and `--color never`. No
  permission-bypass flag (`--dangerously-bypass-approvals-and-sandbox`) is
  ever used.

  ## Compatibility descriptor

  `@compatibility` is a small, versioned map of supported model IDs to their
  allowed `effort` strings, calibrated against locally observed
  `codex-cli 0.157.1` config (`model_reasoning_effort` values actually in use
  on this machine: `"xhigh"`, `"high"`). Codex documents effort as a
  model-advertised string rather than a universal enum, so this descriptor
  is deliberately small and fails closed: an unrecognized model or an
  effort not listed for a recognized model is rejected with
  `{:unsupported_model_config, _}` rather than guessed at. `effort: nil` or
  an omitted `effort` key is always valid regardless of model — it means "no
  override, use the provider default" and carries no compatibility risk.

  ## Capabilities are configuration-scoped

  `:json_object` and `:json_schema` are always advertised: Codex's `-o` and
  `--output-schema` flags are unconditional CLI features, not
  model-gated. `:effort` is advertised only when the configured `model:` is
  present and (with the configured `effort:`, if any) resolves to a
  supported combination in `@compatibility` — this mirrors the design's
  intent that capabilities describe what the *configured* model/client
  combination actually supports, not everything the CLI binary could ever
  do. `:temperature` and `:max_tokens` are never advertised: the `codex`
  CLI has no equivalent switches.
  """

  @behaviour Fullstack.JidoMarketAgents.LLM.Backend

  alias Fullstack.JidoMarketAgents.LLM.Cli.Runner

  @configured_keys [:command, :model, :effort, :timeout_ms, :env]
  @unsupported_keys [:temperature, :max_tokens]
  @supported_roles ["system", "user"]

  @output_filename "codex_output.txt"
  @max_output_bytes 1024 * 1024

  # Small, versioned compatibility descriptor. See moduledoc "Compatibility
  # descriptor" for justification and evidence source.
  @compatibility %{
    "gpt-6-astra" => ["high", "xhigh"],
    "gpt-5.6-luna" => ["high", "xhigh"],
    "gpt-5.6-terra" => ["high", "xhigh"]
  }

  # -- capabilities/1 ----------------------------------------------------

  @impl true
  def capabilities(opts) do
    base = [:json_object, :json_schema]

    if effort_capability?(opts) do
      [:effort | base]
    else
      base
    end
  end

  defp effort_capability?(opts) do
    case Keyword.fetch(opts, :model) do
      {:ok, model} ->
        case Keyword.get(opts, :effort) do
          nil -> model_known?(model)
          effort -> model_known?(model) and effort_allowed?(model, effort)
        end

      :error ->
        false
    end
  end

  # -- validate_config/1 --------------------------------------------------

  @impl true
  def validate_config(opts) do
    with :ok <- require_command(opts),
         :ok <- reject_unsupported(opts),
         :ok <- reject_unknown(opts) do
      validate_model_effort(opts)
    end
  end

  defp require_command(opts) do
    if Keyword.has_key?(opts, :command) do
      :ok
    else
      {:error, {:missing_option, :command}}
    end
  end

  defp reject_unsupported(opts) do
    case Enum.find(@unsupported_keys, &Keyword.has_key?(opts, &1)) do
      nil -> :ok
      key -> {:error, {:unsupported_option, key}}
    end
  end

  defp reject_unknown(opts) do
    case Enum.find(opts, fn {key, _value} -> key not in @configured_keys end) do
      nil -> :ok
      {key, _value} -> {:error, {:unknown_option, key}}
    end
  end

  defp validate_model_effort(opts) do
    case Keyword.fetch(opts, :model) do
      :error ->
        :ok

      {:ok, model} ->
        effort = Keyword.get(opts, :effort)
        validate_model_effort(model, effort)
    end
  end

  defp validate_model_effort(model, nil) do
    if model_known?(model) do
      :ok
    else
      {:error, {:unsupported_model_config, %{model: model, effort: nil}}}
    end
  end

  defp validate_model_effort(model, effort) do
    if model_known?(model) and effort_allowed?(model, effort) do
      :ok
    else
      {:error, {:unsupported_model_config, %{model: model, effort: effort}}}
    end
  end

  defp model_known?(model), do: Map.has_key?(@compatibility, model)

  defp effort_allowed?(model, effort) do
    case Map.fetch(@compatibility, model) do
      {:ok, allowed} -> effort in allowed
      :error -> false
    end
  end

  # -- chat_completion/2 ----------------------------------------------------

  @impl true
  def chat_completion(messages, opts) do
    {response_format, opts} = Keyword.pop(opts, :response_format, :text)

    with {:ok, prompt} <- build_prompt(messages),
         {:ok, command} <- fetch_command(opts) do
      run(command, prompt, opts, response_format)
    end
  end

  defp fetch_command(opts) do
    case Keyword.fetch(opts, :command) do
      {:ok, command} -> {:ok, command}
      :error -> {:error, {:missing_option, :command}}
    end
  end

  defp run(command, prompt, opts, response_format) do
    schema = json_object_schema(response_format)

    with {:ok, schema_path} <- write_schema_file(schema) do
      try do
        argv = build_argv(opts, schema_path, prompt)
        runner_opts = build_runner_opts(opts)

        command
        |> Runner.run(argv, runner_opts)
        |> handle_runner_result(response_format)
      after
        cleanup_schema_file(schema_path)
      end
    end
  end

  defp json_object_schema({:json_object, schema}), do: schema
  defp json_object_schema(:text), do: nil

  defp write_schema_file(nil), do: {:ok, nil}

  defp write_schema_file(schema) do
    path =
      Path.join(
        System.tmp_dir!(),
        "codex_schema_#{System.unique_integer([:positive, :monotonic])}.json"
      )

    case File.write(path, Jason.encode!(schema)) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, {:schema_write_failed, reason}}
    end
  end

  defp cleanup_schema_file(nil), do: :ok
  defp cleanup_schema_file(path), do: File.rm(path)

  defp build_argv(opts, schema_path, prompt) do
    []
    |> add_base_flags()
    |> add_model(opts)
    |> add_effort(opts)
    |> add_schema(schema_path)
    |> add_output(prompt)
  end

  defp add_base_flags(argv) do
    argv ++
      [
        "exec",
        "--skip-git-repo-check",
        "--ephemeral",
        "--sandbox",
        "read-only",
        "--ignore-user-config",
        "--color",
        "never"
      ]
  end

  defp add_model(argv, opts) do
    case Keyword.fetch(opts, :model) do
      {:ok, model} -> argv ++ ["--model", model]
      :error -> argv
    end
  end

  defp add_effort(argv, opts) do
    case Keyword.get(opts, :effort) do
      nil -> argv
      effort -> argv ++ ["-c", ~s(model_reasoning_effort="#{effort}")]
    end
  end

  defp add_schema(argv, nil), do: argv
  defp add_schema(argv, schema_path), do: argv ++ ["--output-schema", schema_path]

  defp add_output(argv, prompt), do: argv ++ ["-o", @output_filename, prompt]

  defp build_runner_opts(opts) do
    []
    |> maybe_put(:timeout_ms, Keyword.get(opts, :timeout_ms))
    |> maybe_put(:env, Keyword.get(opts, :env))
    |> Keyword.put(:before_cleanup, &read_output_file/1)
  end

  defp maybe_put(runner_opts, _key, nil), do: runner_opts
  defp maybe_put(runner_opts, key, value), do: Keyword.put(runner_opts, key, value)

  defp read_output_file(scratch_dir) do
    scratch_dir
    |> Path.join(@output_filename)
    |> File.read()
  end

  defp handle_runner_result({:ok, %{extra: extra}}, response_format) do
    with {:ok, content} <- validate_output_file(extra) do
      finalize(content, response_format)
    end
  end

  defp handle_runner_result({:error, reason}, _response_format), do: {:error, reason}

  defp validate_output_file({:ok, content}) do
    trimmed = String.trim(content)

    cond do
      byte_size(content) > @max_output_bytes -> {:error, {:invalid_output, :oversized}}
      trimmed == "" -> {:error, {:invalid_output, :empty}}
      true -> {:ok, trimmed}
    end
  end

  defp validate_output_file({:error, _reason}), do: {:error, {:invalid_output, :missing}}

  defp finalize(text, :text), do: {:ok, text}

  defp finalize(text, {:json_object, _schema}) do
    with {:ok, decoded} <- decode_json(text),
         {:ok, validated} <- validate_extraction_shape(decoded) do
      {:ok, Jason.encode!(validated)}
    end
  end

  defp decode_json(text) do
    case Jason.decode(text) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:error, {:invalid_output, :malformed_json}}
    end
  end

  @extraction_keys ~w(
    country city business_market initial_budget final_product_proposal product_price
  )

  defp validate_extraction_shape(%{} = map) do
    keys = Map.keys(map)

    cond do
      Enum.sort(keys) != Enum.sort(@extraction_keys) ->
        {:error, {:invalid_output, :schema_violation}}

      not Enum.all?(Map.values(map), &(is_binary(&1) or is_nil(&1))) ->
        {:error, {:invalid_output, :schema_violation}}

      true ->
        {:ok, map}
    end
  end

  defp validate_extraction_shape(_other), do: {:error, {:invalid_output, :schema_violation}}

  # -- prompt folding ---------------------------------------------------------

  defp build_prompt(messages) do
    Enum.reduce_while(messages, {:ok, []}, fn message, {:ok, acc} ->
      case validate_role(message) do
        {:ok, content} -> {:cont, {:ok, [content | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, parts} -> {:ok, parts |> Enum.reverse() |> Enum.join("\n\n")}
      {:error, _reason} = error -> error
    end
  end

  defp validate_role(%{"role" => role, "content" => content}) when role in @supported_roles do
    {:ok, content}
  end

  defp validate_role(%{"role" => role}), do: {:error, {:unsupported_role, role}}
end
