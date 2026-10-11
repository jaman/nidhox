defmodule Nidhox.Objects.Wilds do
  @moduledoc """
  The wilds' living scenery, as the game's code runs it.

    * `Mistletoe` (and `LeavesBunch`, `LeavesBunchDark`, which are mistletoe) create: at
      frame `irandom(image_number)`, flipped `choose(−1, 1)` across and down,
      `imageSpeed` `0.15 + random(0.05)`; step: its frames run at `imageSpeed`
    * `Rain` create: a particle system it updates and draws itself, an emitter and a drop
      (`sRainDrop` at a random frame, speed 13, life `screenHeight × 1.5 / 14`, hue and
      saturation 0, value 50–255); `intensity` 1. Step: with `a` `270 + 5 ×
      sin(frame / 190)`, drops head `a ± 2` and are turned `270 + a ± 2`, both wiggling
      0.1; the emitter on a line from 160 pixels left of the camera to 160 right of it, 8
      above its top; `intensity × (15 × |sin(frame / 60)| + 20)` drops a step. Draw:
      its drops added to what is beneath them. Destroy, room end and game end: the
      system gone
  """

  alias Cauldron2D.GameMaker.{Draw, Instance, PartSystems, World}
  alias Nidhox.Bout.Camera
  alias Nidhox.Gml
  alias Nidhox.Objects.System

  @drop_sprite 104
  @drop_speed 13
  @margin 160
  @above 8

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Mistletoe_Create_0", &leaves/3},
      {"gml_Object_Mistletoe_Step_0",
       fn world, self, _other ->
         World.update(world, self, &%{&1 | image_speed: Gml.var(world, self, :imageSpeed) / 1})
       end},
      {"gml_Object_Rain_Create_0", &rain_start/3},
      {"gml_Object_Rain_Step_0", &rain_step/3},
      {"gml_Object_Rain_Draw_0", &rain_draw/3},
      {"gml_Object_Rain_Destroy_0", &rain_end/3},
      {"gml_Object_Rain_Other_5", &rain_end/3},
      {"gml_Object_Rain_Other_3", &rain_end/3}
    ]
  end

  defp leaves(world, self, _other) do
    %Instance{sprite_index: sprite} = World.fetch(world, self)
    {frame, world} = Gml.irandom(world, length(World.sprite(world, sprite).frames))
    world = World.update(world, self, &%{&1 | image_index: frame / 1})
    {across, world} = Gml.choose(world, [-1, 1])
    world = World.update(world, self, &%{&1 | image_xscale: across / 1})
    {down, world} = Gml.choose(world, [-1, 1])
    world = World.update(world, self, &%{&1 | image_yscale: down / 1})
    {extra, world} = Gml.random(world, 0.05)
    Gml.put(world, self, %{imageSpeed: 0.15 + extra})
  end

  defp rain_start(world, self, _other) do
    {world, system} = PartSystems.system_create(world)
    {world, emitter} = PartSystems.emitter_create(world, system)
    {world, drop} = PartSystems.type_create(world)
    life = Camera.height(world) * 1.5 / (@drop_speed + 1)

    world
    |> PartSystems.type_sprite(drop, @drop_sprite, false, false, true)
    |> PartSystems.type_speed(drop, @drop_speed, @drop_speed, 0, 0)
    |> PartSystems.type_life(drop, life, life)
    |> PartSystems.type_colour_hsv(drop, {0, 0}, {0, 0}, {50, 255})
    |> PartSystems.system_automatic_draw(system, false)
    |> PartSystems.system_automatic_update(system, false)
    |> Gml.put(self, %{
      particleSystem: system,
      particleEmitter: emitter,
      particleType: drop,
      intensity: 1
    })
  end

  defp rain_step(world, self, _other) do
    %{particleSystem: system, particleEmitter: emitter, particleType: drop, intensity: intensity} =
      World.fetch(world, self).vars

    frame = System.get(world, :frame)
    angle = 270 + 5 * :math.sin(frame / 190)

    region =
      {Camera.left(world) - @margin, Camera.right(world) + @margin, Camera.top(world) - @above,
       Camera.top(world) - @above}

    count = trunc(intensity * 15 * abs(:math.sin(frame / 60)) + intensity * 20)

    world
    |> PartSystems.system_update(system)
    |> PartSystems.type_direction(drop, angle - 2, angle + 2, 0, 0.1)
    |> PartSystems.type_orientation(drop, 270 + angle - 2, 270 + angle + 2, 0, 0.1, false)
    |> PartSystems.emitter_region(system, emitter, region, :line, :linear)
    |> PartSystems.emitter_burst(system, emitter, drop, count)
  end

  defp rain_draw(world, self, _other) do
    %Instance{depth: depth, vars: %{particleSystem: system}} = World.fetch(world, self)

    world
    |> PartSystems.items(system)
    |> Enum.reduce(world, &Draw.item(&2, Map.merge(&1, %{depth: depth, mode: :add})))
  end

  defp rain_end(world, self, _other) do
    case World.fetch(world, self).vars do
      %{particleSystem: system} -> PartSystems.system_destroy(world, system)
      _none -> world
    end
  end
end
