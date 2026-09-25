defmodule Fullstack.JidoMarketAgents.RateLimiterTest do
  # The RateLimiter is a single named GenServer (design D6), so every test in this
  # file shares one process and its ETS table. Tests must run serially.
  use ExUnit.Case, async: false

  alias Fullstack.JidoMarketAgents.RateLimiter
  alias Fullstack.JidoMarketAgents.Conversation

  @window_ms Application.compile_env!(:fullstack, Fullstack.JidoMarketAgents)[
               :rate_limit_window_ms
             ]
  @count_limit Application.compile_env!(:fullstack, Fullstack.JidoMarketAgents)[
                 :rate_limit_count
               ]
  @cooldown_ms Application.compile_env!(:fullstack, Fullstack.JidoMarketAgents)[:cooldown_ms]

  setup do
    start_supervised!(RateLimiter)
    :ok
  end

  defp unique_user, do: System.unique_integer([:positive])
  defp unique_conversation, do: System.unique_integer([:positive])

  describe "R7 - per-user rate limiting" do
    test "S7.1 batches under the limit are allowed and recorded" do
      user_id = unique_user()
      conversation_id = unique_conversation()
      Conversation.subscribe(conversation_id)

      assert RateLimiter.check_and_process(user_id, conversation_id, "hello") == :allow
      assert RateLimiter.user_status(user_id) == :active
      refute_receive {:rate_limited, _}, 50
    end

    test "S7.2 the batch over the limit is denied and broadcasts {:rate_limited, ...} with retry_at" do
      user_id = unique_user()

      for _ <- 1..@count_limit do
        conversation_id = unique_conversation()
        assert RateLimiter.check_and_process(user_id, conversation_id, "msg") == :allow
      end

      over_limit_conversation = unique_conversation()
      Conversation.subscribe(over_limit_conversation)

      assert RateLimiter.check_and_process(user_id, over_limit_conversation, "one too many") ==
               :deny

      assert_receive {:rate_limited, payload}
      assert payload.conversation_id == over_limit_conversation
      assert %DateTime{} = payload.retry_at
      assert DateTime.compare(payload.retry_at, DateTime.utc_now()) == :gt
      assert is_binary(payload.message)
    end

    test "S7.3 entries older than the window are pruned - the window slides" do
      user_id = unique_user()
      old_conversation = unique_conversation()

      assert RateLimiter.check_and_process(user_id, old_conversation, "old") == :allow

      # Let the single old entry fall outside the sliding window.
      Process.sleep(@window_ms + 50)

      # Fill the limit with fresh entries. If the old entry still counted, the
      # limit-th fresh batch here would already be denied.
      for _ <- 1..@count_limit do
        conversation_id = unique_conversation()
        assert RateLimiter.check_and_process(user_id, conversation_id, "fresh") == :allow
      end

      assert RateLimiter.user_status(user_id) == :active
    end

    test "S7.4 two users are counted independently" do
      user_a = unique_user()
      user_b = unique_user()

      for _ <- 1..@count_limit do
        assert RateLimiter.check_and_process(user_a, unique_conversation(), "a") == :allow
      end

      # user_a is now at the limit; user_b, a different user, is still fresh.
      assert RateLimiter.check_and_process(user_a, unique_conversation(), "a again") == :deny
      assert RateLimiter.check_and_process(user_b, unique_conversation(), "b") == :allow
      assert RateLimiter.user_status(user_a) == :cooldown
      assert RateLimiter.user_status(user_b) == :active
    end
  end

  describe "R8 - map input bypasses the limiter" do
    test "S8.1 map input consumes no rate-limit entry" do
      user_id = unique_user()
      map_message = %{business_name: "Acme"}

      # Consume the whole limit with map inputs; a subsequent plain-text batch
      # must still be allowed because none of the map inputs recorded an entry.
      for _ <- 1..(@count_limit * 2) do
        assert RateLimiter.check_and_process(user_id, unique_conversation(), map_message) ==
                 :allow
      end

      assert RateLimiter.check_and_process(user_id, unique_conversation(), "text") == :allow
      assert RateLimiter.user_status(user_id) == :active
    end

    test "S8.2 map input is processed immediately during cooldown, not queued" do
      user_id = unique_user()

      for _ <- 1..@count_limit do
        assert RateLimiter.check_and_process(user_id, unique_conversation(), "msg") == :allow
      end

      # Push the user into cooldown.
      assert RateLimiter.check_and_process(user_id, unique_conversation(), "over") == :deny
      assert RateLimiter.user_status(user_id) == :cooldown

      map_conversation = unique_conversation()
      Conversation.subscribe(map_conversation)

      assert RateLimiter.check_and_process(
               user_id,
               map_conversation,
               %{business_name: "Acme"}
             ) == :allow

      refute_receive {:queued_during_cooldown, _}, 50
    end
  end

  describe "R9 - cooldown queues rather than drops" do
    test "S9.1 a denied batch is queued and one cooldown timer starts" do
      user_id = unique_user()

      for _ <- 1..@count_limit do
        assert RateLimiter.check_and_process(user_id, unique_conversation(), "msg") == :allow
      end

      conversation_id = unique_conversation()
      Conversation.subscribe(conversation_id)

      assert RateLimiter.check_and_process(user_id, conversation_id, "queued") == :deny
      assert_receive {:rate_limited, _}
      assert RateLimiter.user_status(user_id) == :cooldown
    end

    test "S9.2 further batches during cooldown queue and broadcast {:queued_during_cooldown, ...}" do
      user_id = unique_user()

      for _ <- 1..@count_limit do
        assert RateLimiter.check_and_process(user_id, unique_conversation(), "msg") == :allow
      end

      # First denial enters cooldown.
      assert RateLimiter.check_and_process(user_id, unique_conversation(), "first over") ==
               :deny

      conversation_id = unique_conversation()
      Conversation.subscribe(conversation_id)

      assert RateLimiter.check_and_process(user_id, conversation_id, "queued too") == :queued
      assert_receive {:queued_during_cooldown, %{conversation_id: ^conversation_id}}
    end

    test "S9.3 on expiry, queued batches forward in order received" do
      user_id = unique_user()

      for _ <- 1..@count_limit do
        assert RateLimiter.check_and_process(user_id, unique_conversation(), "msg") == :allow
      end

      first_conversation = unique_conversation()
      second_conversation = unique_conversation()

      # Both of these get queued: the first triggers the cooldown timer, the
      # second queues behind it while cooldown is already active.
      assert RateLimiter.check_and_process(user_id, first_conversation, "first queued") ==
               :deny

      assert RateLimiter.check_and_process(user_id, second_conversation, "second queued") ==
               :queued

      Conversation.subscribe(first_conversation)
      Conversation.subscribe(second_conversation)

      assert_receive {:cooldown_complete, %{conversation_id: ^first_conversation}},
                     @cooldown_ms + 500

      assert_receive {:cooldown_complete, %{conversation_id: ^second_conversation}}, 500
    end

    test "S9.4 after expiry the user returns to :active and new batches are admitted" do
      user_id = unique_user()

      for _ <- 1..@count_limit do
        assert RateLimiter.check_and_process(user_id, unique_conversation(), "msg") == :allow
      end

      queued_conversation = unique_conversation()
      Conversation.subscribe(queued_conversation)

      assert RateLimiter.check_and_process(user_id, queued_conversation, "queued") == :deny

      assert_receive {:cooldown_complete, %{conversation_id: ^queued_conversation}},
                     @cooldown_ms + 500

      assert RateLimiter.user_status(user_id) == :active

      new_conversation = unique_conversation()
      assert RateLimiter.check_and_process(user_id, new_conversation, "fresh again") == :allow
    end
  end
end
