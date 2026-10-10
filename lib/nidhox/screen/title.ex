defmodule Nidhox.Screen.Title do
  @moduledoc """
  The title over `rMainMenu`, as the game's `MainMenu` draws it: the copy's `sNewTitle`
  logo centred on (160, 70), and under it either "press start" in `fMenu`, centred on
  (160, 130), shown the first 60 steps of every 120, or, once a player has pressed, the
  menu (`Nidhox.Screen.MenuList`). While the single player menu's BEGIN is selected the
  logo gives way to "defeat all opponents!", centred on (160, 48), 200 wide, its lines
  12 apart. `:start`, `:attack` or `:jump` from either side leaves "press start".
  """

  alias Nidhox.Screen.{Art, MenuList}

  @blink_period 120
  @blink_shown 60
  @logo {160, 70}
  @prompt {160, 130}
  @goal {160, 48}
  @goal_width 200
  @goal_separation 12

  @doc "The title's GUI items at step `step`, with `menu` under the logo or `nil` for the prompt."
  @spec items(non_neg_integer(), MenuList.t() | nil, {number(), number()}) :: [map()]
  def items(step, nil, window), do: [logo(window) | prompt(step, window)]

  def items(_step, %MenuList{key: :single} = menu, window) do
    if MenuList.selected(menu) == :begin,
      do: goal(window) ++ MenuList.items(menu, window),
      else: [logo(window) | MenuList.items(menu, window)]
  end

  def items(_step, %MenuList{} = menu, window), do: [logo(window) | MenuList.items(menu, window)]

  @doc "Whether any player pressed something that leaves \"press start\" or a screen waiting on a press."
  @spec continue?(%{1 => map(), 2 => map()}) :: boolean()
  def continue?(players) do
    Enum.any?(Map.values(players), fn input ->
      Enum.any?([:start, :attack, :jump], &(&1 in input.pressed))
    end)
  end

  defp prompt(step, window) do
    if rem(step, @blink_period) < @blink_shown,
      do: Art.text("fMenu", "press start", @prompt, window, halign: :center, valign: :middle),
      else: []
  end

  defp logo(window), do: Art.centred("sNewTitle", 0, @logo, window)

  defp goal(window),
    do:
      Art.text("fMenu", "defeat all opponents!", @goal, window,
        halign: :center,
        valign: :middle,
        wrap: @goal_width,
        separation: @goal_separation
      )
end
