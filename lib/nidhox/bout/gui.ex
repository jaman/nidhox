defmodule Nidhox.Bout.Gui do
  @moduledoc """
  Text placed in the game's GUI space: 640 × 400 units that fill the window and the
  view. The game's GUI text is set in fonts made for that space.

    * `text/5` draws from a draw GUI event: the position is in GUI units and the result
      is in window pixels, text scaled by the same zoom
    * `view_text/5` draws from a draw event onto the view: the position is in GUI units
      from the view's top left, and the view shows two GUI units to a pixel, so the text
      is drawn at half size
  """

  alias Cauldron2D.GameMaker.{Draw, World}
  alias Nidhox.Bout.Camera

  @width 640

  @doc "Window pixels to a GUI unit."
  @spec zoom(World.t()) :: number()
  def zoom(%World{data: %{general: %{window: {width, _height}}}}), do: width / @width

  @doc "The world with `string` in `font` drawn at GUI unit position `{x, y}`; `opts` are `Cauldron2D.GameMaker.Text.items/5`'s."
  @spec text(World.t(), String.t(), String.t(), {number(), number()}, keyword()) :: World.t()
  def text(%World{} = world, font, string, {x, y}, opts \\ []) do
    zoom = zoom(world)
    Draw.text(world, font, string, {x * zoom, y * zoom}, Keyword.put(opts, :scale, {zoom, zoom}))
  end

  @doc "The world with `string` in `font` drawn on the view at GUI unit position `{x, y}` from the view's top left."
  @spec view_text(World.t(), String.t(), String.t(), {number(), number()}, keyword()) ::
          World.t()
  def view_text(%World{} = world, font, string, {x, y}, opts \\ []) do
    position = {Camera.left(world) + x / 2, Camera.top(world) + y / 2}
    Draw.text(world, font, string, position, Keyword.put(opts, :scale, {0.5, 0.5}))
  end
end
