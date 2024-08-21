defmodule Fullstack.Services.CountersTest do
  use ExUnit.Case
  use Fullstack.DataCase
  alias Fullstack.Services.Counters

  setup do
    # {:ok, _pid} = Counters.start_link(table_name: :test_counters)
    :ok
  end

  describe "Basic counter operations" do
    test "Getting a new counter" do
      assert Counters.get("user_0", :identified) == {:identified, 0}
      assert Counters.get(nil, :centralized) == {:centralized, 0}
    end

    test "increase and decrease identified counter values" do
      assert Counters.increase("user_0", :identified) == {:identified, 1}
      assert Counters.increase("user_1", :identified) == {:identified, 1}
      assert Counters.increase("user_1", :identified) == {:identified, 2}

      assert Counters.decrease("user_0", :identified) == {:dentified, 1}
      assert Counters.decrease("user_0", :identified) == {:identified, 0}
      assert Counters.decrease("user_1", :identified) == {:identified, 1}
    end

    @tag :skip
    test "get/2 returns the updated counter values" do
      Counters.increase("user_1", :identified)
      Counters.increase("user_1", :identified)
      Counters.increase(nil, :centralized)
      Counters.increase(nil, :centralized)

      assert Counters.get("user_1", :identified) == {:identified, 2}
      assert Counters.get(nil, :centralized) == {:centralized, 2}
    end

    @tag :skip
    test "ETS table is initialized and used correctly" do
      assert :ets.info(:test_counters)[:name] == :test_counters
      assert :ets.info(:test_counters)[:type] == :set
      assert :ets.info(:test_counters)[:protection] == :public
      assert :ets.info(:test_counters)[:read_concurrency] == true
    end
  end
end
