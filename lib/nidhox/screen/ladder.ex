defmodule Nidhox.Screen.Ladder do
  @moduledoc """
  The tournament's screens (`Nidhox.Tournament`), as GUI items for a window
  `{width, height}`.

    * `intro/2` — every player's icon in a row under PLAYERS, over `rTournamentIntro`
    * `items/2` — the ladder over `rShowLadder`: the winners' bracket above the
      losers' and the finals at the right, each round a column of its matches, each
      match its two players' icons with the loser's faded; under it the next match,
      the yellow fencer (`sYellowPlayerMatchEntry`) against the orange
      (`sOrangePlayerMatchEntry`) with their players' icons, and "final showdown!"
      over the final
    * `champion/2` — the champion's icon over the pyre of `rShowChampion` and
      "player N won!"

  A player's icon, placed by its middle, is a frame of `sPlayerIconBack` tinted in the player's colour
  (`@colours`), with the player's number on it.
  """

  alias Nidhox.Screen.Art
  alias Nidhox.Tournament

  @colours %{
    1 => {230, 70, 60},
    2 => {70, 140, 250},
    3 => {90, 200, 90},
    4 => {200, 90, 220},
    5 => {235, 235, 235},
    6 => {60, 210, 210},
    7 => {150, 110, 70},
    8 => {250, 150, 190}
  }
  @icon 20
  @pair_gap 2
  @column 50
  @row 22
  @left 8
  @winners_top 8
  @losers_top 104
  @faded 0.3
  @number {20, 20, 20}
  @next_y 176
  @showdown {160, 152}
  @intro_y 110
  @champion {162, 30}
  @won {160, 184}

  @doc "The colour of player `player`'s icon."
  @spec colour(Tournament.player()) :: {byte(), byte(), byte()}
  def colour(player), do: Map.fetch!(@colours, player)

  @doc "The intro's GUI items: PLAYERS and every player's icon, for a tournament of `count`."
  @spec intro(pos_integer(), {number(), number()}) :: [map()]
  def intro(count, window) do
    left = 160 - (count * (@icon + 4) - 4) / 2 + @icon / 2

    Art.text("fMenu", "PLAYERS", {160, @intro_y - 30}, window, halign: :center) ++
      Enum.flat_map(1..count, &icon(&1, {left + (&1 - 1) * (@icon + 4), @intro_y}, window))
  end

  @doc "The ladder's GUI items for `tournament`."
  @spec items(Tournament.t(), {number(), number()}) :: [map()]
  def items(%Tournament{} = tournament, window) do
    winners = Tournament.rounds(tournament, :winners)
    losers = Tournament.rounds(tournament, :losers)
    finals_x = @left + max(length(winners), length(losers)) * @column

    bracket(winners, @left, @winners_top, window) ++
      bracket(losers, @left, @losers_top, window) ++
      bracket(Tournament.rounds(tournament, :final), finals_x, @losers_top - @row, window) ++
      next(tournament, window)
  end

  @doc "The champion's GUI items: the icon of `player` over the pyre, and \"player N won!\"."
  @spec champion(Tournament.player(), {number(), number()}) :: [map()]
  def champion(player, window) do
    {x, y} = @champion

    icon(player, {x, y}, window) ++
      Art.text("fMenu", "player #{player} won!", @won, window, halign: :center)
  end

  defp bracket(rounds, left, top, window) do
    for {round, column} <- Enum.with_index(rounds),
        {match, row} <- Enum.with_index(round),
        item <- match(match, {left + column * @column, top + row * @row}, window),
        do: item
  end

  defp match(%{players: {one, two}, winner: winner}, {x, y}, window) do
    middle = y + @icon / 2

    icon(one, {x + @icon / 2, middle}, window, faded(one, winner)) ++
      icon(two, {x + @icon * 1.5 + @pair_gap, middle}, window, faded(two, winner))
  end

  defp faded(player, player), do: 1.0
  defp faded(_player, _winner), do: @faded

  defp next(%Tournament{} = tournament, window) do
    case Tournament.next(tournament) do
      nil -> []
      {yellow, orange} -> pairing(yellow, orange, window) ++ showdown(tournament, window)
    end
  end

  defp pairing(yellow, orange, window) do
    [
      Art.centred("sYellowPlayerMatchEntry", 0, {120, @next_y}, window),
      Art.centred("sOrangePlayerMatchEntry", 0, {200, @next_y}, window)
      | icon(yellow, {82, @next_y}, window) ++ icon(orange, {238, @next_y}, window)
    ]
  end

  defp showdown(tournament, window) do
    if Tournament.final?(tournament),
      do: Art.text("fMenu", "final showdown!", @showdown, window, halign: :center),
      else: []
  end

  defp icon(player, {x, y}, window, alpha \\ 1.0) do
    [
      Art.centred("sPlayerIconBack", player - 1, {x, y}, window,
        blend: colour(player),
        alpha: alpha,
        depth: 0
      )
      | Art.text("fMenu", "#{player}", {x, y}, window,
          halign: :center,
          valign: :middle,
          colour: @number,
          alpha: alpha,
          depth: -1
        )
    ]
  end
end
