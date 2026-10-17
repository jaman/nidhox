defmodule Nidhox.Screen.Gui do
  @moduledoc """
  The game's GUI drawing, in its 640 × 400 GUI units, given as GUI items for a window
  `{width, height}` (`Nidhox.Screen.Art` draws in the 320 × 200 view): rectangles,
  sprites, the `sprtextBgBox` box stretched by its nine parts, and text.

  Text may carry the tags the game's Scribble text uses (`rich/5`): `[c_pink]`,
  `[c_aqua]` and `[c_red]` start a colour and `[/c]` ends it; `[sprite_name]` draws frame 0 of that
  sprite inline, its middle on the line's middle; `#` starts a new line. `glyph/1` writes a
  `Nidhox.Glyphs` glyph as such text. Text is laid out on one line, or wrapped at
  `:wrap` units by words.

  The pieces the game's menus share: `prompts/4` (`drawInputPrompts`), `slider/4`
  (`drawSlider`), `confirm/5` (`drawConfirmBox`) and `shade/3`, the dim over the whole
  screen.
  """

  alias Cauldron2D.GameMaker.{Colour, Data}
  alias Nidhox.Assets
  alias Nidhox.Screen.Art

  @gui_width 640
  @gui {640, 400}
  @tags %{"c_pink" => {255, 105, 180}, "c_aqua" => {0, 255, 255}, "c_red" => {255, 0, 0}}
  @white {255, 255, 255}

  @type window :: {number(), number()}
  @type rgb :: {byte(), byte(), byte()}

  @doc "The GUI's size in units."
  @spec size() :: {pos_integer(), pos_integer()}
  def size, do: @gui

  @doc "The grey `make_color_hsv(0, 0, value)`."
  @spec grey(byte()) :: rgb()
  def grey(value), do: Colour.hsv(0, 0, value)

  @doc "The rectangle from `{left, top}` to `{right, bottom}`, both inside it, filled, at `:alpha` (default 1)."
  @spec rectangle({number(), number(), number(), number()}, rgb(), window(), keyword()) :: [map()]
  def rectangle({left, top, right, bottom}, colour, window, opts \\ []) do
    zoom = zoom(window)

    [
      %{
        picture: :pixel,
        position: {left * zoom, top * zoom},
        scale: {max(right - left + 1, 0) * zoom, max(bottom - top + 1, 0) * zoom},
        blend: colour,
        alpha: Keyword.get(opts, :alpha, 1),
        depth: 0
      }
    ]
  end

  @doc "The rectangle's edges, one unit wide (`draw_rectangle` with an outline)."
  @spec outline({number(), number(), number(), number()}, rgb(), window()) :: [map()]
  def outline({left, top, right, bottom}, colour, window) do
    [
      {left, top, right, top},
      {left, bottom, right, bottom},
      {left, top, left, bottom},
      {right, top, right, bottom}
    ]
    |> Enum.flat_map(&rectangle(&1, colour, window))
  end

  @doc "The whole screen in `colour` at `alpha`."
  @spec shade(rgb(), number(), window()) :: [map()]
  def shade(colour, alpha, window),
    do: rectangle({0, 0, elem(@gui, 0), elem(@gui, 1)}, colour, window, alpha: alpha)

  @doc "Frame `frame` of the copy's sprite `name`, its origin at `{x, y}`; options as `Nidhox.Screen.Art.sprite/5`'s, `:scale` in GUI units."
  @spec sprite(String.t(), non_neg_integer(), {number(), number()}, window(), keyword()) ::
          [map()]
  def sprite(name, frame, {x, y}, window, opts \\ []) do
    {scale_x, scale_y} = Keyword.get(opts, :scale, {1, 1})

    [
      Art.sprite(
        name,
        frame,
        {x / 2, y / 2},
        window,
        Keyword.put(opts, :scale, {scale_x / 2, scale_y / 2})
      )
    ]
  end

  @doc """
  The copy's sprite `name` stretched over `{x, y, width, height}`
  (`draw_sprite_stretched_ext`): by its nine parts when it has them, its borders kept
  and the rest stretched, otherwise whole.
  """
  @spec box(String.t(), {number(), number(), number(), number()}, window(), keyword()) :: [map()]
  def box(name, {x, y, width, height}, window, opts \\ []) do
    data = Assets.get().data
    sprite = Enum.at(data.sprites, Data.index(data, :sprites, name))

    case sprite.nine_slice do
      nil ->
        stretched(
          name,
          sprite.size,
          {0, 0} |> rect(sprite.size),
          {x, y, width, height},
          window,
          opts
        )

      slice ->
        nine(name, sprite.size, slice, {x, y, width, height}, window, opts)
    end
  end

  defp rect({left, top}, {width, height}), do: {left, top, width, height}

  defp nine(name, {sprite_width, sprite_height}, slice, {x, y, width, height}, window, opts) do
    %{left: left, top: top, right: right, bottom: bottom} = slice

    columns = [
      {0, left, 0, left},
      {left, sprite_width - left - right, left, width - left - right},
      {sprite_width - right, right, width - right, right}
    ]

    rows = [
      {0, top, 0, top},
      {top, sprite_height - top - bottom, top, height - top - bottom},
      {sprite_height - bottom, bottom, height - bottom, bottom}
    ]

    for {source_x, source_width, place_x, place_width} <- columns,
        {source_y, source_height, place_y, place_height} <- rows,
        source_width > 0 and source_height > 0 and place_width > 0 and place_height > 0,
        item <-
          stretched(
            name,
            {sprite_width, sprite_height},
            {source_x, source_y, source_width, source_height},
            {x + place_x, y + place_y, place_width, place_height},
            window,
            opts
          ),
        do: item
  end

  defp stretched(name, _size, {sx, sy, sw, sh}, {x, y, width, height}, window, opts) do
    scale = {width / sw / 2, height / sh / 2}

    [
      Art.part(name, 0, {sx, sy, sw, sh}, {x / 2, y / 2}, window,
        scale: scale,
        blend: Keyword.get(opts, :blend, @white)
      )
    ]
  end

  @doc """
  `words` in the copy's font `font` at `{x, y}`, plain text: `:halign` (`:left`,
  `:center`, `:right`), `:valign` (`:top`, `:middle`, `:bottom`), `:colour`, `:alpha` and
  `:scale` as `Nidhox.Screen.Art.text/5` takes them.
  """
  @spec text(String.t(), String.t(), {number(), number()}, window(), keyword()) :: [map()]
  def text(font, words, {x, y}, window, opts \\ []) do
    {scale_x, scale_y} = Keyword.get(opts, :scale, {1, 1})

    Art.text(
      font,
      words,
      {x / 2, y / 2},
      window,
      Keyword.put(opts, :scale, {scale_x / 2, scale_y / 2})
    )
  end

  @doc "The width in GUI units of plain `words` in `font`."
  @spec text_width(String.t(), String.t()) :: number()
  def text_width(font, words), do: Art.text_width(font, words)

  @doc "The height in GUI units of a line of `font`."
  @spec line_height(String.t()) :: number()
  def line_height(font), do: Art.text_height(font, "Ag")

  @doc "A `Nidhox.Glyphs` glyph written as text for `rich/5`."
  @spec glyph({:sprite, String.t()} | {:text, String.t()}) :: String.t()
  def glyph({:sprite, name}), do: "[" <> name <> "]"
  def glyph({:text, text}), do: text

  @doc """
  Text with the game's tags (see the module documentation) in `font` at `{x, y}`. Options:
  `:halign`, `:valign`, `:colour` (the colour outside tags, default white), `:alpha`,
  `:wrap` (the most units across before a new line), `:line_height` (default the font's).
  """
  @spec rich(String.t(), String.t(), {number(), number()}, window(), keyword()) :: [map()]
  def rich(font, words, {x, y}, window, opts \\ []) do
    lines = lines(font, words, opts)
    line_height = Keyword.get(opts, :line_height, line_height(font))
    total = length(lines) * line_height
    top = aligned_top(y, total, Keyword.get(opts, :valign, :top))

    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, index} ->
      width = line_width(line)
      left = aligned_left(x, width, Keyword.get(opts, :halign, :left))
      middle = top + index * line_height + line_height / 2
      placed(font, line, left, middle, window, opts)
    end)
  end

  @doc """
  Text with the game's tags outlined (`drawTextScribbleOutlined`): drawn one unit right,
  up, left and down in `:outline` (default black), then in place in `:colour` (default
  white), wrapped at `:wrap` (default 320); other options as `rich/5`'s.
  """
  @spec outlined(String.t(), String.t(), {number(), number()}, window(), keyword()) :: [map()]
  def outlined(font, words, {x, y}, window, opts \\ []) do
    opts = Keyword.put_new(opts, :wrap, 320)
    outline = Keyword.put(opts, :colour, Keyword.get(opts, :outline, {0, 0, 0}))

    Enum.flat_map([{1, 0}, {0, -1}, {-1, 0}, {0, 1}], fn {dx, dy} ->
      rich(font, words, {x + dx, y + dy}, window, outline)
    end) ++ rich(font, words, {x, y}, window, Keyword.put_new(opts, :colour, @white))
  end

  @doc "The size `{width, height}` in GUI units of text with the game's tags, laid out as `rich/5` lays it out."
  @spec rich_size(String.t(), String.t(), keyword()) :: {number(), number()}
  def rich_size(font, words, opts \\ []) do
    lines = lines(font, words, opts)
    line_height = Keyword.get(opts, :line_height, line_height(font))

    tallest =
      lines |> List.flatten() |> Enum.map(&piece_height(font, &1)) |> Enum.max(fn -> 0 end)

    height = max(length(lines) * line_height, tallest)
    {lines |> Enum.map(&line_width/1) |> Enum.max(fn -> 0 end), height}
  end

  defp aligned_top(y, _total, :top), do: y
  defp aligned_top(y, total, :middle), do: y - total / 2
  defp aligned_top(y, total, :bottom), do: y - total

  defp aligned_left(x, _width, :left), do: x
  defp aligned_left(x, width, :center), do: x - width / 2
  defp aligned_left(x, width, :right), do: x - width

  defp placed(font, line, left, middle, window, opts) do
    {items, _x} =
      Enum.reduce(line, {[], left}, fn piece, {items, x} ->
        {items ++ piece_items(font, piece, {x, middle}, window, opts), x + piece_width(piece)}
      end)

    items
  end

  defp piece_items(font, {:text, text, colour, _width}, {x, middle}, window, opts),
    do:
      text(font, text, {x, middle}, window,
        valign: :middle,
        colour: colour || Keyword.get(opts, :colour, @white),
        alpha: Keyword.get(opts, :alpha, 1)
      )

  defp piece_items(_font, {:sprite, name, {_width, height}}, {x, middle}, window, opts),
    do: sprite(name, 0, {x, middle - height / 2}, window, alpha: Keyword.get(opts, :alpha, 1))

  defp piece_width({:text, _text, _colour, width}), do: width
  defp piece_width({:sprite, _name, {width, _height}}), do: width

  defp piece_height(font, {:text, _text, _colour, _width}), do: line_height(font)
  defp piece_height(_font, {:sprite, _name, {_width, height}}), do: height

  defp line_width(line), do: line |> Enum.map(&piece_width/1) |> Enum.sum()

  defp lines(font, words, opts) do
    words
    |> String.split("#")
    |> Enum.flat_map(fn part ->
      pieces = pieces(font, part)

      case Keyword.get(opts, :wrap) do
        nil -> [pieces]
        width -> wrapped(font, pieces, width)
      end
    end)
  end

  defp pieces(font, words) do
    words
    |> tokens()
    |> Enum.reduce({[], nil}, fn
      {:colour, colour}, {acc, _current} ->
        {acc, colour}

      {:sprite, name}, {acc, current} ->
        {[{:sprite, name, Art.size(name)} | acc], current}

      {:text, text}, {acc, current} ->
        {[{:text, text, current, text_width(font, text)} | acc], current}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp tokens(words) do
    sprites = sprite_names()

    ~r/\[([^\]]*)\]/
    |> Regex.split(words, include_captures: true, trim: true)
    |> Enum.map(&token(&1, Regex.run(~r/^\[([^\]]*)\]$/, &1), sprites))
  end

  defp token(_piece, [_, "/c"], _sprites), do: {:colour, nil}

  defp token(_piece, [_, tag], _sprites) when is_map_key(@tags, tag),
    do: {:colour, Map.fetch!(@tags, tag)}

  defp token(piece, [_, name], sprites),
    do: if(MapSet.member?(sprites, name), do: {:sprite, name}, else: {:text, piece})

  defp token(piece, nil, _sprites), do: {:text, piece}

  defp sprite_names do
    case :persistent_term.get({__MODULE__, :sprites}, nil) do
      nil ->
        names = MapSet.new(Assets.get().data.sprites, & &1.name)
        :persistent_term.put({__MODULE__, :sprites}, names)
        names

      names ->
        names
    end
  end

  defp wrapped(font, pieces, width) do
    pieces
    |> Enum.flat_map(&words(font, &1))
    |> Enum.reduce({[], [], 0}, fn
      {:break, _}, {lines, line, _used} ->
        {[Enum.reverse(line) | lines], [], 0}

      piece, {lines, line, used} ->
        piece_width = piece_width(piece)

        if used + piece_width > width and line != [] and not space?(piece),
          do: {[Enum.reverse(line) | lines], [piece], piece_width},
          else: {lines, [piece | line], used + piece_width}
    end)
    |> then(fn {lines, line, _used} -> Enum.reverse([Enum.reverse(line) | lines]) end)
    |> Enum.map(&trim_leading_space/1)
  end

  defp words(font, {:text, text, colour, _width}) do
    text
    |> String.split(~r/(\s)/, include_captures: true, trim: true)
    |> Enum.map(fn
      "\n" -> {:break, nil}
      word -> {:text, word, colour, text_width(font, word)}
    end)
  end

  defp words(_font, sprite), do: [sprite]

  defp space?({:text, text, _colour, _width}), do: String.trim(text) == ""
  defp space?(_sprite), do: false

  defp trim_leading_space([first | rest] = line), do: if(space?(first), do: rest, else: line)
  defp trim_leading_space([]), do: []

  @doc """
  The prompts `prompts` (`drawInputPrompts`): boxes hanging down from `{x, y}`, their
  right edges on `x`, each one a box as tall as the tallest prompt and 4 more (at least
  24) and as wide as its text and 14, its text right-aligned 7 in from the edge.
  """
  @spec prompts([String.t()], {number(), number()}, String.t(), window()) :: [map()]
  def prompts(prompts, {x, y}, font, window) do
    height =
      prompts
      |> Enum.map(fn prompt -> elem(rich_size(font, prompt), 1) + 4 end)
      |> Enum.max(fn -> 24 end)
      |> max(24)

    {items, _y} =
      Enum.reduce(prompts, {[], y - 1}, fn prompt, {items, top} ->
        {width, _height} = rich_size(font, prompt)
        box_width = width + 14

        prompt_items =
          box("sprtextBgBox", {x - box_width, top, box_width, height}, window) ++
            rich(font, prompt, {x - 7, top + height / 2}, window, halign: :right, valign: :middle)

        {items ++ prompt_items, top + height - 1}
      end)

    items
  end

  @doc "The slider `drawSlider(x, y, w, h, v)`: its outline and its filled part to `value` of the way."
  @spec slider({number(), number(), number(), number()}, number(), rgb(), window()) :: [map()]
  def slider({x, y, width, height}, value, colour, window),
    do:
      outline({x, y, x + width, y + height}, colour, window) ++
        rectangle({x, y, x + width * value, y + height}, colour, window)

  @doc """
  The yes-or-no box (`drawConfirmBox`): the screen dimmed, a 250 × 200 box in its
  middle with `text` centred in it, wrapped at 218 units, lines 20 apart, and the
  `no` and `yes` prompt lines at its bottom right.
  """
  @spec confirm(String.t(), String.t(), String.t(), String.t(), window()) :: [map()]
  def confirm(font, text, no, yes, window) do
    {width, height, x, y, pad} = {250, 200, 195, 100, 16}

    shade({60, 0, 0}, 0.75, window) ++
      box("sprtextBgBox", {x, y, width, height}, window) ++
      rich(font, text, {x + width / 2, y + height / 2}, window,
        halign: :center,
        valign: :middle,
        wrap: width - pad * 2,
        line_height: 20
      ) ++
      rich(font, no, {x + width - pad, y + height - pad - 20}, window,
        halign: :right,
        valign: :bottom
      ) ++
      rich(font, yes, {x + width - pad, y + height - pad}, window,
        halign: :right,
        valign: :bottom
      )
  end

  @doc """
  The `items` inside `{left, top, right, bottom}`: rectangles cut to it, and every other
  item kept when its position is inside it.
  """
  @spec clip([map()], {number(), number(), number(), number()}, window()) :: [map()]
  def clip(items, {left, top, right, bottom}, window) do
    zoom = zoom(window)
    box = {left * zoom, top * zoom, (right + 1) * zoom, (bottom + 1) * zoom}
    Enum.flat_map(items, &clipped(&1, box))
  end

  defp clipped(
         %{picture: :pixel, position: {x, y}, scale: {width, height}} = item,
         {left, top, right, bottom}
       ) do
    {x1, y1} = {max(x, left), max(y, top)}
    {x2, y2} = {min(x + width, right), min(y + height, bottom)}

    if x2 > x1 and y2 > y1,
      do: [%{item | position: {x1, y1}, scale: {x2 - x1, y2 - y1}}],
      else: []
  end

  defp clipped(%{position: {x, y}} = item, {left, top, right, bottom}) do
    if x >= left and x < right and y >= top and y < bottom, do: [item], else: []
  end

  @doc """
  Draw list items laid out in GUI units, such as those draw code adds
  (`Cauldron2D.GameMaker.Draw`), as GUI items for `window`: positions and scales
  multiplied by the window's size over the GUI's.
  """
  @spec scaled([map()], window()) :: [map()]
  def scaled(items, window) do
    zoom = zoom(window)

    Enum.map(items, fn %{position: {x, y}} = item ->
      {scale_x, scale_y} = Map.get(item, :scale, {1, 1})

      item
      |> Map.merge(%{position: {x * zoom, y * zoom}, scale: {scale_x * zoom, scale_y * zoom}})
      |> Map.put(:depth, 0)
    end)
  end

  defp zoom({width, _height}), do: width / @gui_width
end
