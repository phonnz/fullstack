defmodule Fullstack.Waitlist do
  @moduledoc """
  The Waitlist context.
  """

  import Ecto.Query, warn: false
  alias Fullstack.Repo

  alias Fullstack.Waitlist.Signup

  @doc """
  Creates a signup.

  ## Examples

      iex> create_signup(%{field: value})
      {:ok, %Signup{}}

      iex> create_signup(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_signup(attrs \\ %{}) do
    %Signup{}
    |> Signup.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking signup changes.

  ## Examples

      iex> change_signup(signup)
      %Ecto.Changeset{data: %Signup{}}

  """
  def change_signup(%Signup{} = signup, attrs \\ %{}) do
    Signup.changeset(signup, attrs)
  end
end
