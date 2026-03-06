defmodule FullstackWeb.ChannelsChatLive do
  @moduledoc """
  LiveView for channels-based chat with multi-channel support.

  Features:
  - In-memory channel persistence using Cachex
  - 50 message limit per channel
  - Typing indicators via Phoenix.Presence
  - Rate limiting (30 messages per 60 seconds)
  - Three-column layout: channels list, messages, participants
  - Independent scrolling for each column
  """

  use FullstackWeb, :live_view
  alias Phoenix.Presence
  alias FullstackWeb.ChatPresence, as: Presence

  @cache :chat
  @max_messages 50
  @rate_limit_count 30
  @rate_limit_window_seconds 60

  # Public API

  @impl true
  @doc """
  Mounts the LiveView and initializes the socket state.

  Subscribes to the global channels list topic and loads existing channels.
  Initializes streams for channels, messages, and participants.
  """
  def mount(_params, session, socket) do
    socket_id = tmp_id(session)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Fullstack.PubSub, "channels:list")
    end

    {
      :ok,
      socket
      |> assign(:socket_id, socket_id)
      |> assign(:current_channel_id, nil)
      |> assign(:current_channel_owner, nil)
      |> assign(:message_input, "")
      |> assign(:typing_users, %{})
      |> stream(:channels, load_channels(), dom_id: &"channel-#{&1.id}")
      |> stream(:messages, [], dom_id: &"msg-#{&1.id}")
      |> stream(:participants, [], dom_id: &"participant-#{&1.socket_id}"),
      temporary_assigns: [messages: []]
    }
  end

  # Event Handlers

  @doc """
  Handles LiveView events.

  - "create_channel": Creates a new channel with a secure ID and broadcasts to all users
  - "select_channel": Selects a channel, subscribes to its topics, and loads messages/participants
  - "send_message": Sends a message to the current channel with rate limiting
  - "typing": Updates typing status via Phoenix.Presence
  """
  @impl true
  def handle_event("create_channel", _params, socket) do
    channel = %{
      id: generate_channel_id(),
      owner: socket.assigns.socket_id,
      created_at: DateTime.utc_now(),
      participant_count: 0
    }

    save_channel(channel)

    Phoenix.PubSub.broadcast(
      Fullstack.PubSub,
      "channels:list",
      %{event: "channel_created", payload: channel}
    )

    {:noreply, stream_insert(socket, :channels, channel, at: 0)}
  end

  def handle_event("select_channel", %{"channel_id" => channel_id}, socket) do
    socket = unsubscribe_from_current_channel(socket)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Fullstack.PubSub, "channel:#{channel_id}:messages")
      Phoenix.PubSub.subscribe(Fullstack.PubSub, "channel:#{channel_id}:presence")
    end

    messages = load_messages(channel_id)
    participants = load_participants(channel_id)
    channel = find_channel(channel_id)

    Presence.track(self(), "channel:#{channel_id}:presence", socket.assigns.socket_id, %{
      typing: false,
      joined_at: DateTime.utc_now()
    })

    socket =
      socket
      |> assign(:current_channel_id, channel_id)
      |> assign(:current_channel_owner, channel[:owner])
      |> assign(:message_input, "")
      |> assign(:typing_users, %{})
      |> stream(:messages, messages, reset: true)
      |> stream(:participants, participants, reset: true)

    {:noreply, socket}
  end

  def handle_event("send_message", %{"message" => message}, socket)
      when byte_size(message) > 0 do
    channel_id = socket.assigns.current_channel_id

    if is_nil(channel_id) do
      {:noreply, socket}
    else
      case check_rate_limit(socket.assigns.socket_id) do
        :ok ->
          new_message = %{
            id: Ecto.UUID.generate(),
            channel_id: channel_id,
            from: socket.assigns.socket_id,
            text: String.trim(message),
            timestamp: DateTime.utc_now()
          }

          save_message(channel_id, new_message)
          update_participant(channel_id, socket.assigns.socket_id, :increment_message_count)

          Phoenix.PubSub.broadcast(
            Fullstack.PubSub,
            "channel:#{channel_id}:messages",
            %{event: "new_message", payload: new_message}
          )

          Presence.update(
            self(),
            "channel:#{channel_id}:presence",
            socket.assigns.socket_id,
            %{typing: false}
          )

          {:noreply,
           socket
           |> assign(:message_input, "")
           |> stream_insert(:messages, new_message, at: 0)}

        {:error, :rate_limited} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Slow down! Max #{@rate_limit_count} messages per #{@rate_limit_window_seconds} seconds."
           )}
      end
    end
  end

  def handle_event("send_message", _params, socket), do: {:noreply, socket}

  def handle_event("typing", %{"message" => value}, socket) do
    channel_id = socket.assigns.current_channel_id

    if channel_id do
      typing = value != ""

      Presence.update(
        self(),
        "channel:#{channel_id}:presence",
        socket.assigns.socket_id,
        %{typing: typing}
      )
    end

    {:noreply, assign(socket, :message_input, value)}
  end

  # PubSub Message Handlers

  @doc """
  Handles PubSub messages.

  - %{event: "channel_created"}: New channel creation broadcasts
  - %{event: "new_message"}: New message broadcasts
  - %{event: "presence_diff"}: Presence diff updates for typing indicators
  """
  @impl true
  def handle_info(%{event: "channel_created", payload: channel}, socket) do
    {:noreply, stream_insert(socket, :channels, channel, at: 0)}
  end

  def handle_info(%{event: "new_message", payload: message}, socket) do
    if message.channel_id == socket.assigns.current_channel_id do
      participants = load_participants(message.channel_id)

      {:noreply,
       socket
       |> stream_insert(:messages, message, at: 0)
       |> stream(:participants, participants, reset: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(%{event: "presence_diff"}, socket) do
    channel_id = socket.assigns.current_channel_id

    if channel_id do
      typing_users = find_typing_users(channel_id, socket.assigns.socket_id)
      {:noreply, assign(socket, :typing_users, typing_users)}
    else
      {:noreply, socket}
    end
  end

  # Private Helpers

  @spec tmp_id(map()) :: String.t() | nil
  defp tmp_id(%{"_csrf_token" => token}) do
    token |> String.downcase() |> String.slice(1..14)
  end

  defp tmp_id(_session), do: nil

  @spec generate_channel_id() :: String.t()
  defp generate_channel_id do
    timestamp = System.system_time(:millisecond)
    random_hash = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    "ch_#{timestamp}_#{random_hash}"
  end

  @spec save_channel(map()) :: :ok
  defp save_channel(channel) do
    Cachex.transaction!(@cache, ["channels:list"], fn cache ->
      channels =
        case Cachex.get(cache, "channels:list") do
          {:ok, existing} when is_list(existing) -> [channel | existing]
          {:ok, nil} -> [channel]
        end

      Cachex.put!(cache, "channels:list", channels)
    end)

    :ok
  end

  @spec load_channels() :: list(map())
  defp load_channels do
    case Cachex.get(@cache, "channels:list") do
      {:ok, channels} when is_list(channels) -> channels
      {:ok, nil} -> []
    end
  end

  @spec find_channel(String.t()) :: map() | nil
  defp find_channel(channel_id) do
    load_channels()
    |> Enum.find(fn channel -> channel.id == channel_id end)
  end

  @spec save_message(String.t(), map()) :: :ok
  defp save_message(channel_id, message) do
    key = "channel:#{channel_id}:messages"

    Cachex.transaction!(@cache, [key], fn cache ->
      messages =
        case Cachex.get(cache, key) do
          {:ok, existing} when is_list(existing) ->
            [message | existing] |> Enum.take(@max_messages)

          {:ok, nil} ->
            [message]
        end

      Cachex.put!(cache, key, messages)
    end)

    :ok
  end

  @spec load_messages(String.t()) :: list(map())
  defp load_messages(channel_id) do
    key = "channel:#{channel_id}:messages"

    case Cachex.get(@cache, key) do
      {:ok, messages} when is_list(messages) -> messages
      {:ok, nil} -> []
    end
  end

  @spec update_participant(String.t(), String.t(), atom()) :: :ok
  defp update_participant(channel_id, socket_id, action) do
    key = "channel:#{channel_id}:participants"

    Cachex.transaction!(@cache, [key], fn cache ->
      participants =
        case Cachex.get(cache, key) do
          {:ok, existing} when is_map(existing) -> existing
          {:ok, nil} -> %{}
        end

      updated_participants =
        case action do
          :increment_message_count ->
            Map.update(
              participants,
              socket_id,
              %{socket_id: socket_id, joined_at: DateTime.utc_now(), message_count: 1},
              fn participant ->
                Map.update(participant, :message_count, 1, &(&1 + 1))
              end
            )
        end

      Cachex.put!(cache, key, updated_participants)
    end)

    :ok
  end

  @spec load_participants(String.t()) :: list(map())
  defp load_participants(channel_id) do
    key = "channel:#{channel_id}:participants"

    case Cachex.get(@cache, key) do
      {:ok, participants} when is_map(participants) ->
        participants
        |> Map.values()
        |> Enum.sort_by(& &1.message_count, :desc)

      {:ok, nil} ->
        []
    end
  end

  @spec check_rate_limit(String.t()) :: :ok | {:error, :rate_limited}
  defp check_rate_limit(socket_id) do
    key = "rate_limit:#{socket_id}"
    now = System.system_time(:second)

    Cachex.transaction(@cache, [key], fn cache ->
      case Cachex.get(cache, key) do
        {:ok, {count, timestamp}} when now - timestamp < @rate_limit_window_seconds ->
          if count >= @rate_limit_count do
            {:error, :rate_limited}
          else
            Cachex.put!(cache, key, {count + 1, timestamp})
            :ok
          end

        _other ->
          Cachex.put!(cache, key, {1, now})
          :ok
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, _} -> {:error, :rate_limited}
    end
  end

  @spec find_typing_users(String.t(), String.t()) :: map()
  defp find_typing_users(channel_id, current_socket_id) do
    Presence.list("channel:#{channel_id}:presence")
    |> Enum.filter(fn {socket_id, %{metas: [%{typing: typing} | _]}} ->
      socket_id != current_socket_id && typing == true
    end)
    |> Enum.into(%{})
  end

  @spec unsubscribe_from_current_channel(Phoenix.LiveView.Socket.t()) ::
          Phoenix.LiveView.Socket.t()
  defp unsubscribe_from_current_channel(socket) do
    if socket.assigns.current_channel_id do
      channel_id = socket.assigns.current_channel_id

      if connected?(socket) do
        Phoenix.PubSub.unsubscribe(Fullstack.PubSub, "channel:#{channel_id}:messages")
        Phoenix.PubSub.unsubscribe(Fullstack.PubSub, "channel:#{channel_id}:presence")
      end
    end

    socket
  end

  @spec format_timestamp(DateTime.t()) :: String.t()
  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%H:%M")
  end

  @spec truncate_id(String.t(), integer()) :: String.t()
  defp truncate_id(id, length) do
    if String.length(id) > length do
      String.slice(id, 0, length) <> "..."
    else
      id
    end
  end
end
