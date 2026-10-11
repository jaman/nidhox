defmodule Nidhox.Bout.Spawn do
  @moduledoc """
  Fencers coming into a match, as the game's scripts bring them:

    * `player/3` (`spawn_player(x, y, i)`): a `YellowPlayer` (player 1) or an
      `OrangePlayer` (player 2) made at `{x, y}`; `{id, world}`
    * `warp_in/3` (`warp_in_player(x, y, i)`): a fencer made at `{x, y}`, its weapon the
      spawn weapon (`weapon/1`), its state −1 and its next state warping in (79)
    * `weapon/1` (`getSpawnWeapon`): fists (1) in a tournament or versus match with
      `System.noSwords` on; else a sword (2) where the rooms hand out swords
      (`global.swords`), fists otherwise
    * `reset_timer/2` (`reset_spawn_timer(delay)`): the match's `spawnTimer` set to
      `delay`, never under 120
    * `respawns/2` (`manageRespawns`), each frame, outside sudden death and the tutorial:
      a fencer alone on its feet takes the right of way; the spawn timer counts down,
      and at 0 starts again from `spawnDelay` and, in a room with a `RespawnPoint` that
      is not an end room (codes 4 and 7):
        * with one fencer, it takes the right of way and the other comes in `outside`
          (64) pixels past the camera's edge ahead of it, at height 300 — player 2 past
          the right edge when player 1 leads, player 1 past the left edge otherwise
        * with none, nobody has the right of way, both players' swords are their spawn
          weapon, and player 1 comes in past the left edge, player 2 past the right
        * every fencer still entering (23) — when two are up and it stands within 160
          pixels of the other across, it first moves past the camera's other edge — is
          put on the `RespawnPoint` nearest it, takes the spawn weapon and is heard
          coming in (27)
  """

  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Bout.{Camera, Sound}
  alias Nidhox.Gml
  alias Nidhox.Man.{Query, Weapon}
  alias Nidhox.Objects.{RoomCodes, System}

  @objects %{1 => "YellowPlayer", 2 => "OrangePlayer"}
  @warp_in 79
  @entering 23
  @fists 1
  @sword 2
  @least_delay 120
  @outside 64
  @spawn_height 300
  @too_close 160
  @end_rooms [4, 7]
  @coming_in 27

  @doc "`{id, world}` with player `player`'s fencer made at `{x, y}` (`spawn_player`)."
  @spec player(World.t(), {number(), number()}, 1 | 2) :: {non_neg_integer(), World.t()}
  def player(%World{} = world, {x, y}, player) do
    {world, id} = World.create(world, World.object_index(world, @objects[player]), {x, y})
    {id, world}
  end

  @doc "`{id, world}` with player `player`'s fencer warped in at `{x, y}` (`warp_in_player`)."
  @spec warp_in(World.t(), {number(), number()}, 1 | 2) :: {non_neg_integer(), World.t()}
  def warp_in(%World{} = world, position, player) do
    {id, world} = player(world, position, player)

    world =
      world
      |> Weapon.set_type(id, weapon(world))
      |> Gml.put(id, %{state: -1, nextState: @warp_in})

    {id, world}
  end

  @doc "The weapon a fencer comes in with (`getSpawnWeapon`): 1 fists, 2 a sword."
  @spec weapon(World.t()) :: 1 | 2
  def weapon(%World{} = world) do
    cond do
      System.get(world, :flow) in [3, 4] and Gml.truthy?(System.get(world, :noSwords)) -> @fists
      RoomCodes.swords?(world) -> @sword
      true -> @fists
    end
  end

  @doc "The world with the match's spawn timer at `delay`, at least 120 (`reset_spawn_timer`)."
  @spec reset_timer(World.t(), number()) :: World.t()
  def reset_timer(%World{} = world, delay) do
    case Gml.first(world, "Match") do
      nil ->
        world

      match ->
        Gml.put(world, match, %{
          spawnTimer: if(delay > @least_delay, do: delay, else: @least_delay)
        })
    end
  end

  @doc "The world after the match `match` brings fencers back (`manageRespawns`)."
  @spec respawns(World.t(), non_neg_integer()) :: World.t()
  def respawns(%World{} = world, match) do
    if Gml.truthy?(Gml.var(world, match, :sudden_death)) or Gml.exists?(world, "Tutorial"),
      do: world,
      else: world |> lone_leader(match) |> count_down(match)
  end

  defp lone_leader(world, match) do
    case one_left(world) do
      nil -> world
      man -> Gml.put(world, match, %{leadingPlayerIndex: Gml.var(world, man, :playerIndex)})
    end
  end

  defp count_down(world, match) do
    timer = Gml.var(world, match, :spawnTimer) - 1
    world = Gml.put(world, match, %{spawnTimer: timer})

    if timer <= 0 do
      world = reset_timer(world, Gml.var(world, match, :spawnDelay))
      if spawn_room?(world), do: bring_back(world, match), else: world
    else
      world
    end
  end

  defp spawn_room?(world),
    do: Gml.exists?(world, "RespawnPoint") and RoomCodes.room_code(world) not in @end_rooms

  defp bring_back(world, match) do
    case Gml.all(world, "Man") do
      [] -> world |> both_in(match) |> place_entering()
      [man] -> world |> other_in(match, man) |> place_entering()
      _two -> world
    end
  end

  defp both_in(world, match) do
    spawned = weapon(world)

    world =
      Gml.put(world, match, %{leadingPlayerIndex: 0, yellowSword: spawned, orangeSword: spawned})

    {_yellow, world} = player(world, {Camera.left(world) - @outside, @spawn_height}, 1)
    {orange, world} = player(world, {Camera.right(world) + @outside, @spawn_height}, 2)
    Gml.put(world, match, %{nB: orange})
  end

  defp other_in(world, match, man) do
    leader = Gml.var(world, man, :playerIndex)
    world = Gml.put(world, match, %{leadingPlayerIndex: leader})

    {_id, world} =
      if leader == 1,
        do: player(world, {Camera.right(world) + @outside, @spawn_height}, 2),
        else: player(world, {Camera.left(world) - @outside, @spawn_height}, 1)

    world
  end

  defp place_entering(world) do
    world
    |> Gml.all("Man")
    |> Enum.reduce(world, fn man, world ->
      if World.fetch(world, man) && Gml.var(world, man, :state) == @entering,
        do: place(world, man),
        else: world
    end)
  end

  defp place(world, man) do
    world = if players_left(world) == 2, do: away_from_other(world, man), else: world
    %Instance{x: x, y: y} = World.fetch(world, man)

    world =
      case Gml.nearest(world, {x, y}, "RespawnPoint") do
        nil ->
          world

        point ->
          World.update(
            world,
            man,
            &%{&1 | x: World.fetch(world, point).x, y: World.fetch(world, point).y}
          )
      end

    %Instance{x: x, y: y} = World.fetch(world, man)

    world
    |> Weapon.set_type(man, weapon(world))
    |> Sound.play(@coming_in, {x, y})
  end

  defp away_from_other(world, man) do
    %Instance{x: x, y: y} = World.fetch(world, man)
    centre = Camera.center_x(world)

    with other when other != nil <- furthest(world, man, {x, y}),
         true <- abs(x - World.fetch(world, other).x) < @too_close do
      cond do
        x < centre -> World.update(world, man, &%{&1 | x: Camera.right(world) + @outside})
        x > centre -> World.update(world, man, &%{&1 | x: Camera.left(world) - @outside})
        true -> world
      end
    else
      _ -> world
    end
  end

  defp furthest(world, man, {x, y}) do
    case Gml.all(world, "Man") do
      [] ->
        nil

      men ->
        Enum.max_by(men, &squared_distance(world, &1, man, {x, y}))
    end
  end

  defp squared_distance(_world, man, man, _point), do: -1

  defp squared_distance(world, id, _man, {x, y}) do
    %Instance{x: ix, y: iy} = World.fetch(world, id)
    (ix - x) * (ix - x) + (iy - y) * (iy - y)
  end

  @doc "How many fencers are up, not collapsing (`howManyPlayersLeft`)."
  @spec players_left(World.t()) :: non_neg_integer()
  def players_left(%World{} = world),
    do: world |> Gml.all("Man") |> Enum.count(&(not Query.collapsing?(world, &1)))

  @doc "The one fencer up when only one is (`isOnePlayerLeft`), `nil` otherwise."
  @spec one_left(World.t()) :: non_neg_integer() | nil
  def one_left(%World{} = world) do
    case world |> Gml.all("Man") |> Enum.reject(&Query.collapsing?(world, &1)) do
      [man] -> man
      _other -> nil
    end
  end
end
