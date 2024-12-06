defmodule FullstackWeb.UrlRedirectController do
  use FullstackWeb, :controller

  alias Fullstack.Urls

  def index(conn, %{"key" => key}) do
    case Urls.find_url(key) do
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Invalid short link")
        |> redirect(to: "/")

      {:ok, destiny} ->
        redirect(conn, external: destiny)
    end
  end
end
