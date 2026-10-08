defmodule Nidhox.Screen.Title do
  @moduledoc """
  The title screen: the game's name over the room's scenery, and a blinking prompt.
  Any player pressing `:start`, `:attack` or `:jump` goes on to the main menu.
  """

  alias Nidhox.Screen.Text

  @blink 60
  @gold {245, 205, 70}
  @white {235, 235, 235}

  @doc "The title's GUI items at step `step` for a window `{width, height}`."
  @spec items(non_neg_integer(), {number(), number()}) :: [map()]
  def items(step, window) do
    prompt =
      if rem(step, @blink) < div(@blink * 2, 3),
        do: [Text.centred("PRESS ENTER OR ATTACK", @white, 3, 420, window)],
        else: []

    [
      Text.shade(window, {0, 0, 0}, 0.35),
      Text.centred("NIDHOX", @gold, 9, 150, window),
      Text.centred("NIDHOGG OPEN-SOURCE EXPERIENCE", @white, 2, 280, window)
    ] ++ prompt
  end

  @doc "Whether any player pressed something that leaves the title."
  @spec continue?(%{1 => map(), 2 => map()}) :: boolean()
  def continue?(players) do
    Enum.any?(Map.values(players), fn input ->
      Enum.any?([:start, :attack, :jump], &(&1 in input.pressed))
    end)
  end
end
