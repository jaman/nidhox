defmodule Nidhox.Screen.Title do
  @moduledoc """
  The title over `rMainMenu`: the copy's `sNewTitle` logo, and under it either "press
  start" in `fMenu`, centred on `@prompt`, shown the first `@blink_shown` steps of every
  `@blink_period`, or, once a player has pressed, the main menu.
  `:start`, `:attack` or `:jump` from either side leaves "press start".
  """

  alias Nidhox.Screen.{Art, Menu}

  @blink_period 120
  @blink_shown 60
  @logo {160, 52}
  @prompt {160, 130}
  @menu_top {160, 100}

  @doc "The title's GUI items at step `step`, with `menu` under the logo or `nil` for the prompt."
  @spec items(non_neg_integer(), Menu.t() | nil, {number(), number()}) :: [map()]
  def items(step, nil, window), do: [logo(window) | prompt(step, window)]

  def items(_step, %Menu{} = menu, window),
    do: [logo(window) | Menu.items(menu, @menu_top, window)]

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
end
