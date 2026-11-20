defmodule Fullstack.Channels do
  @moduledoc """
  External messaging channels (for example WhatsApp through Twilio) that feed
  the same JidoMarketAgents conversations as the web UI.

  This context owns who an external sender is (`Identity`), which
  conversation the sender is currently using, and which provider message ids
  were already processed. It never writes conversation messages: those go
  through `Fullstack.JidoMarketAgents.Conversations.start_or_resume/3`.
  """
  import Ecto.Query

  alias Fullstack.Accounts
  alias Fullstack.Channels.{Identity, InboundMessage}
  alias Fullstack.Repo

  @new_conversation_commands ~w(/start /nuevo /new)
  @default_max_new_per_hour 50

  @doc """
  Records a provider message id. Returns `:new` the first time the id is seen
  on `channel`, `:duplicate` afterwards.
  """
  @spec record_inbound(String.t(), String.t()) :: :new | :duplicate
  def record_inbound(channel, external_id) do
    {count, _} =
      Repo.insert_all(
        InboundMessage,
        [
          %{
            id: Ecto.UUID.generate(),
            channel: channel,
            external_id: external_id,
            inserted_at: NaiveDateTime.utc_now(:second)
          }
        ],
        on_conflict: :nothing,
        conflict_target: [:channel, :external_id]
      )

    if count == 1, do: :new, else: :duplicate
  end

  @doc """
  Returns the identity of `external_id` on `channel`, creating it and its
  user when the sender is unknown.

  The user gets a placeholder email (`wa-<digits>@whatsapp.invalid`, a
  reserved domain that can never receive mail) and a random password nobody
  knows, so the account can only be entered through a one-time login link.

  New senders are capped per hour (`:max_new_per_hour`, read from the
  `Fullstack.Channels` config when not given) because each one gets its own
  rate limit and therefore its own LLM budget. Over the cap it returns
  `{:error, :new_user_cap_reached}` and creates nothing; known senders are
  never refused.
  """
  @spec resolve_identity(String.t(), String.t(), keyword()) ::
          {:ok, Identity.t()} | {:error, :new_user_cap_reached | Ecto.Changeset.t()}
  def resolve_identity(channel, external_id, opts \\ []) do
    case get_identity(channel, external_id) do
      %Identity{} = identity -> {:ok, identity}
      nil -> create_identity(channel, external_id, max_new_per_hour(opts))
    end
  end

  defp get_identity(channel, external_id) do
    Repo.get_by(Identity, channel: channel, external_id: external_id)
  end

  defp create_identity(channel, external_id, max_new_per_hour) do
    if new_identities_last_hour() >= max_new_per_hour do
      {:error, :new_user_cap_reached}
    else
      insert_identity(channel, external_id)
    end
  end

  defp new_identities_last_hour do
    since = NaiveDateTime.add(NaiveDateTime.utc_now(), -3600, :second)
    Repo.aggregate(from(i in Identity, where: i.inserted_at > ^since), :count)
  end

  defp insert_identity(channel, external_id) do
    Repo.transaction(fn ->
      with {:ok, user} <- Accounts.register_channel_user(channel_user_attrs(channel, external_id)),
           {:ok, identity} <-
             %Identity{}
             |> Identity.create_changeset(%{
               channel: channel,
               external_id: external_id,
               user_id: user.id
             })
             |> Repo.insert() do
        identity
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> recover_concurrent_insert(channel, external_id)
  end

  # Two first messages from the same new sender can race; the loser hits the
  # unique email or identity index and simply reads the winner's identity.
  defp recover_concurrent_insert({:ok, identity}, _channel, _external_id), do: {:ok, identity}

  defp recover_concurrent_insert({:error, changeset}, channel, external_id) do
    case get_identity(channel, external_id) do
      %Identity{} = identity -> {:ok, identity}
      nil -> {:error, changeset}
    end
  end

  defp channel_user_attrs(channel, external_id) do
    digits = String.replace(external_id, ~r/\D/, "")
    prefix = if channel == "whatsapp", do: "wa", else: channel

    %{
      email: "#{prefix}-#{digits}@#{channel}.invalid",
      password: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    }
  end

  defp max_new_per_hour(opts) do
    Keyword.get_lazy(opts, :max_new_per_hour, fn ->
      :fullstack
      |> Application.get_env(__MODULE__, [])
      |> Keyword.get(:max_new_per_hour, @default_max_new_per_hour)
    end)
  end

  @doc """
  Points `identity` at the conversation it is currently using, or clears the
  pointer with `nil` so the next message starts a new conversation.
  """
  @spec set_active_conversation(Identity.t(), Ecto.UUID.t() | nil) ::
          {:ok, Identity.t()} | {:error, Ecto.Changeset.t()}
  def set_active_conversation(%Identity{} = identity, conversation_id) do
    identity
    |> Identity.active_conversation_changeset(conversation_id)
    |> Repo.update()
  end

  @doc """
  Splits an inbound text into a command and its text.

  `/start`, `/nuevo` and `/new` (any case, as the first word) start a new
  conversation; the rest of the text, possibly empty, is its first message.
  Anything else is a regular message.
  """
  @spec parse_command(String.t()) :: {:new_conversation, String.t()} | {:message, String.t()}
  def parse_command(body) when is_binary(body) do
    trimmed = String.trim(body)

    case String.split(trimmed, ~r/\s+/, parts: 2) do
      [command | rest] ->
        if String.downcase(command) in @new_conversation_commands do
          {:new_conversation, rest |> List.first("") |> String.trim()}
        else
          {:message, trimmed}
        end
    end
  end
end
