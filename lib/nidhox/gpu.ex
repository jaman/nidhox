defmodule Nidhox.Gpu do
  @moduledoc """
  A frame's picture drawn by the graphics card, the same picture as
  `Nidhox.Client.picture/2`: the scene's `:gpu` function.

  Each frame is sent as `{:layers, layers}` (`CauldronGPU.SpriteLayer`,
  `CauldronGPU.ColumnLayer`):

    1. the room's draw items into the canvas `:room`, the room view's size at the pane's
       zoom, cleared to the room's background
    2. in the castle stairs' wide view, the room warped into the canvas `:shown` at the
       screen's size by `Nidhox.Bout.Spiral.columns/2`
    3. the GUI's items, then the open menu's, over the shown screen in window pixels
    4. the frame cleared black with the shown screen at its centre

  Pictures are uploaded as textures the first time they are drawn and kept
  (`Cauldron2D.Drafter.Client.Sprites`); a surface is uploaded again when it changes.
  """

  alias Cauldron2D.Drafter.Client.Sprites
  alias CauldronGPU.{ColumnLayer, Sprite, SpriteLayer, Target}
  alias Nidhox.{Assets, Picture}
  alias Nidhox.Bout.Spiral

  @black {0.0, 0.0, 0.0, 1.0}

  @doc """
  The changes that draw `frame` at `size` pixels on `target`, and the cache to pass
  next time (`nil` the first time).
  """
  @spec draw(map() | nil, Target.t(), Sprites.t() | nil, Picture.size()) ::
          {[CauldronGPU.Stream.change()], Sprites.t()}
  def draw(%{items: items, view: {view_x, view_y, _width, _height}} = frame, target, cache, size) do
    layout = Picture.layout(frame, size)
    source = &Picture.source(Assets.get().pictures, Map.get(frame, :surfaces, %{}), &1)
    cache = cache || Sprites.new()
    {room_canvas, cache} = Sprites.canvas(cache, target, :room, layout.viewed)
    {room, cache} = Sprites.sprites(cache, target, items, source)

    {gui, cache} =
      Sprites.sprites(cache, target, frame.gui ++ Map.get(frame, :overlay, []), source)

    {viewed_width, viewed_height} = layout.viewed
    {shown_width, shown_height} = layout.shown

    room_layer = %SpriteLayer{
      target: room_canvas,
      clear: Sprites.colour(frame.background),
      view: {view_x, view_y, viewed_width / layout.zoom, viewed_height / layout.zoom},
      sprites: room
    }

    {shown_canvas, warp_layers, cache} =
      warped(cache, target, room_canvas, layout.shown, Map.get(frame, :spiral))

    gui_layer = %SpriteLayer{
      target: shown_canvas,
      view: {0, 0, shown_width / layout.gui_zoom, shown_height / layout.gui_zoom},
      sprites: gui
    }

    frame_layer = %SpriteLayer{
      clear: @black,
      sprites: [%Sprite{texture: shown_canvas, position: layout.offset}]
    }

    {[{:layers, [room_layer | warp_layers] ++ [gui_layer, frame_layer]}], cache}
  end

  def draw(_frame, _target, cache, _size),
    do: {[{:layers, [%SpriteLayer{clear: @black}]}], cache || Sprites.new()}

  defp warped(cache, _target, room_canvas, _shown, nil), do: {room_canvas, [], cache}

  defp warped(cache, target, room_canvas, {shown_width, _height} = shown, amounts) do
    {shown_canvas, cache} = Sprites.canvas(cache, target, :shown, shown)

    layer = %ColumnLayer{
      target: shown_canvas,
      source: room_canvas,
      columns: Spiral.columns(shown_width, amounts)
    }

    {shown_canvas, [layer], cache}
  end
end
