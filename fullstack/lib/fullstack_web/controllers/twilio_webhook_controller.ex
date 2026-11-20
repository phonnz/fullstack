defmodule FullstackWeb.TwilioWebhookController do
  @moduledoc """
  Twilio WhatsApp webhook.

  Every request must carry a valid `X-Twilio-Signature`; anything else gets
  403 before any side effect. A valid request is answered right away with
  TwiML: empty when the agents will reply later through the relay, or with a
  short system message (command acknowledgement, cap, unsupported media).
  """
  use FullstackWeb, :controller

  alias Fullstack.Channels.Twilio
  alias Fullstack.Channels.WhatsApp
  alias FullstackWeb.WhatsAppLoginController

  def whatsapp(conn, _params) do
    params = conn.body_params

    cond do
      not signed_by_twilio?(conn, params) ->
        send_resp(conn, 403, "")

      not (is_binary(params["From"]) and is_binary(params["MessageSid"])) ->
        send_resp(conn, 400, "")

      true ->
        %{from: params["From"], body: params["Body"], message_sid: params["MessageSid"]}
        |> WhatsApp.receive_message(login_url: &WhatsAppLoginController.login_url/2)
        |> twiml(conn)
    end
  end

  defp signed_by_twilio?(conn, params) do
    signature = conn |> get_req_header("x-twilio-signature") |> List.first()
    Twilio.valid_signature?(signed_url(conn), params, signature, Twilio.auth_token())
  end

  # Twilio signs the public URL it called, which differs from the local one
  # behind a proxy or tunnel; `:webhook_base_url` overrides the endpoint URL.
  defp signed_url(conn) do
    base = Twilio.webhook_base_url() || FullstackWeb.Endpoint.url()
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string
    String.trim_trailing(base, "/") <> conn.request_path <> query
  end

  defp twiml(:noreply, conn), do: send_twiml(conn, "<Response></Response>")

  defp twiml({:reply, text}, conn) do
    escaped = text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
    send_twiml(conn, "<Response><Message>#{escaped}</Message></Response>")
  end

  defp send_twiml(conn, body) do
    conn
    |> put_resp_content_type("text/xml")
    |> send_resp(200, ~s(<?xml version="1.0" encoding="UTF-8"?>) <> body)
  end
end
