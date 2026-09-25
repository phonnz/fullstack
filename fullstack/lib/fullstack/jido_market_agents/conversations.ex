defmodule Fullstack.JidoMarketAgents.Conversations do
  @moduledoc """
  The Conversations context.

  Persistence boundary for market discovery conversations
  (`Fullstack.JidoMarketAgents.Conversations.Record`) and their messages
  (`Fullstack.JidoMarketAgents.Conversations.Message`).

  Ownership is enforced as a `where` clause inside the query, never as a
  caller-side check. There is deliberately no unscoped `get/1`: every
  function that returns a conversation requires a `user_id` and filters on
  it, so a call site cannot forget to guard against reading another user's
  data (design decision D8).
  """

  import Ecto.Query, warn: false
  alias Fullstack.Repo

  alias Fullstack.JidoMarketAgents.Conversations.Message
  alias Fullstack.JidoMarketAgents.Conversations.Record

  @doc """
  Returns the given user's conversations, newest first by `inserted_at`.

  ## Examples

      iex> list_for_user(user.id)
      [%Record{}, ...]

  """
  def list_for_user(user_id) do
    Record
    |> where([r], r.user_id == ^user_id)
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single conversation owned by the given user.

  Returns `nil` when no such conversation exists, **including** when the
  id belongs to a different user — the ownership filter is part of the
  query itself, so this never raises and never leaks whether the id
  exists under another account.

  ## Examples

      iex> get_for_user(record.id, user.id)
      %Record{}

      iex> get_for_user(other_users_record.id, user.id)
      nil

  """
  def get_for_user(id, user_id) do
    Record
    |> where([r], r.id == ^id and r.user_id == ^user_id)
    |> Repo.one()
  end

  @doc """
  Creates a conversation for the given user.

  ## Examples

      iex> create(user.id)
      {:ok, %Record{}}

      iex> create(nil)
      {:error, %Ecto.Changeset{}}

  """
  def create(user_id, attrs \\ %{}) do
    %Record{}
    |> Record.changeset(Map.put(normalize(attrs), :user_id, user_id))
    |> Repo.insert()
  end

  @doc """
  Appends a message to the given conversation.

  ## Examples

      iex> append_message(conversation.id, %{role: "user", content: "hi"})
      {:ok, %Message{}}

  """
  def append_message(conversation_id, attrs) do
    %Message{}
    |> Message.changeset(Map.put(normalize(attrs), :conversation_id, conversation_id))
    |> Repo.insert()
  end

  @doc """
  Lists the messages of a conversation, ordered by `inserted_at` ascending
  (oldest first).

  This function is **not** user-scoped: it trusts the caller to have
  already authorized access to `conversation_id` via `get_for_user/2`. It
  is not a safe public entry point on its own — passing an id obtained
  without that check would bypass ownership enforcement.

  ## Examples

      iex> list_messages(conversation.id)
      [%Message{}, ...]

  """
  def list_messages(conversation_id) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Updates a conversation's lifecycle state (`:status` and/or
  `:validated_data`).

  ## Examples

      iex> update_state(record, %{status: "researching"})
      {:ok, %Record{}}

  """
  def update_state(%Record{} = record, attrs) do
    record
    |> Record.changeset(normalize(attrs))
    |> Repo.update()
  end

  defp normalize(attrs) when is_map(attrs), do: attrs
  defp normalize(attrs), do: Map.new(attrs)
end
