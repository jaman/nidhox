defmodule Nidhox.Objects.Glass do
  @moduledoc """
  Windows that shatter, as the game's code runs them.

    * `Window` create: `shattedDirection` 0
    * `Window` touching a fencer (`Man`) or a thrown sword (`FlyingWeapon`):
      `shattedDirection` the direction away from it (`point_direction` from the window to
      it, + 180°), and the window is gone
    * `Window` destroy: the shatter (`sndGlassShatter`) at it; a `GlassFragment` every 3 pixels up
      its height from its place, each sent at `shattedDirection + random_range(−30, 30)`
      at `random_range(2, 4)`
    * `GlassFragment` create: gone in 360 steps (alarm 0), at a still frame
      `irandom(image_number)`, `spin` `random_range(−10, 10)`, gravity 0.3, friction 0.03
    * `GlassFragment` touching a `Block`: it bounces off everything
      (`action_bounce(false, true)`, `Cauldron2D.GameMaker.Collide.bounce/4`); faster than
      2 it clinks (`choose(sndGlassBounce1, sndGlassBounce2, sndGlassBounce3)`); its speed falls to 0.2 of itself
  """

  alias Cauldron2D.GameMaker.{Collide, Instance, World}
  alias Nidhox.Bout.Sound
  alias Nidhox.Gml

  @shatter "sndGlassShatter"
  @clinks ["sndGlassBounce1", "sndGlassBounce2", "sndGlassBounce3"]
  @every 3
  @spread 30
  @life 360

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Window_Create_0",
       fn world, self, _other -> Gml.put(world, self, %{shattedDirection: 0}) end},
      {"gml_Object_Window_Collision_Man", &struck/3},
      {"gml_Object_Window_Collision_FlyingWeapon", &struck/3},
      {"gml_Object_Window_Destroy_0", &shatter/3},
      {"gml_Object_GlassFragment_Create_0", &fragment/3},
      {"gml_Object_GlassFragment_Alarm_0",
       fn world, self, _other -> World.destroy(world, self) end},
      {"gml_Object_GlassFragment_Collision_Block", &clink/3}
    ]
  end

  defp struck(world, self, other) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    %Instance{x: other_x, y: other_y} = World.fetch(world, other)

    world
    |> Gml.put(self, %{shattedDirection: Gml.point_direction({x, y}, {other_x, other_y}) + 180})
    |> World.destroy(self)
  end

  defp shatter(world, self, _other) do
    %Instance{x: x, y: y, sprite_index: sprite, image_yscale: yscale} = World.fetch(world, self)
    {_width, height} = World.sprite(world, sprite).size
    direction = Gml.var(world, self, :shattedDirection)
    fragment = World.object_index(world, "GlassFragment")
    world = Sound.play_named(world, @shatter, {x, y})

    0
    |> Stream.iterate(&(&1 + @every))
    |> Enum.take_while(&(&1 < height * yscale))
    |> Enum.reduce(world, fn up, world ->
      {world, piece} = World.create(world, fragment, {x, y - up})
      {turn, world} = Gml.random_range(world, -@spread, @spread)
      {speed, world} = Gml.random_range(world, 2, 4)

      World.update(
        world,
        piece,
        &Instance.put_motion(&1, %{direction: direction + turn, speed: speed})
      )
    end)
  end

  defp fragment(world, self, _other) do
    world = World.update(world, self, &Instance.put_alarm(&1, 0, @life))
    %Instance{sprite_index: sprite} = World.fetch(world, self)
    {frame, world} = Gml.irandom(world, length(World.sprite(world, sprite).frames))
    {spin, world} = Gml.random_range(world, -10, 10)

    world
    |> World.update(
      self,
      &%{&1 | image_index: frame / 1, image_speed: 0.0, gravity: 0.3, friction: 0.03}
    )
    |> Gml.put(self, %{spin: spin})
  end

  defp clink(world, self, _other) do
    world = Collide.bounce(world, self, false, :all)
    %Instance{x: x, y: y, speed: speed} = World.fetch(world, self)

    world =
      if speed > 2 do
        {sound, world} = Gml.choose(world, @clinks)
        Sound.play_named(world, sound, {x, y})
      else
        world
      end

    World.update(world, self, &Instance.put_motion(&1, %{speed: &1.speed * 0.2}))
  end
end
