defmodule Nidhox.Objects.Mines do
  @moduledoc """
  The mines' machinery, as the game's code runs it. The pump (`Pump`) has no code: it
  shows its animated sprite.

    * `Screw` create: `imageSpeed` `0.6 + random(0.05)`; step: its frames run at
      `imageSpeed`; draw: for every sprite height `i` along its scaled height, its frame
      at `(x + lengthdir_x(i, image_angle − 90), y + lengthdir_y(i, image_angle − 90))`,
      `random_range(0.95, 1.1)` wide and 1 tall, turned `image_angle`, in its blend and
      alpha

  The smokers (`Smoker`) are `Nidhox.Objects.Smoke`'s.
  """

  alias Cauldron2D.GameMaker.{Draw, Instance, World}
  alias Nidhox.Gml

  @screw_jitter {0.95, 1.1}

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Screw_Create_0", &screw_start/3},
      {"gml_Object_Screw_Step_0", &screw_turn/3},
      {"gml_Object_Screw_Draw_0", &screw_draw/3}
    ]
  end

  defp screw_start(world, self, _other) do
    {extra, world} = Gml.random(world, 0.05)
    Gml.put(world, self, %{imageSpeed: 0.6 + extra})
  end

  defp screw_turn(world, self, _other),
    do: World.update(world, self, &%{&1 | image_speed: Gml.var(world, self, :imageSpeed) / 1})

  defp screw_draw(world, self, _other) do
    %Instance{sprite_index: sprite, image_yscale: yscale} = World.fetch(world, self)
    {_width, height} = World.sprite(world, sprite).size

    0
    |> Stream.iterate(&(&1 + height))
    |> Enum.take_while(&(&1 < height * yscale))
    |> Enum.reduce(world, &screw_segment(&2, self, &1))
  end

  defp screw_segment(world, self, along) do
    %Instance{} = screw = World.fetch(world, self)
    {low, high} = @screw_jitter
    {width, world} = Gml.random_range(world, low, high)
    angle = screw.image_angle - 90

    Draw.sprite(
      world,
      screw.sprite_index,
      screw.image_index,
      {screw.x + Gml.lengthdir_x(along, angle), screw.y + Gml.lengthdir_y(along, angle)},
      scale: {width, 1},
      angle: screw.image_angle,
      blend: screw.image_blend,
      alpha: screw.image_alpha
    )
  end
end
