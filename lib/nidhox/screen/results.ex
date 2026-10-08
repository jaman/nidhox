defmodule Nidhox.Screen.Results do
  @moduledoc """
  The screen after a bout: who won, both sides' wins this session, in Arcade how far
  the run has come, and the prompt to go on.
  """

  alias Nidhox.Screen.Text

  @names %{1 => "YELLOW", 2 => "ORANGE"}
  @colours %{1 => {245, 205, 70}, 2 => {240, 120, 45}}
  @white {235, 235, 235}

  @doc """
  The GUI items for a bout won by `winner`, with `tally` `%{1 => wins, 2 => wins}` and
  `note`, a line about what comes next, for a window `{width, height}`.
  """
  @spec items(
          1 | 2,
          %{1 => non_neg_integer(), 2 => non_neg_integer()},
          String.t(),
          {number(), number()}
        ) ::
          [map()]
  def items(winner, tally, note, window) do
    [
      Text.shade(window, {0, 0, 0}, 0.55),
      Text.centred("#{@names[winner]} WINS", @colours[winner], 7, 120, window),
      Text.centred("YELLOW #{tally[1]}  -  #{tally[2]} ORANGE", @white, 3, 280, window),
      Text.centred(note, @white, 2, 360, window),
      Text.centred("PRESS ENTER OR ATTACK", @white, 2, 460, window)
    ]
  end
end
