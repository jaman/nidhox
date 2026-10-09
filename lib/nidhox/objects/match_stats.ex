defmodule Nidhox.Objects.MatchStats do
  @moduledoc """
  The game's `MatchStats`: one instance counting a match's frames and each player's kills
  (`kills`, by player 1 and 2), and the winner (`winningPlayerIndex`, 0 until decided).

  `add_kill/2` counts a kill for a player, as a fencer's death throes do for its
  opponent (`MatchStats.kills[findOppositeIndex(playerIndex)] += 1`); with no
  `MatchStats` it counts nothing.
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.Gml

  @object "MatchStats"

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers, do: [{"gml_Object_MatchStats_Create_0", &start/3}]

  @doc "The world with a kill counted for `player`."
  @spec add_kill(World.t(), integer()) :: World.t()
  def add_kill(%World{} = world, player) do
    case stats(world) do
      nil ->
        world

      stats ->
        kills = Gml.var(world, stats, :kills, %{})
        Gml.put(world, stats, %{kills: Map.update(kills, player, 1, &(&1 + 1))})
    end
  end

  @doc "The world with a suicide counted for `player` (`MatchStats.suicides[playerIndex] += 1`)."
  @spec add_suicide(World.t(), integer()) :: World.t()
  def add_suicide(%World{} = world, player) do
    case stats(world) do
      nil ->
        world

      stats ->
        suicides = Gml.var(world, stats, :suicides, %{})
        Gml.put(world, stats, %{suicides: Map.update(suicides, player, 1, &(&1 + 1))})
    end
  end

  @doc "The world with `player` as the match's winner (`MatchStats.winningPlayerIndex`)."
  @spec put_winner(World.t(), integer()) :: World.t()
  def put_winner(%World{} = world, player) do
    case stats(world) do
      nil -> world
      stats -> Gml.put(world, stats, %{winningPlayerIndex: player})
    end
  end

  @doc "The match's statistics: `frames`, `kills` and `suicides` by player, and `winningPlayerIndex`; `nil` without a `MatchStats`."
  @spec read(World.t()) :: map() | nil
  def read(%World{} = world) do
    case stats(world) do
      nil -> nil
      stats -> World.fetch(world, stats).vars
    end
  end

  defp start(world, self, _other),
    do:
      Gml.put(world, self, %{
        frames: 0,
        kills: %{1 => 0, 2 => 0},
        suicides: %{1 => 0, 2 => 0},
        winningPlayerIndex: 0
      })

  defp stats(world) do
    with object when is_integer(object) <- World.object_index(world, @object),
         [stats | _] <- World.instances_of(world, object) do
      stats
    else
      _none -> nil
    end
  end
end
