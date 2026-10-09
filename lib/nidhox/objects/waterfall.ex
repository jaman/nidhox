defmodule Nidhox.Objects.Waterfall do
  @moduledoc """
  The wilds' waterfall spray (`ParticleWaterfall`): each emitter is hidden and, every
  `@every` steps, throws a particle of its own sprite (`sParticleWaterfall`) from a
  point up to `@spread` pixels either side of it, falling at `@fall` pixels a step and
  speeding up by `@gravity`, playing its frames and fading out over `@life` steps, at
  the emitter's depth. Where each falls from and its first frame are drawn from the
  emitter's id and the step.
  """

  alias Cauldron2D.GameMaker.Instance
  alias Cauldron2D.GameMaker.Particles
  alias Cauldron2D.GameMaker.World

  @every 2
  @spread 16
  @fall 1.0
  @gravity 0.04
  @life 48

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_ParticleWaterfall_Create_0", &hide/3},
      {"gml_Object_ParticleWaterfall_Step_0", &spray/3}
    ]
  end

  defp hide(world, self, _other), do: World.update(world, self, &%{&1 | visible: false})

  defp spray(world, self, _other) do
    if rem(world.steps + self, @every) == 0 do
      %Instance{x: x, y: y, sprite_index: sprite, depth: depth} = World.fetch(world, self)
      frames = length(World.sprite(world, sprite).frames)
      offset = :erlang.phash2({self, world.steps}, 2 * @spread + 1) - @spread

      Particles.create(world, %{
        sprite: sprite,
        position: {x + offset, y},
        velocity: {0.0, @fall},
        gravity: {0.0, @gravity},
        life: @life,
        frame: :erlang.phash2({self, world.steps, :frame}, frames),
        frame_speed: frames / @life,
        alpha: {1.0, 0.0},
        depth: depth
      })
    else
      world
    end
  end
end
