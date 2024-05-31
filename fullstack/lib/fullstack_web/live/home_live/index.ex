defmodule FullstackWeb.HomeLive.Index do
  use Phoenix.LiveView

  @impl true
  def mount(_, _, socket) do
    {:ok, assign(socket, :counter, 0)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    IO.inspect(params, label: :PARAMS)
    {:noreply, socket}
  end

  @impl true
  def handle_event("inc", params, %{:assigns => %{:counter => counter}} = socket) do
    IO.inspect(params, label: :handle_params)

    {:noreply, assign(socket, :counter, counter + 1)}
  end

  @impl true
  def handle_event("dec", params, %{:assigns => %{:counter => counter}} = socket) do
    IO.inspect(params, label: :handle_params)

    {:noreply, assign(socket, :counter, counter - 1)}
  end
end
