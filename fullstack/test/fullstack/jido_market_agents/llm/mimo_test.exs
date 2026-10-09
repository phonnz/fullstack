defmodule Fullstack.JidoMarketAgents.LLM.MimoTest do
  # Mutates System env (MIMO_BASE_URL/MIMO_API_KEY) via setup_all and, in some
  # tests, Application.get_env(:fullstack, Fullstack.JidoMarketAgents, ...) —
  # must not run concurrently with other tests touching the same state.
  use ExUnit.Case, async: false

  alias Fullstack.JidoMarketAgents.LLM
  alias Fullstack.JidoMarketAgents.LLM.Mimo

  @app :fullstack
  @scope Fullstack.JidoMarketAgents

  setup_all do
    responses = start_supervised!({Agent, fn -> %{} end})

    plug = fn conn, _opts ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)
      message = request["messages"] |> List.last() |> Map.fetch!("content")
      owner = Agent.get(responses, &Map.get(&1, message))
      if owner, do: send(owner, {:mimo_request, request})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{choices: [%{message: %{content: "ok"}}]}))
    end

    server = start_supervised!({Bandit, plug: plug, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    previous_env = Map.new(["MIMO_BASE_URL", "MIMO_API_KEY"], &{&1, System.get_env(&1)})
    System.put_env("MIMO_BASE_URL", "http://127.0.0.1:#{port}/v1")
    System.put_env("MIMO_API_KEY", "local-test-key")

    on_exit(fn ->
      for key <- ["MIMO_BASE_URL", "MIMO_API_KEY"] do
        case previous_env[key] do
          nil -> System.delete_env(key)
          value -> System.put_env(key, value)
        end
      end
    end)

    {:ok, mimo_responses: responses}
  end

  # Registers the last-message content as owned by the calling test process,
  # so the Bandit plug (running outside this process) can relay the decoded
  # request body back via `send/2`. Returns the message list to pass as
  # `chat_completion/2`'s first argument.
  defp stub_and_messages(responses, content) do
    owner = self()
    Agent.update(responses, &Map.put(&1, content, owner))
    [%{"role" => "user", "content" => content}]
  end

  # -- capabilities/1 --------------------------------------------------------

  describe "capabilities/1" do
    test "returns json_object, temperature and max_tokens" do
      caps = Mimo.capabilities(model: "mimo-v2.5-pro")

      assert :json_object in caps
      assert :temperature in caps
      assert :max_tokens in caps
    end

    test "does not include json_schema or effort" do
      caps = Mimo.capabilities(model: "mimo-v2.5-pro")

      refute :json_schema in caps
      refute :effort in caps
    end
  end

  # -- validate_config/1 ------------------------------------------------------

  describe "validate_config/1" do
    test "accepts valid opts with model, temperature and max_tokens" do
      assert :ok =
               Mimo.validate_config(model: "mimo-v2.5-pro", temperature: 0.3, max_tokens: 1024)
    end

    test "accepts omitted model (backward-compatible default)" do
      assert :ok = Mimo.validate_config(max_tokens: 1024)
    end

    test "accepts explicit thinking modes and rejects invalid modes" do
      assert :ok = Mimo.validate_config(thinking: :disabled)
      assert :ok = Mimo.validate_config(thinking: :enabled)
      assert {:error, {:invalid_option, :thinking}} = Mimo.validate_config(thinking: :sometimes)
    end

    test "rejects effort as unsupported" do
      assert {:error, {:unsupported_option, :effort}} =
               Mimo.validate_config(model: "mimo-v2.5-pro", effort: "high")
    end

    test "rejects unknown keys" do
      assert {:error, {:unknown_option, :bogus}} =
               Mimo.validate_config(model: "mimo-v2.5-pro", bogus: true)
    end
  end

  # -- chat_completion/2: response_format translation -------------------------

  describe "chat_completion/2 response_format translation" do
    test ":text does not set response_format in the request body", %{mimo_responses: responses} do
      messages = stub_and_messages(responses, "text-format")

      assert {:ok, "ok"} = Mimo.chat_completion(messages, response_format: :text)
      assert_receive {:mimo_request, request}
      refute Map.has_key?(request, "response_format")
    end

    test "{:json_object, schema} sets response_format json_object and discards the schema", %{
      mimo_responses: responses
    } do
      messages = stub_and_messages(responses, "json-object-format")
      schema = %{"type" => "object", "properties" => %{"country" => %{"type" => "string"}}}

      assert {:ok, "ok"} =
               Mimo.chat_completion(messages, response_format: {:json_object, schema})

      assert_receive {:mimo_request, request}
      assert request["response_format"] == %{"type" => "json_object"}
      refute Map.has_key?(request, "schema")
      refute Map.has_key?(request, "json_schema")
    end
  end

  # -- chat_completion/2: option forwarding ------------------------------------

  describe "chat_completion/2 option forwarding" do
    test "forwards explicit disabled thinking without changing the output contract", %{
      mimo_responses: responses
    } do
      messages = stub_and_messages(responses, "thinking-disabled")

      assert {:ok, "ok"} =
               Mimo.chat_completion(messages, response_format: :text, thinking: :disabled)

      assert_receive {:mimo_request, request}
      assert request["thinking"] == %{"type" => "disabled"}
    end

    test "model reaches the HTTP request body verbatim", %{mimo_responses: responses} do
      messages = stub_and_messages(responses, "model-forwarding")

      assert {:ok, "ok"} =
               Mimo.chat_completion(messages, response_format: :text, model: "custom-model-x")

      assert_receive {:mimo_request, request}
      assert request["model"] == "custom-model-x"
    end

    test "validator-style config (temperature present) and researcher-style config (temperature absent) produce different bodies",
         %{mimo_responses: responses} do
      validator_messages = stub_and_messages(responses, "validator-role-config")

      assert {:ok, "ok"} =
               Mimo.chat_completion(validator_messages,
                 response_format: :text,
                 temperature: 0.3,
                 max_tokens: 1024
               )

      assert_receive {:mimo_request, validator_request}
      assert validator_request["temperature"] == 0.3
      assert validator_request["max_completion_tokens"] == 1024
      refute Map.has_key?(validator_request, "max_tokens")

      researcher_messages = stub_and_messages(responses, "researcher-role-config")

      assert {:ok, "ok"} =
               Mimo.chat_completion(researcher_messages, response_format: :text, max_tokens: 1024)

      assert_receive {:mimo_request, researcher_request}
      assert researcher_request["max_completion_tokens"] == 1024
      refute Map.has_key?(researcher_request, "max_tokens")
      refute Map.has_key?(researcher_request, "thinking")
      # No cross-role leakage: researcher config never carried temperature, so
      # the request falls back to MimoClient's own default (0.7), not the
      # validator's 0.3.
      assert researcher_request["temperature"] == 0.7
    end
  end

  # -- chat_completion/2: error propagation ------------------------------------

  describe "chat_completion/2 error propagation" do
    test "a non-200 response from the stub surfaces as a tagged error" do
      previous = System.get_env("MIMO_BASE_URL")
      # Point at a port with nothing listening to force a transport error.
      System.put_env("MIMO_BASE_URL", "http://127.0.0.1:1/v1")

      on_exit(fn ->
        if previous, do: System.put_env("MIMO_BASE_URL", previous)
      end)

      assert {:error, _reason} =
               Mimo.chat_completion([%{"role" => "user", "content" => "boom"}],
                 response_format: :text
               )
    end
  end

  # -- end-to-end through LLM.chat_completion/3 --------------------------------

  describe "end-to-end dispatch through LLM.chat_completion/3" do
    setup do
      original = Application.get_env(@app, @scope, [])

      on_exit(fn ->
        Application.put_env(@app, @scope, original)
      end)

      :ok
    end

    defp put_backends(validator, researcher) do
      base = Application.get_env(@app, @scope, [])

      Application.put_env(
        @app,
        @scope,
        Keyword.merge(base, validator_backend: validator, researcher_backend: researcher)
      )
    end

    test "LLM.chat_completion(:validator, ...) dispatches through Mimo with validator config",
         %{mimo_responses: responses} do
      put_backends(
        {Mimo, model: "mimo-v2.5-pro", temperature: 0.3, max_tokens: 1024},
        {Mimo, model: "mimo-v2.5-pro", max_tokens: 1024}
      )

      messages = stub_and_messages(responses, "e2e-validator")

      assert {:ok, "ok"} = LLM.chat_completion(:validator, messages, response_format: :text)
    end

    test "LLM.chat_completion(:researcher, ...) dispatches through Mimo with researcher config",
         %{mimo_responses: responses} do
      put_backends(
        {Mimo, model: "mimo-v2.5-pro", temperature: 0.3, max_tokens: 1024},
        {Mimo, model: "mimo-v2.5-pro", max_tokens: 1024}
      )

      messages = stub_and_messages(responses, "e2e-researcher")

      assert {:ok, "ok"} = LLM.chat_completion(:researcher, messages, response_format: :text)
    end

    test "LLM.chat_completion(:validator, {:json_object, _}) succeeds because Mimo advertises json_object",
         %{mimo_responses: responses} do
      put_backends(
        {Mimo, model: "mimo-v2.5-pro", temperature: 0.3, max_tokens: 1024},
        {Mimo, model: "mimo-v2.5-pro", max_tokens: 1024}
      )

      messages = stub_and_messages(responses, "e2e-validator-json")

      assert {:ok, "ok"} =
               LLM.chat_completion(:validator, messages,
                 response_format: {:json_object, %{"type" => "object"}}
               )
    end
  end
end
