defmodule Firmware.ServerLink do
  @moduledoc """
  A socket client for connecting to that other Phoenix server

  """
  use Slipstream,
    restart: :transient

  require Logger
  alias Firmware.Control

  @default_args [
    uri: "ws://192.168.1.203:4000/socket/websocket?",
    port: 4000,
    mac_addr: "e4:5f:01:a1:aa:76",
    main_topic: "group:main",
    interval: for(x <- 500..60_000//500, do: x),
    reconnect_after_msec: [1_000, 5_000, 10_000],
    rejoin_after_msec: [1_000, 3_000, 5_000, 10_000]
  ]

  def start(args), do: Slipstream.start_link(__MODULE__, args, name: __MODULE__)
  def start_ping, do: send(self(), :start_ping)
  def get_state(_pid), do: GenServer.call(self(), :get_state)

  def disconnect() do
    IO.puts("trying to disconnect")

    {:ok, send(self(), :disconnect)}
  end

  def start_link(args) do
    args = Keyword.merge(@default_args, args)
    Slipstream.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl Slipstream
  def init(config) do
    Logger.info(config)

    socket =
      connect!(validate_options(config))
      |> assign(:port, Keyword.get(config, :port))
      |> assign(:vending_id, Keyword.get(config, :mac_addr))
      |> assign(:mac_addr, Keyword.get(config, :mac_addr))
      |> assign(:main_topic, "group:main")

    {:ok, socket, {:continue, :start_ping}}
  end

  @impl Slipstream
  def handle_continue(:start_ping, socket) do
    timer = :timer.send_interval(1000, self(), :request_metrics)

    {:noreply, assign(socket, :ping_timer, timer)}
  end

  @impl Slipstream
  def handle_connect(socket) do
    Logger.info("#{inspect(socket.assigns)}")
    IO.inspect(connected?(socket), label: :connection_status)

    {:ok,
     join(socket, socket.assigns.main_topic, %{
       :join_message => "Joining as #{socket.assigns.mac_addr}"
     })}
  end

  @impl Slipstream
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl Slipstream
  def handle_join("group:main", topic, join_response, socket) do
    Logger.info("Join_response => #{inspect(join_response)}")
    # an asynchronous push with no reply:
    push(socket, "group:main", "handshake", %{:hello => :world})
    {:ok, socket}
  end

  @impl Slipstream
  def handle_info(:request_metrics, socket) do
    # we will asynchronously receive a reply and handle it in the
    # handle_reply/3 implementation below
    {:ok, ref} = push(socket, "group:main", "get_metrics", %{format: "json"})

    {:noreply, assign(socket, :metrics_request, ref)}
  end

  @impl Slipstream
  def handle_reply(ref, metrics, socket) do
    if ref == socket.assigns.metrics_request do
      Logger.info("Do some metrics #{inspect(metrics)}")
      # :ok = MyApp.MetricsPublisher.publish(metrics)
    end

    {:ok, socket}
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
    # IO.inspect(result, label: :RESULT)

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
  def handle_message(some_topic, "action", payload, socket) do
    Control.exec(payload)

    {:ok, socket}
  end

  @impl Slipstream
  def handle_message(topic, event, message, socket) do
    Logger.error(
      "Was not expecting a push from the server. Heard: " <>
        inspect({topic, event, message})
    )

    {:ok, socket}
  end

  @impl Slipstream
  def handle_disconnect(_reason, socket) do
    case reconnect(socket) do
      {:ok, socket} ->
        {:ok, socket}

      {:error, reason} ->
        if Map.has_key?(socket.assigns, :timer), do: :timer.cancel(socket.assigns.ping_timer)
        {:stop, reason, socket}
    end
  end

  defp validate_options(options) do
    options
    |> Keyword.take([
      :uri,
      :heartbeat_interval_msec,
      :headers,
      :serializer,
      :json_parser,
      :reconnect_after_msec,
      :rejoin_after_msec,
      :mint_opts,
      :extensions,
      :test_mode?
    ])
  end
end
