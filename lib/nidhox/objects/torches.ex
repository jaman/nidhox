defmodule Nidhox.Objects.Torches do
  @moduledoc """
  The candles and torches, as the game's code runs them, their flames from the torch
  particles of the `Particles` object (`torchSystem`, `torchEmitter`, `torchParticle`).
  Each step, within 170 pixels across of the camera's centre, each flame sets the
  emitter on an ellipse 2 × 2 pixels about it and, on a `prob(15)`, bursts one
  particle there.

    * `Torch` (the tall candle): flames at `(x, y − 24)`, `(x − 6, y − 21)` and
      `(x + 6, y − 20)`
    * `WallTorch`: one flame at its place
    * `TorchDark`: a `Torch` blended `{64, 64, 64}`
    * `BallLight`, a lamp on a chain from the room's top: create, the parallax object's
      create, shown at frame 0, its alarm in 3 steps; alarm 0, again in
      `irandom_range(3, 4)` steps, at frame `irandom(image_number)`; step, it swings on
      a chain `ystart` long, at `270 + sin(frame / 100 + xstart) × 2` degrees from
      `(xstart, 0)`, and on a `prob(15)` bursts one flame particle about itself
      (`flameAt`); draw, within 180 pixels across of the camera's centre, its chain of
      `sMiniChain` up to the room's top (`Nidhox.Chain`), then itself
  """

  alias Cauldron2D.GameMaker.{Draw, Instance, PartSystems, World}
  alias Nidhox.Bout.Camera
  alias Nidhox.{Chain, Gml}
  alias Nidhox.Objects.System

  @reach 170
  @flame_size 1
  @flame_chance 15
  @candle_flames [{0, -24}, {-6, -21}, {6, -20}]
  @wall_flames [{0, 0}]
  @dark {64, 64, 64}
  @first_frame 3
  @lamp_reach 180

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Torch_Step_0", fn world, self, _other -> burn(world, self, @candle_flames) end},
      {"gml_Object_WallTorch_Step_0", fn world, self, _other -> burn(world, self, @wall_flames) end},
      {"gml_Object_TorchDark_Create_0", &dark/3},
      {"gml_Object_BallLight_Create_0", &lamp/3},
      {"gml_Object_BallLight_Alarm_0", &lamp_frame/3},
      {"gml_Object_BallLight_Step_0", &swing/3},
      {"gml_Object_BallLight_Draw_0", &lamp_draw/3}
    ]
  end

  defp lamp(world, self, _other) do
    world
    |> World.inherited(self, "BallLight", :create, 0)
    |> World.update(self, &(%{&1 | image_index: 0.0, image_speed: 0.0} |> Instance.put_alarm(0, @first_frame)))
  end

  defp lamp_frame(world, self, _other) do
    {again, world} = Gml.irandom_range(world, 3, 4)
    world = World.update(world, self, &Instance.put_alarm(&1, 0, again))
    %Instance{sprite_index: sprite} = World.fetch(world, self)
    {frame, world} = Gml.irandom(world, length(World.sprite(world, sprite).frames))
    World.update(world, self, &%{&1 | image_index: frame / 1, image_speed: 0.0})
  end

  defp swing(world, self, _other) do
    %Instance{xstart: xstart, ystart: ystart} = World.fetch(world, self)
    angle = 270 + :math.sin(System.get(world, :frame) / 100 + xstart) * 2
    x = xstart + Gml.lengthdir_x(ystart, angle)
    y = Gml.lengthdir_y(ystart, angle) + 0.0
    world = World.update(world, self, &%{&1 | x: x, y: y})
    {lit, world} = Gml.prob(world, @flame_chance)
    if lit, do: world |> Gml.all("Particles") |> Enum.reduce(world, &flare(&2, &1, {x, y})), else: world
  end

  defp flare(world, particles, {x, y}) do
    %{torchSystem: system, torchEmitter: emitter, torchParticle: particle} = World.fetch(world, particles).vars
    region = {x - @flame_size, x + @flame_size, y - @flame_size, y + @flame_size}

    world
    |> PartSystems.emitter_region(system, emitter, region, :ellipse, :linear)
    |> PartSystems.emitter_burst(system, emitter, particle, 1)
  end

  defp lamp_draw(world, self, _other) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    world = if abs(x - Camera.center_x(world)) < @lamp_reach, do: Chain.draw(world, {x, y}, {x, 0}, true), else: world
    Draw.self(world, self)
  end

  defp dark(world, self, _other) do
    world
    |> World.inherited(self, "TorchDark", :create, 0)
    |> World.update(self, &%{&1 | image_blend: @dark})
  end

  defp burn(world, self, flames) do
    %Instance{x: x} = World.fetch(world, self)

    if abs(x - Camera.center_x(world)) < @reach,
      do: world |> Gml.all("Particles") |> Enum.reduce(world, &light(&2, &1, self, flames)),
      else: world
  end

  defp light(world, particles, self, flames) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    Enum.reduce(flames, world, fn {dx, dy}, world ->
      %{torchSystem: system, torchEmitter: emitter, torchParticle: particle} = World.fetch(world, particles).vars
      region = {x + dx - @flame_size, x + dx + @flame_size, y + dy - @flame_size, y + dy + @flame_size}
      world = PartSystems.emitter_region(world, system, emitter, region, :ellipse, :linear)
      {lit, world} = Gml.prob(world, @flame_chance)
      if lit, do: PartSystems.emitter_burst(world, system, emitter, particle, 1), else: world
    end)
  end
end
