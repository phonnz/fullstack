defmodule Fullstack.JidoMarketAgents.ConversationStartTest do
  use Fullstack.DataCase, async: false

  import Fullstack.AccountsFixtures

  alias Fullstack.JidoMarketAgents.{Conversation, Conversations}
  alias Fullstack.JidoMarketAgents.ConversationSupervisor
  alias Fullstack.JidoMarketAgents.Conversations.Record

  @registry Fullstack.JidoMarketAgents.ConversationRegistry

  defp cleanup_runtime(id) do
    on_exit(fn ->
      for {pid, _} <- Registry.lookup(@registry, id) do
        DynamicSupervisor.terminate_child(ConversationSupervisor, pid)
      end
    end)
  end

  test "creates an owned record and runtime when no conversation id is supplied" do
    user = user_fixture()

    assert {:ok, %Record{} = record} =
             Conversations.start_conversation(user.id)

    cleanup_runtime(record.id)
    assert record.user_id == user.id
    assert record.title == nil
    assert [record] == Conversations.list_for_user(user.id)
    assert [{pid, _}] = Registry.lookup(@registry, record.id)
    assert :sys.get_state(pid).user_id == user.id
  end

  test "rejects invalid user ids without creating conversations" do
    for user_id <- [nil, 1, :user, "", "not-a-uuid", "abcdefghijklmnop"] do
      assert {:error, :invalid_user_id} = Conversations.start_conversation(user_id)
    end

    assert Repo.aggregate(Record, :count) == 0
  end

  test "preserves create foreign-key validation for an unknown user" do
    assert {:error, %Ecto.Changeset{}} =
             Conversations.start_conversation(Ecto.UUID.generate())
  end

  test "rejects invalid conversation ids before querying or starting a runtime" do
    user = user_fixture()

    for id <- [1, :conversation, "", "not-a-uuid", "abcdefghijklmnop"] do
      assert {:error, :invalid_conversation_id} =
               Conversations.start_conversation(user.id, id)

      assert Registry.lookup(@registry, id) == []
    end

    assert Conversations.list_for_user(user.id) == []
  end

  test "missing and foreign-owned conversations return the same error" do
    owner = user_fixture()
    stranger = user_fixture()
    {:ok, record} = Conversations.create(owner.id)
    {:ok, _message} = Conversations.append_message(record.id, %{role: "user", content: "private"})
    missing_id = Ecto.UUID.generate()

    assert {:error, :not_found} = Conversations.start_conversation(stranger.id, record.id)
    assert {:error, :not_found} = Conversations.start_conversation(stranger.id, missing_id)
    assert Registry.lookup(@registry, record.id) == []
    assert Registry.lookup(@registry, missing_id) == []
  end

  test "reuses the owned active runtime and preserves persisted history" do
    user = user_fixture()
    {:ok, record} = Conversations.create(user.id)
    {:ok, pid} = Conversation.ensure_started(record.id, user.id)
    cleanup_runtime(record.id)
    {:ok, message} = Conversations.append_message(record.id, %{role: "user", content: "history"})

    assert {:ok, ^record} =
             Conversations.start_conversation(String.upcase(user.id), String.upcase(record.id))

    assert Conversations.list_messages(record.id) == [message]
    assert [{^pid, _}] = Registry.lookup(@registry, record.id)
  end

  test "rehydrates owned history after a runtime has stopped, for every persisted status" do
    user = user_fixture()

    for status <- ~w(active researching completed error) do
      {:ok, record} = Conversations.create(user.id, %{status: status})
      {:ok, message} = Conversations.append_message(record.id, %{role: "user", content: status})
      {:ok, old_pid} = Conversation.ensure_started(record.id, user.id)
      :ok = DynamicSupervisor.terminate_child(ConversationSupervisor, old_pid)
      cleanup_runtime(record.id)

      assert {:ok, ^record} =
               Conversations.start_conversation(user.id, record.id)

      assert Conversations.list_messages(record.id) == [message]
      assert [{new_pid, _}] = Registry.lookup(@registry, record.id)
      refute new_pid == old_pid
      assert {:ok, restored_status, [%{content: ^status}]} = Conversation.resume(record.id)
      assert Atom.to_string(restored_status) == status
    end
  end

  test "concurrent reopen requests reuse one runtime" do
    user = user_fixture()
    {:ok, record} = Conversations.create(user.id)
    cleanup_runtime(record.id)

    tasks =
      for _ <- 1..5,
          do: Task.async(fn -> Conversations.start_conversation(user.id, record.id) end)

    for task <- tasks, do: assert({:ok, ^record} = Task.await(task))
    assert [{pid, _}] = Registry.lookup(@registry, record.id)
    assert Process.alive?(pid)
  end

  test "returns a tagged startup error when the runtime supervisor is unavailable" do
    user = user_fixture()
    {:ok, record} = Conversations.create(user.id)
    :ok = Supervisor.terminate_child(Fullstack.Supervisor, ConversationSupervisor)

    try do
      assert {:error, {:conversation_start_failed, _reason}} =
               Conversations.start_conversation(user.id, record.id)
    after
      assert {:ok, _pid} = Supervisor.restart_child(Fullstack.Supervisor, ConversationSupervisor)
    end
  end
end
