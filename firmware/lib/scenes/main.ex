defmodule Firmware.Scene.Main do
  use Scenic.Scene

  require Logger

  import Scenic.Primitives

  alias Scenic.Graph
  alias Scenic.ViewPort

  @font :roboto
  @font_size 20

  @animate_ms 30

  @splash_path "/static/images/rainbow.bmp"
  @splash_hash Scenic.Cache.Support.Hash.file!(
                 :code.priv_dir(:firmware) |> Path.join(@splash_path),
                 :sha
               )
  @splash_width 128
  @splash_height 128
  @splash_alpha_max 256

  def init(first_scene, opts) do
    viewport = opts[:viewport]

    # calculate the transform that centers the parrot in the viewport
    {:ok, %ViewPort.Status{size: {vp_width, vp_height}}} = ViewPort.info(viewport)

    splash_path =
      :code.priv_dir(:sample_scenic_driver_waveshare)
      |> Path.join(@splash_path)

    case Scenic.Cache.Static.Texture.load(splash_path, @splash_hash) do
      {:ok, data} ->
        Logger.debug(">>> splash.init data=#{inspect(data)} hash=#{inspect(@splash_hash)}")

      {:error, reason} ->
        Logger.debug(">>> splash.init error=#{inspect(reason)}")
    end

    position = {
      vp_width / 2 - @splash_width / 2,
      vp_height / 2 - @splash_height / 2
    }

    graph =
      Graph.build(font_size: @font_size, font: @font, theme: :light)
      |> rectangle({vp_width, vp_height}, t: {0, 0}, fill: :black)
      |> rect(
        {@splash_width, @splash_height},
        id: :splash,
        fill: {:image, {@splash_hash, 0}}
      )

    {:ok, timer} = animate(@animate_ms)

    state = %{
      viewport: viewport,
      timer: timer,
      graph: graph,
      first_scene: first_scene,
      alpha: 25
    }

    {:ok, state, push: graph}
  end

  def animate(ms) do
    :timer.send_interval(ms, :animate)
  end

  def handle_info(
        :animate,
        %{timer: timer, alpha: alpha} = state
      )
      when alpha >= @splash_alpha_max do
    :timer.cancel(timer)

    {:noreply, state}
  end

  def handle_info(:animate, %{alpha: alpha, graph: graph} = state) do
    graph =
      Graph.modify(
        graph,
        :splash,
        &update_opts(&1, fill: {:image, {@splash_hash, alpha}})
      )

    {:noreply, %{state | graph: graph, alpha: alpha + 1}, push: graph}
  end

  def handle_input(
        {:key, {key, action, _something}} = event,
        _context,
        %{graph: graph, alpha: alpha} = state
      ) do
    Logger.debug(
      "Firmware.Scene.Main.handle_input: received event #{inspect(event)} state=#{inspect(state)}"
    )

    alpha =
      case {key, action} do
        {:joystick_1_up, :press} when alpha < 255 -> alpha + 1
        {:joystick_1_down, :press} when alpha > 0 -> alpha - 1
        {:joystick_1_right, :press} -> alpha + 10
        {:joystick_1_left, :press} -> alpha - 10
        {:joystick_1_button, :press} -> 128
        {:button_1, :press} -> 0
        _ -> alpha
      end

    alpha =
      cond do
        alpha < 0 -> 0
        alpha > 255 -> 255
        true -> alpha
      end

    {:ok, timer} =
      case {key, action} do
        {:button_1, :press} ->
          case Map.get(state, :timer, nil) do
            nil -> nil
            timer -> :timer.cancel(timer)
          end

          animate(@animate_ms)

        _ ->
          {:ok, Map.get(state, :timer, nil)}
      end

    graph =
      Graph.modify(
        graph,
        :splash,
        &update_opts(&1, fill: {:image, {@splash_hash, alpha}})
      )

    {:noreply, %{state | graph: graph, alpha: alpha, timer: timer}, push: graph}
  end

  def handle_input(event, _context, state) do
    Logger.info("Firmware.Scene.Main.handle_input: received event #{inspect(event)}")

    {:noreply, state}
  end
end
