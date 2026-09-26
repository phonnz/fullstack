defmodule Fullstack.JidoMarketAgents.MessageBufferTest do
  # MessageBuffer forwards flushed batches to a REAL `RateLimiter` (a single
  # named GenServer, design D6). Two async tests both starting it would race
  # on the same registered name and crash with `{:already_started, pid}` —
  # the exact reason `rate_limiter_test.exs` itself is `async: false`.
  # `MessageBuffer` processes are per-user (this task's own process), so
  # nothing about their own shape forces serialization — it is purely the
  # shared `RateLimiter` dependency that does. Serial it stays.
  #
  # T7: both RateLimiter and MessageBufferSupervisor are now started by the
  # application supervision tree (application.ex), so they are already
  # running under their registered names by the time this suite boots.
  # `start_supervised!/1` for either would crash with
  # `{:already_started, pid}`. Tests exercise the already-running
  # application instances directly; per-test isolation still holds via
  # `unique_user/0` / `unique_conversation/0`.
  use ExUnit.Case, async: false

  alias Fullstack.JidoMarketAgents.MessageBuffer
  alias Fullstack.JidoMarketAgents.Conversation

  @debounce_ms Application.compile_env!(:fullstack, Fullstack.JidoMarketAgents)[:debounce_ms]

  defp unique_user, do: System.unique_integer([:positive])
  defp unique_conversation, do: System.unique_integer([:positive])

  # Registers a canned MIMO response and returns the exact user message
  # content MarketValidator will send, keyed to that content, mirroring the
  # stub harness in jido_market_agents_test.exs. Since MessageBuffer forwards
  # a merged "\n\n"-joined string as `message`, and MarketValidator sends
  # that exact string as the last user message's content to MIMO, matching
  # on the merged string itself is a direct, non-brittle proof of the join.
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

  describe "R6 - S6.1 messages inside the debounce window are joined into one batch" do
    test "three appends to the same conversation forward one \\n\\n-joined message", %{
      mimo_responses: responses
    } do
      user_id = unique_user()
      conversation_id = unique_conversation()
      merged = "first\n\nsecond\n\nthird"

      stub_mimo(responses, merged, "{}")
      Conversation.subscribe(conversation_id)

      assert {:ok, :buffered, ^conversation_id} =
               MessageBuffer.append(user_id, conversation_id, "first")

      assert {:ok, :buffered, ^conversation_id} =
               MessageBuffer.append(user_id, conversation_id, "second")

      assert {:ok, :buffered, ^conversation_id} =
               MessageBuffer.append(user_id, conversation_id, "third")

      assert_receive {:mimo_request, %{"messages" => mimo_messages}}, @debounce_ms + 500
      assert %{"content" => ^merged} = List.last(mimo_messages)
    end
  end

  describe "R6 - S6.2 the debounce timer resets on every new message" do
    test "flush happens debounce_ms after the LAST message, not the first", %{
      mimo_responses: responses
    } do
      user_id = unique_user()
      conversation_id = unique_conversation()

      # String messages so the flush actually reaches the LLM stub, which is
      # the only unambiguous "a flush happened" signal available. An earlier
      # version of this test refuted :rate_limited / :queued_during_cooldown
      # instead — but those only fire when the limiter DENIES, so under the
      # limit they never arrive and the refute passed even with a
      # non-resetting timer. Verified: that version still passed with the
      # Process.cancel_timer/1 reset removed.
      merged = "one\n\ntwo"
      stub_mimo(responses, merged, "{}")

      assert {:ok, :buffered, ^conversation_id} =
               MessageBuffer.append(user_id, conversation_id, "one")

      # Wait almost a full window, then send a second message. A
      # first-message-anchored timer would fire ~20ms from here; a correctly
      # resetting one is a fresh @debounce_ms away.
      Process.sleep(@debounce_ms - 20)

      assert {:ok, :buffered, ^conversation_id} =
               MessageBuffer.append(user_id, conversation_id, "two")

      # Strictly less than a full window after the second append. A broken
      # (non-resetting) implementation has already flushed by now.
      refute_receive {:mimo_request, _}, @debounce_ms - 20

      # And it does flush a full window after the LAST message, carrying both
      # messages merged — proving nothing was flushed early and lost.
      assert_receive {:mimo_request, %{"messages" => mimo_messages}}, @debounce_ms + 500
      assert List.last(mimo_messages)["content"] == merged
    end
  end

  describe "R6 - S6.3 two conversations in one window get separate, non-crossing batches" do
    test "each conversation's forwarded content contains only its own messages", %{
      mimo_responses: responses
    } do
      user_id = unique_user()
      conversation_a = unique_conversation()
      conversation_b = unique_conversation()

      merged_a = "a1\n\na2"
      merged_b = "b1"

      stub_mimo(responses, merged_a, "{}")
      stub_mimo(responses, merged_b, "{}")

      Conversation.subscribe(conversation_a)
      Conversation.subscribe(conversation_b)

      assert {:ok, :buffered, ^conversation_a} =
               MessageBuffer.append(user_id, conversation_a, "a1")

      assert {:ok, :buffered, ^conversation_b} =
               MessageBuffer.append(user_id, conversation_b, "b1")

      assert {:ok, :buffered, ^conversation_a} =
               MessageBuffer.append(user_id, conversation_a, "a2")

      assert_receive {:mimo_request, %{"messages" => msgs_1}}, @debounce_ms + 500
      assert_receive {:mimo_request, %{"messages" => msgs_2}}, 500

      contents = Enum.map([msgs_1, msgs_2], &Map.fetch!(List.last(&1), "content"))

      assert merged_a in contents
      assert merged_b in contents
      refute Enum.any?(contents, &(&1 =~ "b1" and &1 =~ "a1"))
    end
  end

  describe "R6 - S6.4 append returns {:ok, :buffered, id} immediately" do
    test "returns without waiting for the debounce window" do
      user_id = unique_user()
      conversation_id = unique_conversation()

      {elapsed_us, result} =
        :timer.tc(fn -> MessageBuffer.append(user_id, conversation_id, %{note: "x"}) end)

      assert result == {:ok, :buffered, conversation_id}
      elapsed_ms = div(elapsed_us, 1_000)

      assert elapsed_ms < @debounce_ms,
             "append took #{elapsed_ms}ms, expected < #{@debounce_ms}ms"
    end
  end

  describe "R6 - S6.5 {:buffered, ...} is broadcast on every append" do
    test "carries conversation_id, message_count for that conversation, and debounce_ms" do
      user_id = unique_user()
      conversation_id = unique_conversation()

      Conversation.subscribe(conversation_id)

      assert {:ok, :buffered, ^conversation_id} =
               MessageBuffer.append(user_id, conversation_id, %{note: "one"})

      assert_receive {:buffered,
                      %{conversation_id: ^conversation_id, message_count: 1, debounce_ms: ms}}

      assert ms == @debounce_ms

      assert {:ok, :buffered, ^conversation_id} =
               MessageBuffer.append(user_id, conversation_id, %{note: "two"})

      assert_receive {:buffered,
                      %{conversation_id: ^conversation_id, message_count: 2, debounce_ms: ^ms}}
    end
  end
end
