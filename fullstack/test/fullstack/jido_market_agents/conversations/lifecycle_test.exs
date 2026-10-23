defmodule Fullstack.JidoMarketAgents.Conversations.LifecycleTest do
  use ExUnit.Case, async: true

  alias Fullstack.JidoMarketAgents.Conversations.Lifecycle

  @stages [:inserted, :validating, :ready, :research, :proposal, :strategy, :delivered]

  test "stages are exposed in lifecycle order" do
    assert Lifecycle.stages() == @stages
  end

  describe "transition/2" do
    test "allows the next adjacent stage" do
      for {from, to} <- Enum.zip(@stages, tl(@stages)) do
        assert Lifecycle.transition(from, to) == :ok
      end
    end

    test "staying on the same stage is a no-op" do
      for stage <- @stages, do: assert(Lifecycle.transition(stage, stage) == :ok)
    end

    test "rejects skipping a stage" do
      assert Lifecycle.transition(:inserted, :ready) ==
               {:error, {:invalid_transition, :inserted, :ready}}

      assert Lifecycle.transition(:ready, :proposal) ==
               {:error, {:invalid_transition, :ready, :proposal}}

      assert Lifecycle.transition(:inserted, :delivered) ==
               {:error, {:invalid_transition, :inserted, :delivered}}
    end

    test "rejects moving backward" do
      for {from, to} <- Enum.zip(tl(@stages), @stages) do
        assert Lifecycle.transition(from, to) == {:error, {:invalid_transition, from, to}}
      end

      assert Lifecycle.transition(:delivered, :inserted) ==
               {:error, {:invalid_transition, :delivered, :inserted}}
    end

    test "delivered is terminal" do
      for to <- @stages -- [:delivered] do
        assert Lifecycle.transition(:delivered, to) ==
                 {:error, {:invalid_transition, :delivered, to}}
      end
    end

    test "rejects values outside the seven stages" do
      assert Lifecycle.transition(:inserted, :bogus) ==
               {:error, {:invalid_transition, :inserted, :bogus}}

      assert Lifecycle.transition(:bogus, :inserted) ==
               {:error, {:invalid_transition, :bogus, :inserted}}
    end
  end

  describe "advance/2" do
    test "returns the target only for the next adjacent stage" do
      for {from, to} <- Enum.zip(@stages, tl(@stages)) do
        assert Lifecycle.advance(from, to) == {:ok, to}
      end
    end

    test "is a no-op for the same stage or any stage behind" do
      for from <- @stages,
          to <- @stages,
          Enum.find_index(@stages, &(&1 == to)) <=
            Enum.find_index(@stages, &(&1 == from)) do
        assert Lifecycle.advance(from, to) == :noop
      end
    end

    test "reports a skip instead of advancing" do
      assert Lifecycle.advance(:inserted, :research) ==
               {:error, {:invalid_transition, :inserted, :research}}

      assert Lifecycle.advance(:research, :delivered) ==
               {:error, {:invalid_transition, :research, :delivered}}
    end
  end

  describe "before?/2" do
    test "orders stages by lifecycle position" do
      assert Lifecycle.before?(:research, :proposal)
      assert Lifecycle.before?(:inserted, :delivered)
      refute Lifecycle.before?(:proposal, :proposal)
      refute Lifecycle.before?(:strategy, :research)
    end
  end

  describe "accepts_messages?/1" do
    test "is true only before research" do
      assert Enum.filter(@stages, &Lifecycle.accepts_messages?/1) ==
               [:inserted, :validating, :ready]

      for stage <- [:research, :proposal, :strategy, :delivered] do
        refute Lifecycle.accepts_messages?(stage)
      end
    end
  end
end
