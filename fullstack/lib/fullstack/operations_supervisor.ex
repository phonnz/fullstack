defmodule Fullstack.Servers.OperationsSupervisor do
  alias Fullstack.Servers.NumberGenerator
  use Supervisor

  def start_link(init_arg \\ []) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children =
      1..10_000
      |> Enum.map(
        &Supervisor.child_spec(
          {Fullstack.Servers.NumberGenerator, &1 * 10},
          id: "#{&1}_generator"
        )
      )

    Supervisor.init(children, strategy: :one_for_all)
  end

  def rand() do
    __MODULE__
    |> Supervisor.which_children()
    |> Enum.map(&elem(&1, 1))
    |> Enum.map(&Task.async(NumberGenerator, :rand, [&1]))
    |> Enum.map(&Task.await(&1, :infinity))
  end
end
