defmodule Nidhox.Objects.DefensiveBlock do
  @moduledoc """
  The clouds' `DefensiveBlock`, as the game's code runs it: a wall of cloud that rises
  in front of the side that is behind, while the camera is away from it.

    * create: off (`on` 0), no `block`, `ledgeLeft` or `ledgeRight`; user event 2 runs
      at once and again on alarm 2, two steps on
    * user event 2: every `RespawnPoint` its mask covers is taken (`spawns`), the last
      one's height kept as `BLOCK_Y`, and each set at its bottom
      (`y + sprite_get_height(mask_index)`)
    * step: the side it defends is player 2 in rooms of `roomCode` 5 to 7, player 1 in
      rooms of `roomCode` 2 to 4, and otherwise player 1 left of the room's middle
      (`cameraCenterX() < room_width / 2`) and player 2 right of it. Off, it turns on
      (user event 0) when the `Match`'s leading player is not that side and it is more
      than 20 pixels off camera (`objectOffCameraBuffer`); on, it turns off (user
      event 1) when the leading player is that side and it is off camera. It is shown
      while on
    * user event 0: a `Block` the size of its mask, a `Ledge` at its left and its
      right edge; its respawn points moved to its top; every `PickupContainer` at its
      place replaced by a `DroppedWeapon` 16 pixels above its top; a `CloudPoof` every
      16 pixels across and every 16 down from 8, each moved by `random_range(−2, 2)`
      both ways (`clouds`)
    * user event 1: the block, ledges and clouds gone, its respawn points back at
      `BLOCK_Y`
    * alarm 0: again in 5 steps, at a random frame (`image_single`)
  """

  alias Cauldron2D.GameMaker.{Collide, Instance, World}
  alias Nidhox.Bout.Camera
  alias Nidhox.Gml
  alias Nidhox.Objects.RoomCodes

  @buffer 20
  @recheck 2
  @frame_again 5
  @spacing 16
  @first_row 8
  @spread 2
  @weapon_lift 16
  @point_lift 100

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_DefensiveBlock_Create_0", &start/3},
      {"gml_Object_DefensiveBlock_Alarm_2",
       fn world, self, _other -> World.perform(world, self, :other, 12) end},
      {"gml_Object_DefensiveBlock_Alarm_0", &random_frame/3},
      {"gml_Object_DefensiveBlock_Step_0", &step/3},
      {"gml_Object_DefensiveBlock_Other_12", &take_points/3},
      {"gml_Object_DefensiveBlock_Other_10", &rise/3},
      {"gml_Object_DefensiveBlock_Other_11", &fall/3}
    ]
  end

  defp start(world, self, _other) do
    world
    |> Gml.put(self, %{on: 0, block: -4, ledgeLeft: -4, ledgeRight: -4, spawns: [], clouds: []})
    |> World.perform(self, :other, 12)
    |> World.update(self, &Instance.put_alarm(&1, 2, @recheck))
  end

  defp random_frame(world, self, _other) do
    world = World.update(world, self, &Instance.put_alarm(&1, 0, @frame_again))
    {frame, world} = Gml.irandom(world, frames(world, self))
    World.update(world, self, &%{&1 | image_index: frame / 1, image_speed: 0.0})
  end

  defp step(world, self, _other) do
    world = switch(world, self, Gml.first(world, "Match"))
    World.update(world, self, &%{&1 | visible: Gml.truthy?(Gml.var(world, self, :on))})
  end

  defp switch(world, _self, nil), do: world

  defp switch(world, self, match) do
    leading = Gml.eq?(Gml.var(world, match, :leadingPlayerIndex), defended(world))
    away = off_camera?(world, self)

    case {Gml.truthy?(Gml.var(world, self, :on)), leading, away} do
      {false, false, true} -> World.perform(world, self, :other, 10)
      {true, true, true} -> World.perform(world, self, :other, 11)
      _otherwise -> world
    end
  end

  defp defended(world) do
    case RoomCodes.room_code(world) do
      code when code in [5, 6, 7] -> 2
      code when code in [2, 3, 4] -> 1
      _other -> if Camera.center_x(world) < Camera.room_width(world) / 2, do: 1, else: 2
    end
  end

  defp off_camera?(world, self) do
    %Instance{x: x, y: y} = instance = World.fetch(world, self)
    {width, height} = scaled(world, instance)

    x + width < Camera.left(world) - @buffer or x > Camera.right(world) + @buffer or
      y + height < Camera.top(world) - @buffer or y > Camera.bottom(world) + @buffer
  end

  defp take_points(world, self, _other) do
    world
    |> take_next_point(self, World.object_index(world, "RespawnPoint"))
    |> set_points(self, World.fetch(world, self).y + mask_height(world, self))
  end

  defp take_next_point(world, self, point) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    case Collide.place(world, self, {x, y}, point) do
      nil ->
        world

      found ->
        world
        |> Gml.put(self, %{
          BLOCK_Y: World.fetch(world, found).y,
          spawns: Gml.var(world, self, :spawns, []) ++ [found]
        })
        |> World.update(found, &%{&1 | y: y - @point_lift})
        |> take_next_point(self, point)
    end
  end

  defp set_points(world, self, height) do
    world
    |> Gml.var(self, :spawns, [])
    |> Enum.reduce(world, fn point, world -> World.update(world, point, &%{&1 | y: height}) end)
  end

  defp rise(world, self, _other) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    {width, height} = mask_size(world, self)
    ledge = World.object_index(world, "Ledge")
    {world, block} = World.create(world, World.object_index(world, "Block"), {x, y})
    {block_width, block_height} = sprite_size(world, World.fetch(world, block).sprite_index)
    {world, left} = World.create(world, ledge, {x, y})
    {world, right} = World.create(world, ledge, {x + width, y})

    world
    |> World.update(
      block,
      &%{&1 | image_xscale: width / block_width, image_yscale: height / block_height}
    )
    |> Gml.put(self, %{block: block, ledgeLeft: left, ledgeRight: right})
    |> set_points(self, y)
    |> drop_pickups(self, World.object_index(world, "PickupContainer"))
    |> lay_clouds(self, {width, height})
    |> Gml.put(self, %{on: 1})
  end

  defp drop_pickups(world, self, pickup) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    case Collide.place(world, self, {x, y}, pickup) do
      nil ->
        world

      found ->
        world
        |> World.create(
          World.object_index(world, "DroppedWeapon"),
          {World.fetch(world, found).x, y - @weapon_lift}
        )
        |> elem(0)
        |> World.destroy(found)
        |> drop_pickups(self, pickup)
    end
  end

  defp lay_clouds(world, self, {width, height}) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    poof = World.object_index(world, "CloudPoof")

    places =
      for across <- steps(0, width), down <- steps(@first_row, height), do: {across, down}

    Enum.reduce(places, world, fn {across, down}, world ->
      {shift_x, world} = Gml.random_range(world, -@spread, @spread)
      {shift_y, world} = Gml.random_range(world, -@spread, @spread)
      {world, cloud} = World.create(world, poof, {x + across + shift_x, y + down + shift_y})
      Gml.put(world, self, %{clouds: Gml.var(world, self, :clouds, []) ++ [cloud]})
    end)
  end

  defp fall(world, self, _other) do
    world =
      [:block, :ledgeLeft, :ledgeRight]
      |> Enum.map(&Gml.var(world, self, &1))
      |> Enum.reduce(world, &World.destroy(&2, &1))
      |> Gml.put(self, %{block: -4, ledgeLeft: -4, ledgeRight: -4})
      |> set_points(self, Gml.var(world, self, :BLOCK_Y))

    world
    |> Gml.var(self, :clouds, [])
    |> Enum.reduce(world, &World.destroy(&2, &1))
    |> Gml.put(self, %{clouds: [], on: 0})
  end

  defp steps(from, below),
    do: from |> Stream.iterate(&(&1 + @spacing)) |> Enum.take_while(&(&1 < below))

  defp mask_height(world, self), do: world |> mask_size(self) |> elem(1)

  defp mask_size(world, self) do
    %Instance{mask_index: mask, sprite_index: sprite} = World.fetch(world, self)
    sprite_size(world, if(mask >= 0, do: mask, else: sprite))
  end

  defp scaled(world, %Instance{sprite_index: sprite, image_xscale: xscale, image_yscale: yscale}) do
    {width, height} = sprite_size(world, sprite)
    {width * xscale, height * yscale}
  end

  defp sprite_size(world, sprite) do
    case World.sprite(world, sprite) do
      nil -> {0, 0}
      definition -> definition.size
    end
  end

  defp frames(world, self) do
    case World.sprite(world, World.fetch(world, self).sprite_index) do
      nil -> 1
      definition -> length(definition.frames)
    end
  end
end
