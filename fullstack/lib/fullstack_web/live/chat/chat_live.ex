defmodule FullstackWeb.ChatLive do
  use FullstackWeb, :live_view
  @cache :chat

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      FullstackWeb.Endpoint.subscribe("chat")
    end

    tmp_id = session |> Map.get("_csrf_token") |> String.downcase() |> String.slice(1..12)

    {
      :ok,
      socket
      |> assign(:tmp_id, tmp_id)
      |> assign(:form, to_form(%{"message" => ""}, as: :form))
      |> assign(:messages, load_messages()),
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
          <span class="bg-slate-100 text-gray p-2"><%= message.from %>:</span> <%= message.text %>
        </p>
      </section>
      <section class="">
        <.simple_form for={@form} phx-submit="save">
          <.input field={@form[:message]} placeholder="Say something!" />
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
  def handle_event("save", %{"form" => %{"message" => message}}, socket) do
    new_message = %{
      id: :rand.uniform(100),
      from: socket.assigns.tmp_id,
      text: message
    }

    FullstackWeb.Endpoint.broadcast("chat", "new_message", new_message)
    save_message(new_message)

    {:noreply,
     assign(socket, :messages, [new_message])
     |> assign(:form, to_form(%{"message" => ""}, as: :form))}
  end

  def load_messages() do
    messages =
      case Cachex.get(@cache, "chat") do
        {:ok, messages} when is_list(messages) ->
          Enum.reverse(messages)

        {:ok, nil} ->
          Cachex.put(@cache, "chat", [])
          []
      end

    [%{id: :rand.uniform(100), from: "Fullstack", text: "Welcome!"} | messages]
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
      {:ok, previous_msg} = Cachex.get(cache, "chat")
      messages = [message | previous_msg] |> Enum.take(11)
      Cachex.put!(cache, "chat", messages)
      messages
    end)
  end
end
