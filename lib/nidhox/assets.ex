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
  @knee 6

  @enforce_keys [:path, :data, :pictures]
  defstruct [:path, :data, :pictures, :pages]

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
      pictures = Pictures.table(pages, data)
      assets = %__MODULE__{path: path, data: data, pictures: pictures, pages: pages}
      :persistent_term.put(@key, assets)
      {:ok, assets}
    end
  end

  @doc "The installed assets; raises when `load/1` has not run."
  @spec get() :: t()
  def get, do: :persistent_term.get(@key)

  @doc "The index and definition of the copy's sprite called `name`; raises when it has none."
  @spec sprite!(String.t()) :: {non_neg_integer(), Cauldron2D.GameMaker.Sprite.t()}
  def sprite!(name) do
    %__MODULE__{data: data} = get()

    case Data.index(data, :sprites, name) do
      nil -> raise ArgumentError, "the copy has no sprite named #{inspect(name)}"
      index -> {index, Enum.at(data.sprites, index)}
    end
  end

  @doc "How many frames the copy's sprite `name` has."
  @spec frame_count(String.t()) :: pos_integer()
  def frame_count(name), do: name |> sprite!() |> elem(1) |> Map.fetch!(:frames) |> length()

  @doc """
  Where the hand is in frame `frame` of sprite `name`, `{dx, dy}` from the sprite's
  origin, facing right: its frontmost opaque pixel at least `@knee` pixels above the
  origin, the one nearest the top when several are. Worked out once per frame and kept.
  """
  @spec hand({String.t(), non_neg_integer()}) :: {integer(), integer()}
  def hand({name, frame}) do
    key = {__MODULE__, :hand, name, frame}

    case :persistent_term.get(key, nil) do
      nil ->
        hand = find_hand(name, frame)
        :persistent_term.put(key, hand)
        hand

      hand ->
        hand
    end
  end

  @doc """
  The opaque bounds of frame `frame` of sprite `name`, `{left, top, right, bottom}` from
  the sprite's origin, facing right. Worked out once per frame and kept.
  """
  @spec bounds({String.t(), non_neg_integer()}) :: {integer(), integer(), integer(), integer()}
  def bounds({name, frame}) do
    key = {__MODULE__, :bounds, name, frame}

    case :persistent_term.get(key, nil) do
      nil ->
        bounds = find_bounds(name, frame)
        :persistent_term.put(key, bounds)
        bounds

      bounds ->
        bounds
    end
  end

  defp find_bounds(name, frame) do
    {index, %{origin: {origin_x, origin_y}}} = sprite!(name)
    raster = Map.fetch!(get().pictures, {:sprite, index, frame})
    {width, _height} = FrenchCurve.Raster.dimensions(raster)

    opaque =
      for {<<_r, _g, _b, alpha>>, at} <-
            raster |> FrenchCurve.Raster.to_rgba_binary() |> chunks() |> Enum.with_index(),
          alpha > 0,
          do: {rem(at, width), div(at, width)}

    case opaque do
      [] ->
        {0, 0, 0, 0}

      points ->
        {xs, ys} = Enum.unzip(points)

        {Enum.min(xs) - origin_x, Enum.min(ys) - origin_y, Enum.max(xs) - origin_x,
         Enum.max(ys) - origin_y}
    end
  end

  defp chunks(rgba), do: for(<<pixel::binary-4 <- rgba>>, do: pixel)

  defp find_hand(name, frame) do
    {index, %{origin: {origin_x, origin_y}}} = sprite!(name)
    raster = Map.fetch!(get().pictures, {:sprite, index, frame})
    {width, _height} = FrenchCurve.Raster.dimensions(raster)

    {x, y} =
      for <<_r, _g, _b, alpha <- FrenchCurve.Raster.to_rgba_binary(raster)>>, reduce: {0, []} do
        {at, found} ->
          {at + 1,
           if(alpha > 0 and div(at, width) <= origin_y - @knee,
             do: [{rem(at, width), div(at, width)} | found],
             else: found
           )}
      end
      |> elem(1)
      |> Enum.min_by(fn {x, y} -> {-x, y} end, fn -> {origin_x, origin_y} end)

    {x - origin_x, y - origin_y}
  end

  @doc "Whether `load/1` has run."
  @spec loaded?() :: boolean()
  def loaded?, do: :persistent_term.get(@key, nil) != nil
end
