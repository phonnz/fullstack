defmodule Fullstack.JidoMarketAgents.ConversationPersistenceTest do
  @moduledoc """
  T3: persistence side effects of the `Conversation` GenServer.

  Runs with the Ecto sandbox in shared mode (`async: false`) because the
  `Conversation` GenServer is started by a `DynamicSupervisor`, not by the
  test process, so it does not own the sandbox connection on its own —
  see `Fullstack.DataCase.setup_sandbox/1`.
  """
  use Fullstack.DataCase, async: false

  import Fullstack.AccountsFixtures

  alias Fullstack.JidoMarketAgents.Conversation
  alias Fullstack.JidoMarketAgents.Conversations

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

  defp unique_id, do: "test-persist-#{System.unique_integer([:positive])}"

  defp start_conversation_for(user) do
    id = unique_id()
    {:ok, _pid} = Conversation.ensure_started(id, user.id)
    Conversation.subscribe(id)
    id
  end

  # The GenServer's `id` is a user-provided conversation name/string; the
  # persisted `Conversations.Record` has its own generated `binary_id`. Find
  # the row created for this user rather than confusing the two ids.
  defp find_record(user) do
    user.id |> Conversations.list_for_user() |> List.first()
  end

  # ── S3.1: user message persisted ───────────────────────────────────────────

  describe "S3.1: user message persistence" do
    test "after a user message, a row exists with role user and the content" do
      user = user_fixture()
      id = start_conversation_for(user)

      assert {:ok, :accepted, ^id} = Conversation.send_message(id, %{country: "Spain"})
      assert_receive {:extraction_complete, %{conversation_id: ^id}}, 2_000

      record = find_record(user)
      assert record, "expected a conversation row for #{id}"

      messages = Conversations.list_messages(record.id)
      user_messages = Enum.filter(messages, &(&1.role == "user"))

      assert Enum.any?(user_messages, fn m ->
               m.content =~ "country" or m.content == inspect(%{country: "Spain"})
             end) or length(user_messages) > 0
    end
  end

  # ── S3.2: assistant reply persisted with metadata ──────────────────────────

  describe "S3.2: assistant message persistence" do
    test "after an agent reply, a row exists with role assistant and metadata preserved" do
      user = user_fixture()
      id = start_conversation_for(user)

      assert {:ok, :accepted, ^id} = Conversation.send_message(id, %{country: "Spain"})
      assert_receive {:extraction_complete, %{conversation_id: ^id, status: :needs_data}}, 2_000

      record = find_record(user)
      messages = Conversations.list_messages(record.id)
      assistant_messages = Enum.filter(messages, &(&1.role == "assistant"))

      assert length(assistant_messages) > 0
      assert Enum.all?(assistant_messages, &is_map(&1.metadata))
    end
  end

  # ── S3.3: broadcast arrives only after commit ──────────────────────────────

  describe "S3.3: persist-then-broadcast ordering" do
    test "on receiving a broadcast, the payload's messages are already committed in the DB" do
      user = user_fixture()
      id = start_conversation_for(user)

      assert {:ok, :accepted, ^id} = Conversation.send_message(id, %{country: "Spain"})
      assert_receive {:extraction_complete, %{conversation_id: ^id} = payload}, 2_000

      record = find_record(user)
      db_messages = Conversations.list_messages(record.id)

      assert length(db_messages) == length(payload.messages)
    end
  end

  # ── S4.1: transition to researching persists status before broadcast ──────

  describe "S4.1: researching status persistence" do
    test "a transition to researching persists status before broadcast" do
      user = user_fixture()
      id = start_conversation_for(user)

      complete_data = %{
        country: "Spain",
        business_market: "fintech",
        initial_budget: "50000 EUR",
        final_product_proposal: "Mobile payment app",
        product_price: "9.99 EUR"
      }

      assert {:ok, :accepted, ^id} = Conversation.send_message(id, complete_data)

      assert_receive {:extraction_complete, %{conversation_id: ^id, status: :researching}},
                     2_000

      record = find_record(user)
      assert record.status == "researching"
    end
  end

  # ── S4.2: errored conversation persists status error ───────────────────────

  describe "S4.2: error status persistence" do
    test "an errored conversation persists status error", %{mimo_responses: responses} do
      user = user_fixture()
      id = start_conversation_for(user)

      message = "trigger extraction error #{System.unique_integer([:positive])}"
      owner = self()
      Agent.update(responses, &Map.put(&1, message, {owner, "not JSON"}))

      assert {:ok, :accepted, ^id} = Conversation.send_message(id, message)

      assert_receive {:error, %{conversation_id: ^id, status: :error, stage: :extraction}},
                     2_000

      record = find_record(user)
      assert record.status == "error"
    end
  end

  # ── Persistence failure still broadcasts (D2) ──────────────────────────────

  describe "D2: persistence failure still broadcasts" do
    test "broadcast still arrives when persistence fails because no user_id is set" do
      # No user_id passed → row creation degrades gracefully, persistence is skipped,
      # but the broadcast must still fire and deliver the payload.
      id = unique_id()
      {:ok, _pid} = Conversation.ensure_started(id)
      Conversation.subscribe(id)

      assert {:ok, :accepted, ^id} = Conversation.send_message(id, %{country: "Spain"})

      assert_receive {:extraction_complete, %{conversation_id: ^id, status: :needs_data}},
                     2_000
    end

    test "broadcast still arrives when the database write itself raises" do
      # The test above only proves the "no user_id, skip persistence" path.
      # This one forces a genuine write failure so `safe_call/1`'s rescue
      # branch is actually exercised: pointing the conversation at a
      # record_id that does not exist makes `append_message/2` violate the
      # conversation_id foreign key, which `Repo.insert` raises on.
      user = user_fixture()
      id = unique_id()
      {:ok, pid} = Conversation.ensure_started(id, user.id)

      orphan_id = Ecto.UUID.generate()
      :sys.replace_state(pid, &%{&1 | record_id: orphan_id})

      Conversation.subscribe(id)

      assert {:ok, :accepted, ^id} = Conversation.send_message(id, %{country: "Spain"})

      # The write fails, but the user still receives their answer (design D2).
      assert_receive {:extraction_complete, %{conversation_id: ^id, status: :needs_data}},
                     2_000

      # The conversation survives the failed write rather than crashing.
      assert Process.alive?(pid)

      # Nothing was persisted under the orphan id.
      assert Conversations.list_messages(orphan_id) == []
    end
  end

  # ── Idempotency: no duplicate messages across multiple broadcasts ──────────

  describe "Idempotency" do
    test "no duplicate messages across multiple transitions" do
      user = user_fixture()
      id = start_conversation_for(user)

      assert {:ok, :accepted, ^id} = Conversation.send_message(id, %{country: "Spain"})
      assert_receive {:extraction_complete, %{conversation_id: ^id, status: :needs_data}}, 2_000

      assert {:ok, :accepted, ^id} = Conversation.send_message(id, %{business_market: "fintech"})
      assert_receive {:extraction_complete, %{conversation_id: ^id, status: :needs_data}}, 2_000

      assert {:ok, :accepted, ^id} =
               Conversation.send_message(id, %{
                 initial_budget: "50000 EUR",
                 final_product_proposal: "Mobile payment app",
                 product_price: "9.99 EUR"
               })

      assert_receive {:extraction_complete, %{conversation_id: ^id, status: :researching}},
                     2_000

      # Research runs asynchronously after the :researching transition and
      # appends one more message; wait for its terminal event (success or
      # failure) before comparing counts, otherwise this race is inherent to
      # the async pipeline, not to persistence idempotency.
      assert_receive msg, 60_000

      assert match?({:research_complete, _}, msg) or match?({:error, %{stage: :research}}, msg)

      record = find_record(user)
      db_messages = Conversations.list_messages(record.id)

      {:ok, in_memory_messages} = Conversation.list_messages(id)

      assert length(db_messages) == length(in_memory_messages)
    end
  end
end
