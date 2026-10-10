defmodule Nidhox.Objects.Smoke do
  @moduledoc """
  Smoke and embers rising from a fire, as the game's code makes them for the mines'
  `Smoker` and the champion's `Pyre`.

  Each has a particle system and emitter, `smoke` (`sSmoke` animated and stretched over
  its life, turned 0–360 turning 1 a step wiggling 0.1, speed 0–0.3, direction 180–360,
  gravity 0.025 upwards, life 60–90, hue and saturation 0, value 0–7) and `ember`
  (`sEmber` animated, life 30–90, speed 0–0.1, any direction wiggling 0.05, gravity 0.02
  upwards). Each step the emitter is set on an ellipse about it, and it puffs one smoke
  when `System.frame` is a multiple of 6 and one ember when it is a multiple of 5.

    * `Smoker`: the ellipse 32 × 4 about its place; it draws its particles itself
    * `Pyre`: the ellipse from 16 left to 16 right of it and from 16 to 2 above it; its
      particles draw themselves; in the tournament's champion room it is tinted the
      champion's colour (`getPlayerColor`), the champion `World.global(:champion)`
      standing for the last of the game's `Tournament.bracketHistory`
  """

  alias Cauldron2D.GameMaker.{Draw, Instance, PartSystems, World}
  alias Nidhox.Bout.PlayerColour
  alias Nidhox.Gml
  alias Nidhox.Objects.System

  @smoke_sprite 277
  @ember_sprite 274
  @smoke_every 6
  @ember_every 5

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Smoker_Create_0", fn world, self, _other -> fire(world, self, false) end},
      {"gml_Object_Smoker_Step_0", fn world, self, _other -> puff(world, self, {-16, 16, -2, 2}) end},
      {"gml_Object_Smoker_Draw_0", &draw/3},
      {"gml_Object_Pyre_Create_0", &pyre/3},
      {"gml_Object_Pyre_Step_0", fn world, self, _other -> puff(world, self, {-16, 16, -16, -2}) end}
    ]
  end

  defp pyre(world, self, _other) do
    world = fire(world, self, true)

    case World.global(world, :champion, nil) do
      nil ->
        world

      champion ->
        {colour, world} = PlayerColour.get(world, self, champion)
        World.update(world, self, &%{&1 | image_blend: colour})
    end
  end

  defp fire(world, self, draws_itself) do
    {world, system} = PartSystems.system_create(world)
    world = if draws_itself, do: world, else: PartSystems.system_automatic_draw(world, system, false)
    {world, emitter} = PartSystems.emitter_create(world, system)
    {world, smoke} = PartSystems.type_create(world)

    world =
      world
      |> PartSystems.type_sprite(smoke, @smoke_sprite, true, true, false)
      |> PartSystems.type_orientation(smoke, 0, 360, 1, 0.1, false)
      |> PartSystems.type_speed(smoke, 0, 0.3, 0, 0)
      |> PartSystems.type_direction(smoke, 180, 360, 0, 0)
      |> PartSystems.type_gravity(smoke, 0.025, 90)
      |> PartSystems.type_life(smoke, 60, 90)
      |> PartSystems.type_colour_hsv(smoke, {0, 0}, {0, 0}, {0, 7})

    {world, ember} = PartSystems.type_create(world)

    world
    |> PartSystems.type_sprite(ember, @ember_sprite, true, false, false)
    |> PartSystems.type_life(ember, 30, 90)
    |> PartSystems.type_speed(ember, 0, 0.1, 0, 0)
    |> PartSystems.type_direction(ember, 0, 360, 0, 0.05)
    |> PartSystems.type_gravity(ember, 0.02, 90)
    |> Gml.put(self, %{particleSystem: system, particleEmitter: emitter, smoke: smoke, ember: ember})
  end

  defp puff(world, self, {left, right, top, bottom}) do
    %Instance{x: x, y: y, vars: %{particleSystem: system, particleEmitter: emitter, smoke: smoke, ember: ember}} =
      World.fetch(world, self)

    frame = System.get(world, :frame)

    world
    |> PartSystems.emitter_region(system, emitter, {x + left, x + right, y + top, y + bottom}, :ellipse, :linear)
    |> burst_on(system, emitter, smoke, every?(frame, @smoke_every))
    |> burst_on(system, emitter, ember, every?(frame, @ember_every))
  end

  defp every?(frame, period), do: abs(:math.fmod(frame, period)) <= 1.0e-5

  defp burst_on(world, system, emitter, type, true), do: PartSystems.emitter_burst(world, system, emitter, type, 1)
  defp burst_on(world, _system, _emitter, _type, false), do: world

  defp draw(world, self, _other) do
    %Instance{depth: depth, vars: %{particleSystem: system}} = World.fetch(world, self)
    world |> PartSystems.items(system) |> Enum.reduce(world, &Draw.item(&2, Map.put(&1, :depth, depth)))
  end
end
