defmodule Firmware.ServerLink do
  @moduledoc """
  A socket client for connecting to that other Phoenix server

  Periodically sends pings and asks the other server for its metrics.
  """

  use Slipstream,
    restart: :temporary

  require Logger
  @endpoint "ws://127.0.0.1:4000/socket/websocket?"
  @mac_addr "e4:5f:01:a1:aa:76"
  @main_topic "group:main"
  @topic "group:#{String.replace(@mac_addr, ":", "")}"
  @interval for x <- 500..60_000//500, do: x

  def start(), do: start_link(%{})
  def start_ping, do: send(self(), :start_ping)
  def get_state(pid), do: GenServer.call(self(), :get_state)

  def disconnect() do
    IO.puts("trying to disconnect")

    {:ok, send(self(), :disconnect)}
  end

  def start_link(args) do
    Slipstream.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl Slipstream
  def init(config) do
    IO.inspect(config, label: :CONFIG)

    opts = [
      uri: "#{@endpoint}mac_addr=#{@mac_addr}",
      reconnect_after_msec: [1_000, 5_000, 10_000],
      rejoin_after_msec: [1_000, 3_000, 5_000, 10_000]
    ]

    {:ok, connect!(opts)}
  end

  @impl Slipstream
  def handle_connect(socket) do
    {:ok, join(socket, @main_topic, %{:join_message => "This is a joinning message"})}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl Slipstream
  def handle_join(@main_topic, join_response, socket) do
    Logger.info("Join_response => #{inspect(join_response)}")
    # an asynchronous push with no reply:
    #    push(socket, @topic, "handshake", %{:hello => :world})
    something = send(self(), :start_ping)
    IO.inspect("sent interval #{inspect(something)}")
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
  def handle_info(:disconnect, socket) do
    IO.inspect("Discotnecct")
    result = :timer.cancel(socket.assigns.ping_timer)
    IO.inspect(result, label: :RESULT)

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
