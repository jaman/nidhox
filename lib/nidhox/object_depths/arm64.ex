defmodule Nidhox.ObjectDepths.Arm64 do
  @moduledoc """
  Reads the object depth table from an arm64 macOS build's code, through its symbol
  table.

  The function is `gml_Script___global_object_depths`. Each element is a call to
  `YYGML_Variable_SetValue` with the array variable's id loaded into `w1` from the
  variable's record, the index in `w2`, and in `x3` the stack slot of the value. A depth
  is a double whose bits are moved into a register and stored to the slot. A name is a
  constant string value copied into the slot by `YYRValue::operator=`.

  Constant string values are filled by the file's start-up function, a call to
  `YYConstString` with the value's address in `x0` and the text's address in `x1`.

  Only the instructions these steps use are followed: `adrp`, `add` and `sub`
  (immediate), `movz`, `movn`, `movk`, `mov` between registers, `str` (64-bit, unsigned
  offset), `stur` (64-bit), `ldr` (32-bit, unsigned offset) and `bl`.
  """

  import Bitwise

  alias Nidhox.ObjectDepths.Elements
  alias Nidhox.ObjectDepths.Image

  @function "__Z33gml_Script___global_object_depthsP9CInstanceS0_R8YYRValueiPPS1_"
  @start_up "__GLOBAL__sub_I_gml_GlobalScript___global_object_depths.gml.cpp"
  @set_value "__Z23YYGML_Variable_SetValueRK8YYRValueiiP6RValue"
  @assign "__ZN8YYRValueaSERKS_"
  @constant_string "__Z13YYConstStringP6RValuePKc"
  @stack 31
  @mask64 0xFFFFFFFFFFFFFFFF

  @doc "The table in `image`: object name to depth, or `{:error, :no_depth_table}`."
  @spec table(Image.t()) :: {:ok, %{String.t() => number()}} | {:error, :no_depth_table}
  def table(%Image{symbols: symbols} = image) do
    calls = calls(symbols)

    with {start, stop} <- Image.named_function(image, @function),
         {_start, _stop} = start_up <- Image.named_function(image, @start_up),
         false <- Map.has_key?(calls, nil) do
      elements = run(image, start, stop, calls).elements
      Elements.table(Enum.map(elements, &double/1), constant_strings(image, start_up))
    else
      _missing -> {:error, :no_depth_table}
    end
  end

  defp constant_strings(%Image{symbols: symbols} = image, {start, stop}) do
    for {value, text} <- run(image, start, stop, calls(symbols)).texts,
        string = Image.text(image, text),
        is_binary(string),
        into: %{},
        do: {value, string}
  end

  defp calls(symbols) do
    %{
      Map.get(symbols, @set_value) => :set_value,
      Map.get(symbols, @assign) => :assign,
      Map.get(symbols, @constant_string) => :constant_string
    }
  end

  defp double({variable, index, {:static, _address} = value}), do: {variable, index, value}

  defp double({variable, index, bits}) do
    <<depth::float-64>> = <<bits::64>>
    {variable, index, depth}
  end

  defp run(image, start, stop, calls) do
    state = %{registers: %{}, stack: %{}, elements: [], texts: %{}, calls: calls}

    image
    |> Image.slice(start, stop)
    |> instructions(start, state)
  end

  defp instructions(<<word::little-32, rest::binary>>, pc, state),
    do: instructions(rest, pc + 4, step(word, pc, state))

  defp instructions(_rest, _pc, state), do: state

  defp step(word, pc, state) when (word &&& 0x9F000000) == 0x90000000 do
    low = word >>> 29 &&& 0x3
    high = word >>> 5 &&& 0x7FFFF
    offset = signed((high <<< 2 ||| low) <<< 12, 33)
    put(state, word &&& 0x1F, (pc &&& bnot(0xFFF)) + offset)
  end

  defp step(word, _pc, state) when (word &&& 0xBF800000) == 0x91000000 do
    shift = if (word &&& 0x400000) != 0, do: 12, else: 0
    sign = if (word &&& 0x40000000) != 0, do: -1, else: 1
    immediate = (word >>> 10 &&& 0xFFF) <<< shift
    source = word >>> 5 &&& 0x1F
    put(state, word &&& 0x1F, plus(get(state, source, :stack), sign * immediate))
  end

  defp step(word, _pc, state) when (word &&& 0x7F800000) == 0x52800000 do
    shift = (word >>> 21 &&& 0x3) * 16
    put(state, word &&& 0x1F, (word >>> 5 &&& 0xFFFF) <<< shift)
  end

  defp step(word, _pc, state) when (word &&& 0x7F800000) == 0x12800000 do
    shift = (word >>> 21 &&& 0x3) * 16
    width = if (word &&& 0x80000000) != 0, do: @mask64, else: 0xFFFFFFFF
    put(state, word &&& 0x1F, bnot((word >>> 5 &&& 0xFFFF) <<< shift) &&& width)
  end

  defp step(word, _pc, state) when (word &&& 0x7F800000) == 0x72800000 do
    shift = (word >>> 21 &&& 0x3) * 16
    target = word &&& 0x1F

    case get(state, target, :zero) do
      old when is_integer(old) ->
        put(state, target, (old &&& bnot(0xFFFF <<< shift)) ||| (word >>> 5 &&& 0xFFFF) <<< shift)

      _unknown ->
        put(state, target, :unknown)
    end
  end

  defp step(word, _pc, state) when (word &&& 0x7FE0FFE0) == 0x2A0003E0,
    do: put(state, word &&& 0x1F, get(state, word >>> 16 &&& 0x1F, :zero))

  defp step(word, _pc, state) when (word &&& 0xFFC00000) == 0xF9000000,
    do: store(state, word, (word >>> 10 &&& 0xFFF) * 8)

  defp step(word, _pc, state) when (word &&& 0xFFE00C00) == 0xF8000000,
    do: store(state, word, signed(word >>> 12 &&& 0x1FF, 9))

  defp step(word, _pc, state) when (word &&& 0xFFC00000) == 0xB9400000 do
    base = word >>> 5 &&& 0x1F
    offset = (word >>> 10 &&& 0xFFF) * 4

    case get(state, base, :stack) do
      address when is_integer(address) and offset == 8 ->
        put(state, word &&& 0x1F, {:variable, address})

      _other ->
        put(state, word &&& 0x1F, :unknown)
    end
  end

  defp step(word, pc, state) when (word &&& 0xFC000000) == 0x94000000 do
    target = pc + signed((word &&& 0x3FFFFFF) <<< 2, 28)
    state |> call(Map.get(state.calls, target)) |> forget_scratch()
  end

  defp step(_word, _pc, state), do: state

  defp store(state, word, offset) do
    case get(state, word >>> 5 &&& 0x1F, :stack) do
      {:stack, at} ->
        %{state | stack: Map.put(state.stack, at + offset, get(state, word &&& 0x1F, :zero))}

      _other ->
        state
    end
  end

  defp call(state, :set_value) do
    with {:variable, variable} <- get(state, 1, :zero),
         index when is_integer(index) <- get(state, 2, :zero),
         {:stack, slot} <- get(state, 3, :stack),
         {:ok, value} when is_integer(value) or is_tuple(value) <- Map.fetch(state.stack, slot) do
      %{state | elements: [{variable, index, value} | state.elements]}
    else
      _unknown -> state
    end
  end

  defp call(state, :assign) do
    case {get(state, 0, :stack), get(state, 1, :zero)} do
      {{:stack, slot}, address} when is_integer(address) ->
        %{state | stack: Map.put(state.stack, slot, {:static, address})}

      _unknown ->
        state
    end
  end

  defp call(state, :constant_string) do
    case {get(state, 0, :zero), get(state, 1, :zero)} do
      {value, text} when is_integer(value) and is_integer(text) ->
        %{state | texts: Map.put(state.texts, value, text)}

      _unknown ->
        state
    end
  end

  defp call(state, nil), do: state

  defp forget_scratch(state),
    do: %{state | registers: Map.drop(state.registers, Enum.to_list(0..18))}

  defp get(_state, @stack, :stack), do: {:stack, 0}
  defp get(_state, @stack, :zero), do: 0
  defp get(state, register, _thirty_one), do: Map.get(state.registers, register, :unknown)

  defp put(state, @stack, _value), do: state

  defp put(state, register, value),
    do: %{state | registers: Map.put(state.registers, register, value)}

  defp plus({:stack, at}, immediate), do: {:stack, at + immediate}
  defp plus(value, immediate) when is_integer(value), do: value + immediate
  defp plus(_unknown, _immediate), do: :unknown

  defp signed(value, bits) do
    if value >= 1 <<< (bits - 1), do: value - (1 <<< bits), else: value
  end
end
