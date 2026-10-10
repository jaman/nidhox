defmodule Nidhox.Objects.Crowd do
  @moduledoc """
  The crowd in the stands of the end rooms, as the game's code runs it.

    * `CrowdFill` create: its width rounded to a multiple of 16 (`image_xscale`); a
      spectator (`o_crowd`) every 14 pixels, rows from the bottom up and from 0.25 of a
      place across, at `(x + 5 + 14i + random_range(−4, 4), y + 8 + 14j)` while `i <
      sprite_width / 14 − 1`; then, about the spectators' depth `d`, the stands as tiles
      (`tile_add`): `bgStands` (353) filling it every 16 pixels at `d + 1`; from half a
      tile left of it to its right edge, `fgStands` (354) 8 pixels above its bottom at
      `d − 1` and `bgBackStands` (356) 16 above its top at `d + 2`; `bgSideStands` (355)
      down both sides every 8 pixels from 8 above its top at `d + 1`. A `CheerControl` at
      its middle, and it is gone
    * `o_crowd` create: its sprite's origin (`xOffset`, `yOffset`), `state` −1,
      `nextState` 57, `frame` 0 shown still; tinted `make_color_hsv(40, 100,
      random_range(190, 220))` in rooms of `roomCode` 7 and hue 20 elsewhere
    * `o_crowd` end step: a new `nextState` becomes the `state` with `frame` 0 — 57
      sitting (`sManSitToStand` or `sManSitToCheer`), 34 standing up, 6 cheering
      (`sManCheering`). Sitting, it stands up once a fencer comes within 120 pixels
      across of it, coming from its side of the room: in rooms of `roomCode` 4 when
      `Man.x − 120 < x`, in 7 when `Man.x + 120 > x`. Standing up and cheering, `frame`
      runs on 0.3 a step: stood up, it cheers; at the end of a cheer it starts another,
      `choose(sManCheering, sManShouting, sManHopping, sManJammin)`. It shows `frame`
  """

  alias Cauldron2D.GameMaker.{Colour, Instance, World}
  alias Nidhox.Gml
  alias Nidhox.Objects.RoomCodes

  @seat 14
  @tile 16
  @side 8
  @spread 4
  @stands 353
  @front 354
  @sides 355
  @back 356
  @sitting 57
  @standing 34
  @cheering 6
  @sit_sprites [175, 176]
  @cheer_sprite 177
  @cheers [177, 179, 180, 181]
  @rate 0.3
  @notice 120

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_CrowdFill_Create_0", &fill/3},
      {"gml_Object_o_crowd_Create_0", &seat/3},
      {"gml_Object_o_crowd_Step_2", &watch/3}
    ]
  end

  defp fill(world, self, _other) do
    %Instance{sprite_index: sprite} = World.fetch(world, self)
    {sprite_width, _height} = World.sprite(world, sprite).size
    {scaled_width, _scaled_height} = scaled(world, self)
    width = Gml.round(scaled_width / @tile) * @tile
    world = World.update(world, self, &%{&1 | image_xscale: width / sprite_width})
    world = seat_crowd(world, self)
    depth = crowd_depth(world)

    world
    |> lay_stands(self, depth)
    |> cheer(self)
    |> World.destroy(self)
  end

  defp seat_crowd(world, self) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    {width, height} = scaled(world, self)
    crowd = World.object_index(world, "o_crowd")

    rows = (height / @seat - 1) |> Stream.iterate(&(&1 - 1)) |> Enum.take_while(&(&1 > -1))
    places = 0.25 |> Stream.iterate(&(&1 + 1)) |> Enum.take_while(&(&1 < width / @seat - 1))

    for row <- rows, place <- places, reduce: world do
      world ->
        {shift, world} = Gml.random_range(world, -@spread, @spread)
        world |> World.create(crowd, {x + 5 + place * @seat + shift, y + 8 + row * @seat}) |> elem(0)
    end
  end

  defp crowd_depth(world) do
    case Gml.first(world, "o_crowd") do
      nil -> 0
      spectator -> World.fetch(world, spectator).depth
    end
  end

  defp lay_stands(world, self, depth) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    {width, height} = scaled(world, self)

    world =
      for row <- upto(0, height / @tile), column <- upto(0, width / @tile), reduce: world do
        world -> World.add_tile(world, @stands, {0, 0, @tile, @tile}, {x + column * @tile, y + row * @tile}, depth + 1)
      end

    world =
      for column <- through(-0.5, width / @tile), reduce: world do
        world ->
          world
          |> World.add_tile(@front, {0, 0, @tile, 2 * @tile}, {x + column * @tile, y + height - 8}, depth - 1)
          |> World.add_tile(@back, {0, 0, @tile, @tile}, {x + column * @tile, y - @tile}, depth + 2)
      end

    for row <- upto(-1, height / @side), reduce: world do
      world ->
        world
        |> World.add_tile(@sides, {0, 0, @side, @side}, {x - @side, y + row * @side}, depth + 1)
        |> World.add_tile(@sides, {0, 0, @side, @side}, {x + width, y + row * @side}, depth + 1)
    end
  end

  defp upto(from, below), do: from |> Stream.iterate(&(&1 + 1)) |> Enum.take_while(&(&1 < below))
  defp through(from, last), do: from |> Stream.iterate(&(&1 + 1)) |> Enum.take_while(&(&1 <= last))

  defp cheer(world, self) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    {width, height} = scaled(world, self)
    world |> World.create(World.object_index(world, "CheerControl"), {x + width / 2, y + height / 2}) |> elem(0)
  end

  defp scaled(world, self) do
    %Instance{sprite_index: sprite, image_xscale: xscale, image_yscale: yscale} = World.fetch(world, self)
    {width, height} = World.sprite(world, sprite).size
    {width * xscale, height * yscale}
  end

  defp seat(world, self, _other) do
    %Instance{sprite_index: sprite} = World.fetch(world, self)
    {origin_x, origin_y} = World.sprite(world, sprite).origin
    hue = if round(RoomCodes.room_code(world)) == 7, do: 40, else: 20
    {value, world} = Gml.random_range(world, 190, 220)

    world
    |> Gml.put(self, %{xOffset: origin_x, yOffset: origin_y, state: -1, nextState: @sitting, frame: 0})
    |> World.update(self, &%{&1 | image_index: 0.0, image_speed: 0.0, image_blend: Colour.hsv(hue, 100, value)})
  end

  defp watch(world, self, _other) do
    world
    |> take_next_state(self)
    |> act(self, round(Gml.var(world, self, :state)))
    |> show(self)
  end

  defp take_next_state(world, self) do
    next = Gml.var(world, self, :nextState)

    cond do
      not Gml.truthy?(next) -> world
      Gml.eq?(next, Gml.var(world, self, :state)) -> Gml.put(world, self, %{nextState: -1})
      true -> world |> Gml.put(self, %{state: next, nextState: -1, frame: 0}) |> dress(self, round(next))
    end
  end

  defp dress(world, self, @sitting) do
    {sprite, world} = Gml.choose(world, @sit_sprites)
    World.update(world, self, &%{&1 | sprite_index: sprite})
  end

  defp dress(world, self, @cheering), do: World.update(world, self, &%{&1 | sprite_index: @cheer_sprite})
  defp dress(world, _self, _state), do: world

  defp act(world, self, @sitting) do
    case Gml.first(world, "Man") do
      nil -> world
      man -> if noticed?(world, self, World.fetch(world, man).x), do: Gml.put(world, self, %{nextState: @standing}), else: world
    end
  end

  defp act(world, self, @standing) do
    frame = Gml.var(world, self, :frame) + @rate
    world = Gml.put(world, self, %{frame: frame})
    if Gml.gt?(frame, frames(world, self)), do: Gml.put(world, self, %{nextState: @cheering}), else: world
  end

  defp act(world, self, @cheering) do
    frame = Gml.var(world, self, :frame) + @rate
    world = Gml.put(world, self, %{frame: frame})

    if Gml.gt?(frame, frames(world, self) - 1) do
      {sprite, world} = Gml.choose(world, @cheers)
      world |> World.update(self, &%{&1 | sprite_index: sprite}) |> Gml.put(self, %{frame: 0})
    else
      world
    end
  end

  defp act(world, _self, _state), do: world

  defp noticed?(world, self, man_x) do
    %Instance{x: x} = World.fetch(world, self)

    case round(RoomCodes.room_code(world)) do
      4 -> man_x - @notice < x
      7 -> man_x + @notice > x
      _other -> false
    end
  end

  defp show(world, self) do
    frame = Gml.clamp(Gml.var(world, self, :frame), 0, frames(world, self) - 1)
    World.update(world, self, &%{&1 | image_index: frame / 1, image_speed: 0.0})
  end

  defp frames(world, self), do: length(World.sprite(world, World.fetch(world, self).sprite_index).frames)
end
