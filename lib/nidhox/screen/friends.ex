defmodule Nidhox.Screen.Friends do
  @moduledoc """
  INVITE FRIEND (`FriendsMenu`), a `Nidhox.Screen.PopupList` window over the online
  menu: the last 3 recent opponents under "Recent opponents", then under "Friends" the
  players heard on the local network (`Nidhox.Online`'s lobbies, each one's host),
  "Loading..." until the first lobbies are heard and "Nobody yet" when there are none.

  A player heard is in the game (green, "In game"); a recent opponent not heard shows
  the day they were last played (white). Up and down move round the players, skipping
  the headings. After the window's first 10 steps, select or start on a player heard
  closes it with `{:join, lobby}`, the player's lobby, and on any other with `{:invite,
  id, name}`; back closes it.

  `context` gives `self` (this player's id), `recent` (the prefs' recent opponents,
  each `%{id, date, name}`), `lobbies`, `heard_at`, `language`, `devices` and
  `prompt_side`.
  """

  alias Nidhox.{Glyphs, Lang}
  alias Nidhox.Screen.{Gui, MainMenu, PopupList}

  @width 360
  @most_rows 12
  @shown_recent 3
  @ready_steps 10
  @in_game {128, 255, 64}

  defstruct popup: nil, age: 0, keep: nil

  @type t :: %__MODULE__{
          popup: PopupList.t() | nil,
          age: non_neg_integer(),
          keep: integer() | nil
        }

  @doc "The window as it opens."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "The window after a step of `players`' input; see the module documentation."
  @spec step(t(), map(), map()) :: {:open, t(), [term()]} | {:closed, [term()]}
  def step(window, players, context) do
    rows = rows(context)
    window = %{window | age: window.age + 1, popup: placed(window, rows)}

    cond do
      window.age < @ready_steps ->
        {:open, window, []}

      MainMenu.any_pressed?(players, 9) ->
        {:closed, []}

      MainMenu.any_pressed?(players, 8) or MainMenu.any_pressed?(players, 10) ->
        chosen(window, rows, context)

      true ->
        navigated(window, rows, players)
    end
  end

  defp chosen(window, rows, context) do
    case Enum.at(rows, window.popup.selection) do
      %{id: id, name: name} ->
        case heard(context, id) do
          nil -> {:closed, [{:sound, :choose}, {:invite, id, name}]}
          lobby -> {:closed, [{:sound, :choose}, {:join, lobby}]}
        end

      _heading ->
        {:open, window, []}
    end
  end

  defp navigated(window, rows, players) do
    direction =
      if(MainMenu.any_pressed?(players, 3), do: 1, else: 0) -
        if MainMenu.any_pressed?(players, 2), do: 1, else: 0

    next = next_selectable(rows, window.popup.selection, direction)

    if next == window.popup.selection do
      {:open, window, []}
    else
      popup = PopupList.move_to(window.popup, next)
      {:open, %{window | popup: popup, keep: Enum.at(rows, next).id}, [{:sound, :move}]}
    end
  end

  defp next_selectable(_rows, from, 0), do: from
  defp next_selectable([], from, _direction), do: from

  defp next_selectable(rows, from, direction) do
    count = length(rows)

    Enum.reduce_while(1..count, from, fn _try, at ->
      at = Integer.mod(at + direction, count)
      if selectable?(Enum.at(rows, at)), do: {:halt, at}, else: {:cont, at}
    end)
  end

  defp placed(window, rows) do
    popup = PopupList.new(@width, max(length(rows), 1), 0, @most_rows)
    previous = window.popup

    selected =
      Enum.find_index(rows, &(selectable?(&1) and &1.id == window.keep)) ||
        Enum.find_index(rows, &selectable?/1) || 0

    popup =
      if previous,
        do: %{popup | scroll: min(previous.scroll, max(popup.count - popup.rows, 0))},
        else: popup

    PopupList.move_to(popup, selected)
  end

  defp rows(context) do
    recent = Enum.take(context.recent, @shown_recent)
    seen = Enum.map(recent, & &1.id)

    recent_rows =
      if recent == [],
        do: [],
        else: [
          %{header: text(context, "recent_opponents", "Recent opponents")}
          | Enum.map(recent, &person(&1, context))
        ]

    heard =
      context.lobbies
      |> Enum.reject(&(&1.owner == context.self or &1.owner in seen))
      |> Enum.uniq_by(& &1.owner)
      |> Enum.map(&person(%{id: &1.owner, name: &1.name, date: 0}, context))

    people =
      cond do
        heard != [] -> heard
        context.heard_at == nil -> [%{note: text(context, "loading", "Loading...")}]
        true -> [%{note: text(context, "nobody_yet", "Nobody yet")}]
      end

    recent_rows ++ [%{header: text(context, "friends", "Friends")} | people]
  end

  defp person(%{id: id, name: name, date: date}, context),
    do: %{id: id, name: name, date: date, in_game?: heard(context, id) != nil}

  defp heard(context, id), do: Enum.find(context.lobbies, &(&1.owner == id))

  defp selectable?(%{id: _id}), do: true
  defp selectable?(_row), do: false

  @doc "The window as GUI items."
  @spec items(t(), map(), Gui.window()) :: [map()]
  def items(%{popup: nil}, _context, _window), do: []

  def items(window, context, size) do
    font = Lang.font(context.language)
    popup = window.popup
    rows = rows(context)
    title = String.upcase(text(context, "invite_friend", "Invite friend"))

    PopupList.draw_window(popup, title, font, size) ++
      Enum.flat_map(Enum.with_index(rows), &row(popup, &1, context, font, size)) ++
      PopupList.draw_scrollbar(popup, size) ++
      Gui.prompts(prompts(window, rows, context), PopupList.prompt_at(popup), font, size)
  end

  defp row(popup, {row, index}, context, font, size) do
    case PopupList.row_top(popup, index) do
      nil -> []
      top -> drawn(popup, row, index, top + 10, context, font, size)
    end
  end

  defp drawn(popup, %{header: header}, _index, middle, _context, font, size),
    do:
      Gui.text(font, String.upcase(header), {PopupList.left(popup) + 12, middle}, size,
        valign: :middle,
        colour: Gui.grey(100)
      )

  defp drawn(popup, %{note: note}, _index, middle, _context, font, size),
    do:
      Gui.text(font, String.upcase(note), {PopupList.left(popup) + 20, middle}, size,
        valign: :middle,
        colour: Gui.grey(150)
      )

  defp drawn(popup, person, index, middle, context, font, size) do
    colour =
      cond do
        person.in_game? -> @in_game
        person.date > 0 -> {255, 255, 255}
        true -> Gui.grey(150)
      end

    colour = if index == popup.selection, do: darker(colour), else: colour

    status =
      cond do
        person.in_game? -> text(context, "in_game", "In game")
        person.date > 0 -> date_text(person.date)
        true -> ""
      end

    PopupList.draw_row(popup, index, "", font, size) ++
      Gui.text(font, String.upcase(person.name), {PopupList.left(popup) + 20, middle}, size,
        valign: :middle,
        colour: colour
      ) ++
      Gui.text(font, String.upcase(status), {PopupList.value_x(popup), middle}, size,
        halign: :right,
        valign: :middle,
        colour: colour
      )
  end

  defp darker({red, green, blue}), do: {round(red * 0.6), round(green * 0.6), round(blue * 0.6)}

  @doc "A `yyyymmdd` day as `YYYY-MM-DD` (`netDateText`), `\"\"` before the year 1000."
  @spec date_text(number()) :: String.t()
  def date_text(date) do
    date = round(date)

    if date < 10_000_101,
      do: "",
      else: "#{div(date, 10_000)}-#{pad(rem(div(date, 100), 100))}-#{pad(rem(date, 100))}"
  end

  defp pad(value), do: value |> Integer.to_string() |> String.pad_leading(2, "0")

  defp prompts(window, rows, context) do
    device = context.devices[context.prompt_side]

    confirm =
      case Enum.at(rows, window.popup.selection) do
        %{id: id} ->
          if heard(context, id),
            do: text(context, "prompt_join", "join"),
            else: text(context, "prompt_invite", "invite")

        _heading ->
          Lang.text(context.language, "main menu", "prompt_select", "select")
      end

    [
      glyph(device, 8) <> " " <> confirm,
      glyph(device, 9) <> " " <> Lang.text(context.language, "main menu", "prompt_back", "back")
    ]
  end

  defp glyph(device, button), do: Gui.glyph(Glyphs.icon(device, button))
  defp text(context, key, english), do: Lang.text(context.language, "online match", key, english)
end
