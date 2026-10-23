defmodule FullstackWeb.EvaluationLiveTest do
  use FullstackWeb.ConnCase

  import Phoenix.LiveViewTest
  import Fullstack.AccountsFixtures
  import Ecto.Query, only: [from: 2]

  alias Fullstack.JidoMarketAgents.Conversations

  defp admin_conn(%{conn: conn}) do
    %{conn: log_in_user(conn, admin_fixture())}
  end

  describe "Index authorization" do
    test "an authenticated non-admin gets a 404", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())

      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/evaluations") end
    end

    test "a :staff user gets a 404", %{conn: conn} do
      conn = log_in_user(conn, user_fixture(role: :staff))

      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/evaluations") end
    end

    test "an anonymous visitor is redirected to log in", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/evaluations")
      assert path == ~p"/users/log_in"
    end
  end

  describe "Index" do
    setup :admin_conn

    test "lists conversations from every user", %{conn: conn} do
      user_a = user_fixture(email: "owner-a@example.com")
      user_b = user_fixture(email: "owner-b@example.com")

      {:ok, _a} = Conversations.create(user_a.id, %{title: "Spain fintech"})
      {:ok, _b} = Conversations.create(user_b.id, %{title: "Berlin logistics"})

      {:ok, _lv, html} = live(conn, ~p"/evaluations")

      assert html =~ "owner-a@example.com"
      assert html =~ "owner-b@example.com"
      assert html =~ "Spain fintech"
      assert html =~ "Berlin logistics"
    end

    test "shows the status and message count", %{conn: conn} do
      user = user_fixture()
      {:ok, record} = Conversations.create(user.id, %{status: "running"})
      {:ok, _} = Conversations.append_message(record.id, %{role: "user", content: "hi"})

      {:ok, _lv, html} = live(conn, ~p"/evaluations")

      assert html =~ "inserted"
      assert html =~ "running"
      assert html =~ "1"
    end

    test "renders a placeholder for a conversation without a title", %{conn: conn} do
      user = user_fixture()
      {:ok, _record} = Conversations.create(user.id)

      {:ok, _lv, html} = live(conn, ~p"/evaluations")

      # `title` is nullable, so the cell must not render "nil".
      refute html =~ "nil"
      assert html =~ "—"
    end

    test "shows an empty state when there are no conversations", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/evaluations")

      assert html =~ "No evaluations yet"
    end

    test "a row navigates to the detail view", %{conn: conn} do
      user = user_fixture()
      {:ok, record} = Conversations.create(user.id, %{title: "Clickable"})

      {:ok, lv, _html} = live(conn, ~p"/evaluations")

      assert lv |> element("#evaluation-#{record.id}") |> render_click()
      assert_redirect(lv, ~p"/evaluations/#{record.id}")
    end
  end

  describe "Show authorization" do
    setup do
      user = user_fixture()
      {:ok, record} = Conversations.create(user.id)
      %{record: record}
    end

    test "an authenticated non-admin gets a 404", %{conn: conn, record: record} do
      conn = log_in_user(conn, user_fixture())

      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/evaluations/#{record.id}") end
    end

    test "the owner themselves is not an admin and gets a 404", %{conn: conn, record: record} do
      owner = Fullstack.Repo.get!(Fullstack.Accounts.User, record.user_id)
      conn = log_in_user(conn, owner)

      # Owning the conversation does not grant access to the admin view.
      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/evaluations/#{record.id}") end
    end

    test "an anonymous visitor is redirected to log in", %{conn: conn, record: record} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/evaluations/#{record.id}")
      assert path == ~p"/users/log_in"
    end
  end

  describe "Show" do
    setup :admin_conn

    test "renders the owner, status and title", %{conn: conn} do
      user = user_fixture(email: "subject@example.com")

      {:ok, record} =
        Conversations.create(user.id, %{title: "Spain fintech", status: "error"})

      {:ok, _lv, html} = live(conn, ~p"/evaluations/#{record.id}")

      assert html =~ "subject@example.com"
      assert html =~ "Spain fintech"
      assert html =~ "inserted"
      assert html =~ "error"
    end

    test "renders the full transcript in order", %{conn: conn} do
      user = user_fixture()
      {:ok, record} = Conversations.create(user.id)

      {:ok, first} =
        Conversations.append_message(record.id, %{role: "user", content: "FIRST-MSG"})

      {:ok, second} =
        Conversations.append_message(record.id, %{role: "assistant", content: "SECOND-MSG"})

      now = NaiveDateTime.utc_now()
      force_message_inserted_at(first, NaiveDateTime.add(now, -10, :second))
      force_message_inserted_at(second, now)

      {:ok, _lv, html} = live(conn, ~p"/evaluations/#{record.id}")

      assert html =~ "FIRST-MSG"
      assert html =~ "SECOND-MSG"

      # Oldest first, matching list_messages/1.
      [first_at, second_at] =
        for needle <- ["FIRST-MSG", "SECOND-MSG"], do: :binary.match(html, needle) |> elem(0)

      assert first_at < second_at
    end

    test "renders validated_data entries", %{conn: conn} do
      user = user_fixture()

      {:ok, record} =
        Conversations.create(user.id, %{
          validated_data: %{"country" => "Spain", "business_market" => "fintech"}
        })

      {:ok, _lv, html} = live(conn, ~p"/evaluations/#{record.id}")

      assert html =~ "Spain"
      assert html =~ "fintech"
    end

    test "handles nil validated_data without raising", %{conn: conn} do
      user = user_fixture()
      {:ok, record} = Conversations.create(user.id)

      {:ok, _lv, html} = live(conn, ~p"/evaluations/#{record.id}")

      assert html =~ "No validated data"
    end

    test "handles empty validated_data without raising", %{conn: conn} do
      user = user_fixture()
      {:ok, record} = Conversations.create(user.id, %{validated_data: %{}})

      {:ok, _lv, html} = live(conn, ~p"/evaluations/#{record.id}")

      assert html =~ "No validated data"
    end

    test "renders a nested validated_data value without raising", %{conn: conn} do
      user = user_fixture()

      {:ok, record} =
        Conversations.create(user.id, %{
          validated_data: %{"research" => %{"competitors" => ["A", "B"]}}
        })

      {:ok, _lv, html} = live(conn, ~p"/evaluations/#{record.id}")

      assert html =~ "research"
    end

    test "shows an empty transcript state", %{conn: conn} do
      user = user_fixture()
      {:ok, record} = Conversations.create(user.id)

      {:ok, _lv, html} = live(conn, ~p"/evaluations/#{record.id}")

      assert html =~ "No messages"
    end

    test "raises for an unknown id", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/evaluations/#{Ecto.UUID.generate()}")
      end
    end

    test "does not start a Conversation GenServer", %{conn: conn} do
      user = user_fixture()
      {:ok, record} = Conversations.create(user.id)

      assert Registry.lookup(Fullstack.JidoMarketAgents.ConversationRegistry, record.id) == []

      {:ok, _lv, _html} = live(conn, ~p"/evaluations/#{record.id}")

      # Opening the admin view must have no side effect on the user's
      # conversation — unlike the end-user chat, which calls
      # Conversation.ensure_started/2.
      assert Registry.lookup(Fullstack.JidoMarketAgents.ConversationRegistry, record.id) == []
    end

    test "offers no message form", %{conn: conn} do
      user = user_fixture()
      {:ok, record} = Conversations.create(user.id)

      {:ok, lv, _html} = live(conn, ~p"/evaluations/#{record.id}")

      refute has_element?(lv, "form")
      refute has_element?(lv, "textarea")
    end
  end

  # Message `timestamps(updated_at: false)` has second granularity, so rows
  # created back-to-back can share an `inserted_at`. Force distinct values
  # rather than sleeping, so the ordering assertion is real.
  defp force_message_inserted_at(message, naive_datetime) do
    naive_datetime = NaiveDateTime.truncate(naive_datetime, :second)

    {1, _} =
      Fullstack.Repo.update_all(
        from(m in Fullstack.JidoMarketAgents.Conversations.Message,
          where: m.id == ^message.id
        ),
        set: [inserted_at: naive_datetime]
      )

    message
  end
end
