defmodule Nidhox.Objects.Clouds do
  @moduledoc """
  The sky's cloud puffs. A `CloudPoof` draws itself as its `sCloudPoof` frame, at its
  scale, angle, blend and alpha. A `FakeCloudPoof` — placed in the copy as a red stand-in
  — becomes an `sCloudPoof` puff when it is created. Each puff holds one of the
  sprite's frames, chosen from its instance id.
  """

  alias Cauldron2D.GameMaker.Draw
  alias Cauldron2D.GameMaker.Instance
  alias Cauldron2D.GameMaker.World
  alias Nidhox.Assets

  @puff "sCloudPoof"

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_CloudPoof_Create_0", &settle/3},
      {"gml_Object_CloudPoof_Draw_0", &draw/3},
      {"gml_Object_FakeCloudPoof_Create_0", &settle/3}
    ]
  end

  defp settle(world, self, _other) do
    {puff, sprite} = Assets.sprite!(@puff)
    frame = :erlang.phash2(self, length(sprite.frames))

    World.update(
      world,
      self,
      &%{&1 | sprite_index: puff, image_index: frame / 1, image_speed: 0.0}
    )
  end

  defp draw(world, self, _other) do
    %Instance{} = puff = World.fetch(world, self)

    Draw.sprite(world, puff.sprite_index, puff.image_index, {puff.x, puff.y},
      scale: {puff.image_xscale, puff.image_yscale},
      angle: puff.image_angle,
      blend: puff.image_blend,
      alpha: puff.image_alpha
    )
  end
end
