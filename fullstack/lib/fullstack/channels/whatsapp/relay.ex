defmodule Fullstack.Channels.WhatsApp.Relay do
  @moduledoc """
  Forwards one conversation's assistant replies to a WhatsApp sender.

  The `Conversation` GenServer only broadcasts on PubSub; this process is the
  WhatsApp listener for one conversation, as the LiveView is the browser's.
  Every broadcast carries the full message list, so the relay sends the
  assistant messages after the ones it has already handled (counted, since
  the list only grows) and never sends one twice.

  Plain text is sent as is, split into chunks of at most 1600 characters
  (Twilio's WhatsApp limit). A stage result (stored as JSON for the web UI)
  becomes a short notice with a one-time login link to the conversation,
  built by the `:login_url_fun` the caller passes in.

  Lifecycle: started by `ensure_started/2` under the conversation
  `DynamicSupervisor` as a temporary child and registered as
  `{:whatsapp_relay, id}` in the conversation registry. It stops after
  `:idle_timeout_ms` (default 30 minutes) without activity; the next inbound
  message starts it again. Replies committed while no relay runs are not
  sent; the web view still shows them.

  Order matters: start the relay before enqueueing the inbound message, so
  the reply's broadcast cannot happen before the subscription.
  """
  use GenServer, restart: :temporary
  require Logger

  alias Fullstack.Channels.Twilio
  alias Fullstack.JidoMarketAgents.{Conversation, ConversationSupervisor}

  @registry Fullstack.JidoMarketAgents.ConversationRegistry
  @default_idle_timeout_ms :timer.minutes(30)
  @max_chunk 1600

  @stage_results %{
    "market_research" => "market research",
    "business_analysis" => "business analysis",
    "systems_strategy" => "systems strategy",
    "tech_strategy" => "technology strategy"
  }

  @rate_limited_text "You are sending messages faster than I can process them. " <>
                       "I will answer as soon as possible."

  @doc """
  Returns the relay of `conversation_id`, starting it when none runs.

  Options: `:to` (the sender's WhatsApp address), `:login_url_fun` (arity 1,
  receives the conversation id, returns a login URL) and optionally
  `:idle_timeout_ms`. A running relay keeps its options and has its idle
  timer reset.
  """
  @spec ensure_started(Ecto.UUID.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def ensure_started(conversation_id, opts) do
    case Registry.lookup(@registry, key(conversation_id)) do
      [{pid, _}] ->
        GenServer.cast(pid, :touch)
        {:ok, pid}

      [] ->
        start(conversation_id, opts)
    end
  end

  defp start(conversation_id, opts) do
    spec = {__MODULE__, Keyword.put(opts, :conversation_id, conversation_id)}

    case DynamicSupervisor.start_child(ConversationSupervisor, spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  def start_link(opts) do
    id = Keyword.fetch!(opts, :conversation_id)
    GenServer.start_link(__MODULE__, opts, name: {:via, Registry, {@registry, key(id)}})
  end

  defp key(conversation_id), do: {:whatsapp_relay, conversation_id}

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :conversation_id)

    # Baseline before subscribing: a reply committed in between is then
    # sent with the next broadcast instead of being counted as handled.
    sent = id |> current_messages() |> assistant_count()
    :ok = Conversation.subscribe(id)

    state = %{
      conversation_id: id,
      to: Keyword.fetch!(opts, :to),
      login_url_fun: Keyword.fetch!(opts, :login_url_fun),
      idle_timeout_ms: Keyword.get(opts, :idle_timeout_ms, @default_idle_timeout_ms),
      sent: sent
    }

    {:ok, state, state.idle_timeout_ms}
  end

  defp current_messages(id) do
    case Conversation.list_messages(id) do
      {:ok, messages} -> messages
      {:error, _} -> []
    end
  catch
    :exit, _ -> []
  end

  @impl true
  def handle_cast(:touch, state), do: {:noreply, state, state.idle_timeout_ms}

  @impl true
  def handle_info({:rate_limited, _payload}, state) do
    deliver(state, @rate_limited_text)
    {:noreply, state, state.idle_timeout_ms}
  end

  def handle_info({_event, %{messages: messages}}, state) when is_list(messages) do
    assistants = Enum.filter(messages, &assistant?/1)

    assistants
    |> Enum.drop(state.sent)
    |> Enum.each(&deliver_message(state, &1))

    {:noreply, %{state | sent: length(assistants)}, state.idle_timeout_ms}
  end

  def handle_info(:timeout, state), do: {:stop, :normal, state}

  def handle_info(_message, state), do: {:noreply, state, state.idle_timeout_ms}

  defp assistant_count(messages), do: Enum.count(messages, &assistant?/1)

  defp assistant?(message), do: field(message, :role) in [:assistant, "assistant"]

  defp deliver_message(state, message) do
    type = message |> field(:metadata) |> field(:type) |> to_string_or_nil()

    case Map.fetch(@stage_results, type) do
      {:ok, label} ->
        url = state.login_url_fun.(state.conversation_id)

        deliver(
          state,
          "Your #{label} is ready. Open it here (single-use link, valid 15 minutes): #{url}"
        )

      :error ->
        message |> field(:content) |> text() |> chunk() |> Enum.each(&deliver(state, &1))
    end
  end

  defp deliver(_state, ""), do: :ok

  defp deliver(state, body) do
    case Twilio.send_whatsapp(state.to, body) do
      {:ok, _sid} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "WhatsApp relay could not send a message for conversation " <>
            "#{state.conversation_id}: #{inspect(reason)}"
        )
    end
  end

  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, to_string(key)))
  defp field(_other, _key), do: nil

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value), do: to_string(value)

  defp text(content) when is_binary(content), do: content
  defp text(_content), do: ""

  @doc false
  # Splits at the last whitespace inside each window so words stay whole;
  # a window without whitespace is cut at the limit.
  def chunk(text) do
    text = String.trim(text)

    if String.length(text) <= @max_chunk do
      [text]
    else
      head = String.slice(text, 0, @max_chunk)

      cut =
        case :binary.matches(head, [" ", "\n", "\t"]) do
          [] -> byte_size(head)
          matches -> matches |> List.last() |> elem(0)
        end

      cut = if cut == 0, do: byte_size(head), else: cut
      <<first::binary-size(cut), rest::binary>> = text
      [String.trim(first) | chunk(rest)]
    end
  end
end
