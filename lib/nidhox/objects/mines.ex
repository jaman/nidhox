defmodule Nidhox.Objects.Mines do
  @moduledoc """
  The mines' machinery, as the game's code runs it.

    * `Pump` draw, a rocking pump-jack: its blend `make_color_hsv(0, cos(frame / 10) × 5
      + 50, 100 + sin(frame / 10) × 10)`; its body (`draw_self`); `sPumpWheel` at `(x −
      30, y − 81)` turned `−frame × 2`; `sPumpHead` at `(x, y − 120)` turned `angle =
      sin(frame / 40 × 2) × 30`; and `sPumpEnd` at its frame `|angle / 30| × 20`, 70
      along `angle` from the head's middle, turned `angle` — all in its blend
    * `Screw` create: `imageSpeed` `0.6 + random(0.05)`; step: its frames run at
      `imageSpeed`; draw: for every sprite height `i` along its scaled height, its frame
      at `(x + lengthdir_x(i, image_angle − 90), y + lengthdir_y(i, image_angle − 90))`,
      `random_range(0.95, 1.1)` wide and 1 tall, turned `image_angle`, in its blend and
      alpha

  The smokers (`Smoker`) are `Nidhox.Objects.Smoke`'s.
  """

  alias Cauldron2D.GameMaker.{Colour, Data, Draw, Instance, World}
  alias Nidhox.Gml
  alias Nidhox.Objects.System

  @screw_jitter {0.95, 1.1}
  @pump_speed 2
  @pump_swing 30
  @pump_pivot_rise 120
  @pump_beam 70
  @wheel_back 30
  @wheel_rise 81

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Screw_Create_0", &screw_start/3},
      {"gml_Object_Screw_Step_0", &screw_turn/3},
      {"gml_Object_Screw_Draw_0", &screw_draw/3},
      {"gml_Object_Pump_Draw_0", &pump_draw/3}
    ]
  end

  defp pump_draw(world, self, _other) do
    frame = System.get(world, :frame)
    blend = Colour.hsv(0, :math.cos(frame / 10) * 5 + 50, 100 + :math.sin(frame / 10) * 10)
    world = World.update(world, self, &%{&1 | image_blend: blend})
    %Instance{x: x, y: y} = World.fetch(world, self)
    angle = :math.sin(frame / 40 * @pump_speed) * @pump_swing
    pivot = {x, y - @pump_pivot_rise}

    world
    |> Draw.self(self)
    |> Draw.sprite(sprite(world, "sPumpWheel"), 0, {x - @wheel_back, y - @wheel_rise},
      angle: -frame * @pump_speed,
      blend: blend
    )
    |> Draw.sprite(sprite(world, "sPumpHead"), 0, pivot, angle: angle, blend: blend)
    |> Draw.sprite(
      sprite(world, "sPumpEnd"),
      abs(angle / @pump_swing) * 20,
      pump_end(pivot, angle),
      angle: angle,
      blend: blend
    )
  end

  defp pump_end({x, y}, angle),
    do: {x + Gml.lengthdir_x(@pump_beam, angle), y + Gml.lengthdir_y(@pump_beam, angle)}

  defp sprite(world, name), do: Data.index(world.data, :sprites, name)

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
