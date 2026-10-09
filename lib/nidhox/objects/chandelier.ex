defmodule Nidhox.Objects.Chandelier do
  @moduledoc """
  The castle's chandeliers, as the game's code moves and draws them.

  A swinging chandelier (`o_chandelier`) starts at `angle` −10° and still. Each step
  its `spin_speed` falls by `@pull` while its angle is above 0 and rises by `@pull`
  otherwise, and its angle moves by the spin; each time it passes to the other side its
  chain squeaks (`sfxChainSqueak1`) 100 pixels below where it hangs. Its creak sounds
  round and round at it (`Nidhox.Objects.Ambience.creak/2`) and it moves with the camera
  as a parallax object at depth 20 (`overrideDepth`). Every 2 steps its alarm picks the
  frame, 1–3, its candles' glow shows.

  It is drawn as its sprite turned by its angle, and over that, added, its glow frame
  tinted `make_color_hsv(random(40), 100, 255)` at alpha 0.35.

  A still chandelier (`ChandelierStill`, the sudden death room) hangs straight, drawn
  with its chain of `sMiniChain` links from where it hangs up to 5 pixels above the
  room's top (`drawChainXYXY`).
  """

  alias Cauldron2D.GameMaker.{Colour, Data, Draw, Instance, World}
  alias Nidhox.Objects.Ambience

  @start_angle -10.0
  @pull 0.01
  @override_depth 20
  @flicker_steps 2
  @glow_alpha 0.35
  @squeak_drop 100
  @tile 16
  @chain_top -5

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_o_chandelier_Create_0", &hang/3},
      {"gml_Object_o_chandelier_Alarm_0", &flicker/3},
      {"gml_Object_o_chandelier_Step_0", &swing/3},
      {"gml_Object_o_chandelier_Draw_0", &draw/3},
      {"gml_Object_ChandelierStill_Step_0", &still/3},
      {"gml_Object_ChandelierStill_Draw_0", &draw_still/3}
    ]
  end

  defp hang(world, self, _other) do
    world
    |> World.update(self, fn chandelier ->
      %{
        chandelier
        | image_angle: @start_angle,
          image_speed: 0.0,
          vars:
            Map.merge(chandelier.vars, %{
              overrideDepth: @override_depth,
              spin_speed: 0.0,
              angle: @start_angle,
              dir: 0,
              foo: 1
            })
      }
      |> Instance.put_alarm(0, @flicker_steps)
    end)
    |> Ambience.creak(self)
  end

  defp flicker(world, self, _other) do
    frame = 1 + :erlang.phash2({world.steps, self, :foo}, 3)

    World.update(world, self, fn chandelier ->
      %{chandelier | vars: Map.put(chandelier.vars, :foo, frame)}
      |> Instance.put_alarm(0, @flicker_steps)
    end)
  end

  defp swing(world, self, _other) do
    %Instance{vars: vars} = chandelier = World.fetch(world, self)

    {spin, side} =
      if vars.angle > 0, do: {vars.spin_speed - @pull, 1}, else: {vars.spin_speed + @pull, 0}

    angle = vars.angle + spin

    world
    |> squeak(chandelier, vars.dir != side)
    |> World.update(self, fn chandelier ->
      %{
        chandelier
        | image_angle: angle,
          vars: Map.merge(chandelier.vars, %{spin_speed: spin, angle: angle, dir: side})
      }
    end)
  end

  defp squeak(world, %Instance{x: x, y: y}, true),
    do:
      World.emit(
        world,
        {{:recording, "sfxChainSqueak1"}, {x / @tile, (y + @squeak_drop) / @tile}}
      )

  defp squeak(world, _chandelier, false), do: world

  defp draw(world, self, _other) do
    %Instance{x: x, y: y, image_angle: angle, sprite_index: sprite, vars: vars} =
      World.fetch(world, self)

    hue = :erlang.phash2({world.steps, self, :hue}, 40_000) / 1000
    glow = Colour.hsv(hue, 100, 255)

    world
    |> Draw.sprite(sprite, 0, {x, y}, angle: angle)
    |> Draw.sprite(sprite, vars.foo, {x, y},
      angle: angle,
      blend: glow,
      alpha: @glow_alpha,
      mode: :add
    )
  end

  defp still(world, self, _other),
    do: World.update(world, self, &%{&1 | image_angle: 0.0, image_speed: 0.0})

  defp draw_still(world, self, _other) do
    %Instance{x: x, y: y, sprite_index: sprite} = World.fetch(world, self)

    world
    |> chain({x, y}, {x, @chain_top})
    |> Draw.sprite(sprite, 0, {x, y})
  end

  defp chain(world, {x, from_y}, {_x, to_y}) do
    case Data.index(world.data, :sprites, "sMiniChain") do
      nil ->
        world

      link ->
        {_width, height} = Enum.at(world.data.sprites, link).size
        Enum.reduce(to_y..trunc(from_y)//height, world, &Draw.sprite(&2, link, 0, {x, &1}))
    end
  end
end
