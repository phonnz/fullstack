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
        ## Task.start(fn -> ShortLinks.increment_hit_count(short_link) end)
        redirect(conn, external: destiny)
    end
  end
end
