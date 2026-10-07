defmodule Nidhox.Objects.Scenery do
  @moduledoc """
  The room dressing that only needs to be set up: the moon shows its shaded picture and
  holds it, the gothic windows hold their first, and birds sit in their standing
  picture, animating slowly.
  """

  alias Cauldron2D.GameMaker.Data
  alias Cauldron2D.GameMaker.World

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Moon_Create_0", &moon/3},
      {"gml_Object_GothicWindowDark_Create_0", &still/3},
      {"gml_Object_GothicWindow_Create_0", &still/3},
      {"gml_Object_Bird_Create_0", &perched/3}
    ]
  end

  defp moon(world, self, _other),
    do: World.update(world, self, &%{&1 | image_speed: 0.0, image_index: 1.0})

  defp still(world, self, _other),
    do: World.update(world, self, &%{&1 | image_speed: 0.0, image_index: 0.0})

  defp perched(world, self, _other) do
    case Data.index(world.data, :sprites, "sprBirdStand") do
      nil -> world
      standing -> World.update(world, self, &%{&1 | sprite_index: standing, image_speed: 0.1})
    end
  end
end
