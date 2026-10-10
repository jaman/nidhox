defmodule Nidhox.Screen.Results do
  @moduledoc """
  The match's statistics after a bout, over `rMatchStats`, as the game's
  `ShowMatchStats` draws them, every line in `fMenu` centred on its x, from its top,
  lines 7 apart:

    * "time" and the bout's time (`getTime`) at y 15
    * the copy's `sWinner` at (160, 72) by its own origin, in the winner's colour
      (`getPlayerColor`)
    * for each side, in its colour, at y 130, around a point 64 to its side of the
      middle (yellow left, orange right): "kills" and its kills 32 left of the point,
      "suicides" and its suicides (falls out of the room) 32 right of it
    * "continue" 32 above the bottom, white

  Any of `:attack`, `:start` or `:jump` goes on. NidhOX adds the replay to it: `:up` or
  `:down` turns the bottom line between "continue" and "watch replay", and the press
  that goes on does what it shows (`input/2`). The statistics are
  `Nidhox.Bout.stats/1`'s.
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.Bout.PlayerColour
  alias Nidhox.Objects.Match
  alias Nidhox.Screen.Art

  @type stats :: %{
          steps: non_neg_integer(),
          kills: %{1 => non_neg_integer(), 2 => non_neg_integer()},
          suicides: %{1 => non_neg_integer(), 2 => non_neg_integer()}
        }

  @centre 160
  @time_top 15
  @winner_at 72
  @rows_top 130
  @apart 64
  @half_apart 32
  @continue_rise 32
  @view_height 200
  @separation 7
  @white {255, 255, 255}

  @type choice :: :continue | :replay

  @doc "What the players did on the results with `choice` shown: `{:go, choice}` or `{:stay, choice}`."
  @spec input(choice(), %{1 => map(), 2 => map()}) :: {:go, choice()} | {:stay, choice()}
  def input(choice, players) do
    pressed = players |> Map.values() |> Enum.flat_map(&MapSet.to_list(&1.pressed))

    cond do
      Enum.any?([:attack, :start, :jump], &(&1 in pressed)) -> {:go, choice}
      :up in pressed or :down in pressed -> {:stay, other(choice)}
      true -> {:stay, choice}
    end
  end

  defp label(:continue), do: "continue"
  defp label(:replay), do: "watch replay"

  defp other(:continue), do: :replay
  defp other(:replay), do: :continue

  @doc "The GUI items for a bout won by side `winner` with `stats` and `choice` on the bottom line, coloured as `world` colours the sides."
  @spec items(World.t(), 1 | 2, stats(), choice(), {number(), number()}) :: [map()]
  def items(%World{} = world, winner, stats, choice, window) do
    List.flatten([
      text("time##{Match.time(stats.steps)}", {@centre, @time_top}, @white, window),
      Art.sprite("sWinner", 0, {@centre, @winner_at}, window, blend: colour(world, winner)),
      Enum.map([1, 2], &side(world, &1, stats, window)),
      text(label(choice), {@centre, @view_height - @continue_rise}, @white, window)
    ])
  end

  defp side(world, side, stats, window) do
    sign = if side == 1, do: -1, else: 1
    middle = @centre + sign * @apart
    colour = colour(world, side)

    [
      text("kills##{stats.kills[side]}", {middle - @half_apart, @rows_top}, colour, window),
      text("suicides##{stats.suicides[side]}", {middle + @half_apart, @rows_top}, colour, window)
    ]
  end

  defp text(words, at, colour, window),
    do:
      Art.text("fMenu", words, at, window,
        halign: :center,
        colour: colour,
        separation: @separation
      )

  defp colour(world, side) do
    {colour, _world} = PlayerColour.get(world, nil, side)
    colour
  end
end
