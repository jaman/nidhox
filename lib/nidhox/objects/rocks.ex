defmodule Nidhox.Objects.Rocks do
  @moduledoc """
  The castle's crumbling stone (`FallingRock`, `sFallingRock`): the pebbles under its
  bridges hang still, each on a frame of its own, until their alarm — between
  `@wait_least` and `@wait_least + @wait_span` steps after the room starts, drawn from
  the instance's id — lets them fall under `@gravity`, tumbling through their frames
  at `@tumble` a step, and are gone once they leave the room.
  """

  alias Cauldron2D.GameMaker.{Instance, World}

  @wait_least 60
  @wait_span 3600
  @gravity 0.15
  @tumble 0.25

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_FallingRock_Create_0", &hang/3},
      {"gml_Object_FallingRock_Alarm_0", &fall/3},
      {"gml_Object_FallingRock_Other_0", &gone/3}
    ]
  end

  defp hang(world, self, _other) do
    frames = length(World.sprite(world, World.fetch(world, self).sprite_index).frames)
    wait = @wait_least + :erlang.phash2({self, :wait}, @wait_span)

    World.update(world, self, fn rock ->
      %{rock | image_speed: 0.0, image_index: :erlang.phash2(self, frames) / 1}
      |> Instance.put_alarm(0, wait)
    end)
  end

  defp fall(world, self, _other),
    do: World.update(world, self, &%{&1 | gravity: @gravity, image_speed: @tumble})

  defp gone(world, self, _other), do: World.destroy(world, self)
end
