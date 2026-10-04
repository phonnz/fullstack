defmodule Fullstack.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Fullstack.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    {role, attrs} = Map.pop(attrs, :role)

    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Fullstack.Accounts.register_user()

    # `:role` is intentionally not castable through registration, so it is
    # applied in a second write (see Fullstack.Accounts.User.role_changeset/2).
    if role do
      {:ok, user} =
        user
        |> Fullstack.Accounts.User.role_changeset(%{role: role})
        |> Fullstack.Repo.update()

      user
    else
      user
    end
  end

  @doc """
  Builds a user holding the `:admin` role.
  """
  def admin_fixture(attrs \\ %{}) do
    attrs |> Map.new() |> Map.put(:role, :admin) |> user_fixture()
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
