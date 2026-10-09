defmodule Nidhox.Objects.Mines do
  @moduledoc """
  The mines' machinery, drawn from the copy's sprites:

    * conveyors (`ConveyorLeft`, `ConveyorRight`, both `Conveyor`s): `sConveyor` drawn a
      column every 8 pixels across the conveyor, stretched to its height, its frames
      running the way the belt moves — left or right at `belt_speed/0` pixels a step,
      which `Nidhox.Terrain` carries a body standing on it by
    * screws (`Screw`): their sprite at their scale and angle, turning at `@screw_speed`
      frames a step
    * the pump (`Pump`): `sPumpBody`, with `sPumpHead` rocking `@rock` degrees either way
      about the body's topmost pixel once every `@rock_period` steps, `sPumpWheel` turning at
      that pivot and `sPumpEnd` playing at the head's end
    * smashers (`Smoosher`): the shaft `sSmoosher` with `sSpikeSmoosh` at its foot
    * smoke (`Smoker`, an editor stand-in, hidden): an `sSmoke` puff every `@smoke_every`
      steps, rising `@smoke_rise` pixels a step and fading over its frames
    * worms (`MiniWorm`): their frames at `@worm_speed` a step
  """

  alias Cauldron2D.GameMaker.Draw
  alias Cauldron2D.GameMaker.Instance
  alias Cauldron2D.GameMaker.Particles
  alias Cauldron2D.GameMaker.World
  alias Nidhox.Assets
  alias Nidhox.Objects.Torches

  @belt_speed 0.5
  @belt_column 8
  @screw_speed 0.25
  @rock 10.0
  @rock_period 150
  @smoke_every 40
  @smoke_rise -0.4
  @worm_speed 0.15

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Conveyor_Draw_0", &conveyor/3},
      {"gml_Object_Screw_Draw_0", &screw/3},
      {"gml_Object_Pump_Draw_0", &pump/3},
      {"gml_Object_Smoosher_Draw_0", &smoosher/3},
      {"gml_Object_Smoker_Create_0", &hide/3},
      {"gml_Object_Smoker_Step_0", &smoke/3},
      {"gml_Object_MiniWorm_Create_0", &worm/3}
    ]
  end

  @doc "How fast a conveyor's belt moves, in pixels a step."
  @spec belt_speed() :: float()
  def belt_speed, do: @belt_speed

  @doc "The way the conveyor object called `name` moves its belt: `-1`, `1`, or `0` for none."
  @spec belt_way(String.t()) :: -1 | 0 | 1
  def belt_way("ConveyorLeft"), do: -1
  def belt_way("ConveyorRight"), do: 1
  def belt_way(_name), do: 0

  defp conveyor(world, self, _other) do
    %Instance{x: x, y: y, image_xscale: across, image_yscale: down} =
      conveyor = World.fetch(world, self)

    {belt, %{frames: frames, size: {width, _height}}} = Assets.sprite!("sConveyor")
    way = belt_way(World.object(world, conveyor.object).name)
    columns = max(round(across * width / @belt_column), 1)
    shift = world.steps * @belt_speed * way

    Enum.reduce(0..(columns - 1), world, fn column, world ->
      frame = Integer.mod(floor(column * @belt_column - shift), length(frames))

      Draw.sprite(world, belt, frame, {x + column * @belt_column, y},
        scale: {@belt_column / width, down}
      )
    end)
  end

  defp screw(world, self, _other) do
    %Instance{} = screw = World.fetch(world, self)

    Draw.sprite(world, screw.sprite_index, world.steps * @screw_speed, {screw.x, screw.y},
      scale: {screw.image_xscale, screw.image_yscale},
      angle: screw.image_angle
    )
  end

  defp pump(world, self, _other) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    {body, _sprite} = Assets.sprite!("sPumpBody")
    top = "sPumpBody" |> Torches.tips() |> Enum.map(&elem(&1, 1)) |> Enum.min()
    {head, _sprite} = Assets.sprite!("sPumpHead")
    {wheel, _sprite} = Assets.sprite!("sPumpWheel")
    {rod, %{frames: rod_frames}} = Assets.sprite!("sPumpEnd")
    {_index, %{size: {head_width, _}, origin: {head_x, _}}} = Assets.sprite!("sPumpHead")
    pivot = {x, y + top}
    angle = @rock * :math.sin(2 * :math.pi() * world.steps / @rock_period)
    reach = head_width - head_x
    radians = angle * :math.pi() / 180
    {px, py} = pivot
    tip = {px + reach * :math.cos(radians), py - reach * :math.sin(radians)}

    rod_frame =
      rem(div(world.steps, div(@rock_period, 2 * length(rod_frames))), length(rod_frames))

    world
    |> Draw.sprite(body, 0, {x, y})
    |> Draw.sprite(head, 0, pivot, angle: angle)
    |> Draw.sprite(wheel, 0, pivot, angle: -world.steps * 360 / @rock_period)
    |> Draw.sprite(rod, rod_frame, tip)
  end

  defp smoosher(world, self, _other) do
    %Instance{} = smasher = World.fetch(world, self)
    {spikes, _sprite} = Assets.sprite!("sSpikeSmoosh")

    world
    |> Draw.sprite(smasher.sprite_index, 0, {smasher.x, smasher.y},
      scale: {smasher.image_xscale, smasher.image_yscale}
    )
    |> Draw.sprite(spikes, 0, {smasher.x, smasher.y})
  end

  defp hide(world, self, _other), do: World.update(world, self, &%{&1 | visible: false})

  defp smoke(world, self, _other) do
    if rem(world.steps + self, @smoke_every) == 0 do
      %Instance{x: x, y: y, depth: depth} = World.fetch(world, self)
      {puff, %{frames: frames}} = Assets.sprite!("sSmoke")
      life = trunc(length(frames) / 0.15)

      Particles.create(world, %{
        sprite: puff,
        position: {x, y},
        velocity: {0.0, @smoke_rise},
        life: life,
        frame_speed: length(frames) / life,
        alpha: {0.8, 0.0},
        depth: depth
      })
    else
      world
    end
  end

  defp worm(world, self, _other), do: World.update(world, self, &%{&1 | image_speed: @worm_speed})
end
