defmodule FullstackWeb.WhatsAppLoginControllerTest do
  use FullstackWeb.ConnCase, async: true

  import Fullstack.AccountsFixtures

  alias Fullstack.Accounts

  setup do
    user = user_fixture()
    %{user: user, token: Accounts.generate_whatsapp_login_token(user), id: Ecto.UUID.generate()}
  end

  describe "GET /whatsapp/login/:token" do
    test "renders a confirmation form and does not consume the token",
         %{conn: conn, token: token, user: user, id: id} do
      conn = get(conn, ~p"/whatsapp/login/#{token}?conversation_id=#{id}")
      html = html_response(conn, 200)

      assert html =~ "Continue"
      assert html =~ ~s(action="/whatsapp/login/#{token}")
      assert html =~ id
      refute get_session(conn, :user_token)
      assert Accounts.get_user_by_whatsapp_login_token(token).id == user.id
    end

    test "redirects to the login page for an invalid token", %{conn: conn} do
      conn = get(conn, ~p"/whatsapp/login/oops")

      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or it has expired"
    end
  end

  describe "POST /whatsapp/login/:token" do
    test "logs the user in, consumes the token and opens the conversation",
         %{conn: conn, token: token, user: user, id: id} do
      conn = post(conn, ~p"/whatsapp/login/#{token}", %{"conversation_id" => id})

      assert redirected_to(conn) == ~p"/business-discovery/evaluate/#{id}"
      assert session_token = get_session(conn, :user_token)
      assert Accounts.get_user_by_session_token(session_token).id == user.id
      assert Accounts.get_user_by_whatsapp_login_token(token) == nil
    end

    test "rejects a token that was already used", %{conn: conn, token: token, id: id} do
      post(conn, ~p"/whatsapp/login/#{token}", %{"conversation_id" => id})

      conn = post(build_conn(), ~p"/whatsapp/login/#{token}", %{"conversation_id" => id})

      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or it has expired"
      refute get_session(conn, :user_token)
    end

    test "falls back to the conversation list for a malformed conversation id",
         %{conn: conn, token: token} do
      conn = post(conn, ~p"/whatsapp/login/#{token}", %{"conversation_id" => "//evil.example"})

      assert redirected_to(conn) == ~p"/business-discovery/evaluate"
    end
  end
end
