defmodule Fullstack.WaitlistTest do
  use Fullstack.DataCase

  alias Fullstack.Waitlist

  describe "waitlist_signups" do
    alias Fullstack.Waitlist.Signup

    @valid_attrs %{email: "lead@example.com", country: "Spain"}
    @invalid_attrs %{email: nil}

    test "create_signup/1 with valid data creates a signup" do
      assert {:ok, %Signup{} = signup} = Waitlist.create_signup(@valid_attrs)
      assert signup.email == "lead@example.com"
      assert signup.country == "Spain"
    end

    test "create_signup/1 without country creates a signup with country: nil" do
      assert {:ok, %Signup{} = signup} = Waitlist.create_signup(%{email: "nolocale@example.com"})
      assert signup.country == nil
    end

    test "create_signup/1 with a discount code stores it as-is" do
      assert {:ok, %Signup{} = signup} =
               Waitlist.create_signup(%{email: "discount@example.com", discount_code: "LAUNCH10"})

      assert signup.discount_code == "LAUNCH10"
    end

    test "create_signup/1 without a discount code creates a signup with discount_code: nil" do
      assert {:ok, %Signup{} = signup} =
               Waitlist.create_signup(%{email: "nodiscount@example.com"})

      assert signup.discount_code == nil
    end

    test "create_signup/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Waitlist.create_signup(@invalid_attrs)
    end

    test "create_signup/1 with malformed email returns error changeset" do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Waitlist.create_signup(%{email: "not-an-email"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "create_signup/1 with duplicate email returns error changeset" do
      assert {:ok, %Signup{}} = Waitlist.create_signup(@valid_attrs)
      assert {:error, %Ecto.Changeset{} = changeset} = Waitlist.create_signup(@valid_attrs)
      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end

    test "change_signup/1 returns a signup changeset" do
      signup = signup_fixture()
      assert %Ecto.Changeset{} = Waitlist.change_signup(signup)
    end

    test "change_signup/2 with attrs returns a changeset with those changes" do
      signup = signup_fixture()
      changeset = Waitlist.change_signup(signup, %{country: "France"})
      assert %Ecto.Changeset{} = changeset
      assert changeset.changes.country == "France"
    end
  end

  defp signup_fixture(attrs \\ %{}) do
    {:ok, signup} =
      attrs
      |> Enum.into(%{email: "fixture-#{System.unique_integer([:positive])}@example.com"})
      |> Fullstack.Waitlist.create_signup()

    signup
  end
end
