defmodule Fullstack.JidoMarketAgents.Conversations.Lifecycle do
  @moduledoc """
  Pure lifecycle table for a market discovery conversation.

  A conversation moves forward through seven ordered stages. Only the next
  adjacent stage is a valid move, staying on the same stage is a no-op, and
  `:delivered` is terminal. From `:research` onward the database enforces the
  same forward-only rule with a trigger.
  """

  @stages [:inserted, :validating, :ready, :research, :proposal, :strategy, :delivered]
  @accepting_messages [:inserted, :validating, :ready]

  @type stage :: :inserted | :validating | :ready | :research | :proposal | :strategy | :delivered

  @doc "Returns the seven stages in lifecycle order."
  @spec stages() :: [stage()]
  def stages, do: @stages

  @doc """
  Validates a move from `from` to `to`.

  Returns `:ok` for the same stage or the next adjacent stage, and
  `{:error, {:invalid_transition, from, to}}` for anything else.
  """
  @spec transition(term(), term()) :: :ok | {:error, {:invalid_transition, term(), term()}}
  def transition(stage, stage) when stage in @stages, do: :ok

  def transition(from, to) do
    if next_stage(from) == to and not is_nil(to) do
      :ok
    else
      {:error, {:invalid_transition, from, to}}
    end
  end

  @doc """
  Decides an advance-only write toward `target` from `current`.

  Returns `{:ok, target}` when `target` is the next adjacent stage, `:noop`
  when it is the same stage or behind (never a write, never an error), and
  `{:error, {:invalid_transition, current, target}}` when it would skip a stage.
  """
  @spec advance(stage(), stage()) ::
          {:ok, stage()} | :noop | {:error, {:invalid_transition, term(), term()}}
  def advance(current, target) when current in @stages and target in @stages do
    if before?(target, current) or current == target do
      :noop
    else
      with :ok <- transition(current, target), do: {:ok, target}
    end
  end

  def advance(current, target), do: {:error, {:invalid_transition, current, target}}

  @doc "Whether `stage` comes strictly before `other` in the lifecycle."
  @spec before?(stage(), stage()) :: boolean()
  def before?(stage, other) when stage in @stages and other in @stages,
    do: index(stage) < index(other)

  @doc "Whether new user messages still update the collected data at `stage`."
  @spec accepts_messages?(stage()) :: boolean()
  def accepts_messages?(stage) when stage in @stages, do: stage in @accepting_messages

  defp index(stage), do: Enum.find_index(@stages, &(&1 == stage))

  defp next_stage(from) do
    case Enum.find_index(@stages, &(&1 == from)) do
      nil -> nil
      index -> Enum.at(@stages, index + 1)
    end
  end
end
