defmodule Fullstack.Channels.WhatsApp do
  @moduledoc """
  Inbound WhatsApp messages into JidoMarketAgents conversations.

  For each new provider message: resolve (or create) the sender's identity,
  apply the `/start`, `/nuevo` and `/new` commands, make sure the sender has
  an active conversation, start its `Relay` (which sends the replies back),
  and enqueue the text through `Conversations.start_or_resume/3`, the same
  entry point the web UI uses.

  Returns `{:reply, text}` when the sender should get an immediate system
  reply (sent by the webhook as TwiML), or `:noreply` when the answer will
  come from the agents through the relay.
  """
  require Logger

  alias Fullstack.Accounts
  alias Fullstack.Channels
  alias Fullstack.Channels.Identity
  alias Fullstack.Channels.WhatsApp.Relay
  alias Fullstack.JidoMarketAgents.Conversations

  @channel "whatsapp"

  @new_conversation_text "Started a new conversation. Tell me about your business idea."
  @text_only_text "For now I can only read text messages. Please send your answer as text."
  @cap_text "We are receiving many new conversations right now. Please try again in an hour."
  @failure_text "Something went wrong on our side. Please send your message again."

  @type inbound :: %{from: String.t(), body: String.t() | nil, message_sid: String.t()}

  @doc """
  Handles one inbound message. `opts` must include `:login_url`, a function
  `(user, conversation_id) -> url` used by the relay for stage results.
  """
  @spec receive_message(inbound(), keyword()) :: {:reply, String.t()} | :noreply
  def receive_message(%{from: from, message_sid: sid} = inbound, opts) do
    case Channels.record_inbound(@channel, sid) do
      :duplicate -> :noreply
      :new -> handle_new(from, inbound[:body] || "", opts)
    end
  end

  defp handle_new(from, body, opts) do
    case Channels.resolve_identity(@channel, from) do
      {:ok, identity} ->
        handle_command(identity, Channels.parse_command(body), opts)

      {:error, :new_user_cap_reached} ->
        {:reply, @cap_text}

      {:error, reason} ->
        failure(:resolve_identity, reason)
    end
  end

  defp handle_command(identity, {:new_conversation, ""}, _opts) do
    case Channels.set_active_conversation(identity, nil) do
      {:ok, _identity} -> {:reply, @new_conversation_text}
      {:error, reason} -> failure(:new_conversation, reason)
    end
  end

  defp handle_command(identity, {:new_conversation, text}, opts) do
    case Channels.set_active_conversation(identity, nil) do
      {:ok, identity} -> forward(identity, text, opts)
      {:error, reason} -> failure(:new_conversation, reason)
    end
  end

  defp handle_command(_identity, {:message, ""}, _opts), do: {:reply, @text_only_text}
  defp handle_command(identity, {:message, text}, opts), do: forward(identity, text, opts)

  # The relay subscribes before start_or_resume/3 enqueues the text, so no
  # reply can be broadcast before it listens.
  defp forward(identity, text, opts) do
    with {:ok, conversation_id} <- active_conversation(identity),
         {:ok, _relay} <-
           Relay.ensure_started(conversation_id,
             to: identity.external_id,
             login_url_fun: login_url_fun(identity.user_id, Keyword.fetch!(opts, :login_url))
           ),
         {:ok, _record} <-
           Conversations.start_or_resume(identity.user_id, text, conversation_id) do
      :noreply
    else
      {:error, reason} -> failure(:forward, reason)
    end
  end

  defp active_conversation(%Identity{active_conversation_id: nil} = identity) do
    with {:ok, record} <- Conversations.create(identity.user_id),
         {:ok, _identity} <- Channels.set_active_conversation(identity, record.id) do
      {:ok, record.id}
    end
  end

  defp active_conversation(%Identity{active_conversation_id: id}), do: {:ok, id}

  # Loads the user when the link is built, so the token is bound to the
  # user's current email.
  defp login_url_fun(user_id, login_url) do
    fn conversation_id -> login_url.(Accounts.get_user!(user_id), conversation_id) end
  end

  defp failure(step, reason) do
    Logger.error("WhatsApp inbound message failed at #{step}: #{inspect(reason)}")
    {:reply, @failure_text}
  end
end
