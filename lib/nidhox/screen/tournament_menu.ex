defmodule Nidhox.Screen.TournamentMenu do
  @moduledoc """
  TOURNAMENT (`TournamentMenu`), a `Nidhox.Screen.PopupList` window over the main menu:
  a preview of the bracket, then PLAYERS, MAP, VARIANTS and START TOURNAMENT.

  `step/3` gives `{:open, window, events}` or `{:closed, events}`. Every step it asks
  for the preview's `Tournament` to be held still (`:tournament_held`). After its first
  10 steps, up and down move round the list:

    * PLAYERS — left and right, or select or start, step the number of players from 3
      to 8 and round (`{:entrants, count}`); the preview is made again for them
    * MAP — left and right, or select or start, step the area through the level
      select's order (`{:area, area}`)
    * VARIANTS — select or start opens `Nidhox.Screen.Variants` over the window, which
      takes the input until it closes
    * START TOURNAMENT — select or start closes the window with `:start_tournament`

  Back closes it with `:tournament_closed` and `:reset_variants`. `context` gives
  `entrants`, `area`, `rules`, `world` (whose `Tournament` the preview draws),
  `language`, `devices` and `prompt_side`.
  """

  alias Nidhox.{Glyphs, Lang}
  alias Nidhox.Objects.Tournament
  alias Nidhox.Screen.{Gui, Levels, MainMenu, PopupList, Variants}

  @items [
    {:players, "players", "PLAYERS"},
    {:map, "map", "MAP"},
    {:variants, "variants", "VARIANTS"},
    {:start, "start_tournament", "START TOURNAMENT"}
  ]

  @width 360
  @preview_height 160
  @pad 12
  @fewest 3
  @choices 6
  @ready_steps 10

  defstruct popup: nil, variants: nil, age: 0

  @type t :: %__MODULE__{
          popup: PopupList.t(),
          variants: Variants.t() | nil,
          age: non_neg_integer()
        }

  @doc "TOURNAMENT with PLAYERS selected; the caller makes the preview's `Tournament`."
  @spec new() :: t()
  def new, do: %__MODULE__{popup: PopupList.new(@width, length(@items), @preview_height)}

  @doc "The window after `players`' input; see the module documentation."
  @spec step(t(), map(), map()) :: {:open, t(), [term()]} | {:closed, [term()]}
  def step(%{variants: nil} = window, players, context) do
    window = %{window | age: window.age + 1}

    if window.age < @ready_steps,
      do: {:open, window, [:tournament_held]},
      else: listed(window, players, context)
  end

  def step(window, players, context) do
    window = %{window | age: 0}

    case Variants.step(window.variants, players, context) do
      {:open, variants, events} ->
        {:open, %{window | variants: variants}, [:tournament_held | events]}

      {:closed, events} ->
        {:open, %{window | variants: nil}, [:tournament_held | events]}
    end
  end

  defp listed(window, players, context) do
    {popup, moved?} = PopupList.navigate(window.popup, players)
    window = %{window | popup: popup}
    moved = if moved?, do: [{:sound, :move}], else: []
    confirm? = MainMenu.any_pressed?(players, 8) or MainMenu.any_pressed?(players, 10)
    direction = if confirm?, do: 1, else: pressed(players, 1) - pressed(players, 0)
    {name, _key, _english} = Enum.at(@items, popup.selection)

    case chosen(window, name, direction, confirm?, context) do
      {:closed, events} ->
        {:closed, moved ++ events}

      {window, events} ->
        if MainMenu.any_pressed?(players, 9),
          do: {:closed, moved ++ events ++ [:tournament_closed, :reset_variants]},
          else: {:open, window, [:tournament_held | moved ++ events]}
    end
  end

  defp chosen(window, :players, direction, _confirm?, context) when direction != 0 do
    entrants = @fewest + Integer.mod(context.entrants - @fewest + direction + @choices, @choices)
    {window, [{:sound, :move}, {:entrants, entrants}]}
  end

  defp chosen(window, :map, direction, _confirm?, context) when direction != 0,
    do: {window, [{:sound, :move}, {:area, Levels.next(context.area, direction)}]}

  defp chosen(window, :variants, _direction, true, context),
    do:
      {%{window | variants: Variants.new(context.rules, prompt_side: context.prompt_side)},
       [{:sound, :choose}]}

  defp chosen(_window, :start, _direction, true, _context),
    do: {:closed, [{:sound, :choose}, :start_tournament]}

  defp chosen(window, _name, _direction, _confirm?, _context), do: {window, []}

  defp pressed(players, button), do: if(MainMenu.any_pressed?(players, button), do: 1, else: 0)

  @doc "The window's drawing as GUI items, VARIANTS over it while open."
  @spec items(t(), map(), Gui.window()) :: [map()]
  def items(window, context, size) do
    font = Lang.font(context.language)
    popup = window.popup

    shown =
      PopupList.draw_window(popup, text(context, "tournament", "TOURNAMENT"), font, size) ++
        preview(popup, context, size) ++
        rows(popup, context, font, size) ++
        PopupList.draw_scrollbar(popup, size) ++
        Gui.prompts(prompts(popup, context), PopupList.prompt_at(popup), font, size)

    case window.variants do
      nil -> shown
      variants -> shown ++ Variants.items(variants, context, size)
    end
  end

  defp preview(popup, context, size) do
    x = PopupList.left(popup) + @pad
    y = PopupList.area_top(popup) + 2
    width = popup.width - @pad * 2
    height = @preview_height - 8

    Gui.rectangle({x, y, x + width, y + height}, Gui.grey(40), size) ++
      Gui.scaled(Tournament.drawn_bracket(context.world, {x + 8, y, width - 16, height}), size)
  end

  defp rows(popup, context, font, size) do
    @items
    |> Enum.with_index()
    |> Enum.flat_map(fn {{name, key, english}, index} ->
      PopupList.draw_row(popup, index, text(context, key, english), font, size) ++
        value(popup, index, name, context, font, size)
    end)
  end

  defp value(popup, index, :players, context, font, size),
    do: PopupList.draw_value(popup, index, Integer.to_string(context.entrants), font, size)

  defp value(popup, index, :map, context, font, size),
    do: PopupList.draw_value(popup, index, Levels.name(context.area), font, size)

  defp value(_popup, _index, _name, _context, _font, _size), do: []

  defp prompts(popup, context) do
    device = context.devices[context.prompt_side]

    first =
      case Enum.at(@items, popup.selection) do
        {name, _key, _english} when name in [:players, :map] ->
          prompt(device, [0, 1], context, "prompt_adjust", "adjust")

        _other ->
          prompt(device, [8], context, "prompt_select", "select")
      end

    [first, prompt(device, [9], context, "prompt_back", "back")]
  end

  defp prompt(device, buttons, context, key, english),
    do:
      Enum.map_join(buttons, &Gui.glyph(Glyphs.icon(device, &1))) <>
        " " <> text(context, key, english)

  defp text(context, key, english), do: Lang.text(context.language, "main menu", key, english)
end
