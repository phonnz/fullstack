defmodule Storybook.Index do
  use PhoenixStorybook.Index

  def folder_icon, do: {:fa, "book-open"}
  def folder_open?, do: true
end
