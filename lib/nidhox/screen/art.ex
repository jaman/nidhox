defmodule Nidhox.Screen.Art do
  @moduledoc """
  The screens' pictures from the player's copy — its sprites, and text in its fonts —
  placed in the pixels of the game's 320 × 200 view and given as GUI items for a window
  `{width, height}`, scaled up by the window's width over the view's so they keep the
  game's pixels.

      Art.sprite("sNewTitle", 0, {160, 50}, window)
      Art.text("fMenu", "PRESS START", {160, 150}, window, halign: :center)
  """

  alias Cauldron2D.GameMaker.Data
  alias Cauldron2D.GameMaker.Text
  alias Nidhox.Assets

  @view_width 320

  @doc """
  Frame `frame` of the copy's sprite `name` with its origin at `{x, y}`. Options are
  those of a draw list item: `:blend`, `:alpha`, `:depth`, and `:scale` multiplying the
  window's.
  """
  @spec sprite(
          String.t(),
          non_neg_integer(),
          {number(), number()},
          {number(), number()},
          keyword()
        ) ::
          map()
  def sprite(name, frame, {x, y}, window, opts \\ []) do
    data = Assets.get().data
    index = Data.index(data, :sprites, name)
    sprite = Enum.at(data.sprites, index)
    zoom = zoom(window)
    {scale_x, scale_y} = Keyword.get(opts, :scale, {1, 1})

    opts
    |> Map.new()
    |> Map.merge(%{
      picture: {:sprite, index, rem(frame, length(sprite.frames))},
      position: {x * zoom, y * zoom},
      origin: sprite.origin,
      scale: {scale_x * zoom, scale_y * zoom}
    })
    |> Map.put_new(:depth, 0)
  end

  @doc """
  The part `{left, top, width, height}` of frame `frame` of the copy's sprite `name`,
  its top-left corner at `{x, y}` (`draw_sprite_part_ext`); options as `sprite/5`'s.
  """
  @spec part(
          String.t(),
          non_neg_integer(),
          {number(), number(), number(), number()},
          {number(), number()},
          {number(), number()},
          keyword()
        ) :: map()
  def part(name, frame, rectangle, {x, y}, window, opts \\ []) do
    name
    |> sprite(frame, {x, y}, window, opts)
    |> then(&%{&1 | picture: {:part, &1.picture, rectangle}, origin: {0, 0}})
  end

  @doc "Frame `frame` of the copy's sprite `name` with its middle at `{x, y}`; options as `sprite/5`'s."
  @spec centred(
          String.t(),
          non_neg_integer(),
          {number(), number()},
          {number(), number()},
          keyword()
        ) ::
          map()
  def centred(name, frame, {x, y}, window, opts \\ []) do
    data = Assets.get().data

    %{size: {width, height}, origin: {origin_x, origin_y}} =
      Enum.at(data.sprites, Data.index(data, :sprites, name))

    {scale_x, scale_y} = Keyword.get(opts, :scale, {1, 1})

    sprite(
      name,
      frame,
      {x + (origin_x - width / 2) * scale_x, y + (origin_y - height / 2) * scale_y},
      window,
      opts
    )
  end

  @doc """
  `words` in the copy's font `font` at `{x, y}`, laid out as
  `Cauldron2D.GameMaker.Text.items/5` lays them out with `opts`, `:wrap` and
  `:separation` in view pixels.
  """
  @spec text(String.t(), String.t(), {number(), number()}, {number(), number()}, keyword()) ::
          [map()]
  def text(font, words, {x, y}, window, opts \\ []) do
    zoom = zoom(window)

    opts = opts |> Keyword.put(:scale, {zoom, zoom}) |> Keyword.put_new(:depth, 0)

    Text.items(Assets.get().data, font, words, {x * zoom, y * zoom}, opts)
  end

  @doc "The width in view pixels of `words` in `font`, laid out with `opts`."
  @spec text_width(String.t(), String.t(), keyword()) :: number()
  def text_width(font, words, opts \\ []), do: Text.width(Assets.get().data, font, words, opts)

  @doc "The height in view pixels of `words` in `font`, laid out with `opts`."
  @spec text_height(String.t(), String.t(), keyword()) :: number()
  def text_height(font, words, opts \\ []), do: Text.height(Assets.get().data, font, words, opts)

  @doc "The size in view pixels of the copy's sprite `name`."
  @spec size(String.t()) :: {non_neg_integer(), non_neg_integer()}
  def size(name) do
    data = Assets.get().data
    Enum.at(data.sprites, Data.index(data, :sprites, name)).size
  end

  @doc "A box of `colour` at `alpha` over the whole window, behind everything else drawn."
  @spec shade({number(), number()}, {byte(), byte(), byte()}, number()) :: map()
  def shade({width, height}, colour, alpha),
    do: %{
      picture: :pixel,
      position: {0, 0},
      scale: {width, height},
      blend: colour,
      alpha: alpha,
      depth: 1
    }

  @doc "The view's width in pixels: 320."
  @spec view_width() :: pos_integer()
  def view_width, do: @view_width

  defp zoom({width, _height}), do: width / @view_width
end
