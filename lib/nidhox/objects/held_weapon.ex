defmodule Nidhox.Objects.HeldWeapon do
  @moduledoc """
  The game's `HeldWeapon`: the weapon a
  fencer (`mother`) holds, placed each step by the fencer's update
  (`Nidhox.Man.Weapon.x_pos/2`, `y_pos/2`) and run by the match's frame as user event 2.

    * create: `type` 1 (fists); the fist and sword reach lists (`fistX`, `swordX`);
      `waitToSmear` 1, cleared by alarm 0 a step later; `mother` none; `visiblePrevious`
      0, `xScalePrevious` 1; `previousX`, `previousY` where it is; its tip (`tipX`, `tipY`)
      a sprite's width ahead; `tipYSpd` and `bounce` 0
    * user event 2: fists show `blankSprite`, a sword `sSword` at image speed 0.1;
      `visiblePrevious` and `xScalePrevious` kept; the tip springs towards the weapon's
      height (plus the fencer's `stairYModifier`): fencing (state 29, 30 or 31), it sways
      by `sin(facing × System.frame × 0.2) × 0.5`, a pixel higher held high and lower
      held low. Settled (`bounce` rounding to 0) the tip's speed keeps 0.6 of itself and
      takes 0.4 of the gap, held to ±30; bouncing, 0.3 and 0.6, held to ±50. The tip sits
      a sprite's width ahead and moves by its speed. `image_angle` is 0, or on stairs the
      stairs' sword direction (`stairSwordDir`) with 180 degrees more when the weapon
      faces left
    * draw: nothing for fists; a sword drawn at its place turned towards its tip (half a
      turn more facing left)
  """

  alias Cauldron2D.GameMaker.{Data, Draw, Instance, World}
  alias Nidhox.Gml
  alias Nidhox.Man.Stairs
  alias Nidhox.Objects.System

  @fist_x [0, 1, 2, 3, 4, 4, 5, 5, 5, 5, 4, 4, 3, 0]
  @sword_x [3, 5, 7, 11, 13, 17, 17, 17, 17, 13, 11, 7, 5, 3, 0, 0]
  @fists_sprite "blankSprite"
  @sword_sprite "sSword"
  @sword_image_speed 0.1
  @fencing_states [29, 30, 31]

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_HeldWeapon_Create_0", &start/3},
      {"gml_Object_HeldWeapon_Alarm_0", &smear_ready/3},
      {"gml_Object_HeldWeapon_Other_12", &update/3},
      {"gml_Object_HeldWeapon_Draw_0", &draw/3}
    ]
  end

  defp start(world, self, _other) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    world
    |> Gml.put(self, %{
      type: 1,
      fistX: @fist_x,
      swordX: @sword_x,
      waitToSmear: 1,
      mother: -4,
      visiblePrevious: 0,
      xScalePrevious: 1,
      previousX: x,
      previousY: y,
      tipX: x + sprite_width(world, self),
      tipY: y,
      tipYSpd: 0,
      bounce: 0
    })
    |> World.update(self, &Instance.put_alarm(&1, 0, 1))
  end

  defp smear_ready(world, self, _other), do: Gml.put(world, self, %{waitToSmear: 0})

  defp update(world, self, _other) do
    world = show_sprite(world, self)
    %Instance{y: y, visible: visible, image_xscale: xscale} = World.fetch(world, self)
    mother = Gml.var(world, self, :mother, -4)

    target =
      (y + Gml.var(world, mother, :stairYModifier, 0))
      |> sway(world, mother)

    world
    |> Gml.put(self, %{visiblePrevious: if(visible, do: 1, else: 0), xScalePrevious: xscale})
    |> spring(self, target)
    |> lean_on_stairs(self, mother)
  end

  defp show_sprite(world, self) do
    case Gml.var(world, self, :type) do
      1 ->
        World.update(world, self, &%{&1 | sprite_index: sprite_index(world, @fists_sprite)})

      2 ->
        World.update(
          world,
          self,
          &%{
            &1
            | sprite_index: sprite_index(world, @sword_sprite),
              image_speed: @sword_image_speed
          }
        )

      _other ->
        world
    end
  end

  defp sprite_index(world, name), do: Data.index(world.data, :sprites, name)

  defp lean_on_stairs(world, self, mother) do
    world = World.update(world, self, &%{&1 | image_angle: 0})

    with %Instance{} <- World.fetch(world, mother),
         stairs when stairs != nil <- Stairs.under(world, mother) do
      turn = if World.fetch(world, self).image_xscale < 0, do: 180, else: 0

      World.update(
        world,
        self,
        &%{&1 | image_angle: sword_direction(world, mother, stairs) + turn}
      )
    else
      _off_stairs -> world
    end
  end

  defp sword_direction(world, mother, stairs) do
    rise = :math.atan(Stairs.ratio(world, stairs)) * 180 / :math.pi()
    up? = Stairs.facing_up?(world, mother, stairs)

    case {Gml.var(world, mother, :facingXScale) > 0, up?} do
      {true, true} -> rise
      {true, false} -> -rise
      {false, true} -> 180 - rise
      {false, false} -> 180 + rise
    end
  end

  defp sway(target, world, mother) do
    if Gml.var(world, mother, :state) in @fencing_states do
      facing = Gml.var(world, mother, :facingXScale, 1)
      wobble = :math.sin(facing * System.get(world, :frame) * 0.2) * 0.5

      case Gml.var(world, mother, :stance) do
        1 -> target + wobble - 1
        2 -> target + wobble + 1
        _middle -> target + wobble
      end
    else
      target
    end
  end

  defp spring(world, self, target) do
    tip_y = Gml.var(world, self, :tipY)
    speed = Gml.var(world, self, :tipYSpd)

    {keep, take, limit} =
      if Gml.round(Gml.var(world, self, :bounce)) == 0, do: {0.6, 0.4, 30}, else: {0.3, 0.6, 50}

    speed = Gml.clamp(speed * keep + (target - tip_y) * take, -limit, limit)
    %Instance{x: x} = World.fetch(world, self)

    Gml.put(world, self, %{
      tipYSpd: speed,
      tipX: x + sprite_width(world, self),
      tipY: tip_y + speed
    })
  end

  defp draw(world, self, _other) do
    %Instance{} = weapon = World.fetch(world, self)

    if Gml.var(world, self, :type) == 1 do
      world
    else
      turn = if weapon.image_xscale < 0, do: 180, else: 0
      tip = {Gml.var(world, self, :tipX), Gml.var(world, self, :tipY)}
      angle = direction({weapon.x, weapon.y}, tip) + turn

      Draw.sprite(world, weapon.sprite_index, weapon.image_index, {weapon.x, weapon.y},
        scale: {weapon.image_xscale, weapon.image_yscale},
        angle: angle,
        blend: weapon.image_blend,
        alpha: weapon.image_alpha
      )
    end
  end

  defp direction({x1, y1}, {x2, y2}) do
    degrees = :math.atan2(-(y2 - y1), x2 - x1) * 180 / :math.pi()
    if degrees < 0, do: degrees + 360, else: degrees
  end

  defp sprite_width(world, id) do
    %Instance{sprite_index: sprite, image_xscale: xscale} = World.fetch(world, id)

    case World.sprite(world, sprite) do
      nil -> 0
      definition -> elem(definition.size, 0) * xscale
    end
  end
end
