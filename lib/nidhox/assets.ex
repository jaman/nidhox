defmodule Nidhox.Assets do
  @moduledoc """
  The game's data file, read once from the player's own copy and shared by every
  process: its resources and every picture cut from its texture pages.

      {:ok, assets} = Nidhox.Assets.load("path/to/data.win")
      Nidhox.Assets.get().data.rooms

  `find/1` names the data file to read: the path given, then `config :nidhox, :data`
  (which `NIDHOX_DATA` sets), then the first of `candidates/0` that exists.
  """

  alias Cauldron2D.GameMaker.Data
  alias Cauldron2D.GameMaker.Pictures

  @key {__MODULE__, :assets}

  @enforce_keys [:path, :data, :pictures]
  defstruct [:path, :data, :pictures]

  @type t :: %__MODULE__{
          path: Path.t(),
          data: Data.t(),
          pictures: %{term() => FrenchCurve.Raster.t()}
        }

  @doc "The data file to read, or `nil` when none is given, configured or installed."
  @spec find(Path.t() | nil) :: Path.t() | nil
  def find(path) do
    path || Application.get_env(:nidhox, :data) || Enum.find(candidates(), &File.exists?/1)
  end

  @doc """
  Where the game's data file sits in its usual installs: the Windows build under
  CrossOver's Steam, then the macOS build under Steam.
  """
  @spec candidates() :: [Path.t()]
  def candidates do
    support = Path.expand("~/Library/Application Support")

    [
      Path.join([
        support,
        "CrossOver/Bottles/Steam/drive_c/Program Files (x86)/Steam/steamapps/common/Nidhogg/data.win"
      ]),
      Path.join([
        support,
        "Steam/steamapps/common/Nidhogg/Nidhogg.app/Contents/Resources/game.ios"
      ])
    ]
  end

  @doc "Read the data file at `path`, cut its pictures and install them for every process."
  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(path) do
    with {:ok, data} <- Data.read(path),
         {:ok, pages} <- Pictures.new(data) do
      pictures = Map.merge(Pictures.table(pages, data), Nidhox.Art.table())
      assets = %__MODULE__{path: path, data: data, pictures: pictures}
      :persistent_term.put(@key, assets)
      {:ok, assets}
    end
  end

  @doc "The installed assets; raises when `load/1` has not run."
  @spec get() :: t()
  def get, do: :persistent_term.get(@key)

  @doc "Whether `load/1` has run."
  @spec loaded?() :: boolean()
  def loaded?, do: :persistent_term.get(@key, nil) != nil
end
