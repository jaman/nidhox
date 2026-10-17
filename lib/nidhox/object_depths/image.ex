defmodule Nidhox.ObjectDepths.Image do
  @moduledoc """
  An executable's bytes with what the depth readers need to find their way in them:
  its sections as addresses and file offsets, its named functions when it keeps a
  symbol table, and the address ranges of its functions when it keeps an exception
  table.

  `Nidhox.ObjectDepths.Pe` and `Nidhox.ObjectDepths.MachO` build one.
  """

  @enforce_keys [:bytes, :machine, :sections]
  defstruct [:bytes, :machine, :sections, symbols: %{}, functions: []]

  @type machine :: :x86 | :x64 | :arm64
  @type section :: %{va: non_neg_integer(), raw: non_neg_integer(), size: non_neg_integer()}
  @type t :: %__MODULE__{
          bytes: binary(),
          machine: machine(),
          sections: [section()],
          symbols: %{String.t() => non_neg_integer()},
          functions: [{non_neg_integer(), non_neg_integer()}]
        }

  @doc "The address of the byte at file offset `at`, or `nil` when no section holds it."
  @spec va(t(), non_neg_integer()) :: non_neg_integer() | nil
  def va(%__MODULE__{sections: sections}, at) do
    Enum.find_value(sections, fn %{va: va, raw: raw, size: size} ->
      if at >= raw and at < raw + size, do: va + at - raw
    end)
  end

  @doc "The file offset of address `va`, or `nil` when no section holds it."
  @spec offset(t(), non_neg_integer()) :: non_neg_integer() | nil
  def offset(%__MODULE__{sections: sections}, va) do
    Enum.find_value(sections, fn %{va: start, raw: raw, size: size} ->
      if va >= start and va < start + size, do: raw + va - start
    end)
  end

  @doc "The bytes from address `from` up to address `to`, or `nil` when `from` is in no section."
  @spec slice(t(), non_neg_integer(), non_neg_integer()) :: binary() | nil
  def slice(%__MODULE__{bytes: bytes} = image, from, to) do
    case offset(image, from) do
      nil -> nil
      at -> binary_part(bytes, at, min(to - from, byte_size(bytes) - at))
    end
  end

  @doc "The zero-terminated text at address `va`, or `nil` when `va` is in no section."
  @spec text(t(), non_neg_integer()) :: String.t() | nil
  def text(%__MODULE__{bytes: bytes} = image, va) do
    case offset(image, va) do
      nil ->
        nil

      at ->
        case :binary.match(bytes, <<0>>, scope: {at, byte_size(bytes) - at}) do
          {stop, _length} -> binary_part(bytes, at, stop - at)
          :nomatch -> binary_part(bytes, at, byte_size(bytes) - at)
        end
    end
  end

  @doc "The address range `{start, stop}` of the function that holds address `va`, or `nil`."
  @spec function_at(t(), non_neg_integer()) :: {non_neg_integer(), non_neg_integer()} | nil
  def function_at(%__MODULE__{functions: functions}, va),
    do: Enum.find(functions, fn {start, stop} -> va >= start and va < stop end)

  @doc "The address range `{start, stop}` of the function named `name` in the symbol table, or `nil`."
  @spec named_function(t(), String.t()) :: {non_neg_integer(), non_neg_integer()} | nil
  def named_function(%__MODULE__{symbols: symbols} = image, name) do
    with start when is_integer(start) <- Map.get(symbols, name) do
      function_at(image, start)
    end
  end
end
