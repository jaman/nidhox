defmodule Nidhox.Bout.Outcome do
  @moduledoc """
  How a match is decided, as the game's scripts decide it:

    * `faceoff/2` (`update_faceoff`): while the match is in its faceoff, `faceoffTimer`
      counts down and the faceoff ends at 0; every 60th count the tick (`sndPickup`) is heard at
      the `Ear`
    * `victory_lap?/1` (`inVictoryLap`): in an end room (room codes 4 and 7)
    * `sudden_death/2` (`startSuddenDeath`): the clock stops (`countDownTimer` 0), a
      fresh faceoff (`faceoff` 1, `faceoffTimer` 0), nobody leads, `sudden_death` 1,
      and the bout goes to the area's sudden death room by `System.level`: 20 the
      castle's, 21 the mines', 22 the sky's, 23 the wilds', 25 the cemetery's, 26 the castle
      stairs'
    * `winner/2` (`showWinningPlayerIndex`): the `Match` is `finished` with the player as
      its `winner`; unless a winner is already shown (`ShowMatchStats`), the player is
      the match's winner (`MatchStats`), the winner is shown (`ShowMatchStats`), a
      tournament's `nextWinner` is the tournament player on that side
      (`Nidhox.Objects.Tournament.won/2`), and `System.winningPlayerHistory` and
      `System.wins` (by player and level) record it. The match ends once
      `Nidhox.Bout.Frame` sets its `matchOver`.
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.Bout.{Rooms, Sound}
  alias Nidhox.Gml
  alias Nidhox.Objects.{Ear, MatchStats, RoomCodes, System, Tournament}

  @tick "sndPickup"
  @tick_every 60
  @end_rooms [4, 7]
  @sudden_death_rooms %{
    20 => "rCastleSuddenDeath",
    21 => "rMinesSuddenDeath",
    22 => "rSkySuddenDeath",
    23 => "rWildsSuddenDeath",
    25 => "rCemeterySuddenDeath",
    26 => "rCastleStairsSuddenDeath"
  }

  @doc "The world after the match `match`'s faceoff counts down (`update_faceoff`)."
  @spec faceoff(World.t(), non_neg_integer()) :: World.t()
  def faceoff(%World{} = world, match) do
    if Gml.truthy?(Gml.var(world, match, :faceoff)) do
      timer = Gml.var(world, match, :faceoffTimer) - 1
      world = Gml.put(world, match, %{faceoffTimer: timer})
      world = if timer <= 0, do: Gml.put(world, match, %{faceoff: 0}), else: world

      if Gml.eq?(:math.fmod(timer, @tick_every), 0),
        do: Sound.play_named(world, @tick, Ear.position(world)),
        else: world
    else
      world
    end
  end

  @doc "Whether the match is in an end room (`inVictoryLap`)."
  @spec victory_lap?(World.t()) :: boolean()
  def victory_lap?(%World{} = world), do: RoomCodes.room_code(world) in @end_rooms

  @doc "The world with the match `match` gone into sudden death (`startSuddenDeath`)."
  @spec sudden_death(World.t(), non_neg_integer()) :: World.t()
  def sudden_death(%World{} = world, match) do
    world =
      Gml.put(world, match, %{
        countDownTimer: 0,
        faceoff: 1,
        faceoffTimer: 0,
        sudden_death: 1,
        leadingPlayerIndex: 0
      })

    case Map.get(@sudden_death_rooms, System.get(world, :level)) do
      nil -> world
      room -> Rooms.goto(world, room)
    end
  end

  @doc "The world with `player` shown as the match's winner (`showWinningPlayerIndex`)."
  @spec winner(World.t(), integer()) :: World.t()
  def winner(%World{} = world, player) do
    world = finish(world, player)

    if Gml.exists?(world, "ShowMatchStats") do
      world
    else
      world
      |> MatchStats.put_winner(player)
      |> then(&elem(World.create(&1, World.object_index(&1, "ShowMatchStats"), {0, 0}), 0))
      |> Tournament.won(player)
      |> record(player)
    end
  end

  defp finish(world, player) do
    world
    |> Gml.all("Match")
    |> Enum.reduce(world, &Gml.put(&2, &1, %{finished: 1, winner: player}))
  end

  defp record(world, player) do
    case Gml.first(world, "System") do
      nil ->
        world

      system ->
        history = Gml.var(world, system, :winningPlayerHistory, [])
        wins = Gml.var(world, system, :wins, %{})
        level = Gml.var(world, system, :level)
        by_level = Map.get(wins, player, %{})

        Gml.put(world, system, %{
          winningPlayerHistory: history ++ [player],
          wins: Map.put(wins, player, Map.update(by_level, level, 1, &(&1 + 1)))
        })
    end
  end
end
