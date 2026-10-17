defmodule Nidhox.Picture do
  @moduledoc """
  The sizes a frame's picture is drawn at, and the pictures its draw items name, for the
  software picture (`Nidhox.Client.picture/2`) and the graphics card's (`Nidhox.Gpu`).

  A picture key is one of:

    * `{:surface, id}` — the frame's surface `id`
    * `{:surface_part, id, {left, top, width, height}}` — that part of surface `id`
    * `{:part, key, {left, top, width, height}}` — that part of picture `key`
    * `{:ellipse, size, fill}` — `Cauldron2D.GameMaker.Shapes.raster/1`'s ellipse
    * `{:tile_layer, room, layer, blend}` — a room's tile layer, drawn once a room
      (`Nidhox.TileLayerCache`)
    * anything else — the game's picture of that key (`Nidhox.Assets`)
  """

  alias Cauldron2D.GameMaker.{Shapes, TileLayers}
  alias FrenchCurve.Raster
  alias Nidhox.Assets
  alias Nidhox.Bout.Spiral
  alias Nidhox.TileLayerCache

  @type size :: {pos_integer(), pos_integer()}
  @type rect :: {number(), number(), number(), number()}
  @type layout :: %{
          zoom: float(),
          shown: size(),
          viewed: size(),
          gui_zoom: float(),
          offset: {integer(), integer()}
        }

  @doc """
  Where a frame is drawn in a pane of `size` pixels: the `zoom` from the screen's pixels,
  the `shown` size of the screen and the `viewed` size of the room's view at that zoom,
  the `gui_zoom` from the window's pixels to the shown screen's, and the `offset` of the
  shown screen centred in the pane.
  """
  @spec layout(map(), size()) :: layout()
  def layout(%{view: {_x, _y, view_width, view_height}} = frame, {width, height}) do
    {screen_width, screen_height} = screen(frame)
    zoom = min(width / screen_width, height / screen_height)
    shown = {max(round(screen_width * zoom), 1), max(round(screen_height * zoom), 1)}
    {shown_width, shown_height} = shown
    {window_width, window_height} = frame.window

    %{
      zoom: zoom,
      shown: shown,
      viewed: {max(round(view_width * zoom), 1), max(round(view_height * zoom), 1)},
      gui_zoom: min(shown_width / window_width, shown_height / window_height),
      offset: {div(width - shown_width, 2), div(height - shown_height, 2)}
    }
  end

  @doc "The screen the frame's view is shown on: the spiral's while it is active, else the view's size."
  @spec screen(map()) :: {number(), number()}
  def screen(%{spiral: {_left, _right}}), do: Spiral.screen_size()
  def screen(%{view: {_x, _y, width, height}}), do: {width, height}

  @doc "The raster `key` names, cut to its part, or `nil`."
  @spec raster(map(), map(), term()) :: Raster.t() | nil
  def raster(pictures, surfaces, key) do
    case source(pictures, surfaces, key) do
      {_key, nil, _rect} ->
        nil

      {_key, raster, {left, top, width, height}} ->
        Raster.crop(raster, {left, top}, {width, height})

      {_key, raster} ->
        raster

      nil ->
        nil
    end
  end

  @doc """
  The picture `key` names as a whole raster and the part of it shown: `{raster_key,
  raster}`, `{raster_key, raster, {left, top, width, height}}`, or `nil`. Keys naming
  parts of the same raster share its `raster_key`.
  """
  @spec source(map(), map(), term()) ::
          {term(), Raster.t() | nil} | {term(), Raster.t() | nil, rect()} | nil
  def source(_pictures, surfaces, {:surface, id} = key), do: {key, Map.get(surfaces, id)}

  def source(_pictures, surfaces, {:surface_part, id, rect}),
    do: {{:surface, id}, Map.get(surfaces, id), rect}

  def source(_pictures, _surfaces, {:ellipse, _size, _fill} = shape),
    do: {shape, Shapes.raster(shape)}

  def source(pictures, _surfaces, {:tile_layer, _room, _layer, _blend} = key) do
    {key,
     TileLayerCache.fetch(key, fn ->
       TileLayers.raster(Assets.get().data, key, &Map.get(pictures, &1))
     end)}
  end

  def source(pictures, surfaces, {:part, key, {left, top, width, height}}) do
    case source(pictures, surfaces, key) do
      nil -> nil
      {whole, raster} -> {whole, raster, {left, top, width, height}}
      {whole, raster, {x, y, _w, _h}} -> {whole, raster, {x + left, y + top, width, height}}
    end
  end

  def source(pictures, _surfaces, key), do: {key, Map.get(pictures, key)}
end
