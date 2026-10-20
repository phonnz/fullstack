defmodule Fullstack.JidoMarketAgents.LLMTest do
  # Mutates and restores `Application.get_env(:fullstack, Fullstack.JidoMarketAgents, ...)`
  # for the duration of each test, so this module must not run concurrently
  # with other tests that read/write the same application env key.
  use ExUnit.Case, async: false

  alias Fullstack.JidoMarketAgents.LLM

  @app :fullstack
  @scope Fullstack.JidoMarketAgents

  # -- Fake backends -----------------------------------------------------

  defmodule FakeBackendJsonObject do
    @moduledoc false
    @behaviour Fullstack.JidoMarketAgents.LLM.Backend

    @impl true
    def chat_completion(_messages, opts) do
      send(self(), {:backend_called, __MODULE__, opts})
      {:ok, "json-object-reply"}
    end

    @impl true
    def capabilities(_opts), do: [:json_object, :temperature]

    @impl true
    def validate_config(_opts), do: :ok
  end

  defmodule FakeBackendTextOnly do
    @moduledoc false
    @behaviour Fullstack.JidoMarketAgents.LLM.Backend

    @impl true
    def chat_completion(_messages, opts) do
      send(self(), {:backend_called, __MODULE__, opts})
      {:ok, "text-reply"}
    end

    @impl true
    def capabilities(_opts), do: []

    @impl true
    def validate_config(_opts), do: :ok
  end

  defmodule FakeBackendInvalidConfig do
    @moduledoc false
    @behaviour Fullstack.JidoMarketAgents.LLM.Backend

    @impl true
    def chat_completion(_messages, _opts), do: {:ok, "unreachable"}

    @impl true
    def capabilities(_opts), do: [:json_object]

    @impl true
    def validate_config(_opts), do: {:error, :bad_backend_config}
  end

  # Deliberately implements only 2 of the 3 required callbacks.
  defmodule FakeBackendMissingCallback do
    @moduledoc false

    def chat_completion(_messages, _opts), do: {:ok, "unreachable"}
    def capabilities(_opts), do: [:json_object]
    # validate_config/1 intentionally not defined.
  end

  # -- Setup ---------------------------------------------------------------

  setup do
    original = Application.get_env(@app, @scope, [])

    on_exit(fn ->
      Application.put_env(@app, @scope, original)
    end)

    :ok
  end

  defp put_backends(validator, researcher, extra \\ []) do
    base = Application.get_env(@app, @scope, [])

    Application.put_env(
      @app,
      @scope,
      Keyword.merge(base, extra ++ [validator_backend: validator, researcher_backend: researcher])
    )
  end

  # -- Dispatch happy paths --------------------------------------------------

  test "dispatches :validator and :researcher independently to their configured backends" do
    put_backends(
      {FakeBackendJsonObject, model: "validator-model"},
      {FakeBackendTextOnly, model: "researcher-model"}
    )

    assert {:ok, "json-object-reply"} =
             LLM.chat_completion(:validator, [%{"role" => "user", "content" => "hi"}],
               response_format: {:json_object, %{}}
             )

    assert_received {:backend_called, FakeBackendJsonObject, opts}
    assert Keyword.get(opts, :model) == "validator-model"

    assert {:ok, "text-reply"} =
             LLM.chat_completion(:researcher, [%{"role" => "user", "content" => "hi"}],
               response_format: :text
             )

    assert_received {:backend_called, FakeBackendTextOnly, opts2}
    assert Keyword.get(opts2, :model) == "researcher-model"
  end

  test "one role's configured opts never leak into the other role's dispatch call" do
    put_backends(
      {FakeBackendJsonObject, model: "validator-only-model", temperature: 0.3},
      {FakeBackendJsonObject, model: "researcher-only-model", max_tokens: 999}
    )

    LLM.chat_completion(:validator, [], response_format: {:json_object, %{}})
    assert_received {:backend_called, FakeBackendJsonObject, validator_opts}

    LLM.chat_completion(:researcher, [], response_format: {:json_object, %{}})
    assert_received {:backend_called, FakeBackendJsonObject, researcher_opts}

    assert Keyword.get(validator_opts, :model) == "validator-only-model"
    assert Keyword.get(validator_opts, :temperature) == 0.3
    refute Keyword.has_key?(validator_opts, :max_tokens)

    assert Keyword.get(researcher_opts, :model) == "researcher-only-model"
    assert Keyword.get(researcher_opts, :max_tokens) == 999
    refute Keyword.has_key?(researcher_opts, :temperature)
  end

  test "all configured backend opts reach the adapter call, including arbitrary keys" do
    put_backends(
      {FakeBackendJsonObject,
       model: "some-model", temperature: 0.42, some_arbitrary_key: :arbitrary_value},
      {FakeBackendTextOnly, model: "other-model"}
    )

    LLM.chat_completion(:validator, [], response_format: {:json_object, %{}})

    assert_received {:backend_called, FakeBackendJsonObject, opts}
    assert Keyword.get(opts, :model) == "some-model"
    assert Keyword.get(opts, :temperature) == 0.42
    assert Keyword.get(opts, :some_arbitrary_key) == :arbitrary_value
  end

  test "response_format is passed through to the backend opts" do
    put_backends(
      {FakeBackendJsonObject, model: "m"},
      {FakeBackendTextOnly, model: "m2"}
    )

    LLM.chat_completion(:validator, [], response_format: {:json_object, %{"type" => "object"}})

    assert_received {:backend_called, FakeBackendJsonObject, opts}
    assert Keyword.get(opts, :response_format) == {:json_object, %{"type" => "object"}}
  end

  test "LLM.backend/1 returns the resolved {module, opts} tuple for a role" do
    put_backends(
      {FakeBackendJsonObject, model: "validator-model"},
      {FakeBackendTextOnly, model: "researcher-model"}
    )

    assert {:ok, {FakeBackendJsonObject, opts}} = LLM.backend(:validator)
    assert Keyword.get(opts, :model) == "validator-model"

    assert {:ok, {FakeBackendTextOnly, opts2}} = LLM.backend(:researcher)
    assert Keyword.get(opts2, :model) == "researcher-model"
  end

  # -- Caller option policy -----------------------------------------------

  test "missing response_format in caller opts is a tagged error" do
    put_backends({FakeBackendJsonObject, model: "m"}, {FakeBackendTextOnly, model: "m2"})

    assert {:error, {:missing_option, :response_format}} =
             LLM.chat_completion(:validator, [], [])
  end

  test "unknown response_format value is a tagged error" do
    put_backends({FakeBackendJsonObject, model: "m"}, {FakeBackendTextOnly, model: "m2"})

    assert {:error, {:invalid_response_format, :bogus}} =
             LLM.chat_completion(:validator, [], response_format: :bogus)
  end

  test "unknown caller opt key is a tagged error" do
    put_backends({FakeBackendJsonObject, model: "m"}, {FakeBackendTextOnly, model: "m2"})

    assert {:error, {:unknown_option, :model}} =
             LLM.chat_completion(:validator, [], response_format: :text, model: "sneaky")
  end

  # -- Role validation ------------------------------------------------------

  test "unknown role atom is a tagged error" do
    put_backends({FakeBackendJsonObject, model: "m"}, {FakeBackendTextOnly, model: "m2"})

    assert {:error, {:unknown_role, :nonexistent_role}} =
             LLM.chat_completion(:nonexistent_role, [], response_format: :text)
  end

  # -- Config shape validation -----------------------------------------------

  test "malformed config entry (not a {module, keyword_list} 2-tuple) is a tagged error, no crash" do
    put_backends(:not_a_tuple, {FakeBackendTextOnly, model: "m2"})

    assert {:error, {:invalid_backend_config, :validator, :not_a_tuple}} =
             LLM.chat_completion(:validator, [], response_format: :text)
  end

  test "malformed config entry with non-keyword-list opts is a tagged error, no crash" do
    put_backends(
      {FakeBackendJsonObject, "not-a-keyword-list"},
      {FakeBackendTextOnly, model: "m2"}
    )

    assert {:error,
            {:invalid_backend_config, :validator, {FakeBackendJsonObject, "not-a-keyword-list"}}} =
             LLM.chat_completion(:validator, [], response_format: :text)
  end

  # -- Backend module validation --------------------------------------------

  test "backend module missing a required callback is a tagged error from dispatch" do
    put_backends({FakeBackendMissingCallback, model: "m"}, {FakeBackendTextOnly, model: "m2"})

    assert {:error, {:invalid_backend_module, FakeBackendMissingCallback}} =
             LLM.chat_completion(:validator, [], response_format: :text)
  end

  test "backend module missing a required callback fails LLM.validate_config/0" do
    put_backends({FakeBackendMissingCallback, model: "m"}, {FakeBackendTextOnly, model: "m2"})

    assert {:error, {:validator, {:invalid_backend_module, FakeBackendMissingCallback}}} =
             LLM.validate_config()
  end

  # -- Backend validate_config/1 propagation --------------------------------

  test "backend validate_config/1 returning {:error, _} is propagated from dispatch" do
    put_backends({FakeBackendInvalidConfig, model: "m"}, {FakeBackendTextOnly, model: "m2"})

    assert {:error, {:backend_config_invalid, FakeBackendInvalidConfig, :bad_backend_config}} =
             LLM.chat_completion(:validator, [], response_format: {:json_object, %{}})
  end

  test "backend validate_config/1 returning {:error, _} is propagated from LLM.validate_config/0" do
    put_backends({FakeBackendInvalidConfig, model: "m"}, {FakeBackendTextOnly, model: "m2"})

    assert {:error,
            {:validator, {:backend_config_invalid, FakeBackendInvalidConfig, :bad_backend_config}}} =
             LLM.validate_config()
  end

  # -- Capability mismatch ---------------------------------------------------

  test "capability mismatch (json_object required, backend lacks it) is a tagged error, backend never called" do
    put_backends({FakeBackendTextOnly, model: "m"}, {FakeBackendTextOnly, model: "m2"})

    assert {:error, {:unsupported_capability, :json_object}} =
             LLM.chat_completion(:validator, [], response_format: {:json_object, %{}})

    refute_received {:backend_called, FakeBackendTextOnly, _opts}
  end

  test "response_format: :text requires no particular capability" do
    put_backends({FakeBackendTextOnly, model: "m"}, {FakeBackendTextOnly, model: "m2"})

    assert {:ok, "text-reply"} =
             LLM.chat_completion(:validator, [], response_format: :text)
  end

  # -- LLM.validate_config/0 ------------------------------------------------

  test "LLM.validate_config/0 succeeds when both roles are structurally valid" do
    put_backends({FakeBackendJsonObject, model: "m"}, {FakeBackendTextOnly, model: "m2"})

    assert :ok = LLM.validate_config()
  end

  test "LLM.validate_config/0 fails when the researcher role is invalid" do
    put_backends({FakeBackendJsonObject, model: "m"}, :not_a_tuple)

    assert {:error, {:researcher, {:invalid_backend_config, :researcher, :not_a_tuple}}} =
             LLM.validate_config()
  end

  test "backend/1 recognizes analyzer systems and strategy roles" do
    config = Application.get_env(@app, @scope, [])

    overrides =
      for {role, key} <- [
            analyzer: :analyzer_backend,
            systems: :systems_backend,
            strategy: :strategy_backend
          ],
          do: {key, {FakeBackendJsonObject, model: Atom.to_string(role)}}

    Application.put_env(@app, @scope, Keyword.merge(config, overrides))

    for role <- [:analyzer, :systems, :strategy] do
      assert {:ok, {FakeBackendJsonObject, opts}} = LLM.backend(role)
      assert opts[:model] == Atom.to_string(role)
    end

    assert {:error, {:unknown_role, :other}} = LLM.backend(:other)
  end
end
