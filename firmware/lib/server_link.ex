defmodule Firmware.ServerLink do
  @moduledoc """
  A socket client for connecting to that other Phoenix server

  Periodically sends pings and asks the other server for its metrics.
  """

  use Slipstream,
    restart: :temporary

  require Logger
  @endpoint "ws://127.0.0.1:4000/socket/websocket?"
  @mac_addr "11:22:33:44:55:66"
  @topic "group:#{String.replace(@mac_addr, ":", "")}"
  @interval for x <- 500..60_000//500, do: x

  def start_link(args) do
    Slipstream.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl Slipstream
  def init(config) do
    IO.inspect(config)

    opts = [
      uri: "#{@endpoint}mac_addr=#{@mac_addr}",
      reconnect_after_msec: [1_000, 5_000, 10_000],
      rejoin_after_msec: [1_000, 3_000, 5_000, 10_000]
    ]

    {:ok, connect!(opts), {:continue, :start_ping}}
  end

  @impl Slipstream
  def handle_continue(:start_ping, socket) do
    timer = :timer.send_interval(10_000, self(), :ping_server)

    {:noreply, assign(socket, :ping_timer, timer)}
  end

  @impl Slipstream
  def handle_connect(socket) do
    {:ok, join(socket, @topic)}
  end

  @impl Slipstream
  def handle_join(@topic, _join_response, socket) do
    # an asynchronous push with no reply:
    push(socket, @topic, "handshake", %{:hello => :world})

    {:ok, socket}
  end

  @impl Slipstream
  def handle_info(:ping_server, socket) do
    # we will asynchronously receive a reply and handle it in the
    # handle_reply/3 implementation below
    {:ok, ref} = push(socket, @topic, "ping", %{format: "json"})

    {:noreply, assign(socket, :last_ping, ref)}
  end

  @impl Slipstream
  def handle_reply(ref, response, socket) do
    Logger.info("Handling reply #{inspect(ref)}")
    Logger.info("Handling reply assings #{inspect(socket.assigns.last_ping)}")
    # if ref == socket.assigns.last_ping do
    #   :ok = Firmware.MetricsPublisher.publish(metrics)
    # end

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
