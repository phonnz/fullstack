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
      |> assign(:messages, load_messages())
      |> assign(:users_count, get_users_count()),
      temporary_assigns: [messages: []]
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.header>
        Hooah! This is your identifier:
        <span class="bg-slate-200 p-2 rounded-sm"><%= assigns.tmp_id %></span>
      </.header>
      <section phx-update="append" id="messages-list">
        <p :for={message <- @messages} id={"m-#{message.id}"} class="border p-4 italic rounded-lg">
          <.message_line message={message}></.message_line>
        </p>
      </section>
      <section class="">
        <.simple_form for={@form} phx-change="change" phx-submit="save">
          <.input
            field={@form[:message]}
            value={@text_value}
            phx-mounted={JS.focus()}
            placeholder="Say something!"
          />
        </.simple_form>
      </section>
      <span><%= @users_count %> users connected</span>
    </div>
    """
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(%{event: "new_message", payload: income_message}, socket) do
    {:noreply, assign(socket, messages: [income_message])}
  end

  @impl true
  def handle_info(%{event: "presence_diff", payload: payload}, socket) do
    {:noreply, assign(socket, :users_count, get_users_count())}
  end

  @impl true
  def handle_event("change", %{"form" => %{"message" => value}}, socket) do
    socket = assign(socket, :text_value, value)
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

    {:noreply,
     socket
     |> assign(:messages, [new_message])
     |> assign(:text_value, nil)}
  end

  def message_line(%{message: %{from: "Fullstack"}} = assigns) do
    ~H"""
    <span class="bg-slate-100 text-gray p-2"><%= assigns.message.text %></span>
    """
  end

  def message_line(assigns) do
    ~H"""
    <span class="bg-slate-100 text-gray p-2">
      <%= assigns.message.from %>:
    </span>
    <%= assigns.message.text %>
    """
  end

  defp tmp_id(%{"_csrf_token" => token}) do
    tmpid = token |> String.downcase() |> String.slice(1..14)

    Presence.track(self(), "chat:presence", "main", %{
      tmp_id: tmpid,
      online_at: DateTime.utc_now()
    })

    broadcast_message(%{
      id: :rand.uniform(100),
      from: "Fullstack",
      text: "#{tmpid} joined the room!"
    })

    tmpid
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

  defp get_users_count do
    case Presence.list("chat:presence") do
      %{"main" => %{metas: items}} ->
        Enum.count(items)

      _other ->
        0
    end
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
end
