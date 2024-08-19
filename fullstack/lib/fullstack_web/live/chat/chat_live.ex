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
    <div class="h-screen flex-1">
      <.header>
        Hooah!<br /> This is your identifier:
        <span class="bg-slate-200 p-2 rounded-lg"><%= assigns.tmp_id %></span>
      </.header>
      <div class="h-2/3 max-h-2/3 pt-8 pb-4">
        <div
          class="h-full "
          style="overflow: scroll;  max-height: 100%;  display: flex;  flex-direction: column-reverse;-ms-overflow-style: none;scrollbar-width:none"
        >
          <div
            phx-update="append"
            id="messages"
            class="height:500px;width: 100%;  color: #001f3f;  background: #3D9970;padding: 5px"
          >
            <div
              :for={message <- @messages}
              id={"m-#{message.id}"}
              class={"flex mb-4 " <> if message.from == @tmp_id, do: "justify-end", else: ""}
            >
              <.message_line message={message} tmp_id={@tmp_id}></.message_line>
            </div>
          </div>
        </div>
      </div>
      <section class="fixed bottom-0 left-0 right-0 w-full p-4">
        <p class="text-gray-500">
          <%= @users_count %> users with <%= @connections %> connections
        </p>
        <p :if={@typing_users != ""} class="text-gray-500">
          <%= @typing_users %> typing...
        </p>
        <span class="text-gray-500"></span>
        <.simple_form for={@form} phx-change="change" phx-submit="save">
          <.input
            field={@form[:message]}
            value={@text_value}
            phx-mounted={JS.focus()}
            placeholder="Say something!"
          />
        </.simple_form>
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
    <div class="flex justify-end mb-4 cursor-pointer">
      <div class="flex max-w-40 bg-indigo-500 text-white rounded-lg p-3 gap-3">
        <p class="text-white"><%= assigns.message.text %></p>
      </div>
    </div>
    """
  end

  def message_line(%{message: %{from: "Fullstack"}} = assigns) do
    ~H"""
    <div class="flex mb-4 cursor-pointer">
      <div class="flex max-w-96 bg-white rounded-lg p-3 gap-3">
        <p class="bg-slate-100 text-gray p-2"><%= assigns.message.text %></p>
      </div>
    </div>
    """
  end

  def message_line(assigns) do
    ~H"""
    <div class="flex mb-4 cursor-pointer">
      <div class="max-w-2/3 rounded-lg flex items-center justify-center px-2 mr-2 bg-slate-400 text-gray-700">
        <%= assigns.message.from %>:
      </div>
      <div class="flex max-w-96 bg-white rounded-lg p-3 gap-3">
        <p class="text-gray-700"><%= assigns.message.text %></p>
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

  defp get_form(params, action \\ :subimt) do
    params
    |> get_changeset()
    |> Map.put(:action, action)
    |> to_form(as: :form)
  end

  defp get_changeset(params) do
    data = %{}
    types = %{question: :string}

    {data, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:question])
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
