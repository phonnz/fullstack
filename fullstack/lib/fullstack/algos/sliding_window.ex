defmodule Fullstack.Algos.SlidingWindow do
  """
  - Find the maximumelement by window
  - k size window
  - use deque

  ## Example
  iex> run([[1, 3, -1, -3, 5, 3, 6, 7], 3)
      [3, 3, 5, 5, 6, 7]

  """

  def run(numbers \\ [1, 3, -1, -3, 5, 3, 6, 7], window_size \\ 3) do
    cond do
      window_size == 0 -> []
      window_size > Enum.count(numbers) -> Enum.max(numbers)
      window_size == 1 -> numbers
      true -> find_max(numbers, window_size)
    end
  end

  defp find_max(ns, k) do
Enum.reduce(0..k-1, {ns, [], []}, &filter_lt/2)
end

  defp filter_lt(ns, idx, {res, []}) do
    {ns, res, [Enum.at(ns, idx)]}
  end
  defp filter_lt(ns, idx, {res, dq}) do
    List.last(dq) < n
  end
