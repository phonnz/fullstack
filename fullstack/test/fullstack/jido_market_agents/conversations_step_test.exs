defmodule Fullstack.JidoMarketAgents.ConversationsStepTest do
  use Fullstack.DataCase, async: false
  import Fullstack.AccountsFixtures

  alias Fullstack.JidoMarketAgents.{Conversation, Conversations}
  alias Fullstack.JidoMarketAgents.Conversations.Step

  test "open/3 with nil creates an owned idle manual session token" do
    user = user_fixture()
    assert {:ok, session} = Step.open(user.id, nil, [])
    assert session.user_id == user.id
    assert session.mode == :manual
    assert is_pid(session.pid) and Process.alive?(session.pid)
    assert is_pid(session.observer) and session.observer != self()
    assert is_reference(session.monitor_ref)
    assert is_reference(session.lease_ref)
    assert {:ok, _} = Ecto.UUID.cast(session.run_ref)
    assert session.topic == Conversation.topic(session.conversation_id)
    assert session.stage_versions == %{}
    assert [record] = Conversations.list_for_user(user.id)
    assert record.id == session.conversation_id
    assert record.status == "active"
    assert record.validated_data["_pipeline"]["run_ref"] == session.run_ref
    refute inspect(record.validated_data) =~ "#Reference"
    state = :sys.get_state(session.pid)
    assert state.user_id == user.id
    assert state.mode == :manual
    assert state.task == nil and state.queue == []
    assert Conversations.list_messages(record.id) == []
    stop_runtime(session)
  end

  test "open/3 returns not_found for missing and foreign-owned ids without leakage" do
    user = user_fixture()
    other = user_fixture()
    {:ok, foreign} = Conversations.create(other.id)
    {:ok, owned} = Conversations.create(user.id)
    missing = Ecto.UUID.generate()

    for id <- [missing, foreign.id, "not-a-uuid"] do
      assert {:error, :not_found} = Step.open(user.id, id, [])
      assert Registry.lookup(Fullstack.JidoMarketAgents.ConversationRegistry, id) == []
    end

    assert {:ok, session} = Step.open(user.id, owned.id, [])
    assert session.conversation_id == owned.id
    assert :sys.get_state(session.pid).user_id == user.id
    assert length(Conversations.list_for_user(user.id)) == 1
    stop_runtime(session)
  end

  defp stop_runtime(session) do
    if Process.alive?(session.observer), do: GenServer.stop(session.observer)

    if Process.alive?(session.pid),
      do:
        DynamicSupervisor.terminate_child(
          Fullstack.JidoMarketAgents.ConversationSupervisor,
          session.pid
        )
  end
end
