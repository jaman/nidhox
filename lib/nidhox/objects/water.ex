defmodule Nidhox.Objects.Water do
  @moduledoc """
  Standing water, as the game's code lays and moves it:

    * `WaterArea` lays a `Water` every `sWater` width along its own width, from its left
      edge, then goes
    * a `Water` plays its frames at `@image_speed` and bobs each step:
      `y = ystart + sin(((x / sprite_width) × 10 + frame) × 0.03) × 4`, `frame` the step
  """

  alias Cauldron2D.GameMaker.{Instance, World}

  @image_speed 0.6
  @bob 4
  @rate 0.03
  @spread 10

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_WaterArea_Create_0", &lay/3},
      {"gml_Object_Water_Create_0", &start/3},
      {"gml_Object_Water_Step_0", &bob/3}
    ]
  end

  defp lay(world, self, _other) do
    %Instance{x: x, y: y, image_xscale: xscale, sprite_index: sprite} = World.fetch(world, self)
    {area_width, _height} = World.sprite(world, sprite).size
    water = World.object_index(world, "Water")
    {piece, _height} = World.sprite(world, World.object(world, water).sprite).size

    0
    |> Stream.iterate(&(&1 + piece))
    |> Enum.take_while(&(&1 < area_width * xscale))
    |> Enum.reduce(world, fn along, world ->
      world |> World.create(water, {x + along, y}) |> elem(0)
    end)
    |> World.destroy(self)
  end

  defp start(world, self, _other),
    do: World.update(world, self, &%{&1 | image_speed: @image_speed})

  defp bob(world, self, _other) do
    World.update(world, self, fn %Instance{} = water ->
      width = World.sprite(world, water.sprite_index).size |> elem(0)
      phase = (water.x / (width * water.image_xscale) * @spread + world.steps) * @rate
      %{water | y: water.ystart + :math.sin(phase) * @bob}
    end)
  end
end
