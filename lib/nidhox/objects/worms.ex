defmodule Nidhox.Objects.Worms do
  @moduledoc """
  The mines' worms, as the game's code runs them.

    * `MiniWorm` create: `beat` `choose(10, 40, 80, 100)`, turned `random(360)`, held
      at frame 0 (`image_single`); ten `WormPiece`s made at its place, the `i`th at
      frame `i` (`pieces`); its user event 0; `holdSpeed` 0
    * `MiniWorm` step: a held speed is given back; then, looking 16 pixels ahead at 45°
      to its left, with no `Block` there it turns 2° right; else with no `Block` 16
      pixels ahead at 45° to its right it turns 2° left; else it turns `sin(frame /
      beat + id × 10) × random_range(2, 4)`. It crawls 0.2 a step the way it faces;
      whenever `System.frame` is a multiple of `beat × 5`, `beat` becomes
      `choose(1, 6, 10, 40, 80)`; then its user event 0
    * `MiniWorm` user event 0: each piece more than 2 pixels from the one before it (the
      first from the worm) moves to 2 pixels behind that one, along the line between
      them; the worm's frame steps on one for a piece that moved and back one for a
      piece that did not, and is 0 after every piece but the first
    * `MiniWormDark` create: the worm's create, then every piece takes its sprite
    * `WormPiece` create: frames at 0.1 a step
    * `WormSurface` create: a clear surface the size of the room (`wormSurface`), then
      its step 120 times; step: every `MiniWorm` drawn onto it in black, at its frame and
      angle (made again if it was lost); draw: the surface at the room's corner;
      destroy, room end and game end: the surface freed
  """

  alias Cauldron2D.GameMaker.{Collide, Draw, Instance, Surfaces, World}
  alias Nidhox.Bout.Camera
  alias Nidhox.Gml
  alias Nidhox.Objects.System

  @pieces 10
  @look 16
  @turn 2
  @crawl 0.2
  @gap 2
  @prime_steps 120
  @black {0, 0, 0}

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_MiniWorm_Create_0", &worm_start/3},
      {"gml_Object_MiniWorm_Step_0", &crawl/3},
      {"gml_Object_MiniWorm_Other_10", &follow/3},
      {"gml_Object_MiniWormDark_Create_0", &dark_start/3},
      {"gml_Object_WormPiece_Create_0",
       fn world, self, _other -> World.update(world, self, &%{&1 | image_speed: 0.1}) end},
      {"gml_Object_WormSurface_Create_0", &surface_start/3},
      {"gml_Object_WormSurface_Step_0", &stamp/3},
      {"gml_Object_WormSurface_Draw_0", &surface_draw/3},
      {"gml_Object_WormSurface_Destroy_0", &surface_free/3},
      {"gml_Object_WormSurface_Other_5", &surface_free/3},
      {"gml_Object_WormSurface_Other_3", &surface_free/3}
    ]
  end

  defp worm_start(world, self, _other) do
    {beat, world} = Gml.choose(world, [10, 40, 80, 100])
    {angle, world} = Gml.random(world, 360)
    %Instance{x: x, y: y} = World.fetch(world, self)
    piece = World.object_index(world, "WormPiece")

    world =
      world
      |> Gml.put(self, %{beat: beat})
      |> World.update(self, &%{&1 | image_angle: angle, image_index: 0.0, image_speed: 0.0})

    {world, pieces} =
      Enum.reduce(0..(@pieces - 1), {world, []}, fn index, {world, pieces} ->
        {world, id} = World.create(world, piece, {x, y})
        {World.update(world, id, &%{&1 | image_index: index / 1}), pieces ++ [id]}
      end)

    world
    |> Gml.put(self, %{pieces: pieces})
    |> World.perform(self, :other, 10)
    |> Gml.put(self, %{holdSpeed: 0})
  end

  defp dark_start(world, self, _other) do
    world = World.inherited(world, self, "MiniWormDark", :create, 0)
    %Instance{sprite_index: sprite} = World.fetch(world, self)

    world
    |> Gml.var(self, :pieces, [])
    |> Enum.reduce(world, fn piece, world ->
      World.update(world, piece, &%{&1 | sprite_index: sprite})
    end)
  end

  defp crawl(world, self, _other) do
    world
    |> give_back_speed(self)
    |> steer(self)
    |> then(
      &World.update(&1, self, fn worm ->
        Instance.put_motion(worm, %{direction: worm.image_angle, speed: @crawl})
      end)
    )
    |> new_beat(self)
    |> World.perform(self, :other, 10)
  end

  defp give_back_speed(world, self) do
    held = Gml.var(world, self, :holdSpeed)

    if held > 0,
      do:
        world
        |> World.update(self, &Instance.put_motion(&1, %{speed: held}))
        |> Gml.put(self, %{holdSpeed: 0}),
      else: world
  end

  defp steer(world, self) do
    %Instance{image_angle: angle} = World.fetch(world, self)
    block = World.object_index(world, "Block")

    cond do
      not wall?(world, self, block, angle + 45) -> turn(world, self, -@turn)
      not wall?(world, self, block, angle - 45) -> turn(world, self, @turn)
      true -> wander(world, self)
    end
  end

  defp wall?(world, self, block, direction) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    Collide.meeting?(
      world,
      self,
      {x + Gml.lengthdir_x(@look, direction), y + Gml.lengthdir_y(@look, direction)},
      block
    )
  end

  defp turn(world, self, by),
    do: World.update(world, self, &%{&1 | image_angle: &1.image_angle + by})

  defp wander(world, self) do
    frame = System.get(world, :frame)
    beat = Gml.var(world, self, :beat)
    {swing, world} = Gml.random_range(world, 2, 4)
    turn(world, self, :math.sin(frame / beat + self * 10) * swing)
  end

  defp new_beat(world, self) do
    if Gml.eq?(:math.fmod(System.get(world, :frame), Gml.var(world, self, :beat) * 5), 0) do
      {beat, world} = Gml.choose(world, [1, 6, 10, 40, 80])
      Gml.put(world, self, %{beat: beat})
    else
      world
    end
  end

  defp follow(world, self, _other) do
    pieces = Gml.var(world, self, :pieces, [])

    pieces
    |> Enum.with_index()
    |> Enum.reduce(world, fn {piece, index}, world ->
      leader = if index == 0, do: self, else: Enum.at(pieces, index - 1)
      world |> follow_piece(self, piece, leader) |> settle_frame(self, index)
    end)
  end

  defp follow_piece(world, self, piece, leader) do
    %Instance{x: px, y: py} = World.fetch(world, piece)
    %Instance{x: lx, y: ly} = World.fetch(world, leader)

    if Gml.gt?(:math.sqrt((lx - px) * (lx - px) + (ly - py) * (ly - py)), @gap) do
      direction = Gml.point_direction({px, py}, {lx, ly})

      world
      |> World.update(
        piece,
        &%{
          &1
          | x: lx - Gml.lengthdir_x(@gap, direction),
            y: ly - Gml.lengthdir_y(@gap, direction)
        }
      )
      |> step_frame(self, 1)
    else
      step_frame(world, self, -1)
    end
  end

  defp step_frame(world, self, by) do
    %Instance{image_index: index, sprite_index: sprite} = World.fetch(world, self)
    frames = length(World.sprite(world, sprite).frames)

    World.update(
      world,
      self,
      &%{&1 | image_index: Gml.clamp(index + by, 0, frames) / 1, image_speed: 0.0}
    )
  end

  defp settle_frame(world, _self, 0), do: world

  defp settle_frame(world, self, _index),
    do: World.update(world, self, &%{&1 | image_index: 0.0, image_speed: 0.0})

  defp surface_start(world, self, _other) do
    {world, surface} = new_surface(world)
    world = Gml.put(world, self, %{wormSurface: surface})
    items = worm_items(world)
    Surfaces.draw(world, surface, List.flatten(List.duplicate(items, @prime_steps)))
  end

  defp stamp(world, self, _other) do
    surface = Gml.var(world, self, :wormSurface, -1)

    {world, surface} =
      if Surfaces.exists?(world, surface), do: {world, surface}, else: new_surface(world)

    world
    |> Gml.put(self, %{wormSurface: surface})
    |> Surfaces.draw(surface, worm_items(world))
  end

  defp new_surface(world) do
    {world, surface} = Surfaces.create(world, round(Camera.room_width(world)), room_height(world))
    {Surfaces.clear(world, surface, {255, 255, 255}, 0), surface}
  end

  defp worm_items(world) do
    for worm <- Gml.all(world, "MiniWorm"),
        %Instance{} = instance = World.fetch(world, worm),
        do: %{
          picture: {:sprite, instance.sprite_index, sprite_frame(world, instance)},
          position: {instance.x, instance.y},
          origin: World.sprite(world, instance.sprite_index).origin,
          angle: instance.image_angle,
          blend: @black,
          alpha: 1.0
        }
  end

  defp sprite_frame(world, %Instance{sprite_index: sprite, image_index: index}) do
    count = length(World.sprite(world, sprite).frames)
    Integer.mod(floor(index), count)
  end

  defp surface_draw(world, self, _other) do
    surface = Gml.var(world, self, :wormSurface, -1)

    if Surfaces.exists?(world, surface),
      do: Draw.item(world, Surfaces.item(world, surface, {0, 0})),
      else: world
  end

  defp surface_free(world, self, _other) do
    surface = Gml.var(world, self, :wormSurface, -1)
    if Surfaces.exists?(world, surface), do: Surfaces.free(world, surface), else: world
  end

  defp room_height(world),
    do: world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size) |> elem(1)
end
