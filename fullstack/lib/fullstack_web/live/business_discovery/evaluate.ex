defmodule FullstackWeb.BusinessDiscoveryLive.Evaluate do
  @moduledoc """
  Authenticated chat LiveView for the Business Discovery agent (Slice C, T9).

  Follows `FullstackWeb.ChannelsChatLive`'s sidebar/streams layout: a list of
  the user's own conversations on the left (`phx-update="stream"`,
  `phx-click="select_conversation"`), and the selected conversation's
  transcript on the right.

  Design contracts this module must honor:

  - D1: the `Conversation` GenServer is the only writer. This LiveView never
    persists a message directly — it renders the user's own message
    optimistically into assigns, then replaces the transcript wholesale once
    the authoritative `payload.messages` arrives via PubSub.
  - D3b: the GenServer id **is** the `Conversations.Record`'s binary_id.
    `Conversations.start_conversation/2` owns creation, ownership validation,
    and runtime startup/restoration under that id.
  - D8: the context enforces ownership as a query filter. There is
    no unscoped getter, so an id belonging to another user cannot be reached
    by editing the URL — it 404s (raises `Ecto.NoResultsError`), it never
    redirects (a redirect would confirm the id exists under another
    account).
  - D9: the "thinking" indicator is a derived `:phase` assign, set by
    whichever `handle_info` clause last fired. Every terminal event clears it
    by construction — there is no boolean flag some path could forget to
    reset.
  """

  use FullstackWeb, :live_view

  alias Fullstack.JidoMarketAgents
  alias Fullstack.JidoMarketAgents.Conversations

  @impl true
  def mount(_params, _session, socket) do
    conversations = Conversations.list_for_user(socket.assigns.current_user.id)

    {:ok,
     socket
     |> stream(:conversations, conversations, dom_id: &"conversation-#{&1.id}")
     |> assign(:conversation, nil)
     |> assign(:messages, [])
     |> assign(:phase, nil)
     |> assign(:error, nil)
     |> assign(:rate_limited, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case Conversations.start_conversation(socket.assigns.current_user.id, id) do
      {:ok, %Conversations.Record{} = record} ->
        socket = unsubscribe_from_current(socket)

        if connected?(socket), do: JidoMarketAgents.subscribe(record.id)

        messages = Conversations.list_messages(record.id)

        {:noreply,
         socket
         |> assign(:conversation, record)
         |> assign(:messages, messages)
         |> assign(:phase, nil)
         |> assign(:error, nil)
         |> assign(:rate_limited, nil)}

      {:error, reason} when reason in [:not_found, :invalid_conversation_id] ->
        # Missing, malformed, and foreign-owned identifiers are indistinguishable.
        raise Ecto.NoResultsError, queryable: Conversations.Record

      {:error, _reason} ->
        {:noreply,
         socket
         |> clear_conversation()
         |> put_flash(:error, "Unable to start the conversation. Please try again.")}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, clear_conversation(socket)}
  end

  @impl true
  def handle_event("new_conversation", _params, socket) do
    case Conversations.start_conversation(socket.assigns.current_user.id) do
      {:ok, %Conversations.Record{} = record} ->
        {:noreply, push_patch(socket, to: ~p"/business-discovery/evaluate/#{record.id}")}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, "Unable to start the conversation. Please try again.")}
    end
  end

  def handle_event("select_conversation", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/business-discovery/evaluate/#{id}")}
  end

  def handle_event("send", %{"message" => message}, socket) do
    if String.trim(message) == "" do
      # S16.3: empty/whitespace-only input sends nothing.
      {:noreply, socket}
    else
      current_user = socket.assigns.current_user
      conversation = socket.assigns.conversation

      # S16.2: subscribe BEFORE sending. handle_params already subscribed
      # this LiveView to this conversation's topic when it was selected, so
      # in the normal flow we are already subscribed here — but the
      # ordering is made explicit anyway (re-subscribing to an already
      # subscribed topic is a harmless no-op) because a broadcast arriving
      # in the gap between send and subscribe would be lost forever: PubSub
      # delivers only to processes subscribed at broadcast time, and there
      # is no replay.
      JidoMarketAgents.subscribe(conversation.id)

      {:ok, :buffered, _conversation_id} =
        JidoMarketAgents.send_message(current_user.id, conversation.id, message, [])

      # D1: optimistic render only — the LiveView never persists this
      # message itself. The GenServer is the sole writer of record; this
      # entry is replaced wholesale the moment the authoritative
      # `payload.messages` arrives (S16.1, S16.4).
      optimistic = %{role: "user", content: message}

      {:noreply,
       socket
       |> assign(:messages, socket.assigns.messages ++ [optimistic])
       |> assign(:phase, :buffering)
       |> assign(:error, nil)
       |> assign(:rate_limited, nil)}
    end
  end

  # ── PubSub handlers ─────────────────────────────────────────────────────
  #
  # D9: :phase is derived from whichever clause fires last. Every terminal
  # event below sets :phase back to nil (or a named terminal phase) by
  # construction — there is no separate boolean to forget to clear.

  @impl true
  def handle_info({:buffered, _payload}, socket) do
    {:noreply, assign(socket, :phase, :buffering)}
  end

  def handle_info({:extraction_complete, %{status: :researching} = payload}, socket) do
    {:noreply,
     socket
     |> assign(:phase, :researching)
     |> replace_messages(payload)}
  end

  def handle_info({:extraction_complete, %{status: :needs_data} = payload}, socket) do
    # S17.2: the agent is WAITING ON THE USER, not working — :idle, not a
    # spinner state.
    {:noreply,
     socket
     |> assign(:phase, :idle)
     |> replace_messages(payload)
     |> refresh_sidebar()}
  end

  def handle_info({:research_complete, payload}, socket) do
    {:noreply,
     socket
     |> assign(:phase, :idle)
     |> replace_messages(payload)
     |> refresh_sidebar()}
  end

  def handle_info({:error, payload}, socket) do
    {:noreply,
     socket
     |> assign(:phase, :idle)
     |> assign(:error, Map.get(payload, :reason))
     |> replace_messages(payload)}
  end

  def handle_info({:rate_limited, payload}, socket) do
    # S17.5: NO spinner while rate limited — :rate_limited is its own
    # terminal phase, distinct from any "thinking" phase, so the template
    # never renders a spinner for it.
    {:noreply,
     socket
     |> assign(:phase, :rate_limited)
     |> assign(:rate_limited, payload)}
  end

  def handle_info({:queued_during_cooldown, _payload}, socket) do
    {:noreply, assign(socket, :phase, :queued)}
  end

  def handle_info({:cooldown_complete, _payload}, socket) do
    {:noreply, assign(socket, :phase, :idle)}
  end

  # Ignores broadcasts for a conversation that is not currently selected
  # (defensive — handle_params unsubscribes from the previous topic on
  # every selection change, but this keeps handle_info total).
  def handle_info(_other, socket), do: {:noreply, socket}

  # ── Private helpers ─────────────────────────────────────────────────────

  defp replace_messages(socket, %{messages: messages}) when is_list(messages) do
    # S16.4: the transcript re-renders from the authoritative
    # payload.messages, replacing the optimistic entry (D1).
    assign(socket, :messages, messages)
  end

  defp replace_messages(socket, _payload), do: socket

  defp refresh_sidebar(socket) do
    conversations = Conversations.list_for_user(socket.assigns.current_user.id)
    stream(socket, :conversations, conversations, reset: true)
  end

  defp unsubscribe_from_current(socket) do
    case socket.assigns[:conversation] do
      %Conversations.Record{id: id} ->
        Phoenix.PubSub.unsubscribe(Fullstack.PubSub, JidoMarketAgents.topic(id))
        socket

      _ ->
        socket
    end
  end

  # Messages come in two shapes: persisted `Conversations.Message` structs
  defp clear_conversation(socket) do
    socket
    |> unsubscribe_from_current()
    |> assign(:conversation, nil)
    |> assign(:messages, [])
    |> assign(:phase, nil)
    |> assign(:error, nil)
    |> assign(:rate_limited, nil)
  end

  # (loaded on selection, or arriving via an authoritative broadcast) and
  # the plain optimistic map assigned in the "send" event (D1). Both carry
  # `role`/`content`, so the template renders either without branching on
  # shape itself.
  @doc false
  def message_role(%{role: role}), do: role
  def message_role(message) when is_map(message), do: Map.get(message, "role")

  @doc false
  def message_content(%{content: content}), do: content
  def message_content(message) when is_map(message), do: Map.get(message, "content")
end
