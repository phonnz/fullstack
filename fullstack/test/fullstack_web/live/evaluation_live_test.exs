defmodule FullstackWeb.EvaluationLiveTest do
  use FullstackWeb.ConnCase

  import Phoenix.LiveViewTest
  import Fullstack.AccountsFixtures

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
      {:ok, record} = Conversations.create(user.id, %{status: "completed"})
      {:ok, _} = Conversations.append_message(record.id, %{role: "user", content: "hi"})

      {:ok, _lv, html} = live(conn, ~p"/evaluations")

      assert html =~ "completed"
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
end
