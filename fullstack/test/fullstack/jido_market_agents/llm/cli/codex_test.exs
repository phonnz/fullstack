defmodule Fullstack.JidoMarketAgents.LLM.Cli.CodexTest do
  use ExUnit.Case, async: true

  alias Fullstack.JidoMarketAgents.LLM.Cli.Codex

  @fixtures_dir Path.join(__DIR__, "../../../../support/fake_cli") |> Path.expand()

  defp fixture(name), do: Path.join(@fixtures_dir, name)

  @extraction_schema %{
    "type" => "object",
    "properties" =>
      Map.new(
        ~w(country city business_market initial_budget final_product_proposal product_price),
        &{&1, %{"type" => ["string", "null"]}}
      ),
    "required" =>
      ~w(country city business_market initial_budget final_product_proposal product_price),
    "additionalProperties" => false
  }

  defp user_message(text), do: %{"role" => "user", "content" => text}
  defp system_message(text), do: %{"role" => "system", "content" => text}

  # -- capabilities/1 ---------------------------------------------------------

  describe "capabilities/1" do
    test "never includes temperature or max_tokens" do
      caps = Codex.capabilities(command: fixture("codex_success_text.sh"))

      refute :temperature in caps
      refute :max_tokens in caps
    end

    test "always includes json_object and json_schema" do
      caps = Codex.capabilities(command: fixture("codex_success_text.sh"))

      assert :json_object in caps
      assert :json_schema in caps
    end

    test "includes effort for a supported model/effort combo" do
      caps =
        Codex.capabilities(
          command: fixture("codex_success_text.sh"),
          model: "gpt-5.6-terra",
          effort: "high"
        )

      assert :effort in caps
    end

    test "still advertises effort as a model capability when effort is omitted" do
      caps = Codex.capabilities(command: fixture("codex_success_text.sh"), model: "gpt-5.6-terra")

      assert :effort in caps
    end
  end

  # -- validate_config/1 ------------------------------------------------------

  describe "validate_config/1" do
    test "requires command" do
      assert {:error, {:missing_option, :command}} = Codex.validate_config(model: "gpt-6-astra")
    end

    test "accepts a minimal config with just command" do
      assert :ok = Codex.validate_config(command: fixture("codex_success_text.sh"))
    end

    test "rejects temperature" do
      assert {:error, {:unsupported_option, :temperature}} =
               Codex.validate_config(command: fixture("codex_success_text.sh"), temperature: 0.3)
    end

    test "rejects max_tokens" do
      assert {:error, {:unsupported_option, :max_tokens}} =
               Codex.validate_config(command: fixture("codex_success_text.sh"), max_tokens: 1024)
    end

    test "rejects unknown keys" do
      assert {:error, {:unknown_option, :bogus}} =
               Codex.validate_config(command: fixture("codex_success_text.sh"), bogus: true)
    end

    test "rejects an unknown model" do
      assert {:error, {:unsupported_model_config, _}} =
               Codex.validate_config(
                 command: fixture("codex_success_text.sh"),
                 model: "not-a-real-model"
               )
    end

    test "rejects an unsupported effort for a known model" do
      assert {:error, {:unsupported_model_config, _}} =
               Codex.validate_config(
                 command: fixture("codex_success_text.sh"),
                 model: "gpt-5.6-terra",
                 effort: "ultra-mega"
               )
    end

    test "accepts a known model with a supported effort" do
      assert :ok =
               Codex.validate_config(
                 command: fixture("codex_success_text.sh"),
                 model: "gpt-5.6-terra",
                 effort: "high"
               )
    end

    test "accepts omitted effort regardless of model" do
      assert :ok =
               Codex.validate_config(
                 command: fixture("codex_success_text.sh"),
                 model: "gpt-5.6-terra"
               )
    end

    test "accepts explicit nil effort regardless of model" do
      assert :ok =
               Codex.validate_config(
                 command: fixture("codex_success_text.sh"),
                 model: "gpt-5.6-terra",
                 effort: nil
               )
    end
  end

  # -- chat_completion/2: argv exactness ---------------------------------------

  describe "chat_completion/2 argv exactness" do
    test "model and effort reach argv verbatim as a single -c pair, alongside isolation flags" do
      assert {:ok, text} =
               Codex.chat_completion(
                 [user_message("hello")],
                 command: fixture("codex_echo_argv.sh"),
                 model: "gpt-5.6-terra",
                 effort: "high",
                 response_format: :text
               )

      assert text =~ "ARG:[--model]"
      assert text =~ "ARG:[gpt-5.6-terra]"
      assert text =~ "ARG:[-c]"
      assert text =~ ~s(ARG:[model_reasoning_effort="high"])
      assert text =~ "ARG:[--skip-git-repo-check]"
      assert text =~ "ARG:[--ephemeral]"
      assert text =~ "ARG:[--sandbox]"
      assert text =~ "ARG:[read-only]"
      assert text =~ "ARG:[--ignore-user-config]"
      assert text =~ "ARG:[hello]"
    end

    test "omitted effort produces no -c pair at all" do
      assert {:ok, text} =
               Codex.chat_completion(
                 [user_message("hello")],
                 command: fixture("codex_echo_argv.sh"),
                 model: "gpt-5.6-terra",
                 response_format: :text
               )

      refute text =~ "ARG:[-c]"
      refute text =~ "model_reasoning_effort"
    end

    test "an unsupported model/effort combo is rejected by validate_config/1 (the dispatcher's gate before any call reaches chat_completion/2)" do
      assert {:error, {:unsupported_model_config, _}} =
               Codex.validate_config(
                 command: fixture("codex_echo_argv.sh"),
                 model: "gpt-5.6-terra",
                 effort: "not-a-real-effort"
               )
    end
  end

  # -- chat_completion/2: critical noisy-stdout regression --------------------

  describe "chat_completion/2 noisy stdout regression" do
    test "succeeds despite 'ERROR: Reconnecting... 2/5' noise on stdout" do
      assert {:ok, text} =
               Codex.chat_completion(
                 [user_message("ping")],
                 command: fixture("codex_noisy_success.sh"),
                 response_format: :text
               )

      assert text == "PONG"
    end
  end

  # -- chat_completion/2: output file failure modes ----------------------------

  describe "chat_completion/2 output file failure modes" do
    test "missing output file is an error" do
      assert {:error, _reason} =
               Codex.chat_completion(
                 [user_message("hello")],
                 command: fixture("codex_missing_output.sh"),
                 response_format: :text
               )
    end

    test "empty (whitespace-only) output file is an error" do
      assert {:error, _reason} =
               Codex.chat_completion(
                 [user_message("hello")],
                 command: fixture("codex_empty_output.sh"),
                 response_format: :text
               )
    end

    test "oversized output file is an error" do
      assert {:error, _reason} =
               Codex.chat_completion(
                 [user_message("hello")],
                 command: fixture("codex_oversized_output.sh"),
                 response_format: :text
               )
    end
  end

  # -- chat_completion/2: text mode success ------------------------------------

  describe "chat_completion/2 text mode success" do
    test "returns the trimmed output file contents" do
      assert {:ok, "PONG"} =
               Codex.chat_completion(
                 [system_message("be terse"), user_message("hello")],
                 command: fixture("codex_success_text.sh"),
                 response_format: :text
               )
    end
  end

  # -- chat_completion/2: structured mode --------------------------------------

  describe "chat_completion/2 structured mode" do
    test "valid partial extraction JSON decodes and re-encodes with all six keys" do
      assert {:ok, json_text} =
               Codex.chat_completion(
                 [user_message("extract")],
                 command: fixture("codex_success_json.sh"),
                 response_format: {:json_object, @extraction_schema}
               )

      decoded = Jason.decode!(json_text)

      assert Map.keys(decoded) |> Enum.sort() ==
               ~w(business_market city country final_product_proposal initial_budget product_price)
               |> Enum.sort()

      assert decoded["country"] == "Argentina"
      assert decoded["city"] == nil
    end

    test "an all-null extraction object is valid" do
      assert {:ok, json_text} =
               Codex.chat_completion(
                 [user_message("extract")],
                 command: fixture("codex_all_null_json.sh"),
                 response_format: {:json_object, @extraction_schema}
               )

      decoded = Jason.decode!(json_text)
      assert Enum.all?(Map.values(decoded), &is_nil/1)
    end

    test "a schema violation (missing/extra keys) is a tagged error" do
      assert {:error, _reason} =
               Codex.chat_completion(
                 [user_message("extract")],
                 command: fixture("codex_bad_schema_json.sh"),
                 response_format: {:json_object, @extraction_schema}
               )
    end

    test "malformed JSON is a tagged error" do
      assert {:error, _reason} =
               Codex.chat_completion(
                 [user_message("extract")],
                 command: fixture("codex_malformed_json.sh"),
                 response_format: {:json_object, @extraction_schema}
               )
    end
  end

  # -- chat_completion/2: scratch dir cleanup ----------------------------------

  describe "chat_completion/2 scratch dir cleanup" do
    test "the scratch dir used for the call no longer exists afterward" do
      alias Fullstack.JidoMarketAgents.LLM.Cli.Runner

      # Codex.chat_completion/2 never exposes its scratch dir to the caller
      # (by the time it returns, Runner has already removed it), so this
      # exercises the same Runner.run/3 lifecycle Codex builds on directly to
      # get a real path back for a post-call existence check.
      assert {:ok, result} = Runner.run(fixture("codex_success_text.sh"), ["-o", "out.txt"])
      refute File.exists?(result.scratch_dir)
    end
  end

  # -- chat_completion/2: error term sanitization -------------------------------

  describe "chat_completion/2 error term sanitization" do
    test "error terms never contain the prompt text or env values" do
      sentinel_prompt = "SENTINEL_PROMPT_MARKER_798213"
      sentinel_env_value = "SENTINEL_ENV_MARKER_321987"

      {:error, reason} =
        Codex.chat_completion(
          [user_message(sentinel_prompt)],
          command: fixture("codex_missing_output.sh"),
          env: %{"SOME_VAR" => sentinel_env_value},
          response_format: :text
        )

      inspected = inspect(reason)
      refute inspected =~ sentinel_prompt
      refute inspected =~ sentinel_env_value
    end
  end

  # -- chat_completion/2: unsupported role rejection ---------------------------

  describe "chat_completion/2 unsupported role rejection" do
    test "an unsupported role is rejected before any subprocess is spawned" do
      marker_dir =
        Path.join(System.tmp_dir!(), "codex_marker_probe_#{System.unique_integer([:positive])}")

      File.mkdir_p!(marker_dir)
      marker_path = Path.join(marker_dir, "codex_marker_on_spawn.touched")

      try do
        assert {:error, {:unsupported_role, "assistant"}} =
                 Codex.chat_completion(
                   [%{"role" => "assistant", "content" => "hi"}, user_message("hello")],
                   command: fixture("codex_marker_on_spawn.sh"),
                   response_format: :text
                 )

        refute File.exists?(marker_path)
      after
        File.rm_rf(marker_dir)
      end
    end
  end
end
