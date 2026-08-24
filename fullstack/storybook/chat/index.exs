defmodule Storybook.Chat.Index do
  use PhoenixStorybook.Index

  def folder_icon, do: {:fa, "comments"}
  def folder_open?, do: false
end
