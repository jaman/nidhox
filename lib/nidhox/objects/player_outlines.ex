defmodule Nidhox.Objects.PlayerOutlines do
  @moduledoc """
  The game's `PlayerOutlines`, made by `System` and kept across rooms: a faint dark edge
  round the fencers' bodies.

    * create: a 320 × 200 surface (`canvas`)
    * draw: (its create again if the canvas was lost) just behind the swords
      (`HeldWeapon.depth + 1`); the canvas cleared, then every body
      (`FleshCollisionMask`) with a sprite drawn onto it in black, one pixel off its place
      at 0°, 90°, 180° and 270°, the canvas standing for the view; the canvas drawn over
      the view at alpha 0.1
    * destroy: the canvas freed
  """

  alias Cauldron2D.GameMaker.{Draw, Instance, Surfaces, World}
  alias Nidhox.Bout.Camera
  alias Nidhox.Gml

  @width 320
  @height 200
  @black {0, 0, 0}
  @white {255, 255, 255}
  @shade 0.1

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_PlayerOutlines_Create_0", &start/3},
      {"gml_Object_PlayerOutlines_Draw_0", &draw/3},
      {"gml_Object_PlayerOutlines_Destroy_0", &free/3}
    ]
  end

  defp start(world, self, _other) do
    {world, canvas} = Surfaces.create(world, @width, @height)
    Gml.put(world, self, %{canvas: canvas})
  end

  defp draw(world, self, _other) do
    world =
      if Surfaces.exists?(world, Gml.var(world, self, :canvas, -1)),
        do: world,
        else: World.perform(world, self, :create, 0)

    world =
      case Gml.first(world, "HeldWeapon") do
        nil -> world
        sword -> World.update(world, self, &%{&1 | depth: World.fetch(world, sword).depth + 1})
      end

    canvas = Gml.var(world, self, :canvas)
    {left, top} = {Camera.left(world), Camera.top(world)}

    world
    |> Surfaces.clear(canvas, @white, 0)
    |> Surfaces.draw(canvas, outlines(world, {left, top}))
    |> then(&Draw.item(&1, Surfaces.item(&1, canvas, {left, top}, alpha: @shade)))
  end

  defp outlines(world, {left, top}) do
    for turn <- 0..3,
        body <- Gml.all(world, "FleshCollisionMask"),
        %Instance{sprite_index: sprite} = instance = World.fetch(world, body),
        World.sprite(world, sprite) != nil do
      {dx, dy} = {Gml.lengthdir_x(1, turn * 90) - left, Gml.lengthdir_y(1, turn * 90) - top}

      %{
        picture: {:sprite, sprite, frame(world, instance)},
        position: {instance.x + dx, instance.y + dy},
        origin: World.sprite(world, sprite).origin,
        scale: {instance.image_xscale, instance.image_yscale},
        blend: @black,
        alpha: 1.0
      }
    end
  end

  defp frame(world, %Instance{sprite_index: sprite, image_index: index}),
    do: Integer.mod(floor(index), length(World.sprite(world, sprite).frames))

  defp free(world, self, _other) do
    canvas = Gml.var(world, self, :canvas, -1)
    if Surfaces.exists?(world, canvas), do: Surfaces.free(world, canvas), else: world
  end
end
