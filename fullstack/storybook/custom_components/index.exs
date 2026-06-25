defmodule Storybook.CustomComponents.Index do
  use PhoenixStorybook.Index

  def folder_icon, do: {:fa, "puzzle-piece"}
  def folder_open?, do: false
end
