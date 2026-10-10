defmodule Nidhox.Screen.Pause do
  @moduledoc """
  The pause over a bout, as the game's `PauseController` runs it.

    * its menu: "UNPAUSE GAME", "CHANGE LEVEL" in a versus bout with no player on
      another machine, and "QUIT TO TITLE SCREEN", the first selected
    * either side moves the selection with `:up` and `:down`, round from the last to
      the first and back, and chooses with `:attack` or `:start` — once neither is held
      by anyone, so the press that paused chooses nothing
    * drawn over the whole screen: a box of `make_color_hsv(0, 0, 30)` at alpha 0.9,
      each choice in lower case in `fMenu`, centred on x 160 with its top at `97 + 10 ×
      i`, the selected one over a white box at alpha 0.1 from `(90, 100 + 10 × i)` to
      `(230, 109 + 10 × i)`
  """

  alias Nidhox.Screen.Art

  @enforce_keys [:choices]
  defstruct [:choices, selected: 0, armed?: false]

  @type option :: :unpause | :change_level | :title
  @type t :: %__MODULE__{
          choices: [{String.t(), option()}],
          selected: non_neg_integer(),
          armed?: boolean()
        }

  @shade {30, 30, 30}
  @shade_alpha 0.9
  @left 90
  @width 140
  @top 100
  @spacing 10
  @text_rise 3
  @highlight_alpha 0.1
  @white {255, 255, 255}
  @choosing [:attack, :start]

  @doc "The pause menu for a bout in `mode`, `remote?` when a player of it is on another machine."
  @spec menu(atom(), boolean()) :: t()
  def menu(mode, remote?) do
    change_level =
      if mode == :versus and not remote?, do: [{"CHANGE LEVEL", :change_level}], else: []

    %__MODULE__{
      choices: [{"UNPAUSE GAME", :unpause}] ++ change_level ++ [{"QUIT TO TITLE SCREEN", :title}]
    }
  end

  @doc "What the players did this step: `{:choose, option}` or `{:stay, pause}`."
  @spec input(t(), %{1 => map(), 2 => map()}) :: {:choose, option()} | {:stay, t()}
  def input(%__MODULE__{} = pause, players) do
    inputs = Map.values(players)
    armed? = pause.armed? or not Enum.any?(inputs, &held_any?(&1, @choosing))

    cond do
      armed? and Enum.any?(inputs, &pressed_any?(&1, @choosing)) ->
        {:choose, selected(pause)}

      Enum.any?(inputs, &pressed_any?(&1, [:up])) ->
        {:stay, %{moved(pause, -1) | armed?: armed?}}

      Enum.any?(inputs, &pressed_any?(&1, [:down])) ->
        {:stay, %{moved(pause, 1) | armed?: armed?}}

      true ->
        {:stay, %{pause | armed?: armed?}}
    end
  end

  @doc "The pause's GUI items over a window `{width, height}`."
  @spec items(t(), {number(), number()}) :: [map()]
  def items(%__MODULE__{} = pause, window) do
    lines =
      pause.choices
      |> Enum.with_index()
      |> Enum.flat_map(fn {{label, _option}, index} ->
        line(label, index, index == pause.selected, window)
      end)

    [Art.shade(window, @shade, @shade_alpha) | lines]
  end

  defp line(label, index, selected?, window) do
    top = @top + index * @spacing

    text =
      Art.text("fMenu", String.downcase(label), {@left + @width / 2, top - @text_rise}, window,
        halign: :center,
        colour: @white
      )

    if selected?, do: highlight(top, window) ++ text, else: text
  end

  defp highlight(top, window) do
    {@left, top, @left + @width, top + @spacing - 1}
    |> Art.rectangle(@white, window, false)
    |> Enum.map(&Map.put(&1, :alpha, @highlight_alpha))
  end

  defp selected(%__MODULE__{choices: choices, selected: index}),
    do: choices |> Enum.at(index) |> elem(1)

  defp moved(%__MODULE__{choices: choices, selected: index} = pause, step),
    do: %{pause | selected: Integer.mod(index + step, length(choices))}

  defp held_any?(%{held: held}, actions), do: Enum.any?(actions, &(&1 in held))
  defp pressed_any?(%{pressed: pressed}, actions), do: Enum.any?(actions, &(&1 in pressed))
end
