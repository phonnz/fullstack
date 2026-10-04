defmodule Fullstack.JidoMarketAgents.Conversations do
  @moduledoc """
  The Conversations context.

  Persistence boundary for market discovery conversations
  (`Fullstack.JidoMarketAgents.Conversations.Record`) and their messages
  (`Fullstack.JidoMarketAgents.Conversations.Message`).

  Ownership is enforced as a `where` clause inside the query, never as a
  caller-side check. In the user-facing API there is deliberately no
  unscoped `get/1`: every function that serves an end user requires a
  `user_id` and filters on it, so a call site cannot forget to guard
  against reading another user's data (design decision D8).

  `list_all/1` and `get_any/1` are the two audited exceptions. They exist
  for the admin review screen at `/evaluations`, which must read across
  users by definition, and each carries a warning in its own
  documentation. They must only be reached from behind an admin
  authorization check (`FullstackWeb.UserAuth`'s `:ensure_admin`) — never
  from user-facing code, which continues to use `get_for_user/2` and
  `list_for_user/1`.
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
  Returns every conversation, newest first, with the owning user preloaded
  and a `:message_count` virtual field set.

  > #### Admin-authorized call sites only {: .warning}
  >
  > This function deliberately bypasses the ownership filter described in
  > this module's documentation. It must only be reached from behind
  > `FullstackWeb.UserAuth`'s `:ensure_admin` (or the equivalent
  > `require_admin_user/2` plug). Do not call it from a user-facing
  > LiveView or controller action.

  The message count is an aggregate in the same query rather than a
  preload, so the cost does not grow with the number of conversations.

  ## Options

    * `:limit` — maximum rows to return.
    * `:offset` — rows to skip, for pagination.

  ## Examples

      iex> list_all()
      [%Record{message_count: 2}, ...]

      iex> list_all(limit: 25, offset: 50)
      [%Record{}, ...]

  """
  def list_all(opts \\ []) do
    Record
    |> join(:left, [r], m in Message, on: m.conversation_id == r.id)
    |> group_by([r], r.id)
    |> order_by([r], desc: r.inserted_at)
    |> select_merge([r, m], %{message_count: count(m.id)})
    |> maybe_limit(Keyword.get(opts, :limit))
    |> maybe_offset(Keyword.get(opts, :offset))
    |> Repo.all()
    |> Repo.preload(:user)
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, value), do: limit(query, ^value)

  defp maybe_offset(query, nil), do: query
  defp maybe_offset(query, value), do: offset(query, ^value)

  @doc """
  Gets a single conversation by id, regardless of owner, with the owning
  user preloaded. Returns `nil` when it does not exist.

  > #### Admin-authorized call sites only {: .warning}
  >
  > Like `list_all/1`, this bypasses the ownership filter on purpose and
  > must sit behind an admin authorization check. User-facing code must
  > use `get_for_user/2` instead.

  ## Examples

      iex> get_any(record.id)
      %Record{}

      iex> get_any(Ecto.UUID.generate())
      nil

  """
  def get_any(id) do
    Record
    |> where([r], r.id == ^id)
    |> Repo.one()
    |> Repo.preload(:user)
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
