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

  # Counts the Repo queries `fun` issues, via telemetry, so an N+1 claim is
  # measured rather than assumed.
  defp count_queries(fun) do
    handler_id = {__MODULE__, :query_counter, System.unique_integer()}
    counter = :counters.new(1, [])

    :ok =
      :telemetry.attach(
        handler_id,
        [:fullstack, :repo, :query],
        fn _event, _measurements, _metadata, _config -> :counters.add(counter, 1, 1) end,
        nil
      )

    try do
      result = fun.()
      {:counters.get(counter, 1), result}
    after
      :telemetry.detach(handler_id)
    end
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

  describe "list_all/1" do
    test "returns conversations across every user, newest first" do
      user_a = user_fixture()
      user_b = user_fixture()

      {:ok, oldest} = Conversations.create(user_a.id)
      {:ok, newest} = Conversations.create(user_b.id)

      now = NaiveDateTime.utc_now()
      oldest = force_inserted_at(oldest, NaiveDateTime.add(now, -20, :second))
      newest = force_inserted_at(newest, now)

      assert Conversations.list_all() |> Enum.map(& &1.id) == [newest.id, oldest.id]
    end

    test "preloads the owning user" do
      user = user_fixture()
      {:ok, _record} = Conversations.create(user.id)

      assert [record] = Conversations.list_all()
      assert record.user.id == user.id
      assert record.user.email == user.email
    end

    test "includes a message count" do
      user = user_fixture()
      {:ok, with_messages} = Conversations.create(user.id)
      {:ok, without} = Conversations.create(user.id)

      {:ok, _} = Conversations.append_message(with_messages.id, %{role: "user", content: "hi"})

      {:ok, _} =
        Conversations.append_message(with_messages.id, %{role: "assistant", content: "hello"})

      counts =
        Conversations.list_all()
        |> Map.new(&{&1.id, &1.message_count})

      assert counts[with_messages.id] == 2
      assert counts[without.id] == 0
    end

    test "returns an empty list when there are no conversations" do
      assert Conversations.list_all() == []
    end

    test "honours :limit and :offset" do
      user = user_fixture()
      {:ok, a} = Conversations.create(user.id)
      {:ok, b} = Conversations.create(user.id)
      {:ok, c} = Conversations.create(user.id)

      now = NaiveDateTime.utc_now()
      a = force_inserted_at(a, NaiveDateTime.add(now, -30, :second))
      b = force_inserted_at(b, NaiveDateTime.add(now, -20, :second))
      c = force_inserted_at(c, NaiveDateTime.add(now, -10, :second))

      assert Conversations.list_all(limit: 2) |> Enum.map(& &1.id) == [c.id, b.id]
      assert Conversations.list_all(limit: 2, offset: 2) |> Enum.map(& &1.id) == [a.id]
    end

    test "issues a bounded number of queries regardless of row count" do
      user = user_fixture()

      for _ <- 1..5 do
        {:ok, record} = Conversations.create(user.id)
        {:ok, _} = Conversations.append_message(record.id, %{role: "user", content: "hi"})
      end

      # A per-row preload or count would scale with the number of rows; the
      # aggregate must stay flat. One query for the rows (with the join) plus
      # at most one for the user preload.
      {queries, records} = count_queries(fn -> Conversations.list_all() end)

      assert length(records) == 5
      assert queries <= 2, "expected at most 2 queries, observed #{queries}"
    end
  end

  describe "get_any/1" do
    test "returns a conversation regardless of owner" do
      owner = user_fixture()
      {:ok, record} = Conversations.create(owner.id)

      assert found = Conversations.get_any(record.id)
      assert found.id == record.id
      assert found.user.id == owner.id
    end

    test "returns nil for an unknown id" do
      assert Conversations.get_any(Ecto.UUID.generate()) == nil
    end
  end

  describe "ownership enforcement is unchanged by the admin readers" do
    test "get_for_user/2 still filters on the owner" do
      owner = user_fixture()
      other = user_fixture()
      {:ok, record} = Conversations.create(owner.id)

      assert Conversations.get_for_user(record.id, owner.id)
      refute Conversations.get_for_user(record.id, other.id)
    end

    test "list_for_user/1 still filters on the owner" do
      owner = user_fixture()
      other = user_fixture()
      {:ok, _record} = Conversations.create(owner.id)

      assert length(Conversations.list_for_user(owner.id)) == 1
      assert Conversations.list_for_user(other.id) == []
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
