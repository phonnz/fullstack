defmodule FullstackWeb.AboutHTML do
  use FullstackWeb, :html

  embed_templates "about_html/*"

  def index(assigns) do
    ~H"""
    <h1>The projects</h1>
    <ul>
      <li><a href="/">FullStack Phoenix Project</a></li>
      <li><a href={~p"/chat"}> Chat application</a></li>
    </ul>
    """
  end
end
