defmodule Fullstack.Services.CountersTest do
  use ExUnit.Case
  use Fullstack.DataCase
  alias Fullstack.Services.Counters

  setup do
    :ets.delete_all_objects(:counters)
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

      assert Counters.decrease("user_0", :identified) == {:identified, 0}
      assert Counters.decrease("user_0", :identified) == {:identified, -1}
      assert Counters.decrease("user_1", :identified) == {:identified, 1}
    end

    test "get/2 returns the updated counter values" do
      Counters.increase("user_1", :identified)
      Counters.increase("user_1", :identified)
      Counters.increase(nil, :centralized)
      Counters.increase(nil, :centralized)

      assert Counters.get("user_1", :identified) == {:identified, 2}
      assert Counters.get(nil, :centralized) == {:centralized, 2}
    end

    test "ETS table is initialized with the expected options" do
      assert :ets.info(:counters)[:name] == :counters
      assert :ets.info(:counters)[:type] == :set
      assert :ets.info(:counters)[:protection] == :public
      assert :ets.info(:counters)[:read_concurrency] == true
    end
  end
end
