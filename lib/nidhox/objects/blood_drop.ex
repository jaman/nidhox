defmodule Nidhox.Objects.BloodDrop do
  @moduledoc """
  The game's `o_blood`: a drop of blood flying from a wound under gravity, staining the
  ground it lands on (`BloodSurface`).

    * `bleed/3` (`bleed_at_pos_color(x, y, colour)`): while there are fewer than 76
      drops, a new one at the point, `hspeed` `(random(30) ÷ 10 − 1.5) × 2`, `vspeed`
      `random(10) ÷ 15 − 0.5`, in the colour; `{drop, world}`, `nil` with too many
    * create: gravity 0.198 pointing `265 + random(10)` degrees, `hspeed`
      `random(100) ÷ 100 − 0.5`, `vspeed` 0, depth −2, 0 or 2, `life` 3, gone after
      `250 + random(30)` steps
    * step: falls no faster than 8 a step
    * meeting a `BloodSurface`: a streak 1.5 wide from where it was to where it is, 4 up,
      drawn onto the surface's blood in its colour; the surface wakes (`active` 60); a
      third time and it is gone
    * draw: still, a dot (a streak a pixel tall); moving, a streak from where it was a
      step ago to a pixel below where it is; 1.5 wide in its colour
    * leaving the room: gone
  """

  alias Cauldron2D.GameMaker.{Draw, Instance, Surfaces, World}
  alias Nidhox.Gml

  @object "o_blood"
  @most 76
  @width 1.5

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_o_blood_Create_0", &start/3},
      {"gml_Object_o_blood_Step_0", &step/3},
      {"gml_Object_o_blood_Alarm_0", &gone/3},
      {"gml_Object_o_blood_Other_0", &gone/3},
      {"gml_Object_o_blood_Draw_0", &draw/3},
      {"gml_Object_o_blood_Collision_BloodSurface", &stain/3}
    ]
  end

  @doc "`{drop, world}`: a drop of blood of `colour` at `{x, y}` (`bleed_at_pos_color`); `nil` with too many."
  @spec bleed(World.t(), {number(), number()}, {byte(), byte(), byte()}) ::
          {non_neg_integer() | nil, World.t()}
  def bleed(%World{} = world, {x, y}, colour) do
    object = World.object_index(world, @object)

    if length(World.instances_of(world, object)) < @most do
      {world, drop} = World.create(world, object, {x, y})
      {across, world} = Gml.random(world, 30)
      {down, world} = Gml.random(world, 10)

      world =
        World.update(world, drop, fn drop ->
          %{drop | hspeed: (across / 10 - 1.5) * 2, vspeed: down / 15 - 0.5, image_blend: colour}
        end)

      {drop, world}
    else
      {nil, world}
    end
  end

  defp start(world, self, _other) do
    {tilt, world} = Gml.random(world, 10)
    {drift, world} = Gml.random(world, 100)
    {depth, world} = Gml.choose(world, [-2, 0, 2])
    {wait, world} = Gml.random(world, 30)

    world
    |> World.update(self, fn drop ->
      %{
        drop
        | gravity_direction: tilt + 265,
          gravity: 0.198,
          hspeed: drift / 100 - 0.5,
          vspeed: 0,
          depth: depth
      }
      |> Instance.put_alarm(0, trunc(wait + 250))
    end)
    |> Gml.put(self, %{life: 3})
  end

  defp step(world, self, _other) do
    World.update(world, self, fn drop ->
      if drop.vspeed > 8, do: %{drop | vspeed: 8}, else: drop
    end)
  end

  defp gone(world, self, _other), do: World.destroy(world, self)

  defp draw(world, self, _other) do
    %Instance{x: x, y: y, xprevious: px, yprevious: py, vspeed: vspeed, image_blend: colour} =
      World.fetch(world, self)

    if Gml.eq?(vspeed, 0),
      do: Draw.line(world, {x, y}, {x, y - 1}, @width, colour),
      else: Draw.line(world, {x, y + 1}, {px, py}, @width, colour)
  end

  defp stain(world, self, surface) do
    %Instance{x: x, y: y, xprevious: px, yprevious: py, image_blend: colour} =
      World.fetch(world, self)

    %Instance{x: sx, y: sy} = World.fetch(world, surface)
    blood = Gml.var(world, surface, :blood, -1)

    world =
      if Surfaces.exists?(world, blood),
        do:
          Surfaces.draw(world, blood, [
            Draw.line_item({px - sx, py - sy}, {x - sx, y - 4 - sy}, @width, colour)
          ]),
        else: world

    life = Gml.var(world, self, :life) - 1

    world
    |> Gml.put(surface, %{active: 60})
    |> Gml.put(self, %{life: life})
    |> then(&if(Gml.truthy?(life), do: &1, else: World.destroy(&1, self)))
  end
end
