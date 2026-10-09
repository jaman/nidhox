defmodule Nidhox.Bout do
  @moduledoc """
  A match as NidhOX's screens start and follow it. The match itself runs in the world
  as the game's objects (`Nidhox.Objects.Match`, the fencers, `Nidhox.Bout.Frame`);
  this module sets it going and reads how it stands.

    * `start/4`: `System`'s settings for the match — the flow (`4` versus and online,
      `3` tournament, `2` single player), the area's level (castle 20, mines 21, sky 22,
      wilds 23, cemetery 25), the time limit in frames and the variant switches
      (`Nidhox.Rules.system/1`) — then a `Match` made and the area's centre room entered
    * `running?/1`: whether the match is still going (its `Match` exists)
    * `winner/1`: the winning player (`MatchStats.winningPlayerIndex`), `nil` before one
    * `stats/1`: `%{steps, kills, suicides}` from `MatchStats`
    * `progress/1`: how far the bout has gone from the area's centre room towards an end
      room, `0.0` in the centre, `1.0` in either end room
    * `rooms/2` and `area/1`: an area's rooms in order, and the area of a room name
  """

  alias Cauldron2D.GameMaker.{Data, Rooms, World}
  alias Nidhox.Gml
  alias Nidhox.Objects.{Match, MatchStats}
  alias Nidhox.Rules

  @order ~w(LeftEnd LeftC LeftB LeftA Center RightA RightB RightC RightEnd)
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

  @doc "How far the bout has gone from its area's centre room towards an end room, `0.0`–`1.0`."
  @spec progress(World.t()) :: float()
  def progress(%World{room: nil}), do: 0.0

  def progress(%World{} = world) do
    name = Enum.at(world.data.rooms, world.room).name

    with area when area != nil <- area(name),
         rooms when rooms != [] <- rooms(world.data, area),
         index when index != nil <- Enum.find_index(rooms, &(&1 == world.room)) do
      centre = Enum.find_index(rooms, &(Enum.at(world.data.rooms, &1).name == "r#{area}Center"))
      if centre in [nil, 0], do: 0.0, else: abs(index - centre) / centre
    else
      _none -> 0.0
    end
  end

  @doc """
  The rooms of area `area` (`"Cemetery"`, `"Castle"`, `"Mines"`, `"Sky"`, `"Wilds"`) in
  order from left end to right end, as indices into `data.rooms`.
  """
  @spec rooms(Data.t(), String.t()) :: [non_neg_integer()]
  def rooms(%Data{} = data, area) do
    for part <- @order,
        index = Data.index(data, :rooms, "r#{area}#{part}"),
        index != nil,
        do: index
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
