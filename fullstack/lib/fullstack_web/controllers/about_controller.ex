defmodule FullstackWeb.AboutController do
  use FullstackWeb, :controller

  def index(conn, _params) do
    render(conn, :index)
  end
end
