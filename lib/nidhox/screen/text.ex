defmodule Nidhox.Screen.Text do
  @moduledoc """
  Lines of text for the screens, as GUI draw items in window pixels.

  A line is `{:text, words, colour, scale}`, which `Nidhox.Client` renders with
  `Linocut.Font`. `centred/5` places a line centred across the window with its top at
  `y`.
  """

  @doc "A line of `words` in `colour` at `scale`, centred across a window `{width, height}`."
  @spec centred(
          String.t(),
          {byte(), byte(), byte()},
          pos_integer(),
          number(),
          {number(), number()}
        ) ::
          map()
  def centred(words, colour, scale, y, {width, _height}) do
    {text_width, _} =
      words |> Linocut.Font.render(colour, scale: scale) |> FrenchCurve.Raster.dimensions()

    %{picture: {:text, words, colour, scale}, position: {(width - text_width) / 2, y}, depth: 0}
  end

  @doc "A box filled with `colour` at `alpha` covering the whole window, behind the text."
  @spec shade({number(), number()}, {byte(), byte(), byte()}, number()) :: map()
  def shade({width, height}, colour, alpha) do
    %{
      picture: :pixel,
      position: {0, 0},
      scale: {width, height},
      blend: colour,
      alpha: alpha,
      depth: 1
    }
  end
end
