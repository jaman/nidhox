defmodule Nidhox.Objects.Chandelier do
  @moduledoc """
  The castle's chandeliers, as the game's code moves and draws them.

    * `o_chandelier` create: the parallax object's create, then `overrideDepth` 20,
      `spin_speed` 0, `angle` −10; an `Empty` made 250 pixels from it at `270 + angle`
      degrees (`bottom`), carrying one of the creaks `choose(sfxChandelier1, sfxChandelier2, sfxChandelier3)` round and round
      (`playSoundAtLoopEffect(…, 1, 1, bottom)`, `soundLoop`); `dir` and `foo` 0; `pv` the
      view's angle; its alarm in 3 steps
    * alarm 0: again in 2 steps; its glow frame `foo` `choose(1, 2, 3)`
    * step: `spin_speed` falls by 0.01 while `angle` is above 0 and rises by 0.01
      otherwise; each time it passes to the other side (`dir`) its chain squeaks
      (`sfxChainSqueak1`) 100 pixels below it; `angle` moves by `spin_speed`, `bottom` stays 250 pixels
      from it at `270 + angle` and it is turned `angle`
    * draw: its frame 0 turned by its angle in its blend, then added over it its glow
      frame `foo` turned `image_angle + pv × 3.5` in `make_color_hsv(random(40), 100,
      255)` at alpha 0.35
    * room end: its creak stopped
    * `ChandelierStill` create: the swinging chandelier's create, and the sudden death
      backdrop (`SuddenDeathBG`) made 96 pixels above it. It swings as the other does, but each step it is set straight, its creak's
      `Empty` is at the camera's centre, and the backdrop is turned by `−angle` instead;
      drawn with its chain (`Nidhox.Chain`, of `sChainLink`) from 250 pixels below it up
      to 5 pixels above the room's top, then as the other is drawn
  """

  alias Cauldron2D.Audio
  alias Cauldron2D.GameMaker.{Colour, Data, Draw, Instance, World}
  alias Nidhox.Bout.{Camera, Sound}
  alias Nidhox.{Chain, Gml}
  alias Nidhox.Objects.Ear

  @start_angle -10.0
  @pull 0.01
  @override_depth 20
  @first_flicker 3
  @flicker_steps 2
  @glow_alpha 0.35
  @squeak "sfxChainSqueak1"
  @squeak_drop 100
  @creaks ["sfxChandelier1", "sfxChandelier2", "sfxChandelier3"]
  @hang 250
  @down 270
  @backdrop_lift 96
  @chain_top -5

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_o_chandelier_Create_0", &hang/3},
      {"gml_Object_o_chandelier_Alarm_0", &flicker/3},
      {"gml_Object_o_chandelier_Step_0", &swing/3},
      {"gml_Object_o_chandelier_Draw_0", &draw/3},
      {"gml_Object_o_chandelier_Other_5", &hush/3},
      {"gml_Object_ChandelierStill_Create_0", &hang_still/3},
      {"gml_Object_ChandelierStill_Step_0", &still/3},
      {"gml_Object_ChandelierStill_Draw_0", &draw_still/3}
    ]
  end

  defp hang(world, self, _other) do
    world =
      world
      |> World.inherited(self, "o_chandelier", :create, 0)
      |> Gml.put(self, %{overrideDepth: @override_depth, spin_speed: 0, angle: @start_angle})

    {world, bottom} =
      World.create(
        world,
        World.object_index(world, "Empty"),
        hung(World.fetch(world, self), @start_angle)
      )

    {creak, world} = Gml.choose(world, @creaks)
    {loop, world} = Ear.attach(world, bottom, creak)

    world
    |> Gml.put(self, %{bottom: bottom, soundLoop: loop, dir: 0, foo: 0, pv: 0})
    |> World.update(self, &Instance.put_alarm(&1, 0, @first_flicker))
  end

  defp hung(%Instance{x: x, y: y}, angle),
    do: {x + Gml.lengthdir_x(@hang, @down + angle), y + Gml.lengthdir_y(@hang, @down + angle)}

  defp flicker(world, self, _other) do
    world = World.update(world, self, &Instance.put_alarm(&1, 0, @flicker_steps))
    {frame, world} = Gml.choose(world, [1, 2, 3])
    Gml.put(world, self, %{foo: frame})
  end

  defp swing(world, self, _other) do
    %Instance{x: x, y: y} = chandelier = World.fetch(world, self)
    angle = Gml.var(world, self, :angle)
    spin = Gml.var(world, self, :spin_speed)
    dir = Gml.var(world, self, :dir)
    {spin, side} = if Gml.gt?(angle, 0), do: {spin - @pull, 1}, else: {spin + @pull, 0}

    world =
      if Gml.eq?(dir, side), do: world, else: squeak(world, {x, y + @squeak_drop})

    angle = angle + spin

    world
    |> Gml.put(self, %{spin_speed: spin, dir: side, angle: angle})
    |> move_bottom(Gml.var(world, self, :bottom), hung(chandelier, angle))
    |> World.update(self, &%{&1 | image_angle: angle / 1})
  end

  defp squeak(world, position),
    do: Sound.play(world, Data.index(world.data, :sounds, @squeak), position)

  defp move_bottom(world, bottom, {x, y}) do
    if World.fetch(world, bottom),
      do: World.update(world, bottom, &%{&1 | x: x, y: y}),
      else: world
  end

  defp draw(world, self, _other) do
    %Instance{} = chandelier = World.fetch(world, self)
    {hue, world} = Gml.random(world, 40)

    world
    |> Draw.sprite(chandelier.sprite_index, 0, {chandelier.x, chandelier.y},
      scale: {chandelier.image_xscale, chandelier.image_yscale},
      angle: chandelier.image_angle,
      blend: chandelier.image_blend
    )
    |> Draw.sprite(
      chandelier.sprite_index,
      Gml.var(world, self, :foo),
      {chandelier.x, chandelier.y},
      scale: {chandelier.image_xscale, chandelier.image_yscale},
      angle: chandelier.image_angle + Gml.var(world, self, :pv) * 3.5,
      blend: Colour.hsv(hue, 100, 255),
      alpha: @glow_alpha,
      mode: :add
    )
  end

  defp hush(world, self, _other),
    do: World.emit(world, Audio.stopped(Gml.var(world, self, :soundLoop, nil)))

  defp hang_still(world, self, _other) do
    world = World.inherited(world, self, "ChandelierStill", :create, 0)
    %Instance{x: x, y: y} = World.fetch(world, self)

    world
    |> World.create(World.object_index(world, "SuddenDeathBG"), {x, y - @backdrop_lift})
    |> elem(0)
  end

  defp still(world, self, _other) do
    world = World.inherited(world, self, "ChandelierStill", :step, 0)
    bottom = Gml.var(world, self, :bottom)
    world = World.update(world, self, &%{&1 | image_angle: 0.0})

    if World.fetch(world, bottom),
      do:
        World.update(world, bottom, &%{&1 | x: Camera.center_x(world), y: Camera.center_y(world)}),
      else: world
  end

  defp draw_still(world, self, _other) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    angle = Gml.var(world, self, :angle)

    world
    |> Gml.all("SuddenDeathBG")
    |> Enum.reduce(
      world,
      &World.update(&2, &1, fn backdrop -> %{backdrop | image_angle: -angle / 1} end)
    )
    |> Chain.draw({x, y + @hang}, {x, @chain_top}, false)
    |> World.inherited(self, "ChandelierStill", :draw, 0)
  end
end
