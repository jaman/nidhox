defmodule Nidhox.ObjectDepths.MachO do
  @moduledoc """
  Reads a macOS executable into a `Nidhox.ObjectDepths.Image`: the arm64 part of a
  universal binary, or a binary that is arm64 only. The image has the part's segments,
  its symbol table's named functions, and the function ranges those names mark out.

      {:ok, image} = Nidhox.ObjectDepths.MachO.read(File.read!("Nidhogg.app/Contents/MacOS/Nidhogg"))
  """

  import Bitwise

  alias Nidhox.ObjectDepths.Image

  @fat 0xCAFEBABE
  @thin 0xFEEDFACF
  @arm64 0x0100000C
  @segment 0x19
  @symbol_table 0x2
  @text_section 0x0E

  @doc "The arm64 image in `bytes`, or `{:error, :not_arm64_mac_executable}`."
  @spec read(binary()) :: {:ok, Image.t()} | {:error, :not_arm64_mac_executable}
  def read(<<@fat::32, count::32, rest::binary>> = bytes) do
    arches =
      for <<cpu::32, _sub::32, at::32, size::32, _align::32 <- binary_part(rest, 0, count * 20)>>,
        do: {cpu, at, size}

    case List.keyfind(arches, @arm64, 0) do
      {@arm64, at, size} -> read(binary_part(bytes, at, size))
      nil -> {:error, :not_arm64_mac_executable}
    end
  end

  def read(
        <<@thin::little-32, @arm64::little-32, _sub::little-32, _type::little-32,
          count::little-32, _size::little-32, _flags::little-32, _reserved::little-32,
          commands::binary>> = bytes
      ) do
    {segments, symbols} = commands(commands, count, [], %{}, bytes)
    image = %Image{bytes: bytes, machine: :arm64, sections: segments, symbols: symbols}
    {:ok, %{image | functions: functions(symbols)}}
  end

  def read(_bytes), do: {:error, :not_arm64_mac_executable}

  defp commands(_rest, 0, segments, symbols, _bytes), do: {Enum.reverse(segments), symbols}

  defp commands(
         <<command::little-32, size::little-32, _::binary>> = rest,
         count,
         segments,
         symbols,
         bytes
       ) do
    <<body::binary-size(size), more::binary>> = rest

    case command do
      @segment -> commands(more, count - 1, [segment(body) | segments], symbols, bytes)
      @symbol_table -> commands(more, count - 1, segments, symbol_table(body, bytes), bytes)
      _other -> commands(more, count - 1, segments, symbols, bytes)
    end
  end

  defp segment(
         <<_command::binary-8, _name::binary-16, va::little-64, _vm_size::little-64,
           raw::little-64, size::little-64, _::binary>>
       ),
       do: %{va: va, raw: raw, size: size}

  defp symbol_table(
         <<_command::binary-8, at::little-32, count::little-32, strings::little-32,
           _size::little-32>>,
         bytes
       ) do
    for <<name::little-32, type, _section, _description::little-16,
          value::little-64 <- binary_part(bytes, at, count * 16)>>,
        (type &&& @text_section) == @text_section,
        value > 0,
        into: %{},
        do: {name(bytes, strings + name), value}
  end

  defp name(bytes, at) do
    [name | _rest] = :binary.split(binary_part(bytes, at, min(512, byte_size(bytes) - at)), <<0>>)
    name
  end

  defp functions(symbols) do
    starts = symbols |> Map.values() |> Enum.uniq() |> Enum.sort()
    Enum.zip(starts, Enum.drop(starts, 1))
  end
end
