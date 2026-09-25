defmodule Fullstack.JidoMarketAgents.ConversationsTest do
  use Fullstack.DataCase, async: true

  import Fullstack.AccountsFixtures

  alias Fullstack.JidoMarketAgents.Conversations
  alias Fullstack.JidoMarketAgents.Conversations.Record

  # `timestamps()` on these schemas has second granularity, so rows created
  # back-to-back in the same test can share an `inserted_at`. Force distinct,
  # explicit timestamps rather than sleeping, so ordering assertions are real.
  defp force_inserted_at(%Record{id: id} = record, naive_datetime) do
    naive_datetime = NaiveDateTime.truncate(naive_datetime, :second)

    {1, _} =
      Repo.update_all(
        from(r in Record, where: r.id == ^id),
        set: [inserted_at: naive_datetime]
      )

    %{record | inserted_at: naive_datetime}
  end

  defp force_message_inserted_at(message, naive_datetime) do
    naive_datetime = NaiveDateTime.truncate(naive_datetime, :second)

    {1, _} =
      Repo.update_all(
        from(m in Fullstack.JidoMarketAgents.Conversations.Message,
          where: m.id == ^message.id
        ),
        set: [inserted_at: naive_datetime]
      )

    %{message | inserted_at: naive_datetime}
  end

  describe "get_for_user/2" do
    test "S1.3: returns nil for a conversation owned by a different user" do
      owner = user_fixture()
      stranger = user_fixture()

      {:ok, record} = Conversations.create(owner.id)

      assert Conversations.get_for_user(record.id, stranger.id) == nil
    end

    test "returns the record when the user owns it" do
      user = user_fixture()
      {:ok, record} = Conversations.create(user.id)

      assert %Record{id: id} = Conversations.get_for_user(record.id, user.id)
      assert id == record.id
    end

    test "returns nil for a non-existent id" do
      user = user_fixture()

      assert Conversations.get_for_user(Ecto.UUID.generate(), user.id) == nil
    end
  end

  describe "list_for_user/1" do
    test "returns only that user's conversations" do
      user_a = user_fixture()
      user_b = user_fixture()

      {:ok, record_a} = Conversations.create(user_a.id)
      {:ok, _record_b} = Conversations.create(user_b.id)

      result = Conversations.list_for_user(user_a.id)

      assert [%Record{id: id}] = result
      assert id == record_a.id
    end

    test "orders newest first by inserted_at" do
      user = user_fixture()

      {:ok, oldest} = Conversations.create(user.id)
      {:ok, middle} = Conversations.create(user.id)
      {:ok, newest} = Conversations.create(user.id)

      now = NaiveDateTime.utc_now()
      oldest = force_inserted_at(oldest, NaiveDateTime.add(now, -20, :second))
      middle = force_inserted_at(middle, NaiveDateTime.add(now, -10, :second))
      newest = force_inserted_at(newest, now)

      assert Conversations.list_for_user(user.id) |> Enum.map(& &1.id) ==
               [newest.id, middle.id, oldest.id]
    end
  end

  describe "create/2" do
    test "returns {:ok, record} for a valid user_id" do
      user = user_fixture()

      assert {:ok, %Record{} = record} = Conversations.create(user.id)
      assert record.user_id == user.id
      assert record.inserted_at
    end

    test "returns {:error, changeset} for an invalid user_id rather than raising" do
      assert {:error, %Ecto.Changeset{}} = Conversations.create(nil)
    end

    test "returns {:error, changeset} for a user_id that does not reference an existing user" do
      assert {:error, %Ecto.Changeset{}} = Conversations.create(Ecto.UUID.generate())
    end
  end

  describe "append_message/2" do
    test "persists role, content and metadata" do
      user = user_fixture()
      {:ok, record} = Conversations.create(user.id)

      attrs = %{
        conversation_id: record.id,
        role: "assistant",
        content: "hello there",
        metadata: %{"model" => "test"}
      }

      assert {:ok, message} = Conversations.append_message(record.id, attrs)
      assert message.role == "assistant"
      assert message.content == "hello there"
      assert message.metadata == %{"model" => "test"}
      assert message.conversation_id == record.id
    end

    test "returns an error changeset for an invalid role" do
      user = user_fixture()
      {:ok, record} = Conversations.create(user.id)

      attrs = %{role: "invalid", content: "hi"}

      assert {:error, %Ecto.Changeset{}} = Conversations.append_message(record.id, attrs)
    end
  end

  describe "list_messages/1" do
    test "S3.4: orders messages by inserted_at ascending" do
      user = user_fixture()
      {:ok, record} = Conversations.create(user.id)

      {:ok, first} =
        Conversations.append_message(record.id, %{role: "user", content: "first"})

      {:ok, second} =
        Conversations.append_message(record.id, %{role: "assistant", content: "second"})

      {:ok, third} =
        Conversations.append_message(record.id, %{role: "user", content: "third"})

      now = NaiveDateTime.utc_now()
      force_message_inserted_at(first, NaiveDateTime.add(now, -20, :second))
      force_message_inserted_at(second, NaiveDateTime.add(now, -10, :second))
      force_message_inserted_at(third, now)

      assert Conversations.list_messages(record.id) |> Enum.map(& &1.content) ==
               ["first", "second", "third"]
    end

    test "returns an empty list for a conversation with no messages" do
      user = user_fixture()
      {:ok, record} = Conversations.create(user.id)

      assert Conversations.list_messages(record.id) == []
    end
  end

  describe "update_state/2" do
    test "persists status and validated_data" do
      user = user_fixture()
      {:ok, record} = Conversations.create(user.id)

      attrs = %{status: "researching", validated_data: %{"industry" => "coffee"}}

      assert {:ok, updated} = Conversations.update_state(record, attrs)
      assert updated.status == "researching"
      assert updated.validated_data == %{"industry" => "coffee"}

      reloaded = Conversations.get_for_user(record.id, user.id)
      assert reloaded.status == "researching"
      assert reloaded.validated_data == %{"industry" => "coffee"}
    end

    test "returns an error changeset for an invalid status" do
      user = user_fixture()
      {:ok, record} = Conversations.create(user.id)

      assert {:error, %Ecto.Changeset{}} =
               Conversations.update_state(record, %{status: "not_a_real_status"})
    end
  end
end
