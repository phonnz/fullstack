defmodule Fullstack.Algos.FastFib do
  @moduledoc """
  Fast Fibonacci implementation using matrix exponentiation.
  This algorithm has O(log n) time complexity.
  """

  @doc """
  Calculate the nth Fibonacci number using matrix exponentiation.
  """
  def fib(n) when n in [0, 1], do: n

  def fib(n) when n > 1 do
    # The matrix [[1,1],[1,0]]^(n-1) gives us the nth Fibonacci number
    # in the top right position
    {fib_n, _, _, _} = matrix_power({1, 1, 1, 0}, n - 1)
    fib_n
  end

  def fib(n) when n < 0 do
    # For negative indices: F(-n) = (-1)^(n+1) * F(n)
    n = abs(n)
    sign = if rem(n, 2) == 0, do: -1, else: 1
    sign * fib(n)
  end

  @doc """
  Raise a 2x2 matrix to the nth power using binary exponentiation.
  Matrix is represented as a tuple {a, b, c, d} for [[a,b],[c,d]].
  """
  def matrix_power(matrix, 1), do: matrix

  def matrix_power(matrix, n) when n > 1 do
    # If power is even, square the matrix and raise to half the power
    # If power is odd, multiply by original matrix and raise to power-1
    if rem(n, 2) == 0 do
      matrix
      |> matrix_multiply(matrix)
      |> matrix_power(div(n, 2))
    else
      matrix_multiply(matrix, matrix_power(matrix, n - 1))
    end
  end

  @doc """
  Multiply two 2x2 matrices.
  Matrices are represented as tuples {a, b, c, d} for [[a,b],[c,d]].
  """
  def matrix_multiply({a1, b1, c1, d1}, {a2, b2, c2, d2}) do
    a = a1 * a2 + b1 * c2
    b = a1 * b2 + b1 * d2
    c = c1 * a2 + d1 * c2
    d = c1 * b2 + d1 * d2
    {a, b, c, d}
  end
end
