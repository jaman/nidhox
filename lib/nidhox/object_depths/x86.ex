defmodule Nidhox.ObjectDepths.X86 do
  @moduledoc """
  Reads the object depth table from a 32-bit Windows build's code.

  The function is found by the instruction that opens it, `mov [esi + 0x10], <its
  name>`. Each element is found by the instructions the compiler writes for it: the
  element's index pushed, then the array pushed (`[esi + 4]` the depths, `[esi + 8]`
  the names), then the value. A depth is a double written as two 32-bit halves into
  `[edi + 4]` and `[edi]`. A name is a pushed pointer to its text.
  """

  alias Nidhox.ObjectDepths.Image

  @function "gml_Script___global_object_depths"
  @span 0x10000
  @depths 4
  @names 8

  @doc "The table in `image`: object name to depth, or `{:error, :no_depth_table}`."
  @spec table(Image.t()) :: {:ok, %{String.t() => float()}} | {:error, :no_depth_table}
  def table(%Image{bytes: bytes} = image) do
    with {:ok, start} <- function_start(image) do
      body = binary_part(bytes, start, min(@span, byte_size(bytes) - start))
      {depths, names} = scan(body, nil, %{}, %{})
      paired(depths, names, image)
    end
  end

  defp function_start(%Image{bytes: bytes} = image) do
    with {at, _length} <- :binary.match(bytes, @function <> <<0>>),
         va when is_integer(va) <- Image.va(image, at),
         {start, _length} <- :binary.match(bytes, <<0xC7, 0x46, 0x10, va::little-32>>) do
      {:ok, start}
    else
      _missing -> {:error, :no_depth_table}
    end
  end

  defp scan(<<>>, _element, depths, names), do: {depths, names}

  defp scan(<<0x6A, index, 0xFF, 0x76, array, rest::binary>>, _element, depths, names)
       when array in [@depths, @names],
       do: scan(rest, {array, index}, depths, names)

  defp scan(<<0x68, index::little-32, 0xFF, 0x76, array, rest::binary>>, _element, depths, names)
       when array in [@depths, @names] and index < 0x10000,
       do: scan(rest, {array, index}, depths, names)

  defp scan(
         <<0xC7, 0x47, 0x04, high::little-32, 0xC7, 0x07, low::little-32, rest::binary>>,
         {@depths, index},
         depths,
         names
       ) do
    <<depth::little-float-64>> = <<low::little-32, high::little-32>>
    scan(rest, nil, Map.put(depths, index, depth), names)
  end

  defp scan(<<0x68, va::little-32, 0x57, rest::binary>>, {@names, index}, depths, names),
    do: scan(rest, nil, depths, Map.put(names, index, va))

  defp scan(<<_byte, rest::binary>>, element, depths, names),
    do: scan(rest, element, depths, names)

  defp paired(depths, names, image) do
    indices = Enum.sort(Map.keys(names))

    if indices != [] and indices == Enum.sort(Map.keys(depths)) and
         indices == Enum.to_list(0..(length(indices) - 1)) do
      {:ok, Map.new(indices, &{Image.text(image, names[&1]), depths[&1]})}
    else
      {:error, :no_depth_table}
    end
  end
end
