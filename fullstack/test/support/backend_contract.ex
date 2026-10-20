defmodule Fullstack.Support.BackendContract do
  @moduledoc """
  Shared ExUnit contract test suite for `Fullstack.JidoMarketAgents.LLM.Backend`
  implementations.

  Injects a fixed set of behaviour-shape tests via `use`, driven purely by
  the options given — never by branching on which backend module is under
  test. This is the "no provider switch statement" extension contract from
  the plan (`odd/tasks/llm-backend-adapter.md`, "Extending providers and
  models"): any new adapter proves it satisfies the shared `Backend`
  contract by using this macro with its own options, with zero changes to
  this module itself.

  ## Usage

      use Fullstack.Support.BackendContract,
        backend: SomeModule,
        valid_config: [command: "...", model: "..."]

  ## Options

    * `:backend` (required) — the backend module under test.
    * `:valid_config` (required) — a keyword list that is a valid,
      structurally complete configuration for `backend`.
    * `:json_config` (optional) — a keyword list to use specifically for the
      `:json_schema` structured-output test, when `:json_schema` is
      advertised. Defaults to `:valid_config`.
    * `:error_config` (optional) — a keyword list expected to make
      `chat_completion/2` return `{:error, reason}`. When omitted, the
      sentinel-leak test is skipped entirely.
    * `:error_sentinels` (optional) — a list of strings that must NOT
      appear in `inspect/1` of the error reason returned for
      `:error_config`. Defaults to `[]` (no-op).
  """

  defmacro __using__(opts) do
    backend = Keyword.fetch!(opts, :backend)
    valid_config = Keyword.fetch!(opts, :valid_config)
    json_config = Keyword.get(opts, :json_config, valid_config)
    error_config = Keyword.get(opts, :error_config)
    error_sentinels = Keyword.get(opts, :error_sentinels, [])

    quote do
      alias Fullstack.JidoMarketAgents.Agents.ExtractionOutput

      @contract_backend unquote(backend)
      @contract_valid_config unquote(valid_config)
      @contract_json_config unquote(json_config)
      @contract_error_config unquote(error_config)
      @contract_error_sentinels unquote(error_sentinels)

      describe "Backend contract (#{inspect(@contract_backend)})" do
        test "#{inspect(@contract_backend)} exports all three Backend callbacks" do
          # `function_exported?/3` alone does not force the module to load —
          # on a module that has been freshly compiled but not yet loaded by
          # this VM instance, it returns `false` for an existing function
          # rather than loading it first. `Code.ensure_loaded?/1` (the same
          # guard `LLM.resolve_and_validate/1` uses) forces the load, so this
          # assertion reflects the module's real callback set instead of an
          # incidental load-order race.
          assert Code.ensure_loaded?(@contract_backend)
          assert function_exported?(@contract_backend, :chat_completion, 2)
          assert function_exported?(@contract_backend, :capabilities, 1)
          assert function_exported?(@contract_backend, :validate_config, 1)
        end

        test "#{inspect(@contract_backend)}.capabilities/1 returns only known capabilities" do
          caps = @contract_backend.capabilities(@contract_valid_config)

          assert is_list(caps)

          assert Enum.all?(
                   caps,
                   &(&1 in [:json_object, :json_schema, :temperature, :max_tokens, :effort])
                 )
        end

        test "#{inspect(@contract_backend)}.validate_config/1 never raises across a range of shapes" do
          for opts <- contract_validate_config_shapes() do
            result =
              try do
                @contract_backend.validate_config(opts)
              rescue
                error -> {:contract_raised, error}
              end

            assert match?(:ok, result) or match?({:error, _reason}, result),
                   "expected :ok or {:error, _}, got #{inspect(result)} for opts #{inspect(opts)}"
          end
        end

        test "#{inspect(@contract_backend)}.validate_config/1 returns fast with no network/subprocess side effect" do
          opts =
            if Keyword.has_key?(@contract_valid_config, :command) do
              Keyword.put(@contract_valid_config, :command, "/nonexistent/path/to/binary")
            else
              @contract_valid_config
            end

          start = System.monotonic_time(:millisecond)

          result =
            try do
              @contract_backend.validate_config(opts)
            rescue
              error -> {:contract_raised, error}
            end

          elapsed = System.monotonic_time(:millisecond) - start

          assert match?(:ok, result) or match?({:error, _reason}, result),
                 "expected :ok or {:error, _}, got #{inspect(result)}"

          assert elapsed < 500,
                 "validate_config/1 took #{elapsed}ms — expected no network/subprocess call"
        end

        test "#{inspect(@contract_backend)}.chat_completion/2 with :text returns {:ok, binary} or {:error, term}, never a raw map" do
          messages = [%{"role" => "user", "content" => "contract probe"}]
          opts = Keyword.put(@contract_valid_config, :response_format, :text)

          case @contract_backend.chat_completion(messages, opts) do
            {:ok, value} -> assert is_binary(value)
            {:error, _reason} -> :ok
            other -> flunk("unexpected chat_completion/2 return shape: #{inspect(other)}")
          end
        end

        if @contract_error_config do
          test "#{inspect(@contract_backend)}.chat_completion/2 error reason leaks none of the configured sentinels" do
            messages = [%{"role" => "user", "content" => "contract probe"}]
            opts = Keyword.put(@contract_error_config, :response_format, :text)

            case @contract_backend.chat_completion(messages, opts) do
              {:error, reason} ->
                inspected = inspect(reason)

                for sentinel <- @contract_error_sentinels do
                  refute inspected =~ sentinel,
                         "error reason #{inspect(reason)} leaked sentinel #{inspect(sentinel)}"
                end

              {:ok, _value} ->
                :ok
            end
          end
        end

        test "#{inspect(@contract_backend)} :json_schema structured output round-trips to a JSON map, when advertised" do
          caps = @contract_backend.capabilities(@contract_json_config)

          if :json_schema in caps do
            messages = [%{"role" => "user", "content" => "contract probe: extract"}]

            opts =
              Keyword.put(
                @contract_json_config,
                :response_format,
                {:json_object, ExtractionOutput.schema()}
              )

            assert {:ok, json_text} = @contract_backend.chat_completion(messages, opts)
            assert is_binary(json_text)
            assert %{} = Jason.decode!(json_text)
          end
        end
      end

      defp contract_validate_config_shapes do
        wrong_typed =
          if Keyword.has_key?(@contract_valid_config, :command) do
            Keyword.put(@contract_valid_config, :command, 12345)
          else
            [garbage_typed_value: 12345, another: %{not: :a_keyword_value}]
          end

        [
          @contract_valid_config,
          [],
          [totally_unknown_key: 123],
          wrong_typed
        ]
      end
    end
  end
end
