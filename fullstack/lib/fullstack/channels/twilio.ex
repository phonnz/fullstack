defmodule Fullstack.Channels.Twilio do
  @moduledoc """
  Minimal Twilio client for the WhatsApp channel: request signature
  validation for inbound webhooks and outbound messages through the
  Messages API.

  Configuration (`config :fullstack, Fullstack.Channels.Twilio`):

    * `:account_sid` and `:auth_token` — API credentials; the auth token also
      signs inbound webhooks.
    * `:whatsapp_from` — the sender address, for example
      `"whatsapp:+14155238886"`.
    * `:base_url` — defaults to `"https://api.twilio.com"`.
    * `:req_options` — extra `Req` options (tests plug `Req.Test` here).
  """

  @default_base_url "https://api.twilio.com"

  @doc """
  Checks an `X-Twilio-Signature` header.

  Twilio signs the full URL it requested followed by every POST parameter
  name and value, sorted by name, with HMAC-SHA1 keyed by the auth token,
  Base64-encoded. A missing signature or token is never valid.
  """
  @spec valid_signature?(String.t(), map(), String.t() | nil, String.t() | nil) :: boolean()
  def valid_signature?(url, params, signature, auth_token)
      when is_binary(signature) and is_binary(auth_token) and auth_token != "" do
    payload =
      params
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.reduce(url, fn {key, value}, acc -> acc <> key <> to_string(value) end)

    expected = :crypto.mac(:hmac, :sha, auth_token, payload) |> Base.encode64()
    Plug.Crypto.secure_compare(expected, signature)
  end

  def valid_signature?(_url, _params, _signature, _auth_token), do: false

  @doc "The configured auth token, used to validate inbound webhooks."
  @spec auth_token() :: String.t() | nil
  def auth_token, do: Keyword.get(config(), :auth_token)

  @doc """
  Sends `body` to the WhatsApp address `to` (for example
  `"whatsapp:+5215512345678"`). Returns the Twilio message sid.
  """
  @spec send_whatsapp(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :not_configured | {:http, integer(), term()} | term()}
  def send_whatsapp(to, body) do
    config = config()

    with {:ok, sid} <- fetch(config, :account_sid),
         {:ok, token} <- fetch(config, :auth_token),
         {:ok, from} <- fetch(config, :whatsapp_from) do
      [
        method: :post,
        base_url: Keyword.get(config, :base_url, @default_base_url),
        url: "/2010-04-01/Accounts/#{sid}/Messages.json",
        auth: {:basic, "#{sid}:#{token}"},
        form: [From: from, To: to, Body: body]
      ]
      |> Keyword.merge(Keyword.get(config, :req_options, []))
      |> Req.request()
      |> handle_response()
    end
  end

  defp handle_response({:ok, %Req.Response{status: status, body: %{"sid" => sid}}})
       when status in 200..299,
       do: {:ok, sid}

  defp handle_response({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, {:http, status, body}}

  defp handle_response({:error, reason}), do: {:error, reason}

  defp fetch(config, key) do
    case Keyword.get(config, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :not_configured}
    end
  end

  defp config, do: Application.get_env(:fullstack, __MODULE__, [])
end
