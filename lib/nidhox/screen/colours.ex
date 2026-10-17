defmodule Nidhox.Screen.Colours do
  @moduledoc """
  CHANGE COLOR (`ColorMenu`), a `Nidhox.Screen.PopupList` window over the pause menu: a
  row for each side, P1 and P2, with the eight palette colours
  (`Nidhox.Bout.PlayerColour.palette/2`) as swatches, the side's own framed in white.

  After its first 10 steps, up and down move between the rows, and left and right move
  the selected side's colour round the palette, skipping the other side's: `step/3`
  gives `{:colour, side, colour}`. With a player on another machine, left and right
  move the colour of the side that pressed them, whatever row is selected. Back closes
  the window with `:colours_kept`, for the colours to be kept in the prefs.

  `context` gives `colours`, `remote?`, `world`, `language` and `devices`.
  """

  alias Nidhox.Bout.PlayerColour
  alias Nidhox.{Glyphs, Lang}
  alias Nidhox.Screen.{Gui, MainMenu, PopupList}

  @width 340
  @colours 8
  @swatch_width 22
  @swatch_height 12
  @gap 4
  @row 20
  @ready_steps 10

  defstruct popup: nil, age: 0, prompt_side: 1

  @type t :: %__MODULE__{popup: PopupList.t(), age: non_neg_integer(), prompt_side: 1 | 2}

  @doc "CHANGE COLOR with P1 selected, its prompts for `prompt_side`."
  @spec new(1 | 2) :: t()
  def new(prompt_side), do: %__MODULE__{popup: PopupList.new(@width, 2), prompt_side: prompt_side}

  @doc "The window after `players`' input; see the module documentation."
  @spec step(t(), map(), map()) :: {:open, t(), [term()]} | {:closed, [term()]}
  def step(window, players, context) do
    window = %{window | age: window.age + 1}

    if window.age < @ready_steps,
      do: {:open, window, []},
      else: listed(window, players, context)
  end

  defp listed(window, players, context) do
    {popup, _moved?} = PopupList.navigate(window.popup, players)
    window = %{window | popup: popup}

    if MainMenu.any_pressed?(players, 9),
      do: {:closed, [:colours_kept]},
      else: {:open, window, moved(window, players, context)}
  end

  defp moved(window, players, context) do
    case direction_and_side(window, players, context.remote?) do
      {0, _side} ->
        []

      {direction, side} ->
        other = Map.fetch!(context.colours, 3 - side)
        colour = next(Map.fetch!(context.colours, side), direction, other, 2)
        [{:colour, side, colour}, {:sound, :move}]
    end
  end

  defp direction_and_side(window, players, false),
    do: {pressed(players, 1) - pressed(players, 0), window.popup.selection + 1}

  defp direction_and_side(_window, players, true) do
    case Enum.find(
           [1, 2],
           &(MainMenu.pressed?(players, &1, 0) or MainMenu.pressed?(players, &1, 1))
         ) do
      nil -> {0, 1}
      side -> {side_pressed(players, side, 1) - side_pressed(players, side, 0), side}
    end
  end

  defp next(colour, _direction, _other, 0), do: colour

  defp next(colour, direction, other, tries) do
    stepped = 1 + Integer.mod(colour - 1 + direction + @colours, @colours)
    if stepped == other, do: next(stepped, direction, other, tries - 1), else: stepped
  end

  defp pressed(players, button), do: if(MainMenu.any_pressed?(players, button), do: 1, else: 0)

  defp side_pressed(players, side, button),
    do: if(MainMenu.pressed?(players, side, button), do: 1, else: 0)

  @doc "The window's drawing as GUI items."
  @spec items(t(), map(), Gui.window()) :: [map()]
  def items(window, context, size) do
    font = Lang.font(context.language)
    popup = window.popup
    title = Lang.text(context.language, "pause screen", "change_color", "CHANGE COLOR")

    PopupList.draw_window(popup, title, font, size) ++
      Enum.flat_map([1, 2], &row(popup, &1, context, font, size)) ++
      PopupList.draw_scrollbar(popup, size) ++
      Gui.prompts(prompts(window, context), PopupList.prompt_at(popup), font, size)
  end

  defp row(popup, side, context, font, size) do
    index = side - 1

    PopupList.draw_row(popup, index, "P#{side}", font, size) ++
      case PopupList.row_top(popup, index) do
        nil -> []
        top -> swatches(popup, top, Map.fetch!(context.colours, side), context.world, size)
      end
  end

  defp swatches(popup, top, current, world, size) do
    y = top + (@row - @swatch_height) / 2

    Enum.flat_map(1..@colours, fn colour ->
      x = PopupList.value_x(popup) - (@colours - colour + 1) * (@swatch_width + @gap) + @gap

      frame =
        if colour == current,
          do:
            Gui.box("sControlButton", {x - 2, y - 2, @swatch_width + 4, @swatch_height + 4}, size),
          else: []

      frame ++
        Gui.box("sControlButton", {x, y, @swatch_width, @swatch_height}, size,
          blend: PlayerColour.palette(world, colour)
        )
    end)
  end

  defp prompts(window, context) do
    device = context.devices[window.prompt_side]

    [
      glyphs(device, [0, 1]) <>
        " " <> Lang.text(context.language, "main menu", "prompt_adjust", "adjust"),
      glyphs(device, [9]) <>
        " " <> Lang.text(context.language, "main menu", "prompt_back", "back")
    ]
  end

  defp glyphs(device, buttons), do: Enum.map_join(buttons, &Gui.glyph(Glyphs.icon(device, &1)))
end
