defmodule Nidhox.Objects.Grass do
  @moduledoc """
  Grass, as the game's code places and moves it.

    * `GrassArea` lays a `Grass` every `@spacing` pixels along its width, at its foot;
      `GrassAreaDark` lays them 2 pixels higher and dark
    * a `Grass` starts 2 pixels lower than placed, `checkTimer` its x over its sprite's
      width, rounded, modulo 7

  `update/3` is the grass's user event 2, which the title menu runs every step and a
  bout runs every bout step. `frame` is the world's step count and `cameraCenterX` the
  middle of the first view. A grass more than `@reach` pixels across from the camera's
  centre is left as it is. For the others:

    * on steps where `(checkTimer + frame) mod 3` is 0, what goes through it touches it:
        * a fencer within `@man_height` above or below and `|x + 8 − its x| < 12`: moving
          faster than 1 a step or attacking sets `touchTimer` to 20; downed (floored or
          dead) lays it flat with `touchTimer` 30; crawling, sliding or falling lays it
          flat. A grass already flat with `touchTimer` 30 or more is not touched
        * a flying sword within the grass's height and `|x + 8 − its x| < width / 2 + 10`
          sets `touchTimer` to 20
        * a cat within the grass's height, `|x + 8 − its x| < 8`, moving faster than 0.5
          a step sets `touchTimer` to 10
      flying swords and cats do not touch a flat grass whose `touchTimer` is 20 or more
    * standing (`sGrassFlatten`): flat, it falls `@fall` frames a step; touched
      (`touchTimer > 0`), it turns to `sGrassOccupied` at frame 0; else it rises
      `@rise` frames a step; held to its frames
    * occupied (`sGrassOccupied`): flat, it turns back to `sGrassFlatten` at frame 1;
      untouched, back at frame 0; else it shakes on `@shake` frames a step, wrapping
      past its last frame
    * it shows that frame, tinted `@light`, or `@dark` when dark; `touchTimer` counts
      down, and at 0 or below the grass is no longer flat
    * it sways: `image_xscale = |sin((frame + x) / 50)| × 0.2 + 1`, and `image_yscale =
      startYScale × (|sin((frame + x × 100) / 200)| × 0.1 + 0.9)`, or for dark grass
      `× (… × 0.2 + 1)`
  """

  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.{Fencer, Parallax}

  @spacing 16
  @dark {54, 54, 54}
  @light {183, 148, 28}
  @reach 200
  @man_height 32
  @fall 0.3
  @rise 0.15
  @shake 0.6
  @attacking [:thrust, :throw, :punch, :punch2, :uppercut, :sweep, :divekick, :heart]
  @downed [:floored, :dead]
  @low [:duck, :slide]

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_GrassArea_Create_0", &lay(&1, &2, &3, 0, false)},
      {"gml_Object_GrassAreaDark_Create_0", &lay(&1, &2, &3, 2, true)},
      {"gml_Object_Grass_Create_0", &start/3}
    ]
  end

  @doc """
  `world` after the grass's user event 2, with `fencers` and the bout's `swords` going
  through it (`Nidhox.Duel.sword/0`; the flying ones touch it).
  """
  @spec update(World.t(), [Fencer.t()], [map()]) :: World.t()
  def update(%World{} = world, fencers, swords) do
    case World.object_index(world, "Grass") do
      nil ->
        world

      grass ->
        scene = scene(world, fencers, swords)

        world
        |> World.instances_of(grass)
        |> Enum.reduce(world, &World.update(&2, &1, fn blade -> step(blade, scene) end))
    end
  end

  defp scene(world, fencers, swords) do
    %{
      world: world,
      frame: world.steps,
      centre: Parallax.camera_center_x(world),
      fencers: fencers,
      swords: for(%{flying: true, position: position} <- swords, do: position),
      cats: cats(world),
      flatten: sprite(world, "sGrassFlatten"),
      occupied: sprite(world, "sGrassOccupied")
    }
  end

  defp cats(world) do
    case World.object_index(world, "Cat") do
      nil ->
        []

      cat ->
        for id <- World.instances_of(world, cat),
            %Instance{x: x, y: y, hspeed: hspeed} = World.fetch(world, id),
            do: %{position: {x, y}, hspd: hspeed}
    end
  end

  defp sprite(world, name) do
    index = Enum.find_index(world.data.sprites, &(&1.name == name))
    %{index: index, frames: length(Enum.at(world.data.sprites, index).frames)}
  end

  defp lay(world, self, _other, raise_by, dark?) do
    %Instance{x: x, y: y, image_xscale: xscale, image_yscale: yscale, sprite_index: sprite} =
      World.fetch(world, self)

    {width, height} = World.sprite(world, sprite).size
    object = World.object_index(world, "Grass")

    Enum.reduce(0..(trunc(width * xscale / @spacing) - 1)//1, world, fn i, world ->
      {world, blade} =
        World.create(world, object, {x + i * @spacing, y + height * yscale - raise_by})

      World.update(world, blade, &%{&1 | vars: Map.put(&1.vars, :dark, dark?)})
    end)
  end

  defp start(world, self, _other) do
    World.update(world, self, fn %Instance{} = blade ->
      width = World.sprite(world, blade.sprite_index).size |> elem(0)

      %{
        blade
        | y: blade.y + 2,
          vars:
            Map.merge(blade.vars, %{
              touchTimer: 0,
              flattened: false,
              frame: 0.0,
              dark: Map.get(blade.vars, :dark, false),
              startYScale: blade.image_yscale,
              checkTimer: rem(round(blade.x / (width * blade.image_xscale)), 7)
            })
      }
    end)
  end

  defp step(%Instance{x: x} = blade, %{centre: centre})
       when abs(x - centre) > @reach,
       do: blade

  defp step(%Instance{} = blade, scene) do
    blade
    |> touched(scene)
    |> posed(scene)
    |> tinted()
    |> counted_down()
    |> swayed(scene.frame)
  end

  defp touched(%Instance{vars: %{checkTimer: check}} = blade, %{frame: frame} = scene)
       when rem(check + frame, 3) == 0 do
    {width, height} = size(blade, scene.world)

    blade
    |> by_fencers(scene.fencers)
    |> by_swords(scene.swords, width, height)
    |> by_cats(scene.cats, height)
  end

  defp touched(blade, _scene), do: blade

  defp by_fencers(blade, fencers), do: Enum.reduce(fencers, blade, &by_fencer(&2, &1))

  defp by_fencer(%Instance{vars: %{flattened: true, touchTimer: timer}} = blade, _fencer)
       when timer >= 30,
       do: blade

  defp by_fencer(%Instance{x: x, y: y} = blade, %Fencer{position: {fx, fy}} = fencer) do
    if abs(y - fy) < @man_height and abs(x + 8 - fx) < 12,
      do: trod(blade, fencer),
      else: blade
  end

  defp trod(blade, %Fencer{action: action, velocity: {hspd, vspd}}) do
    blade
    |> touch_if(abs(hspd) > 1 or action in @attacking, 20)
    |> flatten_if(action in @downed, 30)
    |> flatten_if(action in @low or vspd > 0, nil)
  end

  defp by_swords(blade, swords, width, height) do
    Enum.reduce(swords, blade, fn {sx, sy}, %Instance{x: x, y: y} = blade ->
      reached = abs(sy - y) < height and abs(x + 8 - sx) < width / 2 + 10
      if open?(blade, 20), do: touch_if(blade, reached, 20), else: blade
    end)
  end

  defp by_cats(blade, cats, height) do
    Enum.reduce(cats, blade, fn %{position: {cx, cy}, hspd: hspd}, %Instance{x: x, y: y} = blade ->
      reached = abs(cy - y) < height and abs(x + 8 - cx) < 8 and abs(hspd) > 0.5
      if open?(blade, 20), do: touch_if(blade, reached, 10), else: blade
    end)
  end

  defp open?(%Instance{vars: %{flattened: flat, touchTimer: timer}}, limit),
    do: not flat or timer < limit

  defp touch_if(blade, false, _timer), do: blade
  defp touch_if(blade, true, timer), do: put_vars(blade, %{touchTimer: timer})

  defp flatten_if(blade, false, _timer), do: blade
  defp flatten_if(blade, true, nil), do: put_vars(blade, %{flattened: true})
  defp flatten_if(blade, true, timer), do: put_vars(blade, %{flattened: true, touchTimer: timer})

  defp posed(%Instance{sprite_index: index} = blade, %{flatten: %{index: index}} = scene) do
    %{vars: %{flattened: flat, touchTimer: timer, frame: frame}} = blade

    {blade, frame} =
      cond do
        flat -> {blade, frame + @fall}
        timer > 0 -> {%{blade | sprite_index: scene.occupied.index}, 0.0}
        true -> {blade, frame - @rise}
      end

    shown(blade, frame |> max(0.0) |> min(scene.flatten.frames - 1.0))
  end

  defp posed(%Instance{sprite_index: index} = blade, %{occupied: %{index: index}} = scene) do
    %{vars: %{flattened: flat, touchTimer: timer, frame: frame}} = blade
    last = scene.occupied.frames - 1.0

    cond do
      flat -> shown(%{blade | sprite_index: scene.flatten.index}, 1.0)
      timer <= 0 -> shown(%{blade | sprite_index: scene.flatten.index}, 0.0)
      frame + @shake > last -> shown(blade, max(frame + @shake - last, 0.0))
      true -> shown(blade, max(frame + @shake, 0.0))
    end
  end

  defp posed(blade, _scene), do: shown(blade, blade.vars.frame)

  defp shown(blade, frame),
    do: %{put_vars(blade, %{frame: frame}) | image_speed: 0.0, image_index: frame}

  defp tinted(%Instance{vars: %{dark: true}} = blade), do: %{blade | image_blend: @dark}
  defp tinted(blade), do: %{blade | image_blend: @light}

  defp counted_down(%Instance{vars: %{touchTimer: timer}} = blade) when timer - 1 <= 0,
    do: put_vars(blade, %{touchTimer: timer - 1, flattened: false})

  defp counted_down(%Instance{vars: %{touchTimer: timer}} = blade),
    do: put_vars(blade, %{touchTimer: timer - 1})

  defp swayed(%Instance{x: x, vars: %{dark: dark, startYScale: start}} = blade, frame) do
    breathe = abs(:math.sin((frame + x * 100) / 200))
    height = if dark, do: breathe * 0.2 + 1, else: breathe * 0.1 + 0.9

    %{
      blade
      | image_xscale: abs(:math.sin((frame + x) / 50)) * 0.2 + 1,
        image_yscale: start * height
    }
  end

  defp size(%Instance{sprite_index: index, image_xscale: xscale, image_yscale: yscale}, world) do
    {width, height} = World.sprite(world, index).size
    {width * xscale, height * yscale}
  end

  defp put_vars(%Instance{vars: vars} = blade, changes),
    do: %{blade | vars: Map.merge(vars, changes)}
end
