defmodule Nidhox.Screen.MenuList do
  @moduledoc """
  A menu as the game's `MainMenu` shows one: its choices in a ring that turns to keep
  the selected one in the middle of a window from y 110 to 160, in lower case `fMenu`.

    * the list is laid out 10 apart and repeated a list's height above and below, the
      selected choice's middle at y 135, so the ring shows five lines and wraps
    * the selected choice is white over a bar of `make_color_hsv(0, 0, 30)` 140 wide; the
      choices next to it, the last and first counting as next to each other,
      `make_color_hsv(0, 0, 80)`; the rest `make_color_hsv(0, 0, 30)` — all added to
      what is under them (`bm_add`)
    * a menu with a title has it white at 1.5 times, from x 20 at y 116, and its ring
      32 to the right of the middle

  A choice is `{label, option}`, or `{label, option, level}` for one shown with a
  slider (`drawSlider`): its label ending 4 left of the ring's middle and, from 4 right
  of it, a box 32 wide and 4 tall in the line's colour, outlined and filled for `level`
  (0 to 1).

  `:up` and `:down` from either side move round the ring, `:attack` or `:start` choose,
  `:left` and `:right` change the selected choice's value, and `:jump` goes back.
  """

  alias Nidhox.Screen.Art

  @enforce_keys [:key, :choices]
  defstruct [:key, :title, :choices, selected: 0]

  @type choice :: {String.t(), term()} | {String.t(), term(), number()}
  @type t :: %__MODULE__{
          key: term(),
          title: String.t() | nil,
          choices: [choice(), ...],
          selected: non_neg_integer()
        }

  @spacing 10
  @middle 135
  @window {110, 160}
  @centre 160
  @titled_shift 32
  @bar_half 70
  @title_at {20, 116}
  @title_scale 1.5
  @white {255, 255, 255}
  @near {80, 80, 80}
  @far {30, 30, 30}
  @slider_gap 4
  @slider_width 32
  @slider_height 4

  @doc """
  The menu `key` of `choices`, under `title` (or `nil`), with the choice whose option is
  `selected` chosen, or the first.
  """
  @spec new(term(), String.t() | nil, [choice(), ...], term()) :: t()
  def new(key, title, [_ | _] = choices, selected \\ nil) do
    index = Enum.find_index(choices, &(elem(&1, 1) == selected)) || 0
    %__MODULE__{key: key, title: title, choices: choices, selected: index}
  end

  @doc "The menu with its choices relabelled to `choices`, the same option kept selected."
  @spec relabelled(t(), [choice(), ...]) :: t()
  def relabelled(%__MODULE__{} = menu, choices),
    do: new(menu.key, menu.title, choices, selected(menu))

  @doc "The option of the selected choice."
  @spec selected(t()) :: term()
  def selected(%__MODULE__{choices: choices, selected: index}),
    do: choices |> Enum.at(index) |> elem(1)

  @doc "The menu turned `step` choices round the ring."
  @spec turned(t(), integer()) :: t()
  def turned(%__MODULE__{choices: choices, selected: index} = menu, step),
    do: %{menu | selected: Integer.mod(index + step, length(choices))}

  @doc """
  What the players did this step: `{:choose, option, side}`, `{:change, option, step,
  side}` with `step` −1 or 1, `{:back, side}`, `{:moved, menu}` or `{:stay, menu}`.
  """
  @spec input(t(), %{1 => map(), 2 => map()}) ::
          {:choose, term(), 1 | 2}
          | {:change, term(), -1 | 1, 1 | 2}
          | {:back, 1 | 2}
          | {:moved, t()}
          | {:stay, t()}
  def input(%__MODULE__{} = menu, players) do
    case Enum.find_value([1, 2], &pressed(menu, &1, players[&1].pressed)) do
      nil -> {:stay, menu}
      outcome -> outcome
    end
  end

  @doc "The menu's GUI items over a window `{width, height}`."
  @spec items(t(), {number(), number()}) :: [map()]
  def items(%__MODULE__{} = menu, window) do
    centre = if menu.title, do: @centre + @titled_shift, else: @centre
    title(menu.title, window) ++ Enum.flat_map(lines(menu), &line(&1, centre, window))
  end

  defp pressed(menu, side, pressed) do
    cond do
      :start in pressed or :attack in pressed -> {:choose, selected(menu), side}
      :jump in pressed -> {:back, side}
      :up in pressed -> {:moved, turned(menu, -1)}
      :down in pressed -> {:moved, turned(menu, 1)}
      :left in pressed -> {:change, selected(menu), -1, side}
      :right in pressed -> {:change, selected(menu), 1, side}
      true -> nil
    end
  end

  defp lines(%__MODULE__{choices: choices, selected: selected}) do
    count = length(choices)
    height = count * @spacing
    {top, bottom} = @window
    first = @middle - @spacing / 2 - selected * @spacing - height

    for copy <- first |> Stream.iterate(&(&1 + height)) |> Enum.take_while(&(&1 < bottom)),
        {choice, index} <- Enum.with_index(choices),
        middle = copy + index * @spacing + @spacing / 2,
        middle > top and middle < bottom,
        do: {choice, middle, colour(index, selected, count)}
  end

  defp colour(selected, selected, _count), do: @white

  defp colour(index, selected, count) do
    if abs(index - selected) == 1 or abs(index - selected) == count - 1, do: @near, else: @far
  end

  defp line({choice, middle, colour}, centre, window),
    do: bar(colour, middle, centre, window) ++ shown(choice, middle, colour, centre, window)

  defp bar(@white, middle, centre, window) do
    {centre - @bar_half, middle - @spacing / 2, centre + @bar_half, middle + @spacing / 2 - 1}
    |> Art.rectangle(@far, window, false)
    |> added()
  end

  defp bar(_colour, _middle, _centre, _window), do: []

  defp shown({label, _option, level}, middle, colour, centre, window) do
    {top, bottom} = {middle - @slider_height / 2, middle + @slider_height / 2}
    from = centre + @slider_gap

    label(label, {centre - @slider_gap, middle}, :right, colour, window) ++
      added(Art.rectangle({from, top, from + @slider_width, bottom}, colour, window, true)) ++
      added(
        Art.rectangle({from, top, from + @slider_width * level, bottom}, colour, window, false)
      )
  end

  defp shown({label, _option}, middle, colour, centre, window),
    do: label(label, {centre, middle}, :center, colour, window)

  defp label(label, at, halign, colour, window),
    do:
      Art.text("fMenu", String.downcase(label), at, window,
        halign: halign,
        valign: :middle,
        colour: colour,
        mode: :add
      )

  defp added(items), do: Enum.map(items, &Map.put(&1, :mode, :add))

  defp title(nil, _window), do: []

  defp title(title, window),
    do:
      Art.text("fMenu", String.downcase(title), @title_at, window,
        colour: @white,
        scale: {@title_scale, @title_scale}
      )
end
