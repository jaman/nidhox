defmodule Nidhox.Screen.Logos do
  @moduledoc """
  The logos before the title, over `rLogos`, as the game's `ShowLogos` shows them: the
  copy's `sMesshofLogo`, then its `sDaedelus`, each centred on the view.

  Each logo waits 61 steps unseen, comes in by 1/30 of full a step, stays until 240
  steps after it began to come in, then goes by 1/30 a step; once gone the next
  begins, and after the last the title. While `sDaedelus` is the logo, "with music by"
  stands with its bottom left at (86, 82), and the logo is yellow while `System.frame mod
  4` is under 2, else white.
  """

  alias Nidhox.Screen.Art

  @logos ["sMesshofLogo", "sDaedelus"]
  @wait 61
  @shown 240
  @fade 30
  @each @wait + @shown + @fade
  @middle {160, 100}
  @credit {86, 82}
  @white {248, 255, 255}
  @yellow {255, 255, 0}

  @doc "Whether the logos have all been shown by step `timer` of the screen."
  @spec done?(non_neg_integer()) :: boolean()
  def done?(timer), do: timer >= length(@logos) * @each

  @doc "The logos' GUI items at step `timer` of the screen, `frame` being `System.frame`."
  @spec items(non_neg_integer(), number(), {number(), number()}) :: [map()]
  def items(timer, frame, window) do
    case Enum.at(@logos, div(timer, @each)) do
      nil -> []
      logo -> shown(logo, rem(timer, @each), frame, window)
    end
  end

  defp shown(logo, step, frame, window) do
    logo_item =
      Art.centred(logo, 0, @middle, window, alpha: alpha(step), blend: blend(logo, frame))

    if logo == "sDaedelus",
      do: [logo_item | Art.text("fMenu", "with music by", @credit, window, valign: :bottom)],
      else: [logo_item]
  end

  defp alpha(step) when step < @wait, do: 0.0
  defp alpha(step) when step < @wait + @shown, do: min((step - @wait + 1) / @fade, 1.0)
  defp alpha(step), do: max(1.0 - (step - @wait - @shown + 1) / @fade, 0.0)

  defp blend("sDaedelus", frame) when rem(trunc(frame), 4) < 2, do: @yellow
  defp blend(_logo, _frame), do: @white
end
