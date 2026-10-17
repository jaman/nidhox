defmodule Nidhox.ObjectDepths.X64 do
  @moduledoc """
  Reads the object depth table from a 64-bit Windows build's code.

  The function is the one whose code loads the address of its own name,
  `gml_Script___global_object_depths`, and its extent is its entry in the exception
  table. Inside it each element is a call with the array variable in `edx` (loaded from
  memory), the index in `r8d` and the value's stack slot in `r9`. A slot is filled
  before that by a call with the slot in `rcx` and the value in `edx` or `rdx`: an
  integer for a depth, the address of a constant string value for a name.

  Constant string values are filled at start-up by calls that load the text's address
  into `rdx` and the value's address into `rcx`.

  The code is read byte by byte. Moves of a constant into a stack slot are stepped over
  whole, so their constants are never read as instructions.
  """

  alias Nidhox.ObjectDepths.Elements
  alias Nidhox.ObjectDepths.Image

  @function "gml_Script___global_object_depths"

  @doc "The table in `image`: object name to depth, or `{:error, :no_depth_table}`."
  @spec table(Image.t()) :: {:ok, %{String.t() => number()}} | {:error, :no_depth_table}
  def table(%Image{} = image) do
    with {:ok, {start, stop}} <- named_function(image, @function),
         body when is_binary(body) <- Image.slice(image, start, stop) do
      body
      |> scan(start, %{}, %{}, [])
      |> Elements.table(constant_strings(image))
    else
      _missing -> {:error, :no_depth_table}
    end
  end

  @doc """
  The address range `{start, stop}` of the compiled function named `name` (such as
  `"gml_Script_newsItems"`): the one whose code loads the address of its own name, its
  extent taken from the exception table. Of several functions that load it, the one
  that loads it nearest its start. `:error` when there is none.
  """
  @spec named_function(Image.t(), String.t()) ::
          {:ok, {non_neg_integer(), non_neg_integer()}} | :error
  def named_function(%Image{bytes: bytes} = image, name) do
    with {at, _length} <- :binary.match(bytes, <<0>> <> name <> <<0>>),
         name when is_integer(name) <- Image.va(image, at + 1),
         [_ | _] = ranges <- function_ranges(image, rip_loads(image, <<0x48, 0x8D>>, name)) do
      {:ok, ranges |> Enum.min_by(fn {lea, {start, _stop}} -> lea - start end) |> elem(1)}
    else
      _missing -> :error
    end
  end

  defp function_ranges(image, leas) do
    for lea <- leas, range = Image.function_at(image, lea), is_tuple(range), do: {lea, range}
  end

  defp rip_loads(%Image{bytes: bytes} = image, prefix, target) do
    bytes
    |> :binary.matches(prefix)
    |> Enum.flat_map(fn {at, _length} ->
      rip_load(image, at, binary_part(bytes, at, min(7, byte_size(bytes) - at)), target)
    end)
  end

  defp rip_load(image, at, <<_::binary-2, modrm, displacement::little-signed-32>>, target)
       when rem(modrm, 8) == 5 and div(modrm, 64) == 0 do
    va = Image.va(image, at)
    if va && va + 7 + displacement == target, do: [va], else: []
  end

  defp rip_load(_image, _at, _short, _target), do: []

  defp scan(<<>>, _va, _registers, _slots, elements), do: elements

  defp scan(
         <<0x48, 0x8D, 0x8D, offset::little-signed-32, rest::binary>>,
         va,
         registers,
         slots,
         elements
       ),
       do: scan(rest, va + 7, Map.put(registers, :rcx, {:slot, offset}), slots, elements)

  defp scan(<<0x48, 0x8D, 0x4D, offset::signed-8, rest::binary>>, va, registers, slots, elements),
    do: scan(rest, va + 4, Map.put(registers, :rcx, {:slot, offset}), slots, elements)

  defp scan(
         <<0x4C, 0x8D, 0x8D, offset::little-signed-32, rest::binary>>,
         va,
         registers,
         slots,
         elements
       ),
       do: scan(rest, va + 7, Map.put(registers, :r9, {:slot, offset}), slots, elements)

  defp scan(<<0x4C, 0x8D, 0x4D, offset::signed-8, rest::binary>>, va, registers, slots, elements),
    do: scan(rest, va + 4, Map.put(registers, :r9, {:slot, offset}), slots, elements)

  defp scan(
         <<0x48, 0x8D, 0x15, displacement::little-signed-32, rest::binary>>,
         va,
         registers,
         slots,
         elements
       ),
       do:
         scan(
           rest,
           va + 7,
           Map.put(registers, :rdx, {:static, va + 7 + displacement}),
           slots,
           elements
         )

  defp scan(
         <<0x48, 0x8B, 0x15, _displacement::little-32, rest::binary>>,
         va,
         registers,
         slots,
         elements
       ),
       do: scan(rest, va + 7, Map.put(registers, :rdx, :unknown), slots, elements)

  defp scan(
         <<0x8B, 0x15, displacement::little-signed-32, rest::binary>>,
         va,
         registers,
         slots,
         elements
       ),
       do:
         scan(
           rest,
           va + 6,
           Map.put(registers, :rdx, {:variable, va + 6 + displacement}),
           slots,
           elements
         )

  defp scan(<<0x41, 0xB8, index::little-32, rest::binary>>, va, registers, slots, elements),
    do: scan(rest, va + 6, Map.put(registers, :r8, {:integer, index}), slots, elements)

  defp scan(<<0x45, opcode, 0xC0, rest::binary>>, va, registers, slots, elements)
       when opcode in [0x31, 0x33],
       do: scan(rest, va + 3, Map.put(registers, :r8, {:integer, 0}), slots, elements)

  defp scan(<<0xBA, value::little-signed-32, rest::binary>>, va, registers, slots, elements),
    do: scan(rest, va + 5, Map.put(registers, :rdx, {:integer, value}), slots, elements)

  defp scan(<<opcode, 0xD2, rest::binary>>, va, registers, slots, elements)
       when opcode in [0x31, 0x33],
       do: scan(rest, va + 2, Map.put(registers, :rdx, {:integer, 0}), slots, elements)

  defp scan(<<0xC7, 0x44, 0x24, _::binary-5, rest::binary>>, va, registers, slots, elements),
    do: scan(rest, va + 8, registers, slots, elements)

  defp scan(<<0xC7, 0x45, _::binary-5, rest::binary>>, va, registers, slots, elements),
    do: scan(rest, va + 7, registers, slots, elements)

  defp scan(<<0xC7, 0x85, _::binary-8, rest::binary>>, va, registers, slots, elements),
    do: scan(rest, va + 10, registers, slots, elements)

  defp scan(<<0x48, 0xC7, 0x45, _::binary-5, rest::binary>>, va, registers, slots, elements),
    do: scan(rest, va + 8, registers, slots, elements)

  defp scan(<<0x48, 0xC7, 0x85, _::binary-8, rest::binary>>, va, registers, slots, elements),
    do: scan(rest, va + 11, registers, slots, elements)

  defp scan(<<0xE8, _target::little-32, rest::binary>>, va, registers, slots, elements) do
    {slots, elements} = call(registers, slots, elements)
    scan(rest, va + 5, %{}, slots, elements)
  end

  defp scan(<<_byte, rest::binary>>, va, registers, slots, elements),
    do: scan(rest, va + 1, registers, slots, elements)

  defp call(
         %{rdx: {:variable, variable}, r8: {:integer, index}, r9: {:slot, slot}},
         slots,
         elements
       ) do
    case Map.fetch(slots, slot) do
      {:ok, value} -> {slots, [{variable, index, value} | elements]}
      :error -> {slots, elements}
    end
  end

  defp call(%{rcx: {:slot, slot}, rdx: {:integer, value}}, slots, elements),
    do: {Map.put(slots, slot, value), elements}

  defp call(%{rcx: {:slot, slot}, rdx: {:static, address}}, slots, elements),
    do: {Map.put(slots, slot, {:static, address}), elements}

  defp call(_registers, slots, elements), do: {slots, elements}

  @doc """
  The constant string values filled at start-up: each value's address to its text. Each
  is filled by a call that loads the text's address into `rdx` and the value's into `rcx`.
  """
  @spec constant_strings(Image.t()) :: %{non_neg_integer() => String.t()}
  def constant_strings(%Image{bytes: bytes} = image) do
    for {at, _length} <- :binary.matches(bytes, <<0x48, 0x8D, 0x15>>),
        <<_::binary-3, text::little-signed-32, 0x48, 0x8D, 0x0D, value::little-signed-32, 0xE8,
          _::binary>> <-
          [binary_part(bytes, at, min(19, byte_size(bytes) - at))],
        va = Image.va(image, at),
        is_integer(va),
        string = Image.text(image, va + 7 + text),
        is_binary(string),
        into: %{},
        do: {va + 14 + value, string}
  end
end
