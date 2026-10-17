defmodule Nidhox.Screen.MainMenu do
  @moduledoc """
  The game's main menu (`MainMenu` in `rMainMenu`): "press start" under the logo, then a
  set of lists drawn in a box, and the windows some items open over it.

  The lists, each a list of items:

    * `:main` — MULTIPLAYER, OPTIONS, EXTRAS, QUIT TO DESKTOP, NEWS, SINGLE PLAYER
    * `:extras` — HOW TO PLAY, CPU BATTLE, CREDITS, and NidhOX's CHALLENGE
    * `:single_player` — ARCADE, TRAINING
    * `:multiplayer` — LOCAL, ONLINE, TOURNAMENT
    * `:cpu_battle` — HYPE, TIME LIMIT, SUDDEN DEATH ONLY, BEGIN

  `step/3` takes both sides' input for a step and gives the menu and what the step asks
  of `Nidhox.Flow`, in order:

    * `{:sound, :move | :choose}` — the move (`sfxChangeLevel1`) or choose (`sndLevel`) sound
    * `{:go, item, side}` — the item chosen by the player on `side`, for every item that
      leaves the lists or opens a window (`:options`, `:quit`, `:news`, `:how_to_play`,
      `:credits`, `:arcade`, `:training`, `:local`, `:online`, `:tournament`,
      `:begin_cpu`, `:challenge`)
    * `{:hype, value}` — HYPE changed to `value`
    * `{:time_limit, step}`, `:sudden_death` — TIME LIMIT stepped, SUDDEN DEATH ONLY turned
    * `{:seen, key}` — the "new" marker `key` seen
    * `:reset_variants` — the variants back to their defaults (`variantsReset`)
    * `:idle_reset` — the attract mode's count started again

  The menu buttons are `Nidhox.Glyphs`'s: up and down move round a list, select (jump)
  or start chooses, back goes back (on the main list it selects QUIT TO DESKTOP, and on
  QUIT TO DESKTOP it chooses it), left and right change HYPE and TIME LIMIT. Choosing
  waits for the menu's first 60 steps. While a window is open (`window`), the lists take
  no input and nothing restarts the attract mode's count. The prompt side is the last side to press a menu button, side 1 when both
  do.

  `items/3` draws it, given `context`: the language, each side's device, the game's
  frame count, `hype`, `time_limit`, `sudden_death?`, and `new?/1`, whether an item shows
  the "new" dot.
  """

  alias Nidhox.{Glyphs, Lang}
  alias Nidhox.Screen.Gui

  @lists %{
    main: [:multiplayer, :options, :extras, :quit, :news, :single_player],
    extras: [:how_to_play, :cpu_battle, :credits, :challenge],
    single_player: [:arcade, :training],
    multiplayer: [:local, :online, :tournament],
    cpu_battle: [:hype, :time_limit, :sudden_death_only, :begin_cpu]
  }

  @labels %{
    multiplayer: {"multiplayer", "MULTIPLAYER"},
    options: {"options", "OPTIONS"},
    extras: {"extras", "EXTRAS"},
    quit: {"quit_to_desktop", "QUIT TO DESKTOP"},
    news: {"news", "NEWS"},
    single_player: {"single_player", "SINGLE PLAYER"},
    how_to_play: {"how_to_play", "HOW TO PLAY"},
    cpu_battle: {"cpu_battle", "CPU BATTLE"},
    credits: {"credits", "CREDITS"},
    challenge: {"challenge", "CHALLENGE"},
    arcade: {"arcade", "ARCADE"},
    training: {"training", "TRAINING"},
    local: {"offline_versus", "LOCAL"},
    online: {"online_versus", "ONLINE"},
    tournament: {"tournament", "TOURNAMENT"},
    hype: {"hype", "HYPE"},
    time_limit: {"time_limit", "TIME LIMIT"},
    sudden_death_only: {"sudden_death_only", "SUDDEN DEATH ONLY"},
    begin_cpu: {"begin", "BEGIN"}
  }

  @titles %{
    single_player: {"single_player", "SINGLE PLAYER"},
    multiplayer: {"multiplayer", "MULTIPLAYER"},
    extras: {"extras", "EXTRAS"}
  }

  @openers %{
    multiplayer: :multiplayer,
    extras: :extras,
    single_player: :single_player,
    cpu_battle: :cpu_battle
  }

  @leaves [
    :options,
    :quit,
    :news,
    :how_to_play,
    :credits,
    :arcade,
    :training,
    :local,
    :online,
    :tournament,
    :begin_cpu,
    :challenge
  ]

  @new_keys %{
    training: "training_2026_10",
    online: "online_2026_10",
    cpu_battle: "cpu_battle_2026_10",
    options: "options_2026_10"
  }

  @prompt_buttons [2, 3, 0, 1, 8, 10, 9]
  @row 20
  @ready_steps 60
  @ring_top 260
  @window_top 220
  @window_bottom 320
  @fits_middle 270
  @box_half 140
  @pad 8
  @title_shift 32
  @dim {60, 0, 0}

  defstruct list: nil,
            selection: nil,
            previous: nil,
            menu_y: 0,
            tween_y: 0.0,
            prompt_side: 1,
            room_frame: 0,
            window: nil

  @type list_name :: :main | :extras | :single_player | :multiplayer | :cpu_battle
  @type t :: %__MODULE__{
          list: list_name() | nil,
          selection: atom() | nil,
          previous: atom() | nil,
          menu_y: number(),
          tween_y: number(),
          prompt_side: 1 | 2,
          room_frame: non_neg_integer(),
          window: term()
        }

  @doc """
  A main menu at "press start", or with `resume` open at an item the player comes back
  to (`System.menuResume`): `:how_to_play` or `:credits` in EXTRAS, `:online` in
  MULTIPLAYER.
  """
  @spec new(atom() | nil) :: t()
  def new(nil), do: %__MODULE__{}

  def new(resume) when resume in [:how_to_play, :credits],
    do: %__MODULE__{
      list: :extras,
      selection: resume,
      previous: :extras,
      menu_y: menu_y(:extras, resume)
    }

  def new(:online),
    do: %__MODULE__{
      list: :multiplayer,
      selection: :online,
      previous: :multiplayer,
      menu_y: menu_y(:multiplayer, :online)
    }

  def new(_resume), do: %__MODULE__{}

  @doc "The menu opened at the main list, MULTIPLAYER selected."
  @spec opened(t()) :: t()
  def opened(menu), do: %{menu | list: :main, selection: :multiplayer, previous: :multiplayer}

  @doc "The \"new\" marker key of `item`, or `nil` (`menuNewKey`)."
  @spec new_key(atom()) :: String.t() | nil
  def new_key(item), do: Map.get(@new_keys, item)

  @doc "The items of list `name`."
  @spec list(list_name()) :: [atom()]
  def list(name), do: Map.fetch!(@lists, name)

  @doc "Whether the side's actions `players` press menu button `button` (see `Nidhox.Glyphs`)."
  @spec pressed?(map(), 1 | 2, non_neg_integer()) :: boolean()
  def pressed?(players, side, button) do
    case {Map.get(players, side), Glyphs.action(button)} do
      {%{pressed: pressed}, action} when action != nil -> action in pressed
      _none -> false
    end
  end

  @doc "Whether either side presses menu button `button`."
  @spec any_pressed?(map(), non_neg_integer()) :: boolean()
  def any_pressed?(players, button), do: Enum.any?([1, 2], &pressed?(players, &1, button))

  @doc "The side whose prompts show: the last of sides 2 and 1 to press a menu button, else `side`."
  @spec prompt_side(map(), 1 | 2) :: 1 | 2
  def prompt_side(players, side) do
    Enum.reduce([2, 1], side, fn checked, side ->
      if Enum.any?(@prompt_buttons, &pressed?(players, checked, &1)), do: checked, else: side
    end)
  end

  @doc "The menu after a step of `players`' input, with what the step asks of the flow."
  @spec step(t(), map(), map()) :: {t(), [term()]}
  def step(menu, players, context) do
    menu = %{
      menu
      | prompt_side: prompt_side(players, menu.prompt_side),
        room_frame: menu.room_frame + 1
    }

    if menu.window != nil,
      do: {menu, []},
      else: lists(menu, players, context)
  end

  defp lists(menu, players, context) do
    {menu, events} = moved(menu, players)
    events = events ++ adjusted(menu, players, context)
    {menu, more} = confirmed(menu, players)
    {%{menu | tween_y: menu.tween_y + (menu.menu_y - menu.tween_y) * 0.2}, events ++ more}
  end

  defp moved(%{list: nil} = menu, _players), do: {menu, []}

  defp moved(menu, players) do
    items = list(menu.list)
    index = Enum.find_index(items, &(&1 == menu.selection)) || 0

    step =
      cond do
        any_pressed?(players, 2) -> -1
        any_pressed?(players, 3) -> 1
        true -> 0
      end

    resets = if Enum.any?([5, 4, 0, 1], &any_pressed?(players, &1)), do: [:idle_reset], else: []

    if step == 0,
      do: {menu, resets},
      else:
        {select(menu, Enum.at(items, Integer.mod(index + step, length(items)))),
         [:idle_reset, {:sound, :move}]}
  end

  defp select(menu, item), do: %{menu | selection: item, menu_y: menu_y(menu.list, item)}

  defp menu_y(list, item), do: -(Enum.find_index(list(list), &(&1 == item)) || 0) * @row

  defp adjusted(menu, players, context) do
    direction =
      cond do
        any_pressed?(players, 0) -> -1
        any_pressed?(players, 1) -> 1
        true -> 0
      end

    case {direction, menu.selection} do
      {0, _item} -> []
      {direction, :hype} -> [{:hype, clamp(context.hype + direction * 0.1)}]
      {direction, :time_limit} -> [{:time_limit, direction}, {:sound, :move}]
      _other -> []
    end
  end

  defp clamp(value), do: (value * 10) |> round() |> max(0) |> min(10) |> Kernel./(10)

  defp confirmed(%{room_frame: frame} = menu, _players) when frame < @ready_steps, do: {menu, []}

  defp confirmed(menu, players) do
    side = Enum.find([1, 2], &(pressed?(players, &1, 8) or pressed?(players, &1, 10)))
    back = Enum.find([1, 2], &pressed?(players, &1, 9))
    respond(menu, side, back)
  end

  defp respond(%{list: nil} = menu, side, _back) when side != nil,
    do: {opened(menu), [{:sound, :choose}]}

  defp respond(menu, side, _back) when side != nil,
    do: go(menu, menu.selection, side, [{:sound, :choose}])

  defp respond(%{selection: :quit} = menu, nil, back) when back != nil,
    do: go(menu, :quit, back, [])

  defp respond(%{list: :main} = menu, nil, back) when back != nil, do: {select(menu, :quit), []}

  defp respond(%{list: list} = menu, nil, back) when back != nil and list != nil,
    do: {back(menu), []}

  defp respond(menu, _side, _back), do: {menu, []}

  defp go(menu, item, _side, events) when is_map_key(@openers, item) do
    list = Map.fetch!(@openers, item)
    menu = %{menu | previous: item, list: list}
    events = events ++ seen(item) ++ if(item == :cpu_battle, do: [:reset_variants], else: [])
    {select(menu, hd(list(list))), events}
  end

  defp go(menu, item, side, events) when item in @leaves,
    do: {menu, events ++ seen(item) ++ [{:go, item, side}]}

  defp go(menu, :sudden_death_only, _side, events), do: {menu, events ++ [:sudden_death]}
  defp go(menu, :time_limit, _side, events), do: {menu, events ++ [{:time_limit, 1}]}
  defp go(menu, _item, _side, events), do: {menu, events}

  defp seen(item) when item in [:training, :options, :cpu_battle], do: [{:seen, new_key(item)}]
  defp seen(_item), do: []

  @doc "The menu one list back from where it is (the back item): the list that holds it, at the item that opened it."
  @spec back(t()) :: t()
  def back(menu) do
    previous = if menu.list == :extras, do: :extras, else: menu.previous

    parent =
      case menu.list do
        :cpu_battle -> :extras
        _other -> :main
      end

    selection = if previous in list(parent), do: previous, else: hd(list(parent))
    select(%{menu | list: parent, previous: selection}, selection)
  end

  @doc "The menu's drawing as GUI items for `window`; see the module documentation for `context`."
  @spec items(t(), map(), {number(), number()}) :: [map()]
  def items(menu, context, window) do
    font = Lang.font(context.language)
    logo = Gui.sprite("sNewTitle", 0, {320, 136}, window, scale: {2, 2})

    case menu.list do
      nil -> logo ++ press_start(menu, context, font, window)
      list -> logo ++ shown_list(menu, list, context, font, window)
    end
  end

  defp press_start(_menu, context, font, window) do
    if rem(context.frame, 120) < 60,
      do:
        Gui.rich(font, press_start_text(context, 1), {320, 260}, window,
          halign: :center,
          valign: :middle
        ),
      else: []
  end

  @doc "The \"press {start}\" text (`pressStart`) for `side`'s device."
  @spec press_start_text(map(), 1 | 2) :: String.t()
  def press_start_text(context, side) do
    start = Gui.glyph(Glyphs.icon(context.devices[side], 10))
    Lang.text(context.language, "attract mode", "press_start", "press {0}", [start])
  end

  defp shown_list(menu, list, context, font, window) do
    items = list(list)
    size = length(items)
    title = Map.get(@titles, list)
    shift = if title, do: @title_shift, else: 0
    fits? = size < 7 and list != :main
    {y1, y2} = box_rows(fits?, size)
    title_text = title && localised(context, title)

    x1 =
      if title_text,
        do:
          min(
            320 + shift - @box_half - @pad,
            320 - 180 - Gui.text_width(font, title_text) * 0.75 - @pad
          ),
        else: 320 + shift - @box_half - @pad

    x2 = 320 + shift + @box_half + @pad

    Gui.box("sprtextBgBox", {x1, y1, x2 - x1, y2 - y1}, window) ++
      title_items(title_text, font, window) ++
      rows(menu, items, fits?, shift, context, font, window) ++
      Gui.prompts(prompts(menu, list, context), {x2 - 6, y2}, font, window)
  end

  defp box_rows(true, size),
    do: {@fits_middle - size * @row * 0.5 - @pad, @fits_middle + size * @row * 0.5 + @pad}

  defp box_rows(false, _size), do: {@window_top - @pad, @window_bottom + @pad}

  defp title_items(nil, _font, _window), do: []

  defp title_items(title, font, window),
    do:
      Gui.text(font, String.downcase(title), {140, 232}, window,
        halign: :center,
        valign: :middle,
        scale: {1.5, 1.5}
      )

  defp rows(menu, items, fits?, shift, context, font, window) do
    size = length(items)
    selected = Enum.find_index(items, &(&1 == menu.selection)) || 0
    total = size * @row
    origin = if fits?, do: @fits_middle - total / 2, else: @ring_top + menu.tween_y

    copies =
      if fits?,
        do: [origin],
        else: Enum.map(-2..2, &(origin + &1 * total))

    list = %{
      selected: selected,
      size: size,
      shift: shift,
      context: context,
      font: font,
      window: window
    }

    for copy <- copies,
        {item, index} <- Enum.with_index(items),
        top = copy + index * @row,
        fits? or (top >= @window_top - @row / 2 and top <= @window_bottom - @row / 2),
        row <- row(item, index, top, list),
        do: row
  end

  defp row(item, index, top, list) do
    %{selected: selected, size: size, shift: shift, context: context, font: font, window: window} =
      list

    label =
      String.downcase(localised(context, Map.fetch!(@labels, item)) <> suffix(item, context))

    distance = abs(index - selected)

    colour =
      cond do
        index == selected -> {255, 255, 255}
        distance == 1 or distance == size - 1 -> Gui.grey(80)
        true -> Gui.grey(30)
      end

    x = if item == :sudden_death_only, do: 320 - 11 + shift, else: 320 + shift
    middle = top + @row / 2
    width = Gui.text_width(font, label)

    bar =
      if index == selected,
        do:
          Gui.rectangle(
            {320 + shift - @box_half, top + 4, 320 + shift + @box_half, top + @row},
            Gui.grey(30),
            window
          ),
        else: []

    bar ++
      Gui.text(font, label, {x, middle}, window, halign: :center, valign: :middle, colour: colour) ++
      extras(item, {x, middle, width}, colour, context, window) ++
      dot(item, {x, middle, width}, context, window)
  end

  defp suffix(:time_limit, %{time_limit: 0} = context),
    do: " < " <> Lang.text(context.language, "main menu", "none", "NONE") <> " >"

  defp suffix(:time_limit, context), do: " < " <> time(context.time_limit) <> " >"
  defp suffix(_item, _context), do: ""

  defp time(steps) do
    seconds = div(round(steps), 60)
    "#{div(seconds, 60)}:#{String.pad_leading(Integer.to_string(rem(seconds, 60)), 2, "0")}"
  end

  defp extras(:hype, {x, middle, width}, colour, context, window),
    do: Gui.slider({x + width / 2 + 8, middle - 2, 64, 8}, context.hype, colour, window)

  defp extras(:sudden_death_only, {x, middle, width}, colour, context, window),
    do:
      Gui.sprite(
        "sprMenuToggle",
        if(context.sudden_death?, do: 1, else: 0),
        {round(x + width / 2) + 6, middle - 8},
        window,
        blend: colour
      )

  defp extras(_item, _place, _colour, _context, _window), do: []

  defp dot(item, {x, middle, width}, context, window) do
    if context.new?.(item),
      do: Gui.sprite("sNewDot", 0, {round(x + width / 2) + 10, middle}, window, scale: {2, 2}),
      else: []
  end

  defp prompts(menu, list, context) do
    device = context.devices[menu.prompt_side]

    select =
      glyph(device, 8) <>
        " " <> Lang.text(context.language, "main menu", "prompt_select", "select")

    back =
      glyph(device, 9) <> " " <> Lang.text(context.language, "main menu", "prompt_back", "back")

    adjust =
      glyph(device, 0) <>
        glyph(device, 1) <>
        " " <> Lang.text(context.language, "main menu", "prompt_adjust", "adjust")

    first = if menu.selection == :hype, do: adjust, else: select
    if list == :main, do: [first], else: [first, back]
  end

  defp glyph(device, button), do: Gui.glyph(Glyphs.icon(device, button))

  defp localised(context, {key, english}),
    do: Lang.text(context.language, "main menu", key, english)

  @doc "The screen's dim (`0x3c` at `alpha`) for windows drawn over the menu."
  @spec dim(number(), {number(), number()}) :: [map()]
  def dim(alpha, window), do: Gui.shade(@dim, alpha, window)
end
