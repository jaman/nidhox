defmodule Nidhox.ObjectDepths.Elements do
  @moduledoc """
  Pairs the array elements a depth function sets into the table of object name to depth.

  An element is `{variable, index, value}`. `value` is a number for an element of the
  depths array and `{:static, address}` for an element of the names array, where the
  address is a constant string value that `texts` names. The depths array is the
  variable whose values are all numbers, the names array the one whose values are all
  constant strings. Both must give the same indices. An index neither gives is a place
  in the arrays with no object.
  """

  @type element :: {term(), non_neg_integer(), number() | {:static, non_neg_integer()}}

  @doc "The table from `elements` and `texts` (constant string address to its text), or `{:error, :no_depth_table}`."
  @spec table([element()], %{non_neg_integer() => String.t()}) ::
          {:ok, %{String.t() => number()}} | {:error, :no_depth_table}
  def table(elements, texts) do
    arrays = Enum.group_by(elements, &elem(&1, 0), &{elem(&1, 1), elem(&1, 2)})

    with {:ok, depths} <- array(arrays, &is_number/1),
         {:ok, names} <- array(arrays, &match?({:static, _address}, &1)),
         true <- Enum.sort(Map.keys(depths)) == Enum.sort(Map.keys(names)),
         {:ok, texts} <- texts(names, texts) do
      {:ok, Map.new(depths, fn {index, depth} -> {Map.fetch!(texts, index), depth} end)}
    else
      _other -> {:error, :no_depth_table}
    end
  end

  defp array(arrays, value?) do
    case Enum.filter(Map.values(arrays), fn pairs -> Enum.all?(pairs, &value?.(elem(&1, 1))) end) do
      [pairs] -> {:ok, Map.new(pairs)}
      _none_or_several -> :error
    end
  end

  defp texts(names, texts) do
    found =
      for {index, {:static, address}} <- names,
          text = texts[address],
          into: %{},
          do: {index, text}

    if map_size(found) == map_size(names), do: {:ok, found}, else: :error
  end
end
