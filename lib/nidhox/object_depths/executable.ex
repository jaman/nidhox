defmodule Nidhox.ObjectDepths.Executable do
  @moduledoc """
  The object depth table compiled into the Windows build's `Nidhogg.exe` (GameMaker
  Studio 2, compiled to native code): the arrays `global.__objectDepths` and
  `global.__objectNames` that its `gml_Script___global_object_depths` fills.

  `table/1` reads them from the executable's bytes. The function is found by the
  instruction that opens it, `mov [esi + 0x10], <its name>`, and each element by the
  instructions the compiler writes for it: the element's index pushed, then the array
  pushed (`[esi + 4]` the depths, `[esi + 8]` the names), then the value, a depth being a
  double written as two 32-bit halves into `[edi + 4]` and `[edi]`, a name a pushed
  pointer to its text.

      {:ok, bytes} = File.read("path/to/Nidhogg.exe")
      {:ok, %{"Arrow" => -500.0}} = Nidhox.ObjectDepths.Executable.table(bytes)
  """

  @function "gml_Script___global_object_depths"
  @span 0x10000
  @depths 4
  @names 8

  @type section :: %{va: non_neg_integer(), raw: non_neg_integer(), size: non_neg_integer()}

  @doc """
  The table in executable `bytes`: object name to depth.

  Returns `{:error, :not_windows_executable}` for bytes that are not a Windows executable,
  and `{:error, :no_depth_table}` for an executable without the function, or whose
  function does not give every index from 0 up both a name and a depth.
  """
  @spec table(binary()) ::
          {:ok, %{String.t() => float()}} | {:error, :not_windows_executable | :no_depth_table}
  def table(bytes) do
    with {:ok, sections} <- sections(bytes),
         {:ok, start} <- function_start(bytes, sections) do
      body = binary_part(bytes, start, min(@span, byte_size(bytes) - start))
      {depths, names} = scan(body, nil, %{}, %{})
      paired(depths, names, bytes, sections)
    end
  end

  defp sections(<<"MZ", _::binary-58, header::little-32, _::binary>> = bytes)
       when header + 24 <= byte_size(bytes) do
    case binary_part(bytes, header, 24) do
      <<"PE", 0, 0, _machine::little-16, count::little-16, _::binary-12, optional::little-16,
        _::binary-2>> ->
        <<_::binary-28, base::little-32, _::binary>> = binary_part(bytes, header + 24, optional)
        first = header + 24 + optional
        {:ok, for(index <- 0..(count - 1)//1, do: section(bytes, first + index * 40, base))}

      _other ->
        {:error, :not_windows_executable}
    end
  end

  defp sections(_bytes), do: {:error, :not_windows_executable}

  defp section(bytes, at, base) do
    <<_name::binary-8, _virtual_size::little-32, va::little-32, size::little-32, raw::little-32,
      _::binary>> =
      binary_part(bytes, at, 40)

    %{va: base + va, raw: raw, size: size}
  end

  defp function_start(bytes, sections) do
    with {at, _length} <- :binary.match(bytes, @function <> <<0>>),
         va when is_integer(va) <- va(sections, at),
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

  defp paired(depths, names, bytes, sections) do
    indices = Enum.sort(Map.keys(names))

    if indices != [] and indices == Enum.sort(Map.keys(depths)) and
         indices == Enum.to_list(0..(length(indices) - 1)) do
      {:ok, Map.new(indices, &{text(bytes, sections, names[&1]), depths[&1]})}
    else
      {:error, :no_depth_table}
    end
  end

  defp text(bytes, sections, va) do
    at = offset(sections, va)
    [text | _rest] = :binary.split(binary_part(bytes, at, min(256, byte_size(bytes) - at)), <<0>>)
    text
  end

  defp va(sections, at) do
    Enum.find_value(sections, fn %{va: va, raw: raw, size: size} ->
      if at >= raw and at < raw + size, do: va + at - raw
    end)
  end

  defp offset(sections, va) do
    Enum.find_value(sections, fn %{va: start, raw: raw, size: size} ->
      if va >= start and va < start + size, do: raw + va - start
    end)
  end
end
