defmodule Fullstack.FinancialFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Fullstack.Financial` context.
  """

  @doc """
  Generate a pos.
  """
  def pos_fixture(attrs \\ %{}) do
    {:ok, pos} =
      attrs
      |> Enum.into(%{
        name: "some name"
      })
      |> Fullstack.Financial.create_pos()

    pos
  end
end
