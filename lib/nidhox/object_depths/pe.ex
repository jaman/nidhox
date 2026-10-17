defmodule Nidhox.ObjectDepths.Pe do
  @moduledoc """
  Reads a Windows executable into a `Nidhox.ObjectDepths.Image`: its sections, its
  machine (`:x86` or `:x64`), and for an x64 executable the function ranges its
  exception table lists.

      {:ok, image} = Nidhox.ObjectDepths.Pe.read(File.read!("Nidhogg.exe"))
  """

  alias Nidhox.ObjectDepths.Image

  @pe32 0x10B
  @pe32_plus 0x20B
  @machines %{0x14C => :x86, 0x8664 => :x64}
  @exception_directory 3

  @doc "The image in `bytes`, or `{:error, :not_windows_executable}`."
  @spec read(binary()) :: {:ok, Image.t()} | {:error, :not_windows_executable}
  def read(<<"MZ", _::binary-58, header::little-32, _::binary>> = bytes)
      when header + 24 <= byte_size(bytes) do
    with <<"PE", 0, 0, machine::little-16, count::little-16, _::binary-12, optional::little-16,
           _::binary-2>> <- binary_part(bytes, header, 24),
         {:ok, machine} <- Map.fetch(@machines, machine),
         {:ok, base, directories} <- optional_header(binary_part(bytes, header + 24, optional)) do
      sections =
        for index <- 0..(count - 1)//1,
            do: section(bytes, header + 24 + optional + index * 40, base)

      image = %Image{bytes: bytes, machine: machine, sections: sections}
      {:ok, %{image | functions: functions(image, base, directories)}}
    else
      _other -> {:error, :not_windows_executable}
    end
  end

  def read(_bytes), do: {:error, :not_windows_executable}

  defp optional_header(
         <<@pe32::little-16, _::binary-26, base::little-32, _::binary-60, count::little-32,
           rest::binary>>
       ),
       do: {:ok, base, directories(rest, count)}

  defp optional_header(
         <<@pe32_plus::little-16, _::binary-22, base::little-64, _::binary-76, count::little-32,
           rest::binary>>
       ),
       do: {:ok, base, directories(rest, count)}

  defp optional_header(_other), do: :error

  defp directories(bytes, count) do
    for <<rva::little-32,
          size::little-32 <- binary_part(bytes, 0, min(count * 8, byte_size(bytes)))>>,
        do: {rva, size}
  end

  defp section(bytes, at, base) do
    <<_name::binary-8, _virtual_size::little-32, va::little-32, size::little-32, raw::little-32,
      _::binary>> = binary_part(bytes, at, 40)

    %{va: base + va, raw: raw, size: size}
  end

  defp functions(%Image{machine: :x64} = image, base, directories) do
    case Enum.at(directories, @exception_directory) do
      {rva, size} when rva > 0 and size > 0 ->
        image
        |> Image.slice(base + rva, base + rva + size)
        |> runtime_functions(base)

      _none ->
        []
    end
  end

  defp functions(_image, _base, _directories), do: []

  defp runtime_functions(nil, _base), do: []

  defp runtime_functions(table, base) do
    for <<start::little-32, stop::little-32, _unwind::little-32 <- table>>, start > 0,
      do: {base + start, base + stop}
  end
end
