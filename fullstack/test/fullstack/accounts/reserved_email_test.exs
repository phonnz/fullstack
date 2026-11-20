defmodule Fullstack.Accounts.ReservedEmailTest do
  use Fullstack.DataCase, async: true

  import Fullstack.AccountsFixtures

  alias Fullstack.Accounts

  # `.invalid` addresses are reserved for users created by messaging
  # channels; if anyone could register one, they could block the phone
  # number it belongs to from ever starting a WhatsApp conversation.
  describe "register_user/1" do
    test "rejects emails on the reserved .invalid domain" do
      for email <- ["wa-5215512345678@whatsapp.invalid", "Someone@Example.INVALID"] do
        assert {:error, changeset} =
                 Accounts.register_user(%{email: email, password: valid_user_password()})

        assert "is reserved" in errors_on(changeset).email
      end
    end

    test "still accepts regular emails" do
      assert {:ok, user} =
               Accounts.register_user(%{
                 email: "real@example.com",
                 password: valid_user_password()
               })

      assert user.email == "real@example.com"
    end
  end

  describe "apply_user_email/3" do
    test "rejects changing the email to the reserved .invalid domain" do
      user = user_fixture()

      assert {:error, changeset} =
               Accounts.apply_user_email(user, valid_user_password(), %{
                 email: "wa-5215512345678@whatsapp.invalid"
               })

      assert "is reserved" in errors_on(changeset).email
    end
  end

  describe "register_channel_user/1" do
    test "accepts a reserved .invalid email" do
      assert {:ok, user} =
               Accounts.register_channel_user(%{
                 email: "wa-5215512345678@whatsapp.invalid",
                 password: valid_user_password()
               })

      assert user.email == "wa-5215512345678@whatsapp.invalid"
    end
  end
end
