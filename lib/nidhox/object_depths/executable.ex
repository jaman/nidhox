defmodule Nidhox.ObjectDepths.Executable do
  @moduledoc """
  The object depth table compiled into a GameMaker Studio 2 build of the game (compiled
  to native code): the arrays `global.__objectDepths` and `global.__objectNames` that
  its `gml_Script___global_object_depths` fills.

  `table/1` reads them from the executable's bytes. It reads three kinds of build:

    * a 32-bit Windows `Nidhogg.exe` (`Nidhox.ObjectDepths.X86`)
    * a 64-bit Windows `Nidhogg.exe` (`Nidhox.ObjectDepths.X64`)
    * a macOS `Nidhogg.app/Contents/MacOS/Nidhogg` with an arm64 part
      (`Nidhox.ObjectDepths.Arm64`)

      {:ok, bytes} = File.read("path/to/Nidhogg.exe")
      {:ok, %{"Arrow" => -500.0}} = Nidhox.ObjectDepths.Executable.table(bytes)
  """

  alias Nidhox.ObjectDepths.{Arm64, MachO, Pe, X64, X86}

  @doc """
  The table in executable `bytes`: object name to depth.

  Returns `{:error, :not_an_executable}` for bytes that are none of the three kinds, and
  `{:error, :no_depth_table}` for an executable without the function, or whose function
  does not give every index from 0 up both a name and a depth.
  """
  @spec table(binary()) ::
          {:ok, %{String.t() => number()}} | {:error, :not_an_executable | :no_depth_table}
  def table(bytes) do
    case image(bytes) do
      {:ok, %{machine: :x86} = image} -> X86.table(image)
      {:ok, %{machine: :x64} = image} -> X64.table(image)
      {:ok, %{machine: :arm64} = image} -> Arm64.table(image)
      :error -> {:error, :not_an_executable}
    end
  end

  defp image(<<"MZ", _::binary>> = bytes), do: ok(Pe.read(bytes))
  defp image(bytes), do: ok(MachO.read(bytes))

  defp ok({:ok, image}), do: {:ok, image}
  defp ok({:error, _reason}), do: :error
end
