defmodule Fullstack.Algos.SlidingMaximumWindow do
  """
  - Find the maximumelement by window
  - k size window
  - use deque

  ## Example
  iex> run([[1, 3, -1, -3, 5, 3, 6, 7], 3)
      [3, 3, 5, 5, 6, 7]

  """
  def run(numbers, window_size) do
    cond do
      window_size == 0 -> []
      window_size > Enum.count(numbers) -> Enum.max(numbers)
      window_size == 1 -> numbers
      true -> find_max(numbers, window_size)
    end
  end

  defp find_max(nums, window_size) do
    {initial_deque, first_window} = initialize_deque(nums, window_size)

    # Process the rest of the array
    {_, result} =
      Enum.reduce(window_size..length(nums)-1, {initial_deque, [first_window]}, fn i, {deque, result} ->
        # Remove elements outside the current window
        deque = remove_outdated(deque, i - window_size + 1)

        # Remove elements smaller than the current one
        deque = remove_smaller(deque, nums, nums |> Enum.at(i))

        # Add current element index
        deque = deque ++ [i]

        # The front of deque has the maximum element for current window
        max_val = nums |> Enum.at(hd(deque))

        {deque, result ++ [max_val]}
      end)

    result
  end

  defp emove_smaller(deque, ns, current) do
    deque
    |> Enum.drop_while(fn idx -> Enum.at(ns, idx) > current end)
  end
  defp initialize_deque(nums, window_size) do
    {deque, _} =
      Enum.reduce(0..window_size-1, {[], -1}, fn i , {dq, _} ->  dq = remove_smaller(dq, nums, Enum.at(nums,i));IO.inspect({[ i | dq ], i}) end)
      # Enum.reduce(0..window_size-1, {[], -1}, fn i, {deque, _} ->
      #   # Remove elements smaller than the current one
      #   deque = remove_smaller(deque, nums, nums |> Enum.at(i))

      #   # Add current element index
      #   {deque ++ [i], i}
      #   |> IO.inspect()
      # end)
IO.inspect(deque)
    # Return the deque and the first window's maximum
     {deque, nums |> Enum.at(hd(deque))}
  end

  # Remove indices that are outside the current window
  defp remove_outdated(deque, start_idx) do
    deque |> Enum.drop_while(fn idx -> idx < start_idx end)
  end

  # Remove indices whose corresponding values are smaller than the current value
  defp remove_smaller(deque, nums, current_val) do
    deque
     |> Enum.reverse()
    |> Enum.drop_while(fn idx ->
      nums |> Enum.at(idx) < current_val
    end)
    #  |> Enum.reverse()
  end
end
