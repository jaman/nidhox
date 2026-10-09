defmodule Nidhox.Parallax do
  @moduledoc """
  The room dressing that sits at a depth behind the play — instances of `ParallaxObject`
  and the objects descending from it (the sun, gothic windows, pillars, chandeliers,
  lights) — moved with the camera by part of its motion, as the game's camera does it.

  Each step the camera's centre has moved `diff` pixels along x since the step before,
  and every such instance moves `diff × depth / 400 × @strength`, its `depth` being its
  `overrideDepth` when that is not `-1`, else its own. On entering a room, and on the
  first step, nothing moves: the camera's centre there is where moving is measured from.
  The centre of the camera is `cameraCenterX/1`.
  """

  alias Cauldron2D.GameMaker.World

  @strength 0.7
  @per_depth 1 / 400
  @object "ParallaxObject"
  @anchor :parallax_camera

  @doc "The world with every parallax instance moved by the camera's motion since the step before."
  @spec apply(World.t()) :: World.t()
  def apply(%World{} = world) do
    centre = camera_center_x(world)

    case World.global(world, @anchor) do
      {room, previous} when room == world.room -> move(world, centre - previous)
      _ -> world
    end
    |> World.put_global(@anchor, {world.room, centre})
  end

  @doc "The x of the camera's centre: the middle of the room's first view, or of the room without views."
  @spec camera_center_x(World.t()) :: number()
  def camera_center_x(%World{views: [%{view: {x, _y, width, _height}} | _]}), do: x + width / 2

  def camera_center_x(%World{} = world),
    do: (world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size) |> elem(0)) / 2

  defp move(world, diff) when diff == 0, do: world

  defp move(world, diff) do
    case World.object_index(world, @object) do
      nil ->
        world

      object ->
        world
        |> World.instances_of(object)
        |> Enum.reduce(world, fn id, world ->
          World.update(world, id, &%{&1 | x: &1.x + diff * depth(&1) * @per_depth * @strength})
        end)
    end
  end

  defp depth(instance) do
    case Map.get(instance.vars, :overrideDepth, -1) do
      -1 -> instance.depth
      override -> override
    end
  end
end
