defmodule FullstackWeb.WhatsAppLoginController do
  @moduledoc """
  One-time login links sent over WhatsApp.

  `GET` only renders a confirmation button: WhatsApp fetches links to build
  previews, and a GET that consumed the token would burn it before the person
  taps it. `POST` consumes the token, logs the user in and opens the
  conversation the link was sent for.
  """
  use FullstackWeb, :controller

  alias Fullstack.Accounts
  alias FullstackWeb.UserAuth

  @invalid_link "WhatsApp login link is invalid or it has expired. " <>
                  "Send any message on WhatsApp to get a new one when a result is ready."

  @doc """
  Creates a fresh one-time token for `user` and returns the absolute login
  URL that opens `conversation_id`.
  """
  def login_url(user, conversation_id) do
    token = Accounts.generate_whatsapp_login_token(user)
    url(~p"/whatsapp/login/#{token}?#{[conversation_id: conversation_id]}")
  end

  def show(conn, %{"token" => token} = params) do
    if Accounts.get_user_by_whatsapp_login_token(token) do
      render(conn, :show, token: token, conversation_id: params["conversation_id"] || "")
    else
      invalid_link(conn)
    end
  end

  def create(conn, %{"token" => token} = params) do
    case Accounts.consume_whatsapp_login_token(token) do
      {:ok, user} ->
        conn
        |> put_session(:user_return_to, return_path(params["conversation_id"]))
        |> put_flash(:info, "Welcome!")
        |> UserAuth.log_in_user(user)

      :error ->
        invalid_link(conn)
    end
  end

  # The redirect target is always built here from a cast UUID, never taken
  # from the request, so the link cannot become an open redirect.
  defp return_path(conversation_id) do
    case Ecto.UUID.cast(conversation_id) do
      {:ok, id} -> ~p"/business-discovery/evaluate/#{id}"
      :error -> ~p"/business-discovery/evaluate"
    end
  end

  defp invalid_link(conn) do
    conn
    |> put_flash(:error, @invalid_link)
    |> redirect(to: ~p"/users/log_in")
  end
end
