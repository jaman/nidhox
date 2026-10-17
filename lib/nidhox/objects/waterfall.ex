defmodule Nidhox.Objects.Waterfall do
  @moduledoc """
  The wilds' waterfall spray (`ParticleWaterfall`), as the game's code runs it.

    * create: a particle system it updates itself and an emitter; `pWater`, its own
      sprite stretched over its life at a random frame, falling by gravity 0.33, living
      30–35 steps, heading 269–271° wiggling 0.1, and dying into one `pMist`; `pMist`,
      `sSmoke` animated and stretched, rising by gravity 0.01, living 40–60 steps, heading
      0–180° wiggling 0.1 at speed 0–1, alpha 0.7, added to what is beneath it
    * step: the system updated and at its depth, the emitter on the rectangle from 2
      pixels left of it and 4 above, and one `pWater` a step
    * destroy, and room end (its destroy event): the system and its types gone
  """

  alias Cauldron2D.GameMaker.{Data, Instance, PartSystems, World}
  alias Nidhox.Gml

  @mist_sprite "sSmoke"

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_ParticleWaterfall_Create_0", &start/3},
      {"gml_Object_ParticleWaterfall_Step_0", &spray/3},
      {"gml_Object_ParticleWaterfall_Destroy_0", &finish/3},
      {"gml_Object_ParticleWaterfall_Other_5",
       fn world, self, _other -> World.perform(world, self, :destroy, 0) end}
    ]
  end

  defp start(world, self, _other) do
    %Instance{sprite_index: sprite} = World.fetch(world, self)
    {world, system} = PartSystems.system_create(world)
    {world, emitter} = PartSystems.emitter_create(world, system)
    {world, water} = PartSystems.type_create(world)
    {world, mist} = PartSystems.type_create(world)
    smoke = Data.index(world.data, :sprites, @mist_sprite)

    world
    |> PartSystems.type_sprite(water, sprite, false, true, true)
    |> PartSystems.type_gravity(water, 0.33, 270)
    |> PartSystems.type_life(water, 30, 35)
    |> PartSystems.type_direction(water, 269, 271, 0, 0.1)
    |> PartSystems.type_sprite(mist, smoke, true, true, false)
    |> PartSystems.type_gravity(mist, 0.01, 90)
    |> PartSystems.type_life(mist, 40, 60)
    |> PartSystems.type_direction(mist, 0, 180, 0, 0.1)
    |> PartSystems.type_speed(mist, 0, 1, 0, 0)
    |> PartSystems.type_death(water, 1, mist)
    |> PartSystems.type_alpha1(mist, 0.7)
    |> PartSystems.type_blend(mist, true)
    |> PartSystems.system_automatic_update(system, false)
    |> Gml.put(self, %{pSys: system, pEmit: emitter, pWater: water, pMist: mist})
  end

  defp spray(world, self, _other) do
    %Instance{x: x, y: y, depth: depth, vars: %{pSys: system, pEmit: emitter, pWater: water}} =
      World.fetch(world, self)

    world
    |> PartSystems.system_update(system)
    |> PartSystems.system_depth(system, depth)
    |> PartSystems.emitter_region(system, emitter, {x - 2, x, y - 4, y}, :rectangle, :linear)
    |> PartSystems.emitter_burst(system, emitter, water, 1)
  end

  defp finish(world, self, _other) do
    case World.fetch(world, self).vars do
      %{pSys: system, pWater: water, pMist: mist} ->
        world
        |> PartSystems.type_destroy(water)
        |> PartSystems.type_destroy(mist)
        |> PartSystems.system_destroy(system)

      _none ->
        world
    end
  end
end
