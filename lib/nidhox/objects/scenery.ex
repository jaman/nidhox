defmodule Nidhox.Objects.Scenery do
  @moduledoc """
  Room dressing set up once and then kept moving, as the game's code does it:

    * the moon shows its plain disc at alpha 0.9 (the clouds that cross it are
      `Nidhox.Objects.Wind`'s) and, each end step, is placed `@moon_follow` of the way
      from where the room puts it to the camera's centre:
      `x = xstart + @moon_follow × (cameraCenterX − xstart)`
    * the gothic windows hold their first frame
    * blocks (`Block`, the ground and walls fencers stand on) are not drawn
    * an `Empty` (a place other code moves a sound with) starts at `z` 0
    * `BgColorPulsate` sets the room's colour layer (`Compatibility_Colour`) each step to
      `make_color_hsv(sin(frame / 40) × 10 + 10, 200, 100)`
    * `BackgroundParallaxReference` (a parallax object, `backgroundIndex` from its
      creation code, −1 without): each step its background is at its x
      (`__background_set(3, backgroundIndex, x)`, `Nidhox.Backgrounds`)
    * `BGFolliageWarper`: remembers background 0's x (`xStart`); each step background 0
      is `1 + 0.1 × sin(frame / 30) / 3.14` tall and background 1 `1 + 0.1 ×
      sin(frame / 54) / 3.14`
  """

  alias Cauldron2D.GameMaker.{Colour, World}
  alias Nidhox.{Backgrounds, Gml}
  alias Nidhox.Bout.Camera
  alias Nidhox.Objects.System

  @moon_follow 0.83
  @moon_alpha 0.9
  @colour_layer "Compatibility_Colour"

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Moon_Create_0", &moon/3},
      {"gml_Object_Moon_Step_2", &moon_follow/3},
      {"gml_Object_GothicWindowDark_Create_0", &still/3},
      {"gml_Object_GothicWindow_Create_0", &still/3},
      {"gml_Object_BgColorPulsate_Step_0", &pulse/3},
      {"gml_Object_Block_Draw_0", &unseen/3},
      {"gml_Object_Empty_Create_0", fn world, self, _other -> Gml.put(world, self, %{z: 0}) end},
      {"gml_Object_BackgroundParallaxReference_Create_0", &reference/3},
      {"gml_Object_BackgroundParallaxReference_Step_0", &follow_reference/3},
      {"gml_Object_BGFolliageWarper_Create_0",
       fn world, self, _other -> Gml.put(world, self, %{xStart: Backgrounds.get(world, 3, 0)}) end},
      {"gml_Object_BGFolliageWarper_Step_0", &warp/3}
    ]
  end

  defp reference(world, self, _other) do
    world
    |> World.inherited(self, "BackgroundParallaxReference", :create, 0)
    |> Gml.put(self, %{backgroundIndex: -1, xStart: World.fetch(world, self).x})
  end

  defp follow_reference(world, self, _other) do
    index = Gml.var(world, self, :backgroundIndex, -1)

    if index >= 0,
      do: Backgrounds.set(world, 3, round(index), World.fetch(world, self).x),
      else: world
  end

  defp warp(world, _self, _other) do
    frame = System.get(world, :frame)

    world
    |> Backgrounds.set(10, 0, 1 + 0.1 * :math.sin(frame / 30) / 3.14)
    |> Backgrounds.set(10, 1, 1 + 0.1 * :math.sin(frame / 54) / 3.14)
  end

  defp moon(world, self, _other),
    do:
      World.update(
        world,
        self,
        &%{&1 | image_speed: 0.0, image_index: 0.0, image_alpha: @moon_alpha}
      )

  defp moon_follow(world, self, _other) do
    centre = Camera.center_x(world)
    World.update(world, self, &%{&1 | x: &1.xstart + @moon_follow * (centre - &1.xstart)})
  end

  defp still(world, self, _other),
    do: World.update(world, self, &%{&1 | image_speed: 0.0, image_index: 0.0})

  defp unseen(world, _self, _other), do: world

  defp pulse(world, _self, _other) do
    {red, green, blue} = Colour.hsv(:math.sin(world.steps / 40) * 10 + 10, 200, 100)
    World.put_layer(world, @colour_layer, %{background: %{colour: {red, green, blue, 255}}})
  end
end
