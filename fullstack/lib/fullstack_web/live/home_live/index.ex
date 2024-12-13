defmodule FullstackWeb.HomeLive.Index do
  alias Fullstack.Financial
  use FullstackWeb, :live_view

  alias Fullstack.{Customers, Financial}
  alias Fullstack.Services.Counters
  alias Fullstack.Servers.Generators.Phrases
  import FullstackWeb.CustomComponents

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Fullstack.PubSub, "centralized_counter")
      Phoenix.PubSub.subscribe(Fullstack.PubSub, "transactions")
      Phoenix.PubSub.subscribe(Fullstack.PubSub, "phrases")
    end

    socket =
      socket
      |> assign(:tmp_id, tmp_id(session))
      |> assign(:feature, random_feature())
      |> assign(:logos, list_logos())
      |> assign(:transactions_count, transactions_count())
      |> assign(:customers_count, customers_count())
      |> assign(:devices_count, 0)
      |> assign(:local, 0)
      |> assign(:identified, 0)
      |> assign(:centralized, init_counter(:centralized))
      |> assign(:phrase, "")
      |> start_or_connect_phrases_service()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("inc", %{"id" => "local"}, socket) do
    {:noreply, update(socket, :local, &(&1 + 1))}
  end

  @impl true
  def handle_event("inc", %{"id" => counter_id}, socket) do
    {_counter, value} = increase(counter_id, socket)

    {:noreply, assign(socket, String.to_atom(counter_id), value)}
  end

  @impl true
  def handle_event("dec", %{"id" => counter_id}, socket) do
    {_counter, value} = decrease(counter_id, socket)
    {:noreply, assign(socket, String.to_atom(counter_id), value)}
  end

  @impl true
  def handle_event("crash", _, socket) do
    raise "Crashing the server in purpouse"
    {:noreply, socket}
  end

  @impl true
  def handle_event("destroy", _, socket) do
    Counters.destroy()
    {:noreply, LiveToast.put_toast(socket, :error, "Centralized counter was destroyed.")}
  end

  @impl true
  def handle_info({:set_identified_counter, tmp_id}, socket) do
    {:noreply, assign(socket, :identified, init_counter(:identified, String.to_atom(tmp_id)))}
  end

  @impl true
  def handle_info(%{event: "new_transaction"}, socket) do
    {:noreply, assign(socket, :transactions_count, socket.assigns.transactions_count + 1)}
  end

  @impl true
  def handle_info(%{event: "updated_counter", payload: {counter, value}}, socket) do
    case Atom.to_string(counter) do
      "centralized" ->
        {:noreply, assign(socket, counter, value)}

      counter_name when counter_name == socket.assigns.tmp_id ->
        {:noreply, assign(socket, :identified, value)}

      counter_name when is_binary(counter_name) ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({action, value}, socket) do
    current_phrase = socket.assigns.phrase

    case Atom.to_string(action) do
      "new_string" ->
        {:noreply, assign(socket, :phrase, value)}

      "new_char" ->
        {:noreply, assign(socket, :phrase, current_phrase <> value)}
    end
  end

  defp start_or_connect_phrases_service(socket) do
    if connected?(socket) do
      case Phrases.start_link([]) do
        {:ok, pid} ->
          "Started server #{inspect(pid)}"
          assign(socket, :phrases_id, pid)

        {:error, {:already_started, pid}} ->
          "Atached to server #{inspect(pid)}"
          # Phrases.connected()
          assign(socket, :phrases_id, pid)
      end
    else
      socket
    end
  end

  defp init_counter(counter_id, user_id \\ :none)
       when counter_id in [:identified, :centralized] do
    {_counter, value} = Counters.get(user_id, counter_id)
    value
  end

  defp increase(counter_id, socket) when counter_id in ["identified", "centralized"] do
    Counters.increase(String.to_atom(socket.assigns.tmp_id), String.to_atom(counter_id))
  end

  defp decrease(counter_id, socket) when counter_id in ["identified", "centralized"] do
    Counters.decrease(String.to_atom(socket.assigns.tmp_id), String.to_atom(counter_id))
  end

  defp decrease(counter_id, socket) when counter_id == "local" do
    counter = String.to_existing_atom(counter_id)

    value =
      socket
      |> get_in([Access.key!(:assigns), counter])
      |> Kernel.+(-1)

    {counter, value}
  end

  defp tmp_id(%{"_csrf_token" => token}) do
    tmp_id = token |> String.downcase() |> String.slice(1..14)
    send(self(), {:set_identified_counter, tmp_id})
    tmp_id
  end

  defp tmp_id(_session), do: nil

  defp random_feature(), do: "..."
  defp list_logos, do: Fullstack.EcosystemLogos.list()
  defp transactions_count(), do: Financial.transactions_count()
  defp customers_count(), do: Customers.customers_count()

  attr :logo, Fullstack.EcosystemLogo, required: true

  def ecosystem_logo(assigns) do
    ~H"""
    <.link href={@logo.link} target="_blank">
      <img id={@logo.id} class="ecosystem-logo" src={@logo.logo_path} alt={@logo.name} />
    </.link>
    """
  end
end
