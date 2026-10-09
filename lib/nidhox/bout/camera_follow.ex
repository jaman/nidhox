defmodule Nidhox.Bout.CameraFollow do
  @moduledoc """
  The camera following a match, as the game's `manageCamera` moves it each frame, the
  match (`Match`) its anchor:

    1. both players' fencers are held to the screen (`Nidhox.Bout.RightOfWay.stay_in_view/3`)
    2. with more than one fencer up and somebody leading, the match moves to the
       middle of all the fencers (across; down, their middle plus 100). With exactly
       one up it moves to that fencer, 64 pixels ahead of it in the leader's direction
       (right for player 1, left for player 2); in an end room the camera's centre
       also moves down towards the first fencer's height less 20, when more than 10
       off, by 0.3 of the way, at most 8 a step, and never below 100 above the room's
       bottom. Otherwise the match stays where it is
    3. the camera's centre moves across towards the match, at most 8 pixels a step — at
       once on the room's first frame (`firstFrameOfRoom`, then cleared) — while any
       fencer exists, and is kept inside the room
    4. every `ParallaxObject` moves across by the camera's move since last frame ×
       its depth (its `overrideDepth` when that is set) / 400 × 0.7, the move measured
       from `pCameraCenterX`; then `pCameraCenterX` and `pCameraCenterY` are the
       camera's centre
  """

  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Bout.{Camera, Outcome, RightOfWay, Spawn}
  alias Nidhox.Gml

  @ahead 64
  @below_middle 100
  @steepest 8
  @body_middle 20
  @settle 10
  @ease 0.3
  @floor_margin 100
  @parallax 0.7
  @per_depth 400
  @furthest_move 640_000

  @doc "The world after the camera follows the match `match` (`manageCamera`)."
  @spec manage(World.t(), non_neg_integer()) :: World.t()
  def manage(%World{} = world, match) do
    world
    |> hold_players(match)
    |> place_match(match)
    |> move_camera(match)
    |> keep_in_room()
    |> parallax(match)
    |> remember(match)
  end

  defp hold_players(world, match) do
    Enum.reduce(["YellowPlayer", "OrangePlayer"], world, fn name, world ->
      Enum.reduce(Gml.all(world, name), world, fn man, world ->
        if World.fetch(world, man), do: RightOfWay.stay_in_view(world, man, match), else: world
      end)
    end)
  end

  defp place_match(world, match) do
    leader = Gml.var(world, match, :leadingPlayerIndex)

    cond do
      Spawn.players_left(world) > 1 and leader != 0 -> between(world, match)
      (lone = Spawn.one_left(world)) != nil -> ahead_of(world, match, lone, leader)
      true -> world
    end
  end

  defp between(world, match) do
    men = Enum.map(Gml.all(world, "Man"), &World.fetch(world, &1))
    across = men |> Enum.map(& &1.x) |> Enum.sum()
    down = men |> Enum.map(& &1.y) |> Enum.sum()
    World.update(world, match, &%{&1 | x: across / 2, y: down / 2 + @below_middle})
  end

  defp ahead_of(world, match, lone, leader) do
    x = World.fetch(world, lone).x + lead(leader)
    world = World.update(world, match, &%{&1 | x: x})
    if Outcome.victory_lap?(world), do: settle_height(world), else: world
  end

  defp lead(1), do: @ahead
  defp lead(2), do: -@ahead
  defp lead(_leader), do: 0

  defp settle_height(world) do
    %Instance{y: y} = World.fetch(world, Gml.first(world, "Man"))
    centre = Camera.center_y(world)
    off = y - @body_middle - centre

    if abs(off) - @settle > 1.0e-5 do
      step = Gml.clamp(off * @ease, -@steepest, @steepest)
      Camera.put_center_y(world, min(room_height(world) - @floor_margin, centre + step))
    else
      world
    end
  end

  defp move_camera(world, match) do
    gap = World.fetch(world, match).x - Camera.center_x(world)

    {gap, world} =
      if Gml.truthy?(Gml.var(world, match, :firstFrameOfRoom)),
        do: {gap, Gml.put(world, match, %{firstFrameOfRoom: 0})},
        else: {Gml.clamp(gap, -@steepest, @steepest), world}

    if Gml.exists?(world, "Man"),
      do: Camera.put_center_x(world, Camera.center_x(world) + gap),
      else: world
  end

  defp keep_in_room(world) do
    world = if Camera.left(world) < 0, do: Camera.put_left(world, 0), else: world
    width = room_width(world)
    if Camera.right(world) > width, do: Camera.put_right(world, width), else: world
  end

  defp parallax(world, match) do
    diff = Camera.center_x(world) - Gml.var(world, match, :pCameraCenterX, Camera.center_x(world))

    if abs(diff) < @furthest_move and abs(diff) > 0 do
      world
      |> Gml.all("ParallaxObject")
      |> Enum.reduce(world, fn id, world ->
        World.update(world, id, &%{&1 | x: &1.x + diff * depth(&1) / @per_depth * @parallax})
      end)
    else
      world
    end
  end

  defp depth(%Instance{depth: depth, vars: vars}) do
    override = Map.get(vars, :overrideDepth, 0)
    if Gml.truthy?(override), do: override, else: depth
  end

  defp remember(world, match),
    do: Gml.put(world, match, %{pCameraCenterX: Camera.center_x(world), pCameraCenterY: Camera.center_y(world)})

  defp room_width(world), do: world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size) |> elem(0)
  defp room_height(world), do: world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size) |> elem(1)
end
