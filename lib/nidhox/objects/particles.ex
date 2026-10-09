defmodule Nidhox.Objects.Particles do
  @moduledoc """
  The game's `Particles` object, made once by `System` and kept across rooms: the torch
  and dust particle systems, updated by its step and drawn by its draw.

    * torch: sprite 273, life 10–30, speed 0–0.1, any direction wiggling 0.05, gravity
      0.02 upwards
    * dust: sprite 271 animated from a random frame, size 0.3–0.5 growing 0.01 a step
      wiggling 0.005, life 5–30, speed 0.2–0.5 wiggling 0.025, direction 0–180 wiggling
      0.05, gravity 0.01 downwards, alpha 0 → 0.1 → 0

  `dust_at/2` is the game's `makeDustAt`: one dust particle from an elliptic region 8
  pixels wide centred on a point.
  """

  alias Cauldron2D.GameMaker.{Draw, Instance, PartSystems, World}
  alias Nidhox.Gml

  @object "Particles"

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Particles_Create_0", &start/3},
      {"gml_Object_Particles_Step_0", &step/3},
      {"gml_Object_Particles_Draw_0", &draw/3},
      {"gml_Object_Particles_Destroy_0", &finish/3}
    ]
  end

  @doc "`world` with one dust particle set loose around `{x, y}` (`makeDustAt`)."
  @spec dust_at(World.t(), {number(), number()}) :: World.t()
  def dust_at(%World{} = world, {x, y}) do
    with object when is_integer(object) <- World.object_index(world, @object),
         ids when ids != [] <- World.instances_of(world, object) do
      Enum.reduce(ids, world, fn id, world ->
        %{dustSystem: system, dustEmitter: emitter, dustParticle: dust} =
          World.fetch(world, id).vars

        world
        |> PartSystems.emitter_region(system, emitter, {x - 4, x + 4, y, y}, :ellipse, :linear)
        |> PartSystems.emitter_burst(system, emitter, dust, 1)
      end)
    else
      _none -> world
    end
  end

  defp start(world, self, _other) do
    {world, torch_system} = PartSystems.system_create(world)

    world =
      world
      |> PartSystems.system_automatic_update(torch_system, false)
      |> PartSystems.system_automatic_draw(torch_system, false)

    {world, torch_emitter} = PartSystems.emitter_create(world, torch_system)
    {world, torch} = PartSystems.type_create(world)

    world =
      world
      |> PartSystems.type_sprite(torch, 273, true, false, false)
      |> PartSystems.type_life(torch, 10, 30)
      |> PartSystems.type_speed(torch, 0, 0.1, 0, 0)
      |> PartSystems.type_direction(torch, 0, 360, 0, 0.05)
      |> PartSystems.type_gravity(torch, 0.02, 90)

    {world, dust_system} = PartSystems.system_create(world)

    world =
      world
      |> PartSystems.system_automatic_update(dust_system, false)
      |> PartSystems.system_automatic_draw(dust_system, false)
      |> PartSystems.system_depth(dust_system, 0)

    {world, dust_emitter} = PartSystems.emitter_create(world, dust_system)
    {world, dust} = PartSystems.type_create(world)

    world
    |> PartSystems.type_sprite(dust, 271, true, false, true)
    |> PartSystems.type_size(dust, 0.3, 0.5, 0.01, 0.005)
    |> PartSystems.type_life(dust, 5, 30)
    |> PartSystems.type_speed(dust, 0.2, 0.5, 0, 0.025)
    |> PartSystems.type_direction(dust, 0, 180, 0, 0.05)
    |> PartSystems.type_gravity(dust, 0.01, 270)
    |> PartSystems.type_alpha3(dust, 0, 0.1, 0)
    |> Gml.put(self, %{
      torchSystem: torch_system,
      torchEmitter: torch_emitter,
      torchParticle: torch,
      dustSystem: dust_system,
      dustEmitter: dust_emitter,
      dustParticle: dust
    })
  end

  defp step(world, self, _other) do
    %Instance{vars: %{torchSystem: torch, dustSystem: dust}} = World.fetch(world, self)

    world
    |> PartSystems.system_update(torch)
    |> PartSystems.system_update(dust)
  end

  defp draw(world, self, _other) do
    %Instance{depth: depth, vars: %{torchSystem: torch, dustSystem: dust}} =
      World.fetch(world, self)

    (PartSystems.items(world, torch) ++ PartSystems.items(world, dust))
    |> Enum.reduce(world, &Draw.item(&2, %{&1 | depth: depth}))
  end

  defp finish(world, self, _other) do
    %Instance{vars: %{torchSystem: torch, dustSystem: dust}} = World.fetch(world, self)

    world
    |> PartSystems.system_destroy(torch)
    |> PartSystems.system_destroy(dust)
  end
end
