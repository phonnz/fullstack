defmodule FullstackWeb.ChatLive do
  alias Phoenix.Presence
  use FullstackWeb, :live_view
  alias FullstackWeb.ChatPresence, as: Presence
  @cache :chat

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      FullstackWeb.Endpoint.subscribe("chat")
      Phoenix.PubSub.subscribe(Fullstack.PubSub, "chat:presence")
    end

    {
      :ok,
      socket
      |> assign(:text_value, nil)
      |> assign(:tmp_id, tmp_id(session))
      |> assign(:form, to_form(%{"message" => ""}, as: :form))
      |> assign(:typing_users, [])
      |> assign(:messages, load_messages())
      |> set_users_state(),
      temporary_assigns: [messages: []]
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-screen bg-base-200">
      <.header>
        Hooah!<br /> This is your identifier:
        <span class="badge badge-neutral badge-lg"><%= assigns.tmp_id %></span>
      </.header>
      <div class="flex-1 overflow-y-auto p-4 space-y-2">
        <div phx-update="append" id="messages" class="w-full bg-base-100 text-base-content p-2">
          <div :for={message <- @messages} id={"m-#{message.id}"} class="w-full">
            <.message_line message={message} tmp_id={@tmp_id}></.message_line>
          </div>
        </div>
      </div>
      <section class="shrink-0 border-t border-base-300 bg-base-100 p-4">
        <div class="text-sm text-base-content/60">
          <%= @users_count %> users with <%= @connections %> connections
        </div>
        <p
          :if={@typing_users != ""}
          role="status"
          aria-live="polite"
          class="text-sm text-base-content/60"
        >
          <span class="loading loading-dots loading-xs"></span>
          <%= @typing_users %> typing...
        </p>
        <.form for={@form} phx-change="change" phx-submit="save" class="mt-3 flex gap-2">
          <input
            type="text"
            name={@form[:message].name}
            id={@form[:message].id}
            value={@text_value}
            class="input input-bordered w-full"
            phx-mounted={JS.focus()}
            placeholder="Say something!"
            autocomplete="off"
          />
          <button type="submit" class="btn btn-primary">Send</button>
        </.form>
      </section>
    </div>
    """
  end

  @impl true
  def handle_info(%{event: "new_message", payload: income_message}, socket) do
    {:noreply, assign(socket, messages: [income_message])}
  end

  @impl true
  def handle_info(%{event: "presence_diff"}, socket) do
    {:noreply, set_users_state(socket)}
  end

  @impl true
  def handle_event("change", %{"form" => %{"message" => value}}, socket) do
    typing = if value == "", do: false, else: true

    Presence.update(self(), "chat:presence", socket.assigns.tmp_id, %{
      typing: typing
    })

    socket =
      socket
      |> assign(:typing, typing)
      |> assign(:text_value, value)

    {:noreply, socket}
  end

  @impl true
  def handle_event("save", %{"form" => %{"message" => message}}, socket) do
    new_message = %{
      id: :rand.uniform(100),
      from: socket.assigns.tmp_id,
      text: message
    }

    new_message
    |> save_message
    |> broadcast_message

    Presence.update(self(), "chat:presence", socket.assigns.tmp_id, %{
      typing: false
    })

    {:noreply,
     socket
     |> assign(:messages, [new_message])
     |> assign(:text_value, nil)}
  end

  def message_line(%{message: %{from: sender}, tmp_id: me} = assigns) when sender == me do
    ~H"""
    <div class="chat chat-end">
      <div class="chat-bubble chat-bubble-primary">
        <%= @message.text %>
      </div>
    </div>
    """
  end

  def message_line(%{message: %{from: "Fullstack"}} = assigns) do
    ~H"""
    <div class="chat chat-start">
      <div class="chat-bubble chat-bubble-info">
        <%= @message.text %>
      </div>
    </div>
    """
  end

  def message_line(assigns) do
    ~H"""
    <div class="chat chat-start">
      <div class="chat-header text-xs opacity-50">
        <%= @message.from %>
      </div>
      <div class="chat-bubble">
        <%= @message.text %>
      </div>
    </div>
    """
  end

  defp tmp_id(%{"_csrf_token" => token}) do
    tmp_id = token |> String.downcase() |> String.slice(1..14)

    Presence.track(self(), "chat:presence", tmp_id, %{
      typing: false
    })

    broadcast_message(%{
      id: :rand.uniform(1000),
      from: "Fullstack",
      text: "#{tmp_id} joined the chat!"
    })

    tmp_id
  end

  defp tmp_id(_session), do: nil

  defp broadcast_message(message) do
    FullstackWeb.Endpoint.broadcast("chat", "new_message", message)
  end

  def load_messages() do
    case Cachex.get(@cache, "chat") do
      {:ok, messages} when is_list(messages) ->
        Enum.reverse(messages)

      {:ok, nil} ->
        Cachex.put(@cache, "chat", [])
        []
    end
  end

  defp set_users_state(socket) do
    users = Presence.list("chat:presence")

    socket
    |> assign(:connections, count_total_connections(users))
    |> assign(:users_count, find_uniq_users(users))
    |> assign(:typing_users, find_typing_users(users))
  end

  defp count_total_connections(users) do
    Enum.reduce(users, 0, fn {_user, value}, connections ->
      Enum.count(value.metas) + connections
    end)
  end

  defp find_uniq_users(items) do
    items
    |> Map.keys()
    |> Enum.uniq()
    |> Enum.count()
  end

  defp save_message(message) do
    Cachex.transaction!(@cache, ["chat"], fn cache ->
      messages =
        case Cachex.get(cache, "chat") do
          {:ok, previous_msg} when is_list(previous_msg) ->
            [message | Enum.reverse(previous_msg)]

          {:ok, nil} ->
            Cachex.put(@cache, "chat", [])
            []
        end
        |> Enum.take(11)

      Cachex.put!(cache, "chat", messages)
      :ok
    end)

    message
  end

  defp find_typing_users(connections) do
    connections
    |> Enum.filter(fn {_k, v} ->
      %{metas: [%{typing: typing} | _]} = v
      typing == true
    end)
    |> Enum.into(%{})
    |> Map.keys()
    |> Enum.uniq()
    |> Enum.join(", ")
  end
end
