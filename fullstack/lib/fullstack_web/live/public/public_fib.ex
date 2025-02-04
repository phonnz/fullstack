defmodule FullstackWeb.Public.FibonacciLive.Index do
  use FullstackWeb, :live_view

  alias Fullstack.Servers.Fibonacci.Fibonacci

  @impl true
  def mount(_params, _session, socket) do
    Process.flag(:trap_exit, true)

    socket =
      socket
      |> assign(:messages, [])
      |> assign(:memo_messages, [])
      |> assign(:task, nil)
      |> assign(:task_m, nil)
      |> assign(:form, to_form(%{}))

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Fibonacci</h1>
    <.form
      for={@form}
      id="fib_form"
      phx-submit="compute"
      class="flex items-center grid grid-cols-5 gap-10"
    >
      <div class="span-col-2">
        <.input
          type="text"
          name="value"
          field={@form[:value]}
          value="3"
          required={true}
          placeholder="number"
          class="px-10 py-3 w-full "
          autocomplete="off"
          phx-debounce="500"
        />
      </div>
      <button
        :if={is_nil(@task)}
        type="submit"
        name="option"
        value="simple"
        class="span-col-1 text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 me-2 mb-2 dark:bg-blue-600 dark:hover:bg-blue-700 focus:outline-none dark:focus:ring-blue-800"
      >
        Simple
      </button>
      <button
        :if={is_nil(@task)}
        type="submit"
        name="option"
        value="both"
        phx-action="both"
        class="span-col-1 focus:outline-none text-white bg-green-700 hover:bg-green-800 focus:ring-4 focus:ring-green-300 font-medium rounded-lg text-sm px-5 py-2.5 me-2 mb-2 dark:bg-green-600 dark:hover:bg-green-700 dark:focus:ring-green-800"
      >
        Both
      </button>
      <button
        :if={is_nil(@task)}
        type="submit"
        name="option"
        value="memoized"
        class="span-col-1 focus:outline-none text-white bg-purple-700 hover:bg-purple-800 focus:ring-4 focus:ring-purple-300 font-medium rounded-lg text-sm px-5 py-2.5 mb-2 dark:bg-purple-600 dark:hover:bg-purple-700 dark:focus:ring-purple-900"
      >
        Memoized
      </button>
      <button
        :if={@task || @task_m}
        type="button"
        phx-click="cancel"
        class="span-col-1 focus:outline-none text-white bg-red-700 hover:bg-red-800 focus:ring-4 focus:ring-red-300 font-medium rounded-lg text-sm px-5 py-2.5 me-2 mb-2 dark:bg-red-600 dark:hover:bg-red-700 dark:focus:ring-red-900"
      >
        Cancel
      </button>
    </.form>
    <div class="grid grid-cols-2 gap-10 max-h-[150px]">
      <div class="h-full max-h-1/3">
        <h3>Simple</h3>
        <span :for={message <- @messages} class="font-size-8">
          <%= if String.starts_with?(message, "=>") do %>
            <b><%= message %></b> <br />
          <% else %>
            .
          <% end %>
        </span>
      </div>
      <div class="max-h-1/3">
        <h3>Memoization</h3>
        <article :for={message <- @memo_messages} class="column-2">
          <b><%= message %></b>
        </article>
      </div>
    </div>
    """
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_message, %{message: message}}, socket) do
    messages = socket.assigns.messages

    {:noreply, assign(socket, :messages, [message | messages])}
  end

  @impl true
  def handle_info({:new_memo_message, %{message: message}}, socket) do
    messages = socket.assigns.memo_messages

    {:noreply, assign(socket, :memo_messages, [message | messages])}
  end

  @impl true
  def handle_event("compute", %{"option" => option, "value" => value} = params, socket)
      when option in ["simple", "both", "memoized"] and
             value not in [nil, ""] do
    pid_from = self()

    socket =
      case option do
        "simple" ->
          {:ok, task} =
            Task.start_link(fn ->
              Fibonacci.fib(value, pid_from)
            end)

          socket
          |> assign(:messages, [])
          |> assign(:task, task)

        "both" ->
          {:ok, task} =
            Task.start_link(fn ->
              Fibonacci.fib(value, pid_from)
            end)

          {:ok, task_m} = Task.start_link(fn -> Fibonacci.fibm(pid_from, value) end)

          socket
          |> assign(:messages, [])
          |> assign(:memo_messages, [])
          |> assign(:task, task)
          |> assign(:task_m, task_m)

        "memoized" ->
          {:ok, task_m} = Task.start_link(fn -> Fibonacci.fibm(pid_from, value) end)

          socket
          |> assign(:memo_messages, [])
          |> assign(:task_m, task_m)
      end

    {:noreply, socket}
  end

  def handle_event("cancel", _, socket) do
    if is_pid(socket.assigns.task), do: Process.exit(socket.assigns.task, :kill)
    if is_pid(socket.assigns.task_m), do: Process.exit(socket.assigns.task_m, :kill)

    socket =
      socket
      |> assign(:task, nil)
      |> assign(:task_m, nil)
      |> put_flash(:info, "Cancelled")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:EXIT, pid, reason} = args, socket) do
    socket =
      cond do
        pid == socket.assigns.task ->
          assign(socket, :task, nil)

        pid == socket.assigns.task_m ->
          assign(socket, :task_m, nil)
      end

    {:noreply, socket}
  end
end
