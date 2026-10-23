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
  require Logger
  alias Fullstack.Repo

  alias Fullstack.JidoMarketAgents.Conversations.Lifecycle
  alias Fullstack.JidoMarketAgents.Conversations.Message
  alias Fullstack.JidoMarketAgents.Conversations.Record

  defp validate_conversation_id(nil), do: {:ok, nil}
  defp validate_conversation_id(id), do: validate_start_id(id, :invalid_conversation_id)

  # UUID.cast also accepts raw 16-byte binaries; this API requires UUID text.
  defp validate_start_id(id, error) when is_binary(id) and byte_size(id) == 36 do
    case Ecto.UUID.cast(id) do
      {:ok, normalized_id} -> {:ok, normalized_id}
      :error -> {:error, error}
    end
  end

  defp validate_start_id(_id, error), do: {:error, error}

  @doc """
  Validates and enqueues a user's message, creating or resuming the owned
  conversation it belongs to, in a single write entry point.

  With a `nil` conversation id, creates a new untitled conversation owned by
  `user_id`. With an owned id whose runtime is live, resumes it and reuses the
  running process. With an owned id whose runtime has stopped, rehydrates it
  from persisted state (any status). With an id that does not exist, or that
  belongs to a different user, returns `{:error, :not_found}` without
  revealing which case applied. A blank or non-binary `message` returns
  `{:error, :invalid_message}` before anything else is checked or changed.

  No side effect of any kind (no row, no runtime, no buffered message) occurs
  unless every validation passes. This context never persists `message`
  itself — the `Conversation` GenServer is the sole writer of conversation
  messages (design D1) — and never subscribes any process to PubSub; it only
  enqueues `message` through `Fullstack.JidoMarketAgents.send_message/4`,
  which debounces and rate limits per user.

  Returns `{:ok, record}`. Invalid user or conversation id strings return
  `:invalid_user_id` or `:invalid_conversation_id`; a blank or non-binary
  message returns `:invalid_message`; missing and foreign-owned records both
  return `:not_found`; creation returns its changeset error unchanged, while
  runtime startup errors are tagged `:conversation_start_failed`.
  """
  @spec start_or_resume(term(), term(), term()) ::
          {:ok, Record.t()}
          | {:error,
             :invalid_user_id
             | :invalid_message
             | :invalid_conversation_id
             | :not_found
             | Ecto.Changeset.t()
             | {:conversation_start_failed, term()}}
  def start_or_resume(user_id, message, conversation_id) do
    with {:ok, user_id} <- validate_start_id(user_id, :invalid_user_id),
         {:ok, message} <- validate_message(message),
         {:ok, conversation_id} <- validate_conversation_id(conversation_id),
         {:ok, record} <- find_or_create_conversation(user_id, conversation_id),
         {:ok, _pid} <- ensure_conversation_started(record, user_id),
         {:ok, :buffered, _conversation_id} <-
           Fullstack.JidoMarketAgents.send_message(user_id, record.id, message, []) do
      {:ok, record}
    end
  end

  defp validate_message(message) when is_binary(message) do
    if String.trim(message) == "" do
      {:error, :invalid_message}
    else
      {:ok, message}
    end
  end

  defp validate_message(_message), do: {:error, :invalid_message}

  defp find_or_create_conversation(user_id, nil), do: create(user_id)

  defp find_or_create_conversation(user_id, id) do
    case get_for_user(id, user_id) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  defp ensure_conversation_started(record, user_id) do
    case Fullstack.JidoMarketAgents.Conversation.ensure_started(record.id, user_id) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} when is_pid(pid) -> {:ok, pid}
      {:error, reason} -> {:error, {:conversation_start_failed, reason}}
    end
  catch
    :exit, reason -> {:error, {:conversation_start_failed, reason}}
  end

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
  Lists the messages of a conversation with durable pipeline boundaries in
  sequence order. Legacy messages retain their chronological display positions.

  This function is **not** user-scoped: it trusts the caller to have
  already authorized access to `conversation_id` via `get_for_user/2`. It
  is not a safe public entry point on its own — passing an id obtained
  without that check would bypass ownership enforcement.

  ## Examples

      iex> list_messages(conversation.id)
      [%Message{}, ...]

  """
  def list_messages(conversation_id) do
    ordered_messages(Repo, conversation_id)
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

  @doc """
  Moves `record` toward the lifecycle stage `target`, advance-only.

  Meant to run inside the transaction of a persistence path that already owns
  the record, so the stage write shares that path's lock and boundary check.
  A `nil` target, the same stage, or a stage behind the stored one writes
  nothing and returns the record unchanged. Only the next adjacent stage is
  written. A target that would skip a stage is logged and not written, so a
  lagging row never blocks the boundary it belongs to.
  """
  @spec advance_stage(module(), Record.t(), Lifecycle.stage() | nil) ::
          {:ok, Record.t()} | {:error, Ecto.Changeset.t()}
  def advance_stage(_repo, %Record{} = record, nil), do: {:ok, record}

  def advance_stage(repo, %Record{} = record, target) do
    case Lifecycle.advance(record.stage, target) do
      :noop ->
        {:ok, record}

      {:ok, next} ->
        repo.update(Record.stage_changeset(record, next))

      {:error, {:invalid_transition, from, to}} ->
        Logger.warning(
          "Conversation #{record.id}: stage #{from} cannot skip to #{to}; stage left unchanged"
        )

        {:ok, record}
    end
  end

  @result_stages %{
    "research" => {nil, "market_research"},
    "analysis" => {:business_analysis, "business_analysis"},
    "systems" => {:systems_strategy, "systems_strategy"},
    "tech_strategy" => {:tech_strategy, "tech_strategy"}
  }

  @doc """
  Atomically persists an owned, normalized stage result and its readable message.

  `transition` carries stage, run/request UUID strings, input fingerprint,
  contract version, result digest, completion timestamp, result map, status,
  mode, pending stage and optional readable content. The caller must have
  durably admitted the same run/request/input before calling this function.
  No provider call, broadcast or stage scheduling occurs inside this boundary.

  Returns `{:ok, :committed | :replayed, %{record: record, messages: messages}}`
  or `{:error, reason}`. Replays are checked under the same owned row lock and
  never insert a second message. Control metadata is JSON-safe and system-owned.
  """
  @spec persist_stage_transition(Ecto.UUID.t(), Ecto.UUID.t(), non_neg_integer(), map()) ::
          {:ok, :committed | :replayed, %{record: Record.t(), messages: [%Message{}]}}
          | {:error, term()}
  def persist_stage_transition(user_id, record_id, expected_version, transition) do
    with {:ok, transition} <- normalize_transition(transition),
         true <- is_integer(expected_version) and expected_version >= 0 do
      Ecto.Multi.new()
      |> Ecto.Multi.run(:boundary, fn repo, _ ->
        query =
          from r in Record,
            where: r.id == ^record_id and r.user_id == ^user_id,
            lock: "FOR UPDATE"

        case repo.one(query) do
          nil -> {:error, :not_found}
          record -> check_boundary(repo, record, expected_version, transition)
        end
      end)
      |> Ecto.Multi.run(:message, fn repo, %{boundary: boundary} ->
        persist_transition_message(repo, boundary, expected_version, transition)
      end)
      |> Ecto.Multi.run(:record, fn repo, %{boundary: boundary} ->
        persist_transition_record(repo, boundary, expected_version, transition)
      end)
      |> Ecto.Multi.run(:snapshot, fn repo, %{record: record, boundary: boundary} ->
        {:ok, {boundary.outcome, %{record: record, messages: ordered_messages(repo, record.id)}}}
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{snapshot: {outcome, snapshot}}} -> {:ok, outcome, snapshot}
        {:error, :boundary, reason, _changes} -> {:error, reason}
        {:error, operation, reason, _changes} -> {:error, {operation, reason}}
      end
    else
      _ -> {:error, :invalid_transition}
    end
  rescue
    error in Postgrex.Error ->
      # Repo.transaction has already rolled back before this rescue runs.
      # Keep raw database messages (which can contain customer data) private.
      {:error, {:persistence_failed, (error.postgres || %{})[:code] || :database_error}}

    _error in DBConnection.ConnectionError ->
      {:error, {:persistence_failed, :connection_error}}
  end

  defp normalize_transition(transition) when is_map(transition) do
    with {:ok, encoded} <- Jason.encode(transition),
         {:ok, data} <- Jason.decode(encoded),
         true <- Map.has_key?(@result_stages, data["stage"]),
         true <- data["mode"] in ["automatic", "manual"],
         true <-
           is_nil(data["pending_stage"]) or
             data["pending_stage"] in ~w(validator research analysis systems tech_strategy),
         true <- is_nil(data["lifecycle_stage"]) or lifecycle_stage(data) != nil,
         {:ok, _} <- Ecto.UUID.cast(data["run_ref"]),
         {:ok, _} <- Ecto.UUID.cast(data["request_ref"]),
         true <- is_map(data["result"]),
         true <-
           Enum.all?(~w(input_fingerprint contract_version result_digest completed_at), fn key ->
             is_binary(data[key]) and String.trim(data[key]) != ""
           end) do
      {:ok, data}
    else
      _ -> {:error, :invalid_transition}
    end
  end

  defp normalize_transition(_transition), do: {:error, :invalid_transition}

  defp check_boundary(repo, record, expected, transition) do
    control = pipeline_metadata(record)
    version = Map.get(control, "boundary_version", 0)

    same_input? =
      Enum.all?(~w(run_ref request_ref input_fingerprint), fn key ->
        control[key] == transition[key]
      end)

    cond do
      not same_input? ->
        {:error, :boundary_conflict}

      version in [expected, expected + 1] and replayed_result?(repo, record, expected, transition) ->
        {:ok, %{record: record, outcome: :replayed}}

      version == expected ->
        {:ok, %{record: record, outcome: :committed}}

      true ->
        {:error, :boundary_conflict}
    end
  end

  defp pipeline_metadata(record) do
    case record.validated_data do
      %{"_pipeline" => control} when is_map(control) -> control
      _ -> %{}
    end
  end

  defp transition_meta(version, transition) do
    transition
    |> Map.take(
      ~w(stage contract_version input_fingerprint result_digest completed_at run_ref request_ref guide_digest)
    )
    |> Map.put("boundary_version", version + 1)
  end

  defp transition_result(version, transition) do
    Map.put(transition["result"], "_meta", transition_meta(version, transition))
  end

  defp replayed_result?(repo, record, _version, transition) do
    {field, type} = Map.fetch!(@result_stages, transition["stage"])

    Enum.any?(ordered_messages(repo, record.id), fn message ->
      metadata = message.metadata || %{}
      result = metadata["result"]
      meta = if is_map(result), do: result["_meta"] || %{}, else: %{}

      metadata["type"] == type and is_map(result) and
        (is_nil(field) or Map.get(record, field) == result) and
        Enum.all?(
          ~w(stage run_ref request_ref input_fingerprint contract_version result_digest),
          &(meta[&1] == transition[&1])
        ) and
        Map.delete(result, "_meta") == transition["result"]
    end)
  end

  @doc """
  Reads an eligible cached stage under the owned row lock and live boundary.
  This is the manual-call replay boundary, not an in-memory preflight shortcut.
  It returns the original durable result without inserting messages or events.
  """
  def cached_stage_result(
        user_id,
        record_id,
        expected_version,
        binding,
        stage,
        fingerprint,
        contract_version
      ) do
    Repo.transaction(fn ->
      record =
        Repo.one(
          from r in Record,
            where: r.id == ^record_id and r.user_id == ^user_id,
            lock: "FOR UPDATE"
        )

      if is_nil(record), do: Repo.rollback(:not_found)
      control = pipeline_metadata(record)

      if control["boundary_version"] != expected_version or
           control["run_ref"] != binding.run_ref or control["request_ref"] != binding.request_ref,
         do: Repo.rollback(:boundary_conflict)

      case Map.fetch(@result_stages, to_string(stage)) do
        :error ->
          Repo.rollback(:invalid_stage)

        {:ok, {field, type}} ->
          messages = ordered_messages(Repo, record.id)

          result =
            Enum.find_value(Enum.reverse(messages), fn message ->
              metadata = message.metadata || %{}
              result = metadata["result"]
              meta = if is_map(result), do: result["_meta"] || %{}, else: %{}

              if metadata["type"] == type and meta["input_fingerprint"] == fingerprint and
                   meta["contract_version"] == contract_version and
                   (is_nil(field) or Map.get(record, field) == result),
                 do: result
            end)

          %{record: record, messages: messages, result: result}
      end
    end)
  end

  defp persist_transition_message(_repo, %{outcome: :replayed}, _version, _transition),
    do: {:ok, nil}

  defp persist_transition_message(repo, %{record: record}, version, transition) do
    {_field, type} = Map.fetch!(@result_stages, transition["stage"])
    result = transition_result(version, transition)

    attrs = %{
      conversation_id: record.id,
      role: "assistant",
      content: Map.get(transition, "content", Jason.encode!(result)),
      metadata: %{"type" => type, "result" => result, "_meta" => result["_meta"]}
    }

    repo.insert(Message.changeset(%Message{}, attrs))
  end

  defp persist_transition_record(
         _repo,
         %{outcome: :replayed, record: record},
         _version,
         _transition
       ),
       do: {:ok, record}

  defp persist_transition_record(repo, %{record: record}, version, transition) do
    {field, _type} = Map.fetch!(@result_stages, transition["stage"])

    control =
      record
      |> pipeline_metadata()
      |> Map.merge(
        Map.take(transition, ~w(run_ref request_ref input_fingerprint mode pending_stage))
      )
      |> Map.put("boundary_version", version + 1)

    data = Map.put(record.validated_data || %{}, "_pipeline", control)

    status =
      if transition["mode"] == "manual" and transition["status"] not in ["completed", "error"],
        do: "active",
        else: transition["status"]

    descendants =
      case transition["stage"] do
        "research" -> [:business_analysis, :systems_strategy, :tech_strategy]
        "analysis" -> [:systems_strategy, :tech_strategy]
        "systems" -> [:tech_strategy]
        "tech_strategy" -> []
      end

    attrs = Map.merge(Map.new(descendants, &{&1, nil}), %{status: status, validated_data: data})

    attrs =
      if field, do: Map.put(attrs, field, transition_result(version, transition)), else: attrs

    with {:ok, record} <- repo.update(Record.changeset(record, attrs)) do
      advance_stage(repo, record, lifecycle_stage(transition))
    end
  end

  # The transition crosses a JSON roundtrip, so the stage arrives as text.
  # Match it against the closed stage list instead of creating atoms.
  defp lifecycle_stage(%{"lifecycle_stage" => name}) when is_binary(name),
    do: Enum.find(Lifecycle.stages(), &(Atom.to_string(&1) == name))

  defp lifecycle_stage(_transition), do: nil

  defp ordered_messages(repo, record_id) do
    messages =
      repo.all(
        from m in Message,
          where: m.conversation_id == ^record_id,
          order_by: [asc: m.inserted_at]
      )

    # Legacy messages have no durable sequence. Preserve their chronological
    # positions, sorting only sequenced messages into the sequenced slots.
    # NULLS FIRST would incorrectly move later legacy user turns ahead of all
    # previous pipeline results; timestamp alone loses same-second boundaries.
    sequenced =
      messages
      |> Enum.filter(&(not is_nil(message_boundary(&1))))
      |> Enum.sort_by(&message_boundary/1)

    {ordered, []} =
      Enum.map_reduce(messages, sequenced, fn message, remaining ->
        if is_nil(message_boundary(message)) do
          {message, remaining}
        else
          [next | rest] = remaining
          {next, rest}
        end
      end)

    ordered
  end

  defp message_boundary(%{metadata: %{"_meta" => %{"boundary_version" => version}}})
       when is_integer(version) and version >= 0, do: version

  defp message_boundary(_message), do: nil

  defp normalize(attrs) when is_map(attrs), do: attrs
  defp normalize(attrs), do: Map.new(attrs)
end
