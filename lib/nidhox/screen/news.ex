defmodule Nidhox.Screen.News do
  @moduledoc """
  NEWS (`NewsMenu`), a window over the main menu: the copy's articles (`Nidhox.News`)
  listed with their dates, an unread one with a dot, and the chosen one opened to read.

  On the list, up and down move (without wrapping), select or start opens the article
  and marks it read (`step/3` gives `{:read, key}`), back closes NEWS. An article opens
  and closes over 10 steps. While it is open, holding up or down scrolls its text 4 units
  a step; select on an article with a link asks for the link on the player's clipboard
  (`{:link, url}`), and back or start, or select on one without a link, closes it. The
  window ignores input for its first 10 steps and while an article is opening or
  closing.

  An article shows its title, its body, a video's place (its file named in the box the
  game plays it in), its second body, and its link. Bodies are drawn as the game draws
  them (`drawNewsBody`): a line by itself for every line of the text, those starting
  `- ` as bullets indented by the width of `- `, wrapped at the article's width.
  """

  alias Nidhox.{Glyphs, Lang}
  alias Nidhox.Screen.{Gui, MainMenu}

  @rows 8
  @row 20
  @head 30
  @pad 12
  @window_width 408
  @view_height 200
  @line 16
  @ready_steps 10
  @scroll 4
  @video {213, 120}

  defstruct selection: 0, scroll: 0, reading: false, open: 0.0, text_scroll: 0, age: 0

  @type t :: %__MODULE__{
          selection: non_neg_integer(),
          scroll: non_neg_integer(),
          reading: boolean(),
          open: float(),
          text_scroll: number(),
          age: non_neg_integer()
        }

  @doc "NEWS with its first article selected."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  The window after `players`' input; `context` gives `news` (the articles), `language`
  and the rest `items/3` needs. Events: `{:sound, :move | :choose}`, `{:read, key}`,
  `{:link, url}`.
  """
  @spec step(t(), map(), map()) :: {:open, t(), [term()]} | {:closed, [term()]}
  def step(window, players, context) do
    window = %{window | age: window.age + 1}

    window = %{
      window
      | open: (window.open + if(window.reading, do: 0.1, else: -0.1)) |> max(0.0) |> min(1.0)
    }

    cond do
      window.age < @ready_steps -> {:open, window, []}
      window.reading -> reading(window, players, context)
      true -> listing(window, players, context)
    end
  end

  defp reading(%{open: open} = window, _players, _context) when open < 1, do: {:open, window, []}

  defp reading(window, players, context) do
    item = Enum.at(context.news, window.selection)
    scroll = window.text_scroll + held(players, :down) - held(players, :up)
    window = %{window | text_scroll: scroll |> max(0) |> min(scroll_max(item, context))}
    link = Map.get(item, :url)

    cond do
      link != nil and MainMenu.any_pressed?(players, 8) ->
        {:open, window, [{:sound, :choose}, {:link, link}]}

      Enum.any?([9, 8, 10], &MainMenu.any_pressed?(players, &1)) ->
        {:open, %{window | reading: false}, [{:sound, :choose}]}

      true ->
        {:open, window, []}
    end
  end

  defp listing(%{open: open} = window, _players, _context) when open > 0, do: {:open, window, []}

  defp listing(window, players, context) do
    last = max(length(context.news) - 1, 0)
    step = pressed(players, 3) - pressed(players, 2)
    selection = (window.selection + step) |> max(0) |> min(last)

    {window, moved} =
      if selection != window.selection,
        do:
          {%{
             window
             | selection: selection,
               scroll: window.scroll |> max(selection - @rows + 1) |> min(selection)
           }, [{:sound, :move}]},
        else: {window, []}

    cond do
      MainMenu.any_pressed?(players, 9) ->
        {:closed, moved}

      context.news != [] and
          (MainMenu.any_pressed?(players, 8) or MainMenu.any_pressed?(players, 10)) ->
        key = Enum.at(context.news, window.selection).key

        {:open, %{window | reading: true, text_scroll: 0},
         moved ++ [{:sound, :choose}, {:read, key}]}

      true ->
        {:open, window, moved}
    end
  end

  defp held(players, action),
    do: if(Enum.any?(Map.values(players), &(action in &1.held)), do: @scroll, else: 0)

  defp pressed(players, button), do: if(MainMenu.any_pressed?(players, button), do: 1, else: 0)

  defp text_width, do: @window_width - @pad * 2 - 8

  defp scroll_max(item, context), do: max(0, content_height(item, context) - @view_height)

  defp content_height(item, context) do
    font = Lang.font(context.language)
    height = body_height(font, field(item, :body, context))
    height = if Map.has_key?(item, :video), do: height + 8 + elem(@video, 1), else: height

    height =
      if Map.has_key?(item, :body2),
        do: height + 8 + body_height(font, field(item, :body2, context)),
        else: height

    if Map.has_key?(item, :url), do: height + 8 + body_height(font, item.url), else: height
  end

  defp body_height(font, text) do
    text
    |> String.split("\n")
    |> Enum.map(fn line ->
      {_bullet, body} = bullet(font, line)

      if body == "",
        do: @line,
        else: elem(Gui.rich_size(font, body, wrap: text_width(), line_height: @line), 1)
    end)
    |> Enum.sum()
  end

  defp bullet(font, "- " <> body), do: {Gui.text_width(font, "- "), body}
  defp bullet(_font, line), do: {0, line}

  @doc "The window's drawing as GUI items; `context` gives `news`, `seen` (the keys read), `language`, `devices` and `prompt_side`."
  @spec items(t(), map(), Gui.window()) :: [map()]
  def items(window, context, size) do
    font = Lang.font(context.language)
    count = length(context.news)
    t = 1 - :math.pow(1 - window.open, 3)
    {list_width, list_height} = {@window_width - 32, @head + @view_height + @pad - 32}
    window_height = @head + @view_height + @pad
    {list_x, list_y} = {320 - list_width / 2, 200 - list_height / 2}
    {window_x, window_y} = {320 - @window_width / 2, 200 - window_height / 2}

    box =
      {lerp(list_x, window_x, t), lerp(list_y, window_y, t), lerp(list_width, @window_width, t),
       lerp(list_height, window_height, t)}

    top = list_y + @head
    device = context.devices[context.prompt_side]

    MainMenu.dim(0.8, size) ++
      Gui.box("sprtextBgBox", box, size) ++
      Gui.text(font, text(context, "main menu", "news", "NEWS"), {320, list_y + @head / 2}, size,
        halign: :center,
        valign: :middle,
        colour: {255, 255, 0}
      ) ++
      Gui.rectangle(
        {list_x + @pad, top - 3, list_x + list_width - @pad, top - 3},
        Gui.grey(50),
        size
      ) ++
      list_rows(window, context, {list_x, top, list_width}, font, size, count) ++
      article(
        window,
        context,
        {list_x, top, list_width},
        {window_x, window_y, window_height},
        t,
        font,
        size
      ) ++
      Gui.prompts(
        prompts(window, context, device),
        {elem(box, 0) + elem(box, 2) - 6, elem(box, 1) + elem(box, 3)},
        font,
        size
      )
  end

  defp lerp(from, to, t), do: round(from + (to - from) * t)

  defp list_rows(window, context, {list_x, top, list_width}, font, size, count) do
    for index <- window.scroll..min(count, window.scroll + @rows)//1,
        index < count,
        item = Enum.at(context.news, index),
        row_top = top + (index - window.scroll) * @row,
        piece <- list_row(window, item, index, {list_x, row_top, list_width}, context, font, size),
        do: piece
  end

  defp list_row(window, item, index, {list_x, row_top, list_width}, context, font, size) do
    selected? = index == window.selection
    middle = row_top + @row / 2

    bar =
      if selected?,
        do:
          Gui.rectangle(
            {list_x + 4, row_top, list_x + list_width - 4, row_top + @row - 1},
            Gui.grey(30),
            size
          ),
        else: []

    dot =
      if item.key in context.seen,
        do: [],
        else: Gui.sprite("sNewDot", 0, {list_x + @pad + 4, middle}, size, scale: {2, 2})

    bar ++
      dot ++
      Gui.rich(font, field(item, :title, context), {list_x + @pad + 16, middle}, size,
        valign: :middle,
        colour: if(selected?, do: {255, 255, 255}, else: Gui.grey(150))
      ) ++
      Gui.text(font, item.date, {list_x + list_width - @pad - 8, middle}, size,
        halign: :right,
        valign: :middle,
        colour: Gui.grey(150)
      )
  end

  defp article(%{open: open}, _context, _list, _window_box, _t, _font, _size) when open <= 0,
    do: []

  defp article(
         window,
         context,
         {list_x, top, list_width},
         {window_x, window_y, window_height},
         t,
         font,
         size
       ) do
    item = Enum.at(context.news, window.selection)
    row_top = top + (window.selection - window.scroll) * @row

    rect =
      {lerp(list_x + 4, window_x + 2, t), lerp(row_top, window_y + 2, t),
       lerp(list_x + list_width - 4, window_x + @window_width - 2, t),
       lerp(row_top + @row, window_y + window_height - 2, t)}

    background = merge(Gui.grey(30), t)
    view_top = window_y + @head
    view_bottom = view_top + @view_height

    content =
      body(
        font,
        field(item, :body, context),
        {window_x + @pad, view_top - window.text_scroll},
        size
      )
      |> then(fn {items, height} -> {items, view_top - window.text_scroll + height} end)
      |> video(item, window_x, font, size)
      |> second_body(item, context, window_x, font, size)
      |> link(item, window_x, font, size)

    Gui.rectangle(rect, background, size) ++
      Gui.clip(
        Gui.clip(
          elem(content, 0),
          {window_x, view_top, window_x + @window_width, view_bottom - 1},
          size
        ),
        rect,
        size
      ) ++
      Gui.clip(
        Gui.rich(
          font,
          field(item, :title, context),
          {window_x + @window_width / 2, window_y + @head / 2},
          size,
          halign: :center,
          valign: :middle,
          colour: {255, 255, 0}
        ) ++
          Gui.rectangle(
            {window_x + @pad, view_top - 3, window_x + @window_width - @pad, view_top - 3},
            Gui.grey(50),
            size
          ) ++
          scrollbar(window, item, context, {window_x, view_top}, size),
        rect,
        size
      )
  end

  defp merge({r, g, b}, t), do: {round(r * (1 - t)), round(g * (1 - t)), round(b * (1 - t))}

  defp body(font, text, {x, y}, size) do
    text
    |> String.split("\n")
    |> Enum.reduce({[], 0}, fn line, {items, height} ->
      body_line(font, bullet(font, line), {x, y + height}, size, {items, height})
    end)
  end

  defp body_line(_font, {_indent, ""}, _at, _size, {items, height}), do: {items, height + @line}

  defp body_line(font, {indent, words}, {x, top}, size, {items, height}) do
    {_width, line_height} =
      Gui.rich_size(font, words, wrap: text_width() - indent, line_height: @line)

    bullet_items = if indent > 0, do: Gui.text(font, "-", {x, top}, size), else: []

    {items ++
       bullet_items ++
       Gui.rich(font, words, {x + indent, top}, size,
         wrap: text_width() - indent,
         line_height: @line
       ), height + line_height}
  end

  defp video({items, y}, %{video: name}, window_x, font, size) do
    {width, height} = @video
    x = window_x + div(@window_width - width, 2)
    top = y + 8

    {items ++
       Gui.rectangle({x, top, x + width - 1, top + height - 1}, {0, 0, 0}, size) ++
       Gui.text(font, name, {x + width / 2, top + height / 2}, size,
         halign: :center,
         valign: :middle,
         colour: Gui.grey(150)
       ), top + height}
  end

  defp video(content, _item, _window_x, _font, _size), do: content

  defp second_body({items, y}, %{body2: _text} = item, context, window_x, font, size) do
    {more, height} = body(font, field(item, :body2, context), {window_x + @pad, y + 8}, size)
    {items ++ more, y + 8 + height}
  end

  defp second_body(content, _item, _context, _window_x, _font, _size), do: content

  defp link({items, y}, %{url: url}, window_x, font, size) do
    {more, height} = body(font, "[c_aqua]" <> url <> "[/c]", {window_x + @pad, y + 8}, size)
    {items ++ more, y + 8 + height}
  end

  defp link(content, _item, _window_x, _font, _size), do: content

  defp scrollbar(window, item, context, {window_x, view_top}, size) do
    scroll_max = scroll_max(item, context)

    if scroll_max > 0 do
      thumb = max(8, @view_height * (@view_height / (@view_height + scroll_max)))
      thumb_top = view_top + (@view_height - thumb) * (window.text_scroll / scroll_max)
      x = window_x + @window_width - 10

      Gui.rectangle({x, view_top, x + 3, view_top + @view_height}, Gui.grey(50), size) ++
        Gui.rectangle({x, thumb_top, x + 3, thumb_top + thumb}, Gui.grey(150), size)
    else
      []
    end
  end

  defp prompts(window, context, device) do
    back = glyph(device, 9) <> " " <> text(context, "main menu", "prompt_back", "back")

    if window.reading do
      item = Enum.at(context.news, window.selection)

      link =
        if Map.has_key?(item, :url),
          do: [glyph(device, 8) <> " " <> field(item, :button, context)],
          else: []

      scroll =
        if scroll_max(item, context) > 0,
          do: [
            glyph(device, 2) <>
              glyph(device, 3) <> " " <> text(context, "news", "prompt_scroll", "scroll")
          ],
          else: []

      scroll ++ link ++ [back]
    else
      [glyph(device, 8) <> " " <> text(context, "main menu", "prompt_select", "select"), back]
    end
  end

  defp glyph(device, button), do: Gui.glyph(Glyphs.icon(device, button))

  defp field(item, field, context),
    do: Lang.text(context.language, "news", "#{item.key}_#{field}", Map.get(item, field, ""))

  defp text(context, section, key, english),
    do: Lang.text(context.language, section, key, english)
end
