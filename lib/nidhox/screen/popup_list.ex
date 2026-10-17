defmodule Nidhox.Screen.PopupList do
  @moduledoc """
  The window with a title and a scrolling list that the game's OPTIONS, VARIANTS,
  TOURNAMENT and CHANGE COLOR use (`PopupList`), in GUI units.

  `new(width, count, extra_height, max_rows)` lays it out: rows 20 apart, a 30-unit
  head, 12 of padding, at most `max_rows` rows shown (default 10), `extra_height` units
  between the head and the rows, the window centred across and a little above the
  middle of the screen. `navigate/2` moves the selection round the list on up and down,
  scrolling to keep it in view; `draw_window/4`, `draw_row/5`, `draw_value/5`,
  `draw_tick/5`, `draw_bar/5` and `draw_scrollbar/2` draw its parts.
  """

  alias Nidhox.Screen.{Gui, MainMenu}

  @row 20
  @head 30
  @pad 12

  @enforce_keys [:width, :count, :rows, :extra]
  defstruct [:width, :count, :rows, :extra, selection: 0, scroll: 0]

  @type t :: %__MODULE__{
          width: number(),
          count: non_neg_integer(),
          rows: non_neg_integer(),
          extra: number(),
          selection: non_neg_integer(),
          scroll: non_neg_integer()
        }

  @doc "A window `width` wide for `count` rows, with `extra_height` above them and at most `max_rows` shown."
  @spec new(number(), non_neg_integer(), number(), pos_integer()) :: t()
  def new(width, count, extra_height \\ 0, max_rows \\ 10),
    do: %__MODULE__{width: width, count: count, rows: min(count, max_rows), extra: extra_height}

  @doc "The window's height."
  @spec height(t()) :: number()
  def height(popup), do: @head + popup.extra + popup.rows * @row + @pad

  @doc "The window's left edge."
  @spec left(t()) :: number()
  def left(popup), do: 320 - popup.width / 2

  @doc "The window's top edge."
  @spec top(t()) :: number()
  def top(popup), do: 200 - (height(popup) + 46) / 2

  @doc "The top of the area under the head."
  @spec area_top(t()) :: number()
  def area_top(popup), do: top(popup) + @head

  @doc "The top of the list."
  @spec list_top(t()) :: number()
  def list_top(popup), do: area_top(popup) + popup.extra

  @doc "Where values are drawn to, right-aligned."
  @spec value_x(t()) :: number()
  def value_x(popup), do: left(popup) + popup.width - @pad - 8

  @doc "Where the prompts hang from, `{x, y}`."
  @spec prompt_at(t()) :: {number(), number()}
  def prompt_at(popup), do: {left(popup) + popup.width - 6, top(popup) + height(popup)}

  @doc "The window with row `index` selected and scrolled into view (`moveTo`)."
  @spec move_to(t(), non_neg_integer()) :: t()
  def move_to(%{count: count, rows: rows} = popup, index) when count > rows do
    scroll =
      popup.scroll |> max(index - rows + 2) |> min(index - 1) |> max(0) |> min(count - rows + 1)

    %{popup | selection: index, scroll: scroll}
  end

  def move_to(popup, index), do: %{popup | selection: index}

  @doc "The window after up and down in `players`' input, round the list, and whether it moved (`navigate`)."
  @spec navigate(t(), map()) :: {t(), boolean()}
  def navigate(popup, players) do
    step =
      if(MainMenu.any_pressed?(players, 3), do: 1, else: 0) -
        if(MainMenu.any_pressed?(players, 2), do: 1, else: 0)

    next = Integer.mod(popup.selection + step, max(popup.count, 1))
    if next == popup.selection, do: {popup, false}, else: {move_to(popup, next), true}
  end

  @doc "The top of row `index`, or `nil` when it is scrolled out of view."
  @spec row_top(t(), non_neg_integer()) :: number() | nil
  def row_top(popup, index) do
    if index >= popup.scroll and index < popup.scroll + popup.rows,
      do: list_top(popup) + (index - popup.scroll) * @row
  end

  @doc "The colour of row `index`: white when selected, else grey 150."
  @spec row_colour(t(), non_neg_integer()) :: Gui.rgb()
  def row_colour(%{selection: index}, index), do: {255, 255, 255}
  def row_colour(_popup, _index), do: Gui.grey(150)

  @doc "The window with `title` (`drawWindow`): the screen dimmed, the box, the title in yellow and a line under the head."
  @spec draw_window(t(), String.t(), String.t(), Gui.window()) :: [map()]
  def draw_window(popup, title, font, window) do
    {left, top, width} = {left(popup), top(popup), popup.width}
    line = area_top(popup) - 3

    MainMenu.dim(0.8, window) ++
      Gui.box("sprtextBgBox", {left, top, width, height(popup)}, window) ++
      Gui.text(font, title, {320, top + @head / 2}, window,
        halign: :center,
        valign: :middle,
        colour: {255, 255, 0}
      ) ++
      Gui.rectangle({left + @pad, line, left + width - @pad, line}, Gui.grey(50), window)
  end

  @doc "Row `index` with `label` in lower case (`drawRow`), its bar when selected."
  @spec draw_row(t(), non_neg_integer(), String.t(), String.t(), Gui.window()) :: [map()]
  def draw_row(popup, index, label, font, window) do
    case row_top(popup, index) do
      nil ->
        []

      top ->
        left = left(popup)

        bar =
          if index == popup.selection,
            do:
              Gui.rectangle(
                {left + 4, top, left + popup.width - 4, top + @row - 1},
                Gui.grey(30),
                window
              ),
            else: []

        bar ++
          Gui.rich(font, String.downcase(label), {left + @pad + 8, top + @row / 2}, window,
            valign: :middle,
            colour: row_colour(popup, index)
          )
    end
  end

  @doc "`< text >` right-aligned on the value edge of row `index` (`drawValue`)."
  @spec draw_value(t(), non_neg_integer(), String.t(), String.t(), Gui.window()) :: [map()]
  def draw_value(popup, index, text, font, window) do
    case row_top(popup, index) do
      nil ->
        []

      top ->
        Gui.text(
          font,
          "< " <> String.downcase(text) <> " >",
          {value_x(popup), top + @row / 2},
          window,
          halign: :right,
          valign: :middle,
          colour: row_colour(popup, index)
        )
    end
  end

  @doc "The on-or-off toggle of row `index` (`drawTick`)."
  @spec draw_tick(t(), non_neg_integer(), boolean(), String.t(), Gui.window()) :: [map()]
  def draw_tick(popup, index, on?, _font, window) do
    case row_top(popup, index) do
      nil ->
        []

      top ->
        Gui.sprite(
          "sprMenuToggle",
          if(on?, do: 1, else: 0),
          {value_x(popup) - 16, top + @row / 2 - 8},
          window,
          blend: row_colour(popup, index)
        )
    end
  end

  @doc "The slider of row `index` at `value` (`drawBar`)."
  @spec draw_bar(t(), non_neg_integer(), number(), String.t(), Gui.window()) :: [map()]
  def draw_bar(popup, index, value, _font, window) do
    case row_top(popup, index) do
      nil ->
        []

      top ->
        Gui.slider(
          {value_x(popup) - 64, top + @row / 2 - 4, 64, 8},
          value,
          row_colour(popup, index),
          window
        )
    end
  end

  @doc "The scrollbar, when the list has more rows than it shows (`drawScrollbar`)."
  @spec draw_scrollbar(t(), Gui.window()) :: [map()]
  def draw_scrollbar(%{count: count, rows: rows} = popup, window) when count > rows do
    track = rows * @row
    thumb = track * rows / (count + 1)
    list_top = list_top(popup)
    thumb_top = list_top + (track - thumb) * popup.scroll / (count - rows + 1)
    x = left(popup) + popup.width - 10

    Gui.rectangle({x, list_top, x + 3, list_top + track}, Gui.grey(50), window) ++
      Gui.rectangle({x, thumb_top, x + 3, thumb_top + thumb}, Gui.grey(150), window)
  end

  def draw_scrollbar(_popup, _window), do: []
end
