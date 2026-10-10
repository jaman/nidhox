defmodule Nidhox.Objects.Rocks do
  @moduledoc """
  The castle's crumbling stone (`FallingRock`), as the game's code runs it.

    * create: its alarm in `random(3600)` steps; held at frame `irandom(image_number −
      1)` (`image_single`)
    * alarm 0: it falls (gravity 0.3)
    * leaving the room: gone
  """

  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Gml

  @wait 3600
  @gravity 0.3

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_FallingRock_Create_0", &hang/3},
      {"gml_Object_FallingRock_Alarm_0", fn world, self, _other -> World.update(world, self, &%{&1 | gravity: @gravity}) end},
      {"gml_Object_FallingRock_Other_0", fn world, self, _other -> World.destroy(world, self) end}
    ]
  end

  defp hang(world, self, _other) do
    {wait, world} = Gml.random(world, @wait)
    world = World.update(world, self, &Instance.put_alarm(&1, 0, trunc(wait)))
    %Instance{sprite_index: sprite} = World.fetch(world, self)
    {frame, world} = Gml.irandom(world, length(World.sprite(world, sprite).frames) - 1)
    World.update(world, self, &%{&1 | image_index: frame / 1, image_speed: 0.0})
  end
end
