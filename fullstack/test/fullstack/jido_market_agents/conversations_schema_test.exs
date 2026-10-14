defmodule Fullstack.JidoMarketAgents.ConversationsSchemaTest do
  use Fullstack.DataCase, async: true

  import Fullstack.AccountsFixtures

  alias Fullstack.JidoMarketAgents.Conversations.Message
  alias Fullstack.JidoMarketAgents.Conversations.Record

  describe "Record persistence" do
    test "changeset accepts analyzing and building_strategy" do
      user = user_fixture()

      for status <- ["analyzing", "building_strategy"] do
        changeset = Record.changeset(%Record{}, %{user_id: user.id, status: status})
        assert changeset.valid?
        assert {:ok, record} = Repo.insert(changeset)
        assert Repo.get!(Record, record.id).status == status
      end

      refute Record.changeset(%Record{}, %{user_id: user.id, status: "needs_data"}).valid?
    end

    # S1.1
    test "a conversation created for a user has that user's user_id and inserted_at set" do
      user = user_fixture()

      {:ok, record} =
        %Record{}
        |> Record.changeset(%{user_id: user.id, status: "active"})
        |> Repo.insert()

      assert record.user_id == user.id
      assert record.inserted_at
    end

    # S1.2
    test "deleting a user deletes their conversations and those conversations' messages" do
      user = user_fixture()

      {:ok, record} =
        %Record{}
        |> Record.changeset(%{user_id: user.id, status: "active"})
        |> Repo.insert()

      {:ok, message} =
        %Message{}
        |> Message.changeset(%{conversation_id: record.id, role: "user", content: "hello"})
        |> Repo.insert()

      Repo.delete!(user)

      assert Repo.get(Record, record.id) == nil
      assert Repo.get(Message, message.id) == nil
    end

    # S2.1
    test "two conversations created for the same user get distinct ids" do
      user = user_fixture()

      {:ok, record1} =
        %Record{}
        |> Record.changeset(%{user_id: user.id, status: "active"})
        |> Repo.insert()

      {:ok, record2} =
        %Record{}
        |> Record.changeset(%{user_id: user.id, status: "active"})
        |> Repo.insert()

      assert record1.id != record2.id
    end

    test "changeset rejects a missing user_id" do
      changeset = Record.changeset(%Record{}, %{status: "active"})

      refute changeset.valid?
      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset rejects an invalid status" do
      user = user_fixture()
      changeset = Record.changeset(%Record{}, %{user_id: user.id, status: "bogus"})

      refute changeset.valid?
      assert %{status: [_ | _]} = errors_on(changeset)
    end
  end

  describe "Message changeset" do
    test "rejects an invalid role" do
      changeset =
        Message.changeset(%Message{}, %{
          conversation_id: Ecto.UUID.generate(),
          role: "system",
          content: "hello"
        })

      refute changeset.valid?
      assert %{role: [_ | _]} = errors_on(changeset)
    end

    test "requires content" do
      changeset =
        Message.changeset(%Message{}, %{
          conversation_id: Ecto.UUID.generate(),
          role: "user"
        })

      refute changeset.valid?
      assert %{content: ["can't be blank"]} = errors_on(changeset)
    end
  end
end
