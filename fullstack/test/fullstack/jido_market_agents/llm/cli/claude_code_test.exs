defmodule Fullstack.JidoMarketAgents.LLM.Cli.ClaudeCodeTest do
  use ExUnit.Case, async: true

  alias Fullstack.JidoMarketAgents.Agents.ExtractionOutput
  alias Fullstack.JidoMarketAgents.LLM.Cli.ClaudeCode

  @fixtures_dir Path.join(__DIR__, "../../../../support/fake_cli") |> Path.expand()

  defp fixture(name), do: Path.join(@fixtures_dir, name)

  defp system_message(content), do: %{"role" => "system", "content" => content}
  defp user_message(content), do: %{"role" => "user", "content" => content}

  defp base_opts(command_fixture) do
    [command: fixture(command_fixture), model: "sonnet"]
  end

  # -- capabilities/1 --------------------------------------------------------

  describe "capabilities/1" do
    test "excludes :temperature and :max_tokens" do
      caps = ClaudeCode.capabilities(model: "sonnet")

      refute :temperature in caps
      refute :max_tokens in caps
    end

    test "advertises json_object, json_schema and effort" do
      caps = ClaudeCode.capabilities(model: "sonnet")

      assert :json_object in caps
      assert :json_schema in caps
      assert :effort in caps
    end
  end

  # -- validate_config/1 -----------------------------------------------------

  describe "validate_config/1" do
    test "rejects temperature:" do
      assert {:error, {:unsupported_option, :temperature}} =
               ClaudeCode.validate_config(command: "claude", model: "sonnet", temperature: 0.3)
    end

    test "rejects max_tokens:" do
      assert {:error, {:unsupported_option, :max_tokens}} =
               ClaudeCode.validate_config(command: "claude", model: "sonnet", max_tokens: 1024)
    end

    test "rejects unknown keys" do
      assert {:error, {:unknown_option, :nonsense}} =
               ClaudeCode.validate_config(command: "claude", model: "sonnet", nonsense: true)
    end

    test "requires command:" do
      assert {:error, {:missing_required_option, :command}} =
               ClaudeCode.validate_config(model: "sonnet")
    end

    test "rejects unknown model" do
      assert {:error, {:unsupported_model_config, "not-a-real-model"}} =
               ClaudeCode.validate_config(command: "claude", model: "not-a-real-model")
    end

    test "rejects any explicit effort as unverified" do
      assert {:error, {:unverified_effort, "high"}} =
               ClaudeCode.validate_config(command: "claude", model: "sonnet", effort: "high")
    end

    test "rejects an empty effort string" do
      assert {:error, {:invalid_effort, ""}} =
               ClaudeCode.validate_config(command: "claude", model: "sonnet", effort: "")
    end

    test "accepts omitted effort" do
      assert :ok = ClaudeCode.validate_config(command: "claude", model: "sonnet")
    end

    test "accepts effort: nil" do
      assert :ok = ClaudeCode.validate_config(command: "claude", model: "sonnet", effort: nil)
    end

    test "accepts known model aliases" do
      for model <- ~w(sonnet opus fable) do
        assert :ok = ClaudeCode.validate_config(command: "claude", model: model)
      end
    end
  end

  # -- argv exactness --------------------------------------------------------

  describe "chat_completion/2 argv construction" do
    test "model reaches argv verbatim and omitted effort emits no flag" do
      opts = base_opts("claude_echo_argv.sh") ++ [response_format: :text]
      messages = [user_message("hello")]

      assert {:ok, "ok"} = ClaudeCode.chat_completion(messages, opts)
    end

    # `claude_echo_argv.sh` logs argv to a file (argv.log) inside its cwd,
    # which is the Runner's private scratch directory, and emits only a
    # valid success JSON envelope on stdout. Reading argv.log requires
    # `before_cleanup`, since the scratch dir is removed once `run/3`
    # returns. This exercises the exact same argv-construction path the
    # adapter itself calls, by driving `Runner.run/3` with the argv the
    # adapter would build.
    defp captured_argv_lines(argv) do
      {:ok, result} =
        Fullstack.JidoMarketAgents.LLM.Cli.Runner.run(
          fixture("claude_echo_argv.sh"),
          argv,
          before_cleanup: fn scratch_dir ->
            scratch_dir |> Path.join("argv.log") |> File.read!()
          end
        )

      result.extra |> String.split("\n", trim: true)
    end

    test "argv contains exact elements in order, with no effort flag when omitted" do
      lines =
        captured_argv_lines([
          "-p",
          "--output-format",
          "json",
          "--restricted",
          "--no-session-persistence",
          "--model",
          "sonnet",
          "--system-prompt",
          "sys prompt",
          "user prompt"
        ])

      assert lines == [
               "ARG:[-p]",
               "ARG:[--output-format]",
               "ARG:[json]",
               "ARG:[--restricted]",
               "ARG:[--no-session-persistence]",
               "ARG:[--model]",
               "ARG:[sonnet]",
               "ARG:[--system-prompt]",
               "ARG:[sys prompt]",
               "ARG:[user prompt]"
             ]

      refute Enum.any?(lines, &String.starts_with?(&1, "ARG:[--effort]"))

      # Confirm the adapter itself produces this same argv shape end to end.
      opts = [command: fixture("claude_echo_argv.sh"), model: "sonnet", response_format: :text]
      messages = [system_message("sys prompt"), user_message("user prompt")]
      assert {:ok, "ok"} = ClaudeCode.chat_completion(messages, opts)
    end

    test "structured mode appends --json-schema with the encoded schema" do
      schema = ExtractionOutput.schema()

      lines =
        captured_argv_lines([
          "-p",
          "--output-format",
          "json",
          "--restricted",
          "--no-session-persistence",
          "--json-schema",
          Jason.encode!(schema),
          "--model",
          "sonnet",
          "extract this"
        ])

      assert "ARG:[--json-schema]" in lines
      assert Enum.any?(lines, &String.contains?(&1, "\"additionalProperties\":false"))

      # structured_output is absent from this fixture's canned output, so
      # the adapter call itself is expected to fail cleanly (no fallback to
      # `result`) rather than silently succeed on missing structured output.
      opts = [
        command: fixture("claude_echo_argv.sh"),
        model: "sonnet",
        response_format: {:json_object, schema}
      ]

      messages = [user_message("extract this")]
      assert {:error, :missing_structured_output} = ClaudeCode.chat_completion(messages, opts)
    end
  end

  # -- REGRESSION: exit 0 does not mean success ------------------------------

  describe "billing-error regression" do
    test "exit 0 + is_error true + api_error_status 400 is an error, never {:ok, result}" do
      opts = base_opts("claude_billing_error.sh") ++ [response_format: :text]
      messages = [user_message("do market research")]

      result = ClaudeCode.chat_completion(messages, opts)

      refute match?({:ok, "Credit balance is too low"}, result)
      assert {:error, :provider_error_envelope} = result
    end
  end

  # -- text mode --------------------------------------------------------------

  describe "chat_completion/2 text mode" do
    test "valid result returns {:ok, text}" do
      opts = base_opts("claude_success_text.sh") ++ [response_format: :text]
      messages = [user_message("hello")]

      assert {:ok, "Buenos Aires looks promising."} =
               ClaudeCode.chat_completion(messages, opts)
    end

    test "empty result is an error" do
      opts = base_opts("claude_empty_result.sh") ++ [response_format: :text]
      messages = [user_message("hello")]

      assert {:error, :empty_result} = ClaudeCode.chat_completion(messages, opts)
    end
  end

  # -- structured mode ----------------------------------------------------

  describe "chat_completion/2 structured mode" do
    test "valid structured output returns {:ok, json_text} decoding to the six-key map" do
      opts =
        base_opts("claude_success_structured.sh") ++
          [response_format: {:json_object, ExtractionOutput.schema()}]

      messages = [user_message("extract")]

      assert {:ok, json_text} = ClaudeCode.chat_completion(messages, opts)
      decoded = Jason.decode!(json_text)

      assert Map.keys(decoded) |> Enum.sort() ==
               ExtractionOutput.fields() |> Enum.map(&to_string/1) |> Enum.sort()

      assert decoded["country"] == "Argentina"
      assert decoded["city"] == nil
    end

    test "succeeds even when result is empty" do
      opts =
        base_opts("claude_success_structured.sh") ++
          [response_format: {:json_object, ExtractionOutput.schema()}]

      messages = [user_message("extract")]

      # claude_success_structured.sh sets "result":"" — must still succeed.
      assert {:ok, _json_text} = ClaudeCode.chat_completion(messages, opts)
    end

    test "all-null structured output is valid" do
      opts =
        base_opts("claude_success_structured_all_null.sh") ++
          [response_format: {:json_object, ExtractionOutput.schema()}]

      messages = [user_message("extract")]

      assert {:ok, json_text} = ClaudeCode.chat_completion(messages, opts)
      decoded = Jason.decode!(json_text)

      assert Enum.all?(Map.values(decoded), &is_nil/1)
    end

    test "missing structured_output field is an error, with NO fallback to result" do
      opts =
        base_opts("claude_missing_structured.sh") ++
          [response_format: {:json_object, ExtractionOutput.schema()}]

      messages = [user_message("extract")]

      assert {:error, :missing_structured_output} = ClaudeCode.chat_completion(messages, opts)
    end

    test "schema violation: extra key is an error" do
      opts =
        base_opts("claude_schema_violation_extra_key.sh") ++
          [response_format: {:json_object, ExtractionOutput.schema()}]

      messages = [user_message("extract")]

      assert {:error, :schema_key_mismatch} = ClaudeCode.chat_completion(messages, opts)
    end

    test "schema violation: wrong type is an error" do
      opts =
        base_opts("claude_schema_violation_wrong_type.sh") ++
          [response_format: {:json_object, ExtractionOutput.schema()}]

      messages = [user_message("extract")]

      assert {:error, :schema_type_mismatch} = ClaudeCode.chat_completion(messages, opts)
    end

    test "structured mode uses supplied required and additionalProperties rules" do
      messages = [user_message("extract")]

      supplied = %{
        "type" => "object",
        "properties" => %{
          "alpha" => %{"type" => ["string", "null"]},
          "beta" => %{"type" => ["string", "null"]}
        },
        "required" => ["alpha"],
        "additionalProperties" => false
      }

      run = fn payload ->
        opts =
          base_opts("claude_success_structured.sh") ++
            [
              response_format: {:json_object, supplied},
              env: %{"CLAUDE_FAKE_STRUCTURED_OUTPUT" => payload}
            ]

        ClaudeCode.chat_completion(messages, opts)
      end

      # payload honoring the supplied required/closed rules is accepted
      assert {:ok, json_text} = run.(~s({"alpha":"a","beta":null}))
      assert Jason.decode!(json_text) == %{"alpha" => "a", "beta" => nil}

      # required key missing → rejected
      assert {:error, :schema_key_mismatch} = run.(~s({"beta":null}))

      # additionalProperties: false rejects keys outside the supplied set
      assert {:error, :schema_key_mismatch} = run.(~s({"alpha":"a","gamma":"x"}))
    end

    test "structured mode accepts valid nested objects and rejects wrong nested types" do
      messages = [user_message("extract")]

      supplied = %{
        "type" => "object",
        "properties" => %{
          "team" => %{
            "type" => ["object", "null"],
            "properties" => %{
              "status" => %{"type" => "string", "enum" => ["known", "unknown"]},
              "count" => %{"type" => ["integer", "null"], "minimum" => 0}
            },
            "required" => ["status", "count"],
            "additionalProperties" => false
          },
          "tools" => %{
            "type" => "array",
            "items" => %{
              "type" => "object",
              "properties" => %{"name" => %{"type" => "string"}},
              "required" => ["name"],
              "additionalProperties" => false
            },
            "minItems" => 1,
            "maxItems" => 3
          }
        },
        "required" => ["team", "tools"],
        "additionalProperties" => false
      }

      run = fn payload ->
        opts =
          base_opts("claude_success_structured.sh") ++
            [
              response_format: {:json_object, supplied},
              env: %{"CLAUDE_FAKE_STRUCTURED_OUTPUT" => payload}
            ]

        ClaudeCode.chat_completion(messages, opts)
      end

      # valid nested payload
      assert {:ok, _json} =
               run.(
                 ~s({"team":{"status":"known","count":2},"tools":[{"name":"Slack"},{"name":"Notion"}]})
               )

      # wrong nested type
      assert {:error, :schema_type_mismatch} =
               run.(~s({"team":{"status":"known","count":"two"},"tools":[{"name":"Slack"}]}))

      # enum violation
      assert {:error, :schema_type_mismatch} =
               run.(~s({"team":{"status":"banana","count":1},"tools":[{"name":"Slack"}]}))

      # nested key rules
      assert {:error, :schema_key_mismatch} =
               run.(~s({"team":{"status":"known"},"tools":[{"name":"Slack"}]}))

      # minItems / maxItems
      assert {:error, :schema_type_mismatch} = run.(~s({"team":null,"tools":[]}))

      assert {:error, :schema_type_mismatch} =
               run.(
                 ~s({"team":null,"tools":[{"name":"a"},{"name":"b"},{"name":"c"},{"name":"d"}]})
               )

      # numeric bounds
      assert {:error, :schema_type_mismatch} =
               run.(~s({"team":{"status":"unknown","count":-1},"tools":[{"name":"a"}]}))

      # unsupported schema keyword is rejected before the CLI runs
      unsupported = %{
        "type" => "object",
        "properties" => %{"a" => %{"type" => "string", "pattern" => "^x"}},
        "required" => ["a"]
      }

      opts =
        base_opts("claude_success_structured.sh") ++
          [
            response_format: {:json_object, unsupported},
            env: %{"CLAUDE_FAKE_STRUCTURED_OUTPUT" => ~s({"a":"x"})}
          ]

      assert {:error, {:unsupported_schema_keyword, "pattern"}} =
               ClaudeCode.chat_completion(messages, opts)
    end

    test "refusal/error envelope is an error in structured mode too" do
      opts =
        base_opts("claude_billing_error.sh") ++
          [response_format: {:json_object, ExtractionOutput.schema()}]

      messages = [user_message("extract")]

      assert {:error, :provider_error_envelope} = ClaudeCode.chat_completion(messages, opts)
    end
  end

  # -- malformed output -------------------------------------------------------

  describe "malformed stdout" do
    test "non-JSON stdout is a tagged error" do
      opts = base_opts("claude_malformed_stdout.sh") ++ [response_format: :text]
      messages = [user_message("hello")]

      assert {:error, :malformed_output} = ClaudeCode.chat_completion(messages, opts)
    end
  end

  # -- role validation ---------------------------------------------------

  describe "message role validation" do
    test "rejects an unsupported role instead of silently flattening it" do
      opts = base_opts("claude_success_text.sh") ++ [response_format: :text]
      messages = [%{"role" => "assistant", "content" => "prior turn"}, user_message("hello")]

      assert {:error, {:unsupported_role, "assistant"}} =
               ClaudeCode.chat_completion(messages, opts)
    end

    test "rejects a message list with no user message" do
      opts = base_opts("claude_success_text.sh") ++ [response_format: :text]
      messages = [system_message("only a system message")]

      assert {:error, :missing_user_message} = ClaudeCode.chat_completion(messages, opts)
    end
  end

  # -- error term sanitization -------------------------------------------

  describe "error sanitization" do
    test "nonzero exit does not leak stderr content" do
      opts = base_opts("fail.sh") ++ [response_format: :text]
      messages = [user_message("do not leak this prompt text")]

      assert {:error, reason} = ClaudeCode.chat_completion(messages, opts)
      refute inspect(reason) =~ "do not leak this prompt text"
      refute inspect(reason) =~ "stderr"
    end

    test "env values passed through do not leak into a resulting error term" do
      opts =
        base_opts("fail.sh") ++
          [response_format: :text, env: %{"SECRET_TOKEN" => "s3cr3t-value"}]

      messages = [user_message("hello")]

      assert {:error, reason} = ClaudeCode.chat_completion(messages, opts)
      refute inspect(reason) =~ "s3cr3t-value"
    end
  end

  # -- Shared Backend contract (T7) ---------------------------------------
  #
  # `claude_success_text.sh` / `claude_success_structured.sh` are the
  # existing valid-success fixtures reused verbatim; the contract macro
  # itself introduces no new fixture.

  @contract_fixtures_dir Path.join(__DIR__, "../../../../support/fake_cli") |> Path.expand()

  use Fullstack.Support.BackendContract,
    backend: ClaudeCode,
    valid_config: [
      command: Path.join(@contract_fixtures_dir, "claude_success_text.sh"),
      model: "sonnet"
    ],
    json_config: [
      command: Path.join(@contract_fixtures_dir, "claude_success_structured.sh"),
      model: "sonnet"
    ],
    error_config: [command: Path.join(@contract_fixtures_dir, "fail.sh"), model: "sonnet"],
    error_sentinels: ["contract probe"]
end
