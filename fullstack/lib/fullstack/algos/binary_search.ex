defmodule Fullstack.Algos.TimestampSearch do
  @doc """
  Finds the first registry in a sorted list that occurs after the given timestamp.

  Returns the registry or nil if no registry is found after the timestamp.

  Assumes registries are sorted by timestamp in ascending order.
  Each registry is expected to have a :timestamp field.

  ## Parameters:
    - registries: A sorted list of registries (maps or structs with a :timestamp field)
    - target_timestamp: The timestamp to search for

  ## Examples:
  iex> registries = for i <- 1..1_000_000, do: %{id: i, timestamp: Enum.random(ti..tf)}
  iex> TimestampSearch.find_first_after(registries, t) # Returns %{id: id, timestamp: t + 1}

  iex> registries = [
        %{id: 1, timestamp: 1000},
        %{id: 2, timestamp: 2000},
        %{id: 3, timestamp: 3000}
      ]
  iex> TimestampSearch.find_first_after(registries, 1500) # Returns %{id: 2, timestamp: 2000}
  """
  def find_first_after(registries, target_timestamp) when is_list(registries) do
    case registries do
      [] -> nil
      [_ | _] -> do_binary_search(registries, target_timestamp, 0, length(registries) - 1)
    end
  end

  # Private binary search implementation
  defp do_binary_search(registries, target_timestamp, left, right) when left <= right do
    mid = div(left + right, 2)
    mid_registry = Enum.at(registries, mid)

    cond do
      # If we found a registry with timestamp > target and previous registry (if exists) has timestamp <= target
      mid_registry.timestamp > target_timestamp &&
          (mid == 0 || Enum.at(registries, mid - 1).timestamp <= target_timestamp) ->
        mid_registry

      # If mid timestamp is <= target, search the right half
      mid_registry.timestamp <= target_timestamp ->
        do_binary_search(registries, target_timestamp, mid + 1, right)

      # If mid timestamp is > target, but not the first one after target, search the left half
      true ->
        do_binary_search(registries, target_timestamp, left, mid - 1)
    end
  end

  # When left > right, we didn't find any registry after the target timestamp
  defp do_binary_search(_registries, _target_timestamp, _left, _right), do: nil
end
