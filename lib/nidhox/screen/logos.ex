defmodule Nidhox.Screen.Logos do
  @moduledoc """
  The logos before the title, over `rLogos`: the copy's `sMesshofLogo`, then "with music
  by" over its `sDaedelus`, each for `@each` steps, fading in and out over `@fade`.
  """

  alias Nidhox.Screen.Art

  @each 150
  @fade 30
  @middle {160, 100}
  @credit {160, 82}
  @under {160, 104}

  @doc "Whether the logos have all been shown by step `timer` of the screen."
  @spec done?(non_neg_integer()) :: boolean()
  def done?(timer), do: timer >= 2 * @each

  @doc "The logos' GUI items at step `timer` of the screen."
  @spec items(non_neg_integer(), {number(), number()}) :: [map()]
  def items(timer, window) when timer < @each,
    do: [Art.centred("sMesshofLogo", 0, @middle, window, alpha: fade(timer))]

  def items(timer, window) do
    alpha = fade(timer - @each)

    [
      Art.centred("sDaedelus", 0, @under, window, alpha: alpha)
      | Art.text("fMenu", "with music by", @credit, window, halign: :center, alpha: alpha)
    ]
  end

  defp fade(step), do: step |> min(@each - step) |> max(0) |> Kernel./(@fade) |> min(1.0)
end
