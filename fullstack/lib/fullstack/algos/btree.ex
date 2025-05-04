defmodule Fullstack.Algos.Btree.Node do
  defstruct [:value, :left, :right]
end

defmodule Fullstack.Algos.Btree do
  alias Fullstack.Algos.Btree.Node

  """
  ## Example
        6
      /   \
     4     8
    / \   /  \
   1   5  -   9
  """

  def init() do
    node_b = %Node{value: 1}
    node_c = %Node{value: 5}

    node_a = %Node{value: 4, left: node_b, right: node_c}

    node_e = %Node{value: 9}
    node_d = %Node{value: 8, right: node_e}

    node_n = %Node{value: 7}
    root = %Node{value: 6, left: node_a, right: node_d}
  end

  # inorder -> LVR
  def inorder(node) when not is_nil(node) do
    inorder(node.left)
    IO.puts(node.value)
    inorder(node.right)
  end

  def inorder(_node), do: nil

  # preorder -> VLR
  def preorder(node) when not is_nil(node) do
    IO.puts(node.value)
    preorder(node.left)
    preorder(node.right)
  end

  def preorder(_node), do: nil

  # postorder -> VLR
  def postorder(node) when not is_nil(node) do
    postorder(node.left)
    postorder(node.right)
    IO.puts(node.value)
  end

  def postorder(_node), do: nil

  def insert(btree, value) when not is_nil(btree) do
    case btree do
      %Node{value: node_value, right: right} = node
      when node_value <= value and is_nil(right) ->
        struct(node, right: %Node{value: value})

      %Node{value: node_value, right: right} = node
      when node_value <= value and not is_nil(right) ->
        struct(node, right: insert(right, value))

      %Node{value: node_value, left: left} = node
      when node_value >= value and is_nil(left) ->
        struct(node, left: %Node{value: value})

      %Node{value: node_value, left: left} = node
      when node_value >= value and not is_nil(left) ->
        struct(node, left: insert(left, value))

      _ ->
        nil
    end
  end

  def find(%Node{value: value} = btree, to_find) when value == to_find, do: btree

  def find(%Node{left: left, right: right} = btree, to_find) do
    [l, r] = Enum.map([left, right], &find(&1, to_find))
    l || r
  end

  def find(btree, _to_find) when is_nil(btree), do: nil
end
