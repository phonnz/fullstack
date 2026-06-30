defmodule Fullstack.BlogFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Fullstack.Blog` context.
  """

  @doc """
  Generate a post.
  """
  def post_fixture(attrs \\ %{}) do
    author = Fullstack.AccountsFixtures.user_fixture()

    {:ok, post} =
      attrs
      |> Enum.into(%{
        content: "some content",
        title: "some title",
        author_id: author.id
      })
      |> Fullstack.Blog.create_post()

    post
  end
end
