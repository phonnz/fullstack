defmodule Fullstack.JidoMarketAgents.FacadeSendMessageTest do
  # RateLimiter and MessageBufferSupervisor are now started by the application
  # supervision tree (T7, design section 5), so every test here shares the
  # same named RateLimiter and the same DynamicSupervisor. Serial, like
  # rate_limiter_test.exs and message_buffer_test.exs, for the same reason:
  # a single named GenServer cannot be started twice.
  use ExUnit.Case, async: false

  alias Fullstack.JidoMarketAgents
  alias Fullstack.JidoMarketAgents.Conversation

  @debounce_ms Application.compile_env!(:fullstack, Fullstack.JidoMarketAgents)[:debounce_ms]

  defp unique_user, do: System.unique_integer([:positive])
  defp unique_conversation, do: System.unique_integer([:positive])

  defp stub_mimo(responses, message, content) do
    owner = self()
    Agent.update(responses, &Map.put(&1, message, {owner, content}))
  end

  setup_all do
    responses = start_supervised!({Agent, fn -> %{} end})

    plug = fn conn, _opts ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)
      message = request["messages"] |> List.last() |> Map.fetch!("content")
      {owner, content} = Agent.get(responses, &Map.get(&1, message, {nil, "{}"}))
      if owner, do: send(owner, {:mimo_request, request})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{choices: [%{message: %{content: content}}]}))
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

  describe "R10 - S10.1 legacy send_message/3 bypasses buffer and limiter" do
    test "reaches the conversation directly and returns {:ok, :accepted, id}", %{
      mimo_responses: responses
    } do
      id = "legacy-#{unique_conversation()}"
      stub_mimo(responses, "hello", "{}")
      Conversation.subscribe(id)

      # {:ok, :accepted, id} is the legacy tuple shape - the buffered path
      # (S10.2 below) can only ever return {:ok, :buffered, conversation_id}.
      # Returning :accepted here is itself proof this call never touched
      # MessageBuffer or RateLimiter.
      assert {:ok, :accepted, ^id} = JidoMarketAgents.send_message(id, "hello")

      assert_receive {:mimo_request, _}, 2_000
    end
  end

  describe "R10 - S10.2 buffered send_message/4 goes through buffer and limiter" do
    test "returns {:ok, :buffered, conversation_id} and only reaches the conversation after the debounce window",
         %{mimo_responses: responses} do
      user_id = unique_user()
      conversation_id = unique_conversation()
      stub_mimo(responses, "hi there", "{}")
      Conversation.subscribe(conversation_id)

      assert {:ok, :buffered, ^conversation_id} =
               JidoMarketAgents.send_message(user_id, conversation_id, "hi there", [])

      # Not reached immediately - still inside the debounce window.
      refute_receive {:mimo_request, _}, div(@debounce_ms, 2)

      assert_receive {:mimo_request, _}, @debounce_ms + 500
    end
  end

  describe "end-to-end - rapid messages merge into one batch, flush, extract, and broadcast" do
    test "three rapid send_message/4 calls forward one merged batch and broadcast extraction", %{
      mimo_responses: responses
    } do
      user_id = unique_user()
      conversation_id = unique_conversation()
      merged = "one\n\ntwo\n\nthree"

      stub_mimo(responses, merged, "{}")
      Conversation.subscribe(conversation_id)

      assert {:ok, :buffered, ^conversation_id} =
               JidoMarketAgents.send_message(user_id, conversation_id, "one", [])

      assert {:ok, :buffered, ^conversation_id} =
               JidoMarketAgents.send_message(user_id, conversation_id, "two", [])

      assert {:ok, :buffered, ^conversation_id} =
               JidoMarketAgents.send_message(user_id, conversation_id, "three", [])

      assert_receive {:mimo_request, %{"messages" => mimo_messages}}, @debounce_ms + 500
      assert %{"content" => ^merged} = List.last(mimo_messages)

      assert_receive {:extraction_complete, %{conversation_id: ^conversation_id}}, 2_000
    end
  end

  describe "user_status/1" do
    test "reports :active before any batch and :cooldown once the limit is exceeded" do
      user_id = unique_user()

      assert JidoMarketAgents.user_status(user_id) == :active

      count_limit =
        Application.get_env(:fullstack, Fullstack.JidoMarketAgents)[:rate_limit_count]

      for _ <- 1..count_limit do
        Fullstack.JidoMarketAgents.RateLimiter.check_and_process(
          user_id,
          unique_conversation(),
          "msg"
        )
      end

      assert JidoMarketAgents.user_status(user_id) == :active

      Fullstack.JidoMarketAgents.RateLimiter.check_and_process(
        user_id,
        unique_conversation(),
        "over"
      )

      assert JidoMarketAgents.user_status(user_id) == :cooldown
    end
  end

  describe "buffer_status/1" do
    test "reports whether a buffer process exists for the user" do
      user_id = unique_user()
      conversation_id = unique_conversation()

      refute JidoMarketAgents.buffer_status(user_id) == :buffering

      assert {:ok, :buffered, ^conversation_id} =
               JidoMarketAgents.send_message(user_id, conversation_id, %{note: "x"}, [])

      assert JidoMarketAgents.buffer_status(user_id) == :buffering
    end
  end
end
