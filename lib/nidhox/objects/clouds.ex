defmodule Nidhox.Objects.Clouds do
  @moduledoc """
  The sky's clouds, as the game's code runs them.

    * `CloudBlockArea` lays a `NewCloudBlock` every `sFancyCloudPlat` width
      along its own width and is gone
    * `NewCloudBlock`, a cloud a fencer can stand on: its `frame`
      runs on 0.3 a step while a fencer stands on it (`touched`, set by the fencer) up to
      its last frame, and back 0.075 a step otherwise. Each match frame (user event 2)
      then user event 0: worn all the way through it loses its `PassThroughBlock`
      (`block`); otherwise it has one at its place, 16 pixels wide and
      `100 / sprite_get_height(block.sprite_height)` tall in scale. It shows `frame`;
      `touched` is cleared. It draws its sprite at its frame and blend, `|sin(x + y +
      frame / 30)| × 0.1 + 1` wide and `|cos(x + y + frame / 50)| × 0.1 + 1` tall,
      moved back by half of what that adds to its size, so it swells about its middle
    * `DarkCloudPoofArea` lays a `CloudPoof` every 16 pixels along its width, at
      `(x + 16i + 2 sin(i / 10), y + sprite_height + 8 + 2 cos(i / 5))`
    * `CloudPoof`, a puff: its starting scale (`startXScale`, `startYScale`) its scaled
      sprite over its sprite, `randomStart` `random(1000)`, `frame` `irandom` of its
      frames, `touchTimer` its place in sprite sizes rounded, modulo 7. Each match frame, within
      200 pixels of the camera's centre across: it breathes (`image_xscale` its start
      + `sin(randomStart + frame / 30) × 0.1`, `image_yscale` the same with `cos`); on
      every fourth frame (with `touchTimer`) it is `touched` when a moving fencer is
      within 22 pixels of its place or of 20 above it. Touched, a `sCloudPoof` turns to
      `sCloudEvaporate` at frame 0 and an evaporating one runs on a frame a step;
      untouched, an evaporating one comes back a quarter frame a step and at frame 0
      is a `sCloudPoof` again at a random frame, which drifts on 0.1 a step. It shows
      `frame`, dark (`{28, 28, 28}`) in level 25
    * `FakeCloudPoof`: a `sCloudPoof` at a random frame, its frames running at 0.1 a step;
      each match frame within 200 pixels of the camera's centre across it breathes as a
      `CloudPoof` does
  """

  alias Cauldron2D.GameMaker.{Data, Draw, Instance, World}
  alias Nidhox.Bout.Camera
  alias Nidhox.Gml
  alias Nidhox.Objects.System

  @poof "sCloudPoof"
  @evaporate "sCloudEvaporate"
  @plat "sFancyCloudPlat"
  @wear 0.3
  @mend 0.25
  @reach 200
  @touch 22
  @dark_level 25
  @dark {28, 28, 28}
  @spacing 16
  @touch_cycle 7

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_CloudBlockArea_Create_0", &lay_blocks/3},
      {"gml_Object_NewCloudBlock_Create_0",
       fn world, self, _other -> Gml.put(world, self, %{frame: 0, block: -4, touched: 0}) end},
      {"gml_Object_NewCloudBlock_Other_12", &wear/3},
      {"gml_Object_NewCloudBlock_Other_10", &solid/3},
      {"gml_Object_NewCloudBlock_Draw_0", &draw_block/3},
      {"gml_Object_DarkCloudPoofArea_Create_0", &lay_poofs/3},
      {"gml_Object_CloudPoof_Create_0", &poof/3},
      {"gml_Object_CloudPoof_Other_12", &breathe/3},
      {"gml_Object_CloudPoof_Draw_0", fn world, self, _other -> Draw.self(world, self) end},
      {"gml_Object_FakeCloudPoof_Other_12", &fake_breathe/3},
      {"gml_Object_FakeCloudPoof_Create_0", &fake/3},
      {"gml_Object_FakeCloudPoof_Step_0",
       fn world, self, _other -> World.update(world, self, &%{&1 | image_speed: 0.1}) end}
    ]
  end

  defp draw_block(world, self, _other) do
    %Instance{x: x, y: y, sprite_index: sprite, image_index: image, image_blend: blend} =
      World.fetch(world, self)

    frame = System.get(world, :frame)
    wide = abs(:math.sin(x + y + frame / 30)) * 0.1 + 1
    tall = abs(:math.cos(x + y + frame / 50)) * 0.1 + 1
    {width, height} = Enum.at(world.data.sprites, sprite).size

    Draw.sprite(
      world,
      sprite,
      image,
      {x - (width * wide - width) / 2, y - (height * tall - height) / 2},
      scale: {wide, tall},
      blend: blend
    )
  end

  defp lay_blocks(world, self, _other) do
    %Instance{x: x, y: y} = instance = World.fetch(world, self)
    width = scaled(world, instance) |> elem(0)
    step = world |> sprite_named(@plat) |> then(&sprite_size(world, &1)) |> elem(0)
    block = World.object_index(world, "NewCloudBlock")

    0
    |> Stream.iterate(&(&1 + step))
    |> Enum.take_while(&(&1 < width))
    |> Enum.reduce(world, &(World.create(&2, block, {x + &1, y}) |> elem(0)))
    |> World.destroy(self)
  end

  defp wear(world, self, _other) do
    frame = Gml.var(world, self, :frame)
    last = frames(world, self) - 1

    frame =
      if Gml.truthy?(Gml.var(world, self, :touched)),
        do: min(frame + @wear, last),
        else: max(frame - @wear * @mend, 0)

    world |> Gml.put(self, %{frame: frame}) |> World.perform(self, :other, 10)
  end

  defp solid(world, self, _other) do
    frame = Gml.var(world, self, :frame)
    block = Gml.var(world, self, :block, -4)

    world =
      if Gml.eq?(frame, frames(world, self) - 1),
        do: worn_through(world, self, block),
        else: whole(world, self, block)

    world
    |> World.update(self, &%{&1 | image_index: frame / 1, image_speed: 0.0})
    |> Gml.put(self, %{touched: 0})
  end

  defp worn_through(world, _self, -4), do: world

  defp worn_through(world, self, block),
    do: world |> World.destroy(block) |> Gml.put(self, %{block: -4})

  defp whole(world, self, -4) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    {world, block} = World.create(world, World.object_index(world, "PassThroughBlock"), {x, y})
    %Instance{sprite_index: sprite} = body = World.fetch(world, block)
    {width, _height} = sprite_size(world, sprite)
    tall = sprite_size(world, round(scaled(world, body) |> elem(1))) |> elem(1)

    world
    |> World.update(
      block,
      &%{
        &1
        | image_xscale: 16 / width,
          image_yscale: if(tall > 0, do: 100 / tall, else: &1.image_yscale)
      }
    )
    |> Gml.put(self, %{block: block})
  end

  defp whole(world, _self, _block), do: world

  defp lay_poofs(world, self, _other) do
    %Instance{x: x, y: y} = instance = World.fetch(world, self)
    {width, height} = scaled(world, instance)
    poof = World.object_index(world, "CloudPoof")

    0
    |> Stream.iterate(&(&1 + 1))
    |> Enum.take_while(&(&1 < width / @spacing))
    |> Enum.reduce(world, fn i, world ->
      across = x + i * @spacing + :math.sin(i / 10) * 2
      down = y + height + 8 + :math.cos(i / 5) * 2
      world |> World.create(poof, {across, down}) |> elem(0)
    end)
  end

  defp poof(world, self, _other) do
    %Instance{x: x, y: y, sprite_index: sprite} = instance = World.fetch(world, self)
    {width, height} = scaled(world, instance)
    {sprite_width, sprite_height} = sprite_size(world, sprite)
    {start, world} = Gml.random(world, 1000)
    {frame, world} = Gml.irandom(world, frames(world, self))

    Gml.put(world, self, %{
      startXScale: width / sprite_width,
      startYScale: height / sprite_height,
      randomStart: start,
      frame: frame,
      touched: 0,
      touchTimer: :math.fmod(Gml.round(x / width + y / height), @touch_cycle),
      flash: 0
    })
  end

  defp breathe(world, self, _other) do
    %Instance{x: x} = World.fetch(world, self)

    if abs(x - Camera.center_x(world)) > @reach do
      world
    else
      frame = System.get(world, :frame)

      world
      |> swell(self)
      |> Gml.put(self, %{flash: 0})
      |> check_touch(self, frame)
      |> evaporate(self)
      |> show(self)
    end
  end

  defp fake_breathe(world, self, _other) do
    %Instance{x: x} = World.fetch(world, self)
    if abs(x - Camera.center_x(world)) > @reach, do: world, else: swell(world, self)
  end

  defp swell(world, self) do
    frame = System.get(world, :frame)
    start = Gml.var(world, self, :randomStart)

    World.update(world, self, fn poof ->
      %{
        poof
        | image_xscale: Gml.var(world, self, :startXScale) + :math.sin(start + frame / 30) * 0.1,
          image_yscale: Gml.var(world, self, :startYScale) + :math.cos(start + frame / 30) * 0.1
      }
    end)
  end

  defp check_touch(world, self, frame) do
    if Gml.eq?(:math.fmod(frame + Gml.var(world, self, :touchTimer), 4), 0) do
      world = Gml.put(world, self, %{flash: 1, touched: 0})
      %Instance{x: x, y: y} = World.fetch(world, self)

      Enum.reduce(Gml.all(world, "Man"), world, &touch_by(&2, self, {x, y}, &1))
    else
      world
    end
  end

  defp touch_by(world, self, {x, y}, man) do
    %Instance{x: man_x, y: man_y, vars: vars} = World.fetch(world, man)
    moving = abs(Map.get(vars, :hspd, 0)) + abs(Map.get(vars, :vspd, 0)) - 0.2 > 1.0e-5

    if not Gml.truthy?(Gml.var(world, self, :touched)) and moving and
         (distance({x, y - 20}, {man_x, man_y}) < @touch or
            distance({x, y}, {man_x, man_y}) < @touch),
       do: Gml.put(world, self, %{touched: 1}),
       else: world
  end

  defp evaporate(world, self) do
    %Instance{sprite_index: sprite} = World.fetch(world, self)
    frame = Gml.var(world, self, :frame)
    last = frames(world, self) - 1
    poof = sprite_named(world, @poof)
    evaporate = sprite_named(world, @evaporate)

    case {Gml.truthy?(Gml.var(world, self, :touched)), sprite} do
      {true, ^poof} ->
        world
        |> World.update(self, &%{&1 | sprite_index: evaporate})
        |> Gml.put(self, %{frame: 0})

      {true, ^evaporate} ->
        Gml.put(world, self, %{frame: Gml.clamp(frame + 1, 0, last)})

      {false, ^evaporate} ->
        mend(world, self, Gml.clamp(frame - @mend, 0, last))

      {false, ^poof} ->
        Gml.put(world, self, %{frame: frame + 0.1})

      _other ->
        world
    end
  end

  defp mend(world, self, frame) do
    if Gml.eq?(frame, 0) do
      world = World.update(world, self, &%{&1 | sprite_index: sprite_named(world, @poof)})
      {again, world} = Gml.irandom(world, frames(world, self))
      Gml.put(world, self, %{frame: again})
    else
      Gml.put(world, self, %{frame: frame})
    end
  end

  defp show(world, self) do
    frame = Gml.var(world, self, :frame)
    world = World.update(world, self, &%{&1 | image_index: frame / 1, image_speed: 0.0})

    if System.get(world, :level) == @dark_level,
      do: World.update(world, self, &%{&1 | image_blend: @dark}),
      else: world
  end

  defp fake(world, self, _other) do
    %Instance{sprite_index: sprite} = instance = World.fetch(world, self)
    {width, height} = scaled(world, instance)
    {sprite_width, sprite_height} = sprite_size(world, sprite)
    {start, world} = Gml.random(world, 1000)
    world = World.update(world, self, &%{&1 | sprite_index: sprite_named(world, @poof)})
    {frame, world} = Gml.irandom(world, frames(world, self))

    world
    |> Gml.put(self, %{
      startXScale: width / sprite_width,
      startYScale: height / sprite_height,
      randomStart: start
    })
    |> World.update(self, &%{&1 | image_index: frame / 1})
  end

  defp distance({x1, y1}, {x2, y2}), do: :math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))

  defp scaled(world, %Instance{sprite_index: sprite, image_xscale: xscale, image_yscale: yscale}) do
    {width, height} = sprite_size(world, sprite)
    {width * xscale, height * yscale}
  end

  defp sprite_named(world, name), do: Data.index(world.data, :sprites, name)

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
