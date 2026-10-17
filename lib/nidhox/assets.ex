defmodule Nidhox.Assets do
  @moduledoc """
  The game's data file, read once from the player's own copy and shared by every
  process: its resources, every picture cut from its texture pages, the depths its
  objects are created at (`Nidhox.ObjectDepths`), and its news (`Nidhox.News`), read from
  the game's executable.

      {:ok, assets} = Nidhox.Assets.load("path/to/data.win")
      Nidhox.Assets.get().data.rooms

  `find/1` names the data file to read: the path given, else `config :nidhox, :data`,
  which `config/runtime.exs` sets to `NIDHOX_DATA`, else the first of the game's usual
  installs under the home directory that exists.
  """

  alias Cauldron2D.GameMaker.Data
  alias Cauldron2D.GameMaker.Pictures

  @key {__MODULE__, :assets}
  @knee 6

  @enforce_keys [:path, :data, :pictures, :object_depths]
  defstruct [:path, :data, :pictures, :pages, :object_depths, news: []]

  @type t :: %__MODULE__{
          path: Path.t(),
          data: Data.t(),
          pictures: %{term() => FrenchCurve.Raster.t()},
          object_depths: %{String.t() => number()},
          news: [Nidhox.News.item()]
        }

  @doc "The data file to read, or `nil` when none is given, configured or installed."
  @spec find(Path.t() | nil) :: Path.t() | nil
  def find(path), do: path || Application.get_env(:nidhox, :data)

  @doc """
  Read the data file at `path`, its object depths (`Nidhox.ObjectDepths.read/2`) and its
  news (`Nidhox.News.read/1`), cut its pictures, and install them for every process. A
  copy whose executable has no news has none. Returns the first error met.
  """
  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(path) do
    with {:ok, data} <- Data.read(path),
         {:ok, object_depths} <- Nidhox.ObjectDepths.read(path, data),
         {:ok, news} <- news(path, data),
         {:ok, pages} <- Pictures.new(data) do
      pictures = Pictures.table(pages, data)

      assets = %__MODULE__{
        path: path,
        data: data,
        pictures: pictures,
        pages: pages,
        object_depths: object_depths,
        news: news
      }

      :persistent_term.put(@key, assets)
      {:ok, assets}
    end
  end

  defp news(_path, %Data{general: %{format: :gms1}}), do: {:ok, []}

  defp news(path, _data) do
    with {:ok, executable} <- Nidhox.ObjectDepths.executable(path) do
      case Nidhox.News.read(executable) do
        {:ok, items} -> {:ok, items}
        {:error, :no_news} -> {:ok, []}
        {:error, reason} -> {:error, reason}
      end
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
