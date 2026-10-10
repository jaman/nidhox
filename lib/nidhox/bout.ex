defmodule Nidhox.Bout do
  @moduledoc """
  A match as NidhOX's screens start and follow it. The match itself runs in the world
  as the game's objects (`Nidhox.Objects.Match`, the fencers, `Nidhox.Bout.Frame`);
  this module sets it going and reads how it stands.

    * `start_arcade/1`: a single player run begun; `area_of_level/1` the area of a
      `System.level`
    * `start/4`: `System`'s settings for the match — the flow (`4` versus and online,
      `3` tournament, `2` single player), the area's level (castle 20, mines 21, sky 22,
      wilds 23, cemetery 25), the time limit in frames and the variant switches
      (`Nidhox.Rules.system/1`) — then a `Match` made and the area's centre room entered
    * `running?/1`: whether the match is still going (its `Match` exists)
    * `winner/1`: the winning player (`MatchStats.winningPlayerIndex`), `nil` before one
    * `stats/1`: `%{steps, kills, suicides}` from `MatchStats`
    * `area/1`: the area of a room name
  """

  alias Cauldron2D.GameMaker.{Data, Rooms, World}
  alias Nidhox.Gml
  alias Nidhox.Objects.{Arcade, Match, MatchStats}
  alias Nidhox.Rules

  @levels %{"Castle" => 20, "Mines" => 21, "Sky" => 22, "Wilds" => 23, "Cemetery" => 25}
  @flows %{versus: 4, online: 4, tournament: 3, arcade: 2}

  @doc "The world with a match begun in area `area` under `rules`, for the screens' `mode`."
  @spec start(World.t(), String.t(), Rules.t(), atom()) :: World.t()
  def start(%World{} = world, area, %Rules{} = rules, mode) do
    world =
      case Gml.first(world, "System") do
        nil ->
          world

        system ->
          Gml.put(
            world,
            system,
            Map.merge(Rules.system(rules), %{flow: Map.get(@flows, mode, 4), level: Map.fetch!(@levels, area)})
          )
      end

    {_match, world} = Match.create(world)
    Rooms.enter(world, Data.index(world.data, :rooms, "r#{area}Center"))
  end

  @doc """
  The world ready for a single player run (`Nidhox.Objects.Arcade.start/1`): `System`'s
  settings at their defaults (`Nidhox.Rules`), its flow the single player's (2), and the
  run begun.
  """
  @spec start_arcade(World.t()) :: World.t()
  def start_arcade(%World{} = world) do
    world =
      case Gml.first(world, "System") do
        nil -> world
        system -> Gml.put(world, system, Map.put(Rules.system(%Rules{}), :flow, @flows.arcade))
      end

    Arcade.start(world)
  end

  @doc "The area whose `System.level` is `level`, `nil` for none."
  @spec area_of_level(number()) :: String.t() | nil
  def area_of_level(level), do: Enum.find_value(@levels, fn {area, number} -> if round(level) == number, do: area end)

  @doc "Whether the match is still going."
  @spec running?(World.t()) :: boolean()
  def running?(%World{} = world), do: Gml.exists?(world, "Match")

  @doc "The match's winning player, `nil` while there is none."
  @spec winner(World.t()) :: 1 | 2 | nil
  def winner(%World{} = world) do
    case MatchStats.read(world) do
      %{winningPlayerIndex: player} when player in [1, 2] -> player
      _none -> nil
    end
  end

  @doc "The match's statistics: frames fought (`steps`), and `kills` and `suicides` by player."
  @spec stats(World.t()) :: %{steps: number(), kills: map(), suicides: map()}
  def stats(%World{} = world) do
    case MatchStats.read(world) do
      nil -> %{steps: 0, kills: %{1 => 0, 2 => 0}, suicides: %{1 => 0, 2 => 0}}
      stats -> %{steps: stats.frames, kills: stats.kills, suicides: stats.suicides}
    end
  end

  @doc "The area a room named `name` belongs to; `nil` for a room that is no area's, and for no room at all."
  @spec area(String.t() | nil) :: String.t() | nil
  def area(nil), do: nil

  def area(name) do
    case Regex.run(~r/^r([A-Z][a-z]+)(LeftEnd|LeftC|LeftB|LeftA|Center|RightA|RightB|RightC|RightEnd|SuddenDeath)$/, name) do
      [_, area, _part] -> area
      nil -> nil
    end
  end
end
