defmodule Fullstack.JidoMarketAgents.MessageBufferSupervisor do
  @moduledoc """
  `DynamicSupervisor` for per-user `MessageBuffer` processes (design D6).

  `MessageBuffer` takes the opposite shape from `RateLimiter`: one process
  per `user_id` rather than one shared named process, so that each user's
  debounce timer resets independently and a crash in one user's buffer
  cannot affect another's. This supervisor holds exactly those children.
  """
  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
