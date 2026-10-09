defmodule Nidhox.Objects.Scenery do
  @moduledoc """
  Room dressing set up once and then kept moving, as the game's code does it:

    * the moon shows its plain disc at alpha 0.9 (the clouds that cross it are
      `Nidhox.Objects.Wind`'s) and, each end step, is placed `@moon_follow` of the way
      from where the room puts it to the camera's centre:
      `x = xstart + @moon_follow × (cameraCenterX − xstart)`
    * the gothic windows hold their first frame
    * blocks (`Block`, the ground and walls fencers stand on) are not drawn
    * `BgColorPulsate` sets the room's colour layer (`Compatibility_Colour`) each step to
      `make_color_hsv(sin(frame / 40) × 10 + 10, 200, 100)`
  """

  alias Cauldron2D.GameMaker.{Colour, World}
  alias Nidhox.Parallax

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
      {"gml_Object_Block_Draw_0", &unseen/3}
    ]
  end

  defp moon(world, self, _other),
    do:
      World.update(
        world,
        self,
        &%{&1 | image_speed: 0.0, image_index: 0.0, image_alpha: @moon_alpha}
      )

  defp moon_follow(world, self, _other) do
    centre = Parallax.camera_center_x(world)
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
