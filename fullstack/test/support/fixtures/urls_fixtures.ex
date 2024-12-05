defmodule Fullstack.UrlsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Fullstack.Urls` context.
  """

  @doc """
  Generate a url.
  """
  def url_fixture(attrs \\ %{}) do
    {:ok, url} =
      attrs
      |> Enum.into(%{
        destiny: "some destiny",
        origin: "some origin",
        visit_count: 42
      })
      |> Fullstack.Urls.create_url()

    url
  end
end
