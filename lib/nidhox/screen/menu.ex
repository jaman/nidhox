defmodule Nidhox.Screen.Menu do
  @moduledoc """
  A menu: a heading and a list of choices, one of them selected.

  Either side moves the selection with `:up` and `:down`, chooses with `:start` or
  `:attack`, and goes back with `:jump`. `input/2` says which happened; `items/3` draws
  the menu as GUI items, the selected choice marked.
  """

  alias Nidhox.Screen.Text

  @enforce_keys [:heading, :choices]
  defstruct [:heading, :choices, selected: 0]

  @type choice :: {String.t(), term()}
  @type t :: %__MODULE__{heading: String.t(), choices: [choice()], selected: non_neg_integer()}

  @gold {245, 205, 70}
  @white {235, 235, 235}
  @dim {150, 150, 150}
  @top 200
  @spacing 56

  @doc "A menu headed `heading` offering `choices`, each `{label, option}`, the first selected."
  @spec new(String.t(), [choice()], non_neg_integer()) :: t()
  def new(heading, [_ | _] = choices, selected \\ 0),
    do: %__MODULE__{heading: heading, choices: choices, selected: selected}

  @doc "The option of the selected choice."
  @spec selected(t()) :: term()
  def selected(%__MODULE__{choices: choices, selected: index}),
    do: choices |> Enum.at(index) |> elem(1)

  @doc """
  What the players did to the menu this step: `{:choose, option}`, `:back`, or
  `{:stay, menu}` with the selection moved if they moved it.
  """
  @spec input(t(), %{1 => map(), 2 => map()}) :: {:choose, term()} | :back | {:stay, t()}
  def input(%__MODULE__{} = menu, players) do
    pressed = players |> Map.values() |> Enum.reduce(MapSet.new(), &MapSet.union(&2, &1.pressed))
    last = length(menu.choices) - 1

    cond do
      :start in pressed or :attack in pressed -> {:choose, selected(menu)}
      :jump in pressed -> :back
      :up in pressed -> {:stay, %{menu | selected: max(menu.selected - 1, 0)}}
      :down in pressed -> {:stay, %{menu | selected: min(menu.selected + 1, last)}}
      true -> {:stay, menu}
    end
  end

  @doc "The menu's GUI items for a window `{width, height}`."
  @spec items(t(), {number(), number()}) :: [map()]
  def items(%__MODULE__{} = menu, window) do
    heading = Text.centred(menu.heading, @gold, 5, 80, window)

    choices =
      menu.choices
      |> Enum.with_index()
      |> Enum.map(fn {{label, _option}, index} ->
        {words, colour} =
          if index == menu.selected, do: {"> #{label} <", @white}, else: {label, @dim}

        Text.centred(words, colour, 3, @top + index * @spacing, window)
      end)

    [Text.shade(window, {0, 0, 0}, 0.45), heading | choices]
  end
end
