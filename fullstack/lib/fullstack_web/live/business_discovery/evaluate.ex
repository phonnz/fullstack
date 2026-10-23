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
    `Conversations.start_or_resume/3` owns creation, ownership validation,
    and runtime startup/restoration under that id, driven by the user's
    first message. Navigation (`handle_params`) is read-only: it never
    starts a runtime, it only loads an existing, owned record (D10).
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
  alias Fullstack.JidoMarketAgents.Telemetry, as: AgentTelemetry

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
  # This is the self-patch right after the first send already created the
  # record (see `send_message/3` below): the optimistic user message is not
  # persisted yet (D1, persistence is async in the GenServer), so this
  # clause is a no-op — no reload, and no second subscribe.
  def handle_params(
        %{"id" => id},
        _uri,
        %{assigns: %{conversation: %Conversations.Record{id: id}}} = socket
      ) do
    {:noreply, socket}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    with {:ok, _uuid} <- cast_conversation_id(id),
         %Conversations.Record{} = record <-
           Conversations.get_for_user(id, socket.assigns.current_user.id) do
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
    else
      # Malformed, missing, and foreign-owned identifiers are
      # indistinguishable (D8) and all 404.
      _ -> raise Ecto.NoResultsError, queryable: Conversations.Record
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, clear_conversation(socket)}
  end

  # Mirrors `Conversations.validate_start_id/2`: `Ecto.UUID.cast/1` alone
  # also accepts arbitrary 16-byte binaries, which is too lenient for text
  # ids arriving from a URL param. Requiring canonical 36-byte UUID text
  # keeps `get_for_user/2` from ever raising a `CastError` (a 500) on a
  # malformed id — it must 404 instead.
  defp cast_conversation_id(id) when is_binary(id) and byte_size(id) == 36 do
    Ecto.UUID.cast(id)
  end

  defp cast_conversation_id(_id), do: :error

  @impl true
  def handle_event("new_conversation", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/business-discovery/evaluate")}
  end

  def handle_event("select_conversation", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/business-discovery/evaluate/#{id}")}
  end

  def handle_event("send", %{"message" => message}, socket) do
    if String.trim(message) == "" do
      # S16.3: empty/whitespace-only input sends nothing.
      {:noreply, socket}
    else
      send_message(socket, message, socket.assigns.conversation)
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
     |> replace_messages(payload)
     |> handled(:extraction_complete_researching)}
  end

  def handle_info({:extraction_complete, %{status: :needs_data} = payload}, socket) do
    # S17.2: the agent is WAITING ON THE USER, not working — :idle, not a
    # spinner state.
    {:noreply,
     socket
     |> assign(:phase, :idle)
     |> replace_messages(payload)
     |> refresh_sidebar()
     |> handled(:extraction_complete_needs_data)}
  end

  def handle_info({:research_complete, payload}, socket) do
    {:noreply,
     socket
     |> assign(:phase, :idle)
     |> replace_messages(payload)
     |> refresh_sidebar()
     |> handled(:research_complete)}
  end

  # From `:research` onward a message is stored as chat only and no pipeline
  # event follows it, so this is its terminal event.
  def handle_info({:message_received, payload}, socket) do
    {:noreply,
     socket
     |> assign(:phase, :idle)
     |> replace_messages(payload)
     |> handled(:message_received)}
  end

  def handle_info({:error, payload}, socket) do
    {:noreply,
     socket
     |> assign(:phase, :idle)
     |> assign(:error, Map.get(payload, :reason))
     |> replace_messages(payload)
     |> handled(:error)}
  end

  def handle_info({:rate_limited, payload}, socket) do
    # S17.5: NO spinner while rate limited — :rate_limited is its own
    # terminal phase, distinct from any "thinking" phase, so the template
    # never renders a spinner for it.
    {:noreply,
     socket
     |> assign(:phase, :rate_limited)
     |> assign(:rate_limited, payload)
     |> handled(:rate_limited)}
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
  #
  # This clause is the pipeline's one truly silent failure: a payload whose
  # shape matches none of the clauses above is discarded with no assign
  # change and no log line, so a response that WAS produced never reaches
  # the screen and nothing anywhere records that it arrived. The probe
  # makes that case loud — it is emitted at :warning by the reporter,
  # unlike every other line in the trace.
  def handle_info(other, socket) do
    AgentTelemetry.emit(
      [:fullstack, :jido_market_agents, :liveview, :dropped],
      %{},
      %{
        conversation_id: current_conversation_id(socket),
        event: dropped_event_name(other),
        payload: other
      }
    )

    {:noreply, socket}
  end

  # ── Private helpers ─────────────────────────────────────────────────────

  # Empty state: start_or_resume/3 creates the record. The LiveView
  # subscribes only after success — the context never subscribes the
  # caller — then patches to the new conversation's url so handle_params'
  # self-patch clause (above) sees it and skips the reload.
  defp send_message(socket, message, nil) do
    current_user = socket.assigns.current_user

    case Conversations.start_or_resume(current_user.id, message, nil) do
      {:ok, record} ->
        JidoMarketAgents.subscribe(record.id)

        {:noreply,
         socket
         |> assign_sent(record, message)
         |> refresh_sidebar()
         |> push_patch(to: ~p"/business-discovery/evaluate/#{record.id}")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Unable to send your message. Please try again.")}
    end
  end

  # An already-selected conversation: handle_params already subscribed this
  # LiveView to its topic, so no subscribe happens here. Re-subscribing on
  # every send would stack duplicate registrations (phoenix_pubsub 2.2.0
  # `subscribe/3` is a bare `Registry.register`).
  defp send_message(socket, message, %Conversations.Record{id: id} = record) do
    current_user = socket.assigns.current_user

    case Conversations.start_or_resume(current_user.id, message, id) do
      {:ok, _record} ->
        {:noreply, assign_sent(socket, record, message)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Unable to send your message. Please try again.")}
    end
  end

  # D1: optimistic render only — the LiveView never persists this message
  # itself. The GenServer is the sole writer of record; this entry is
  # replaced wholesale the moment the authoritative `payload.messages`
  # arrives (S16.1, S16.4).
  defp assign_sent(socket, record, message) do
    optimistic = %{role: "user", content: message}

    socket
    |> assign(:conversation, record)
    |> assign(:messages, socket.assigns.messages ++ [optimistic])
    |> assign(:phase, :buffering)
    |> assign(:error, nil)
    |> assign(:rate_limited, nil)
  end

  defp clear_conversation(socket) do
    socket
    |> unsubscribe_from_current()
    |> assign(:conversation, nil)
    |> assign(:messages, [])
    |> assign(:phase, nil)
    |> assign(:error, nil)
    |> assign(:rate_limited, nil)
  end

  # Records that a broadcast was actually matched and applied. Paired with
  # `broadcast.emitted`, this closes the loop: emitted-without-handled is a
  # dropped response, handled-without-render is a template problem.
  defp handled(socket, event) do
    AgentTelemetry.emit(
      [:fullstack, :jido_market_agents, :liveview, :handled],
      %{message_count: length(socket.assigns.messages)},
      %{
        conversation_id: current_conversation_id(socket),
        event: event,
        phase: socket.assigns.phase
      }
    )

    socket
  end

  defp current_conversation_id(socket) do
    case socket.assigns[:conversation] do
      %Conversations.Record{id: id} -> id
      _ -> nil
    end
  end

  # A broadcast is a `{event, payload}` tuple in every producing path; the
  # name is extracted for the trace without assuming the rest of the shape,
  # since an unmatched message is by definition of unknown shape.
  defp dropped_event_name({event, _payload}) when is_atom(event), do: event
  defp dropped_event_name(_other), do: :unknown

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

  # Messages reach the template in THREE shapes, not two:
  #
  #   1. persisted `Conversations.Message` structs, loaded on selection —
  #      `role` is a `:string` field (`conversations/message.ex:21`), so
  #      `"user"` / `"assistant"`;
  #   2. the plain optimistic map assigned in the "send" event (D1), which
  #      uses the string `"user"` by construction (`handle_event("send")`);
  #   3. the `Conversation` GenServer's IN-MEMORY maps, which use ATOM
  #      roles (`%{role: :user}`, `conversation.ex:323`/`352`). `broadcast/3`
  #      puts `state.messages` on the wire verbatim
  #      (`conversation.ex:497`), so every authoritative PubSub payload
  #      carries atoms, not strings.
  #
  # Shape 3 is the live path — the one the user actually watches. Comparing
  # an atom `:user` against the template's `"user"` is always false, so
  # before this normalization every broadcast message, user and assistant
  # alike, fell through to the assistant branch and rendered left-aligned.
  # The role is normalized to a string here, at the single point the
  # template reads it, so the template keeps one comparison and the three
  # producers stay free to use whichever shape is natural for them.
  @doc false
  def message_role(%{role: role}), do: normalize_role(role)
  def message_role(message) when is_map(message), do: normalize_role(Map.get(message, "role"))

  defp normalize_role(role) when is_atom(role) and not is_nil(role), do: Atom.to_string(role)
  defp normalize_role(role), do: role

  @doc false
  def message_content(%{content: content}), do: content
  def message_content(message) when is_map(message), do: Map.get(message, "content")
end
