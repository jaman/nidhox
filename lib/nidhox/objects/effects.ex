defmodule Nidhox.Objects.Effects do
  @moduledoc """
  The small objects a fight leaves behind for a moment:

    * `BloodEffect`: a spurt where a blade goes in, animating at 0.6 and gone when its
      animation ends
    * `Flash` (`flash_screen`): a white frame over the whole view, gone after two steps;
      a new flash replaces any already showing (`flash/1`)
    * `ClashPosition`: where swords last clashed (`clashXY`), `z` 0, `cleared` 1 at
      first
    * `Trail`: a copy of a fencer's body left behind with trails on, fading by 0.15 a
      step and gone once faded (its alpha no longer above half, as the game reads it),
      drawn added in a random hue
  """

  alias Cauldron2D.GameMaker.{Colour, Draw, World}
  alias Nidhox.Gml

  @white {255, 255, 255}

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_BloodEffect_Create_0", &spurt/3},
      {"gml_Object_BloodEffect_Other_7", &gone/3},
      {"gml_Object_Flash_Create_0", &flash_start/3},
      {"gml_Object_Flash_Step_0", &flash_step/3},
      {"gml_Object_Flash_Draw_0", &flash_draw/3},
      {"gml_Object_ClashPosition_Create_0", &clash_start/3},
      {"gml_Object_Trail_Step_0", &trail_step/3},
      {"gml_Object_Trail_Draw_0", &trail_draw/3}
    ]
  end

  @doc "The world with the screen flashing white (`flash_screen`)."
  @spec flash(World.t()) :: World.t()
  def flash(%World{} = world) do
    object = World.object_index(world, "Flash")
    world = world |> World.instances_of(object) |> Enum.reduce(world, &World.destroy(&2, &1))
    {world, _flash} = World.create(world, object, {0, 0})
    world
  end

  defp spurt(world, self, _other), do: World.update(world, self, &%{&1 | image_speed: 0.6})

  defp gone(world, self, _other), do: World.destroy(world, self)

  defp flash_start(world, self, _other), do: Gml.put(world, self, %{wait: 1})

  defp flash_step(world, self, _other) do
    wait = Gml.var(world, self, :wait) - 1
    world = Gml.put(world, self, %{wait: wait})
    if wait < -1.0e-5, do: World.destroy(world, self), else: world
  end

  defp flash_draw(world, _self, _other) do
    {x, y, width, height} = view(world)
    Draw.rectangle(world, {x - 1, y - 1, x + width + 1, y + height + 1}, @white)
  end

  defp clash_start(world, self, _other), do: Gml.put(world, self, %{z: 0, cleared: 1})

  defp trail_step(world, self, _other) do
    world = World.update(world, self, &%{&1 | image_alpha: &1.image_alpha - 0.15})
    if World.fetch(world, self).image_alpha > 0.5, do: world, else: World.destroy(world, self)
  end

  defp trail_draw(world, self, _other) do
    {hue, world} = Gml.random(world, 255)
    world = World.update(world, self, &%{&1 | image_blend: Colour.hsv(hue, 255, 255)})
    trail = World.fetch(world, self)

    Draw.sprite(world, trail.sprite_index, trail.image_index, {trail.x, trail.y},
      scale: {trail.image_xscale, trail.image_yscale},
      angle: trail.image_angle,
      blend: trail.image_blend,
      alpha: trail.image_alpha,
      mode: :add
    )
  end

  defp view(%World{views: [%{view: rectangle} | _]}), do: rectangle

  defp view(%World{} = world) do
    {width, height} = Enum.at(world.data.rooms, world.room).size
    {0, 0, width, height}
  end
end
