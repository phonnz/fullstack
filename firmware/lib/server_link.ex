defmodule Firmware.ServerLink do
  @moduledoc """
  A socket client for connecting to that other Phoenix server

  Periodically sends pings and asks the other server for its metrics.
  """
  use Slipstream,
    restart: :temporary

  require Logger

  @host "ws://localhost:"
  @topic "grabngo:status:"
  @interval for x <- 500..60_000//500, do: x

  def start_link(args \\ []),
    do:
      Slipstream.start_link(__MODULE__, args,
        name: String.to_atom("#{__MODULE__}.#{Keyword.get(args, :id, "0")}")
      )

  def start_ping, do: send(self(), :start_ping)
  def get_state(_pid), do: GenServer.call(self(), :get_state)

  @impl Slipstream
  def init(args) do
    port = Keyword.get(args, :port, "4000")
    mac_addr = Keyword.get(args, :mac_addr, "e4:5f:01:a1:aa:76")

    host_uri =
      "#{@host}#{port}/websocket?mac_addr=#{mac_addr}" |> IO.inspect(lable: :host_uri)

    opts = [
      uri: host_uri,
      reconnect_after_msec: [1_000],
      rejoin_after_msec: [1_000]
    ]

    socket =
      connect!(opts)
      |> assign(:port, port)
      |> assign(:vending_id, mac_addr)
      |> assign(:mac_addr, mac_addr)

    {:ok, socket}
  end

  @impl Slipstream
  def handle_connect(socket) do
    IO.inspect(Map.keys(socket))
    IO.inspect(socket, label: :socket_connect)

    {:ok, join(socket, @topic <> socket.assigns.mac_addr, %{})}
  end

  @impl Slipstream
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl Slipstream
  def handle_join(@topic <> _someaddres, join_response, socket) do
    Logger.info("Join_response => #{inspect(join_response)}")
    # an asynchronous push with no reply:
    #    push(socket, @topic, "handshake", %{:hello => :world})
    ## something = send(self(), :start_ping)
    ## IO.inspect("sent interval #{inspect(something)}")
    {:ok, socket}
  end

  @impl Slipstream
  def handle_info(:start_ping, socket) do
    IO.inspect("Start ping")

    timer = :timer.send_interval(10_000, self(), :ping_server)
    IO.inspect(timer, label: :TIMER)
    {:noreply, assign(socket, :ping_timer, timer)}
  end

  @impl Slipstream
  def handle_info(:ping_server, socket) do
    # we will asynchronously receive a reply and handle it in the
    # handle_reply/3 implementation below
    {:ok, ref} = push(socket, @main_topic, "ping", %{format: "json"})

    {:noreply, assign(socket, :last_ping, ref)}
  end

  @impl Slipstream
  def handle_info({:error, reason}, socket) do
    Logger.error("Info error #{inspect(reason)}")

    {:noreply, socket}
  end

  @impl Slipstream
  def handle_info(:disconnect, socket) do
    IO.inspect("Disconect")
    ## result = :timer.cancel(socket.assigns.ping_timer)
    ## IO.inspect(result, label: :RESULT)

    {:ok, socket} =
      socket
      |> disconnect()
      |> await_disconnect()

    {:noreply, socket}
  end

  @impl Slipstream
  def handle_reply(ref, response, socket) do
    Logger.info("Handling reply #{inspect(ref)}")
    Logger.info("Handling reply assings #{inspect(socket.assigns.last_ping)}")
    # if ref == socket.assigns.last_ping do
    #   :ok = Firmware.MetricsPublisher.publish(metrics)
    # end
    Logger.info("Reponse #{inspect(response)}")
    {:ok, socket}
  end

  @impl Slipstream
  def handle_message(
        _topic,
        "presence_diff",
        %{"joins" => joins, "leaves" => leaves} = _payload,
        socket
      ) do
    IO.inspect(%{joins: Map.keys(joins), leaves: Map.keys(leaves)}, label: :presence)
    {:ok, socket}
  end

  @impl Slipstream
  def handle_message(
        _topic,
        "presence_state",
        presences,
        socket
      ) do
    IO.inspect(Map.keys(presences), label: :presence)
    {:ok, socket}
  end

  @impl Slipstream
  def handle_message(_topic, event, message, socket) do
    Logger.error(
      "Was not expecting a push from the server. Heard: " <>
        inspect({@topic, event, message})
    )

    {:ok, socket}
  end

  @impl Slipstream
  def handle_disconnect(_reason, socket) do
    # :timer.cancel(socket.assigns.ping_timer)

    case reconnect(socket) do
      {:ok, socket} -> {:ok, socket}
      {:error, reason} -> {:stop, reason, socket}
    end

    {:stop, :normal, socket}
  end

  @impl Slipstream
  def handle_topic_close(device_topic, reason, socket) do
    Logger.error("MAIN_SERVICES_CONNECTIONS_CHANNEL_DISCONNECT #{inspect(reason)}")
    rejoin(socket, device_topic)
  end

  @impl Slipstream
  def terminate(reason, socket) do
    Logger.error("MAIN_SERVICES_CONNECTIONS_SOCKET_TERMINATE #{inspect(reason)}")

    disconnect(socket)
  end
end
