defmodule Fullstack.JidoMarketAgents.ConversationsSchemaTest do
  use Fullstack.DataCase, async: true

  import Fullstack.AccountsFixtures

  alias Fullstack.JidoMarketAgents.Conversations.Message
  alias Fullstack.JidoMarketAgents.Conversations.Record

  describe "Record persistence" do
    test "record persists business systems and tech result maps" do
      user = user_fixture()

      results = %{
        business_analysis: %{"recommended_offer" => "Service"},
        systems_strategy: %{"quarterly_focus" => "delivery"},
        tech_strategy: %{"diagnosis" => ["automation"]}
      }

      assert {:ok, record} =
               Repo.insert(Record.changeset(%Record{}, Map.put(results, :user_id, user.id)))

      reloaded = Repo.get!(Record, record.id)
      for {field, expected} <- results, do: assert(Map.get(reloaded, field) == expected)
      assert {:ok, empty} = Repo.insert(Record.changeset(%Record{}, %{user_id: user.id}))
      for field <- Map.keys(results), do: assert(is_nil(Map.get(empty, field)))
    end

    test "changeset accepts every run health value" do
      user = user_fixture()

      for status <- [:idle, :running, :error] do
        changeset = Record.changeset(%Record{}, %{user_id: user.id, status: status})
        assert changeset.valid?
        assert {:ok, record} = Repo.insert(changeset)
        assert Repo.get!(Record, record.id).status == status
      end

      assert Record.changeset(%Record{}, %{user_id: user.id, status: "running"}).changes.status ==
               :running
    end

    test "changeset rejects the retired lifecycle-shaped status values" do
      user = user_fixture()

      for status <- ~w(active researching analyzing building_strategy completed needs_data) do
        changeset = Record.changeset(%Record{}, %{user_id: user.id, status: status})
        refute changeset.valid?
        assert %{status: ["is invalid"]} = errors_on(changeset)
      end
    end

    test "a new record defaults to idle and the column is a native enum" do
      user = user_fixture()
      {:ok, record} = Repo.insert(Record.changeset(%Record{}, %{user_id: user.id}))

      assert record.status == :idle

      assert %{rows: [["conversation_status"]]} =
               Repo.query!(
                 "SELECT udt_name FROM information_schema.columns " <>
                   "WHERE table_name = 'jido_conversations' AND column_name = 'status'"
               )

      assert %{rows: [[["idle", "running", "error"]]]} =
               Repo.query!(
                 "SELECT array_agg(e::text ORDER BY e) FROM unnest(enum_range(NULL::conversation_status)) e"
               )
    end

    # S1.1
    test "a conversation created for a user has that user's user_id and inserted_at set" do
      user = user_fixture()

      {:ok, record} =
        %Record{}
        |> Record.changeset(%{user_id: user.id, status: "idle"})
        |> Repo.insert()

      assert record.user_id == user.id
      assert record.inserted_at
    end

    # S1.2
    test "deleting a user deletes their conversations and those conversations' messages" do
      user = user_fixture()

      {:ok, record} =
        %Record{}
        |> Record.changeset(%{user_id: user.id, status: "idle"})
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
        |> Record.changeset(%{user_id: user.id, status: "idle"})
        |> Repo.insert()

      {:ok, record2} =
        %Record{}
        |> Record.changeset(%{user_id: user.id, status: "idle"})
        |> Repo.insert()

      assert record1.id != record2.id
    end

    test "changeset rejects a missing user_id" do
      changeset = Record.changeset(%Record{}, %{status: "idle"})

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
