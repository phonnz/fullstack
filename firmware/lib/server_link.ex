defmodule Firmware.ServerLink do
  @moduledoc """
  A socket client for connecting to that other Phoenix server

  Periodically sends pings and asks the other server for its metrics.
  """
  use Slipstream,
    restart: :temporary

  require Logger

  @host "ws://127.0.0.1:"
  @topic "group:main"
  @default_mac "00:00:00:00:00"
  @core_topic "grabngo:status:"
  @interval for x <- 500..60_000//500, do: x
  @default_args [
    host: @host,
    topic: @topic,
    mac_addr: @default_mac,
    core_topic: @core_topic,
    interva: @interval
  ]
  def start(args \\ @default_args), do: Slipstream.start_link(__MODULE__, args, name: __MODULE__)
  def start_ping, do: send(self(), :start_ping)
  def get_state(_pid), do: GenServer.call(self(), :get_state)

  @impl Slipstream
  def init(args) do
    IO.inspect(args, label: :CONFIG)
    port = Keyword.get(args, :port, "4000")
    mac_addr = Keyword.get(args, :mac_addr)

    host_uri =
      "#{@host}#{port}/socket/websocket?mac_addr=#{mac_addr}" |> IO.inspect(lable: :host_uri)

    opts = [
      uri: host_uri,
      reconnect_after_msec: [1_000, 5_000, 10_000],
      rejoin_after_msec: [1_000, 3_000, 5_000, 10_000]
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
    IO.inspect(socket, label: :socket_connect)

    {:ok,
     join(socket, @topic, %{
       :join_message => "This is a joinning message"
     })}
  end

  @impl Slipstream
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl Slipstream
  def handle_join(@topic, join_response, socket) do
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
        @topic,
        "presence_diff",
        %{"joins" => joins, "leaves" => leaves} = _payload,
        socket
      ) do
    IO.inspect(%{joins: Map.keys(joins), leaves: Map.keys(leaves)}, label: :presence)
    {:ok, socket}
  end

  @impl Slipstream
  def handle_message(
        @topic,
        "presence_state",
        presences,
        socket
      ) do
    IO.inspect(Map.keys(presences), label: :presence)
    {:ok, socket}
  end

  @impl Slipstream
  def handle_message(@topic, event, message, socket) do
    Logger.error(
      "Was not expecting a push from the server. Heard: " <>
        inspect({@topic, event, message})
    )

    {:ok, socket}
  end

  @impl Slipstream
  def handle_disconnect(_reason, socket) do
    :timer.cancel(socket.assigns.ping_timer)

    {:stop, :normal, socket}
  end
end
