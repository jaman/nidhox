defmodule Nidhox.Screen.Credits do
  @moduledoc "The credits: who made what you are playing. Any choice goes back to the menu."

  alias Nidhox.Screen.Text

  @gold {245, 205, 70}
  @white {235, 235, 235}

  @doc "The credits' GUI items for a window `{width, height}`."
  @spec items({number(), number()}) :: [map()]
  def items(window) do
    [
      Text.shade(window, {0, 0, 0}, 0.6),
      Text.centred("NIDHOX", @gold, 6, 70, window),
      Text.centred("NIDHOGG OPEN-SOURCE EXPERIENCE", @white, 2, 170, window),
      Text.centred("GAME CODE: THE NIDHOX PROJECT", @white, 2, 240, window),
      Text.centred("ENGINE: CAULDRON", @white, 2, 280, window),
      Text.centred(
        "ROOMS AND SCENERY: READ FROM YOUR COPY OF NIDHOGG BY MESSHOF",
        @white,
        2,
        320,
        window
      ),
      Text.centred("PRESS ENTER OR ATTACK", @white, 2, 460, window)
    ]
  end
end
