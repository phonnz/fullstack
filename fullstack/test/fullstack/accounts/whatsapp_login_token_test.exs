defmodule Fullstack.Accounts.WhatsAppLoginTokenTest do
  use Fullstack.DataCase, async: true

  import Fullstack.AccountsFixtures

  alias Fullstack.Accounts
  alias Fullstack.Accounts.UserToken

  setup do
    user = user_fixture()
    %{user: user, token: Accounts.generate_whatsapp_login_token(user)}
  end

  test "stores only the hash of the token", %{token: token} do
    refute Repo.get_by(UserToken, token: token)
    assert Repo.get_by(UserToken, context: "whatsapp_login")
  end

  test "get_user_by_whatsapp_login_token/1 finds the user without consuming the token",
       %{user: user, token: token} do
    assert Accounts.get_user_by_whatsapp_login_token(token).id == user.id
    assert Accounts.get_user_by_whatsapp_login_token(token).id == user.id
  end

  test "consume_whatsapp_login_token/1 works exactly once", %{user: user, token: token} do
    assert {:ok, consumed} = Accounts.consume_whatsapp_login_token(token)
    assert consumed.id == user.id

    assert Accounts.consume_whatsapp_login_token(token) == :error
    assert Accounts.get_user_by_whatsapp_login_token(token) == nil
  end

  test "an expired token is rejected", %{token: token} do
    sixteen_minutes_ago = NaiveDateTime.add(NaiveDateTime.utc_now(:second), -16 * 60, :second)
    Repo.update_all(UserToken, set: [inserted_at: sixteen_minutes_ago])

    assert Accounts.get_user_by_whatsapp_login_token(token) == nil
    assert Accounts.consume_whatsapp_login_token(token) == :error
  end

  test "malformed tokens and tokens of other contexts are rejected", %{user: user} do
    assert Accounts.get_user_by_whatsapp_login_token("not base64 !!") == nil
    assert Accounts.consume_whatsapp_login_token("not base64 !!") == :error

    {reset_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)

    assert Accounts.get_user_by_whatsapp_login_token(reset_token) == nil
    assert Accounts.consume_whatsapp_login_token(reset_token) == :error
  end
end
