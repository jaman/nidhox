defmodule Nidhox.ObjectDepths do
  @moduledoc """
  The depths the game creates its objects at, by object name, read from the player's
  copy: what its `instance_create` gives an instance through `object_get_depth`. A lower
  depth is drawn further in front. Instances a room places take their layer's depth
  instead.

  A GameMaker Studio 1 copy, such as the macOS build's `game.ios`, keeps each object's
  depth on the object itself, so the table is empty and the objects' own depths stand. A
  GameMaker Studio 2 copy, such as the Windows build's `data.win`, keeps them in a table
  its code fills, read from the `Nidhogg.exe` beside the data file
  (`Nidhox.ObjectDepths.Executable`).

      {:ok, data} = Cauldron2D.GameMaker.Data.read("path/to/data.win")
      {:ok, depths} = Nidhox.ObjectDepths.read("path/to/data.win", data)
  """

  alias Cauldron2D.GameMaker.Data
  alias Nidhox.ObjectDepths.Executable

  @executable "nidhogg.exe"

  @doc """
  The depth table for the data file at `path`, read as `data`: object name to depth.

  Returns `{:ok, %{}}` for a GameMaker Studio 1 file. For a Studio 2 file, the table read
  from the `Nidhogg.exe` in the data file's directory (`Nidhox.ObjectDepths.Executable`),
  or `{:error, {:no_executable, dir}}` when `dir` holds none, `{:error, {:unreadable, path,
  reason}}` when it cannot be read, `{:error, :not_windows_executable}` or
  `{:error, :no_depth_table}` when it is not a build whose table this reads, and
  `{:error, {:unknown_objects, names}}` when the table names objects the data file lacks.
  """
  @spec read(Path.t(), Data.t()) :: {:ok, %{String.t() => number()}} | {:error, term()}
  def read(_path, %Data{general: %{format: :gms1}}), do: {:ok, %{}}

  def read(path, %Data{} = data) do
    with {:ok, executable} <- executable(Path.dirname(path)),
         {:ok, bytes} <- read_executable(executable),
         {:ok, table} <- Executable.table(bytes) do
      known(table, data)
    end
  end

  defp executable(dir) do
    with {:ok, names} <- File.ls(dir),
         name when is_binary(name) <- Enum.find(names, &(String.downcase(&1) == @executable)) do
      {:ok, Path.join(dir, name)}
    else
      nil -> {:error, {:no_executable, dir}}
      {:error, reason} -> {:error, {:unreadable, dir, reason}}
    end
  end

  defp read_executable(path) do
    case File.read(path) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, {:unreadable, path, reason}}
    end
  end

  defp known(table, %Data{objects: objects}) do
    names = MapSet.new(objects, & &1.name)

    case Enum.reject(Map.keys(table), &MapSet.member?(names, &1)) do
      [] -> {:ok, table}
      unknown -> {:error, {:unknown_objects, Enum.sort(unknown)}}
    end
  end
end
