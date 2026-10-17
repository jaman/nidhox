defmodule Nidhox.Objects.Grass do
  @moduledoc """
  Grass, as the game's code places and moves it.

    * `GrassArea` lays a `Grass` every 16 pixels along its width, at its foot;
      `GrassAreaDark` lays them 2 pixels higher and dark
    * a `Grass` starts 2 pixels lower than placed, `checkTimer` its x over its sprite's
      width, rounded, modulo 7

  Its user event 2 runs every match frame (`Nidhox.Bout.Frame`) and every step of the
  main menu (`update_all/1`). `frame` below is `System.frame`. A grass more than 200
  pixels across from the camera's centre (`cameraCenterX`) is left as it is. For the
  others:

    * on frames where `(checkTimer + frame) mod 3` is 0, what goes through it touches it;
      `x` and `y` are the grass's and `width`, `height` its scaled sprite's:
        * a fencer — unless the grass is flat with `touchTimer` 30 or more — less than
          its own sprite's height from `y` and `|x + 8 − its x| < 12`: moving faster
          than 1 a step or attacking (`isAttacking`) sets `touchTimer` 20; collapsing,
          stabbed or knocked down lays it flat with `touchTimer` 30; sliding (58),
          rolling (59), lying (61) or falling lays it flat
        * a thrown sword — unless flat with `touchTimer` 20 or more — less than `height`
          from `y` and `|x + 8 − its x| < width / 2 + 10` sets `touchTimer` 20
        * a cat — the same — within `height`, `|x + 8 − its x| < 8`, moving faster than
          0.5 a step sets `touchTimer` 10
        * a held sword, shown and moved this step — unless flat with `touchTimer` 10 or
          more — within `height` and `|its x + 9 × its fencer's facing − x + 8| <
          width / 2 + 5` sets `touchTimer` 10
    * standing (`sGrassFlatten`): flat, it falls 0.3 frames a step; touched, it turns to
      `sGrassOccupied` at frame 0; else it rises 0.15 a step; held to its frames
    * occupied (`sGrassOccupied`): flat, back to `sGrassFlatten` at frame 1; untouched,
      back at frame 0; else it shakes on 0.6 frames a step, wrapping past its last frame
    * it shows that frame, tinted `{183, 148, 28}`, or `{54, 54, 54}` when dark;
      `touchTimer` counts down, and at 0 or below the grass is no longer flat
    * it sways: `image_xscale = |sin((frame + x) / 50)| × 0.2 + 1`, and `image_yscale =
      startYScale × (|sin((frame + x × 100) / 200)| × 0.1 + 0.9)`, or for dark grass
      `× (… × 0.2 + 1)`
  """

  alias Cauldron2D.GameMaker.{Data, Instance, World}
  alias Nidhox.Bout.Camera
  alias Nidhox.Gml
  alias Nidhox.Man.Query
  alias Nidhox.Objects.System

  @spacing 16
  @dark {54, 54, 54}
  @light {183, 148, 28}
  @reach 200
  @fall 0.3
  @rise 0.15
  @shake 0.6
  @lying [58, 59, 61]
  @flatten "sGrassFlatten"
  @occupied "sGrassOccupied"

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_GrassArea_Create_0", &lay(&1, &2, &3, 0, 0)},
      {"gml_Object_GrassAreaDark_Create_0", &lay(&1, &2, &3, 2, 1)},
      {"gml_Object_Grass_Create_0", &start/3},
      {"gml_Object_Grass_Other_12", &update/3}
    ]
  end

  @doc "The world after every grass's user event 2 (`with (Grass) event_user(2)`)."
  @spec update_all(World.t()) :: World.t()
  def update_all(%World{} = world),
    do: Enum.reduce(Gml.all(world, "Grass"), world, &World.perform(&2, &1, :other, 12))

  defp lay(world, self, _other, raise_by, dark) do
    %Instance{x: x, y: y, image_xscale: xscale, image_yscale: yscale, sprite_index: sprite} =
      World.fetch(world, self)

    {width, height} = World.sprite(world, sprite).size
    object = World.object_index(world, "Grass")

    Enum.reduce(0..(ceil(width * xscale / @spacing) - 1)//1, world, fn i, world ->
      {world, blade} =
        World.create(world, object, {x + i * @spacing, y + height * yscale - raise_by})

      Gml.put(world, blade, %{dark: dark})
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
              flattened: 0,
              frame: 0.0,
              dark: Map.get(blade.vars, :dark, 0),
              startYScale: blade.image_yscale,
              checkTimer: rem(round(blade.x / (width * blade.image_xscale)), 7)
            })
      }
    end)
  end

  defp update(world, self, _other) do
    %Instance{x: x} = World.fetch(world, self)

    if abs(x - Camera.center_x(world)) > @reach do
      world
    else
      frame = System.get(world, :frame)

      world
      |> touched(self, frame)
      |> World.update(self, &(&1 |> posed(world) |> tinted() |> counted_down() |> swayed(frame)))
    end
  end

  defp touched(world, self, frame) do
    if Gml.eq?(:math.fmod(Gml.var(world, self, :checkTimer) + frame, 3), 0) do
      world
      |> by_each("Man", self, &by_man/3)
      |> by_each("FlyingWeapon", self, &by_thrown/3)
      |> by_each("Cat", self, &by_cat/3)
      |> by_each("HeldWeapon", self, &by_held/3)
    else
      world
    end
  end

  defp by_each(world, name, self, touch),
    do: Enum.reduce(Gml.all(world, name), world, &touch.(&2, &1, self))

  defp by_man(world, man, self) do
    %Instance{x: x, y: y} = blade = World.fetch(world, self)
    %Instance{x: man_x, y: man_y, vars: vars} = body = World.fetch(world, man)

    cond do
      flat_at_least?(blade, 30) -> world
      not Gml.lt?(abs(y - man_y) - height(world, body), 0) -> world
      not Gml.lt?(abs(x + 8 - man_x) - 12, 0) -> world
      true -> trodden(world, man, self, vars)
    end
  end

  defp trodden(world, man, self, vars) do
    world =
      if Gml.gt?(abs(Map.get(vars, :hspd, 0)), 1) or Query.attacking?(world, man),
        do: Gml.put(world, self, %{touchTimer: 20}),
        else: world

    world =
      if Query.collapsing?(world, man) or Query.stabbed?(world, man) or
           Query.knocked_down?(world, man),
         do: Gml.put(world, self, %{flattened: 1, touchTimer: 30}),
         else: world

    if Map.get(vars, :state) in @lying or Map.get(vars, :vspd, 0) > 0,
      do: Gml.put(world, self, %{flattened: 1}),
      else: world
  end

  defp by_thrown(world, sword, self) do
    %Instance{x: x, y: y} = blade = World.fetch(world, self)
    %Instance{x: sword_x, y: sword_y} = World.fetch(world, sword)

    if not flat_at_least?(blade, 20) and Gml.lt?(abs(sword_y - y) - height(world, blade), 0) and
         Gml.lt?(abs(x + 8 - sword_x) - (width(world, blade) / 2 + 10), 0),
       do: Gml.put(world, self, %{touchTimer: 20}),
       else: world
  end

  defp by_cat(world, cat, self) do
    %Instance{x: x, y: y} = blade = World.fetch(world, self)
    %Instance{x: cat_x, y: cat_y, vars: vars} = World.fetch(world, cat)

    if not flat_at_least?(blade, 20) and Gml.lt?(abs(cat_y - y) - height(world, blade), 0) and
         Gml.lt?(abs(x + 8 - cat_x) - 8, 0) and Gml.gt?(abs(Map.get(vars, :hspd, 0)), 0.5),
       do: Gml.put(world, self, %{touchTimer: 10}),
       else: world
  end

  defp by_held(world, sword, self) do
    %Instance{x: x, y: y} = blade = World.fetch(world, self)
    held = World.fetch(world, sword)

    if not flat_at_least?(blade, 10) and Map.get(held.vars, :type) == 2 and held.visible and
         moved?(held) and
         Gml.lt?(abs(held.y - y) - height(world, blade), 0) and
         Gml.lt?(abs(held.x + facing(world, held) * 9 - x + 8) - (width(world, blade) / 2 + 5), 0),
       do: Gml.put(world, self, %{touchTimer: 10}),
       else: world
  end

  defp moved?(%Instance{x: x, y: y, xprevious: px, yprevious: py}),
    do: not Gml.eq?(x, px) or not Gml.eq?(y, py)

  defp facing(world, %Instance{vars: vars}),
    do: Gml.var(world, Map.get(vars, :mother, -4), :facingXScale, 1)

  defp flat_at_least?(%Instance{vars: vars}, timer),
    do: Gml.truthy?(Map.get(vars, :flattened, 0)) and Map.get(vars, :touchTimer, 0) >= timer

  defp height(world, %Instance{sprite_index: sprite, image_yscale: yscale}),
    do: world |> size(sprite) |> elem(1) |> Kernel.*(yscale)

  defp width(world, %Instance{sprite_index: sprite, image_xscale: xscale}),
    do: world |> size(sprite) |> elem(0) |> Kernel.*(xscale)

  defp size(world, sprite) do
    case World.sprite(world, sprite) do
      nil -> {0, 0}
      definition -> definition.size
    end
  end

  defp posed(%Instance{sprite_index: sprite} = blade, world) do
    flatten = sprite_index(world, @flatten)
    occupied = sprite_index(world, @occupied)

    cond do
      sprite == flatten -> standing(blade, world, occupied)
      sprite == occupied -> occupied(blade, world, flatten)
      true -> shown(blade, blade.vars.frame)
    end
  end

  defp standing(%Instance{vars: vars} = blade, world, occupied) do
    {blade, frame} =
      cond do
        Gml.truthy?(vars.flattened) -> {blade, vars.frame + @fall}
        vars.touchTimer > 0 -> {%{blade | sprite_index: occupied}, 0.0}
        true -> {blade, vars.frame - @rise}
      end

    shown(blade, Gml.clamp(frame, 0, frames(world, blade.sprite_index) - 1))
  end

  defp occupied(%Instance{vars: vars} = blade, world, flatten) do
    cond do
      Gml.truthy?(vars.flattened) ->
        shown(%{blade | sprite_index: flatten}, 1.0)

      vars.touchTimer <= 0 ->
        shown(%{blade | sprite_index: flatten}, 0.0)

      true ->
        last = frames(world, blade.sprite_index) - 1
        frame = vars.frame + @shake
        frame = if frame > last, do: frame - last, else: frame
        shown(blade, max(frame, 0))
    end
  end

  defp sprite_index(world, name), do: Data.index(world.data, :sprites, name)

  defp frames(world, sprite) do
    case World.sprite(world, sprite) do
      nil -> 1
      definition -> length(definition.frames)
    end
  end

  defp shown(blade, frame),
    do: %{put_vars(blade, %{frame: frame}) | image_speed: 0.0, image_index: frame / 1}

  defp tinted(%Instance{vars: %{dark: dark}} = blade),
    do: %{blade | image_blend: if(Gml.truthy?(dark), do: @dark, else: @light)}

  defp counted_down(%Instance{vars: %{touchTimer: timer}} = blade) when timer - 1 <= 0,
    do: put_vars(blade, %{touchTimer: timer - 1, flattened: 0})

  defp counted_down(%Instance{vars: %{touchTimer: timer}} = blade),
    do: put_vars(blade, %{touchTimer: timer - 1})

  defp swayed(%Instance{x: x, vars: %{dark: dark, startYScale: start}} = blade, frame) do
    breathe = abs(:math.sin((frame + x * 100) / 200))
    height = if Gml.truthy?(dark), do: breathe * 0.2 + 1, else: breathe * 0.1 + 0.9

    %{
      blade
      | image_xscale: abs(:math.sin((frame + x) / 50)) * 0.2 + 1,
        image_yscale: start * height
    }
  end

  defp put_vars(%Instance{vars: vars} = blade, changes),
    do: %{blade | vars: Map.merge(vars, changes)}
end
