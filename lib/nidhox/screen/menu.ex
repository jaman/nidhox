defmodule Nidhox.Screen.Menu do
  @moduledoc """
  A list of choices in the copy's `fMenu` font, one of them selected and drawn brighter
  than the rest.

  A choice is `{label, option}`, or `{label, :disabled}` for one shown dimmed that the
  selection passes over. Either side moves the selection with `:up` and `:down`,
  chooses with `:start` or `:attack`, and goes back with `:jump`. `input/2` says which
  happened and which side did it; `items/3` draws the menu.
  """

  alias Nidhox.Screen.Art

  @enforce_keys [:choices]
  defstruct [:choices, selected: 0]

  @type choice :: {String.t(), term()}
  @type t :: %__MODULE__{choices: [choice()], selected: non_neg_integer()}

  @chosen {255, 255, 255}
  @other {150, 150, 150}
  @disabled {80, 80, 80}
  @spacing 14

  @doc "A menu of `choices`, each `{label, option}`, the first choosable one selected."
  @spec new([choice()]) :: t()
  def new([_ | _] = choices) do
    first = Enum.find_index(choices, &choosable?/1) || 0
    %__MODULE__{choices: choices, selected: first}
  end

  @doc "The option of the selected choice."
  @spec selected(t()) :: term()
  def selected(%__MODULE__{choices: choices, selected: index}),
    do: choices |> Enum.at(index) |> elem(1)

  @doc """
  What the players did to the menu this step: `{:choose, option, side}`,
  `{:back, side}`, or `{:stay, menu}` with the selection moved if they moved it.
  """
  @spec input(t(), %{1 => map(), 2 => map()}) ::
          {:choose, term(), 1 | 2} | {:back, 1 | 2} | {:stay, t()}
  def input(%__MODULE__{} = menu, players) do
    case Enum.find_value([1, 2], &pressed(menu, &1, players[&1].pressed)) do
      nil -> {:stay, menu}
      outcome -> outcome
    end
  end

  @doc "The menu's GUI items, its lines centred on `x` from `top` down, in view pixels."
  @spec items(t(), {number(), number()}, {number(), number()}) :: [map()]
  def items(%__MODULE__{} = menu, {x, top}, window) do
    menu.choices
    |> Enum.with_index()
    |> Enum.flat_map(fn {{label, option}, index} ->
      colour = colour(option, index == menu.selected)

      Art.text("fMenu", label, {x, top + index * @spacing}, window,
        halign: :center,
        colour: colour
      )
    end)
  end

  defp pressed(menu, side, pressed) do
    cond do
      :start in pressed or :attack in pressed -> {:choose, selected(menu), side}
      :jump in pressed -> {:back, side}
      :up in pressed -> {:stay, move(menu, -1)}
      :down in pressed -> {:stay, move(menu, 1)}
      true -> nil
    end
  end

  defp move(%__MODULE__{choices: choices, selected: selected} = menu, step) do
    found =
      Stream.iterate(selected + step, &(&1 + step))
      |> Stream.take_while(&(&1 >= 0 and &1 < length(choices)))
      |> Enum.find(&choosable?(Enum.at(choices, &1)))

    %{menu | selected: found || selected}
  end

  defp choosable?({_label, :disabled}), do: false
  defp choosable?({_label, _option}), do: true

  defp colour(:disabled, _selected?), do: @disabled
  defp colour(_option, true), do: @chosen
  defp colour(_option, false), do: @other
end
