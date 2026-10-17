defmodule Nidhox.ObjectDepths do
  @moduledoc """
  The depths the game creates its objects at, by object name, read from the player's
  copy: what its `instance_create` gives an instance through `object_get_depth`. A lower
  depth is drawn further in front. Instances a room places take their layer's depth
  instead.

  A GameMaker Studio 1 copy, such as an older macOS build's `game.ios`, keeps each
  object's depth on the object itself, so the table is empty and the objects' own depths
  stand. A GameMaker Studio 2 copy keeps them in a table its code fills. The table is
  read from the game's executable (`Nidhox.ObjectDepths.Executable`): the `Nidhogg.exe`
  beside a `data.win`, or the `MacOS/Nidhogg` of the app whose `Resources` hold a
  `game.ios`.

      {:ok, data} = Cauldron2D.GameMaker.Data.read("path/to/data.win")
      {:ok, depths} = Nidhox.ObjectDepths.read("path/to/data.win", data)
  """

  alias Cauldron2D.GameMaker.Data
  alias Nidhox.ObjectDepths.Executable

  @windows "nidhogg.exe"
  @mac Path.join(["..", "MacOS", "Nidhogg"])

  @doc """
  The depth table for the data file at `path`, read as `data`: object name to depth.

  Returns `{:ok, %{}}` for a GameMaker Studio 1 file. For a Studio 2 file, returns the
  table read from the game's executable (`Nidhox.ObjectDepths.Executable`). It returns
  `{:error, {:no_executable, path}}` when there is no executable at `path`, and
  `{:error, {:unreadable, path, reason}}` when it cannot be read. It returns
  `{:error, :not_an_executable}` or `{:error, :no_depth_table}` when the file is not a
  build whose table this reads. The table holds only the objects the data file has, as
  the game's runtime matches the table's names to the data file's objects.
  """
  @spec read(Path.t(), Data.t()) :: {:ok, %{String.t() => number()}} | {:error, term()}
  def read(_path, %Data{general: %{format: :gms1}}), do: {:ok, %{}}

  def read(path, %Data{} = data) do
    with {:ok, executable} <- executable(path),
         {:ok, bytes} <- read_executable(executable),
         {:ok, table} <- Executable.table(bytes) do
      {:ok, known(table, data)}
    end
  end

  @doc """
  The game's executable for the data file at `path`: the `Nidhogg.exe` beside a
  `data.win`, or the `MacOS/Nidhogg` of the app whose `Resources` hold a `game.ios`.
  `{:error, {:no_executable, path}}` when it is not there.
  """
  @spec executable(Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def executable(path) do
    dir = Path.dirname(path)

    case String.downcase(Path.extname(path)) do
      ".ios" -> mac_executable(Path.expand(@mac, dir))
      _windows -> windows_executable(dir)
    end
  end

  defp mac_executable(path) do
    if File.regular?(path), do: {:ok, path}, else: {:error, {:no_executable, path}}
  end

  defp windows_executable(dir) do
    with {:ok, names} <- File.ls(dir),
         name when is_binary(name) <- Enum.find(names, &(String.downcase(&1) == @windows)) do
      {:ok, Path.join(dir, name)}
    else
      nil -> {:error, {:no_executable, Path.join(dir, "Nidhogg.exe")}}
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
    Map.filter(table, fn {name, _depth} -> MapSet.member?(names, name) end)
  end
end
