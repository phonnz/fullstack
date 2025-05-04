defmodule Fullstack.Servers.Fibonacci.Fibonacci do
  use Agent

  def start do
    Agent.start_link(fn -> %{0 => 0, 1 => 1} end, name: __MODULE__)
  end

  def fibm(from, value) when is_binary(value) do
    start()

    value =
      value
      |> String.to_integer()

    r = fibm(from, value)
    Process.send(from, {:new_memo_message, %{message: "=> Fib for #{value} = #{r}"}}, [])

    :ok
  end

  def fibm(from, n) do
    cached_value = Agent.get(__MODULE__, &Map.get(&1, n))

    if cached_value do
      cached_value
    else
      Process.send(from, {:new_memo_message, %{message: "fib for #{n}"}}, [])

      v = fibm(from, n - 1) + fibm(from, n - 2)
      Agent.update(__MODULE__, &Map.put(&1, n, v))
      v
    end
  end

  def fib(value, from) when is_binary(value) do
    value =
      value
      |> String.to_integer()

    r = fib(from, value)
    Process.send(from, {:new_message, %{message: "=> Fib for #{value} = #{r}"}}, [])

    :ok
  end

  def fib(_from, value) when value in [0, 1], do: value

  def fib(from, value) when value < 15 do
    Process.send(from, {:new_message, %{message: "#{value}"}}, [])

    fib(from, value - 1) + fib(from, value - 2)
  end

  def fib(_from, _value) do
    "Only values under 15 "
  end
end
