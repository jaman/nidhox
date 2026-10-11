defmodule Nidhox.Bout.Overlap do
  @moduledoc """
  Whether the fencers' weapons, fists and feet reach each other, as the game's overlap
  scripts test them: each a line (`collision_line`, precise, not counting the tester)
  against an instance's shape.

    * `held?/3` (`check_HeldWeapon_overlap(weapon, target)`): the blade from a fifth of
      its length to its end along the weapon's height (on stairs, along its tip's
      direction turned 25 degrees). A sword shown going up or down stairs measures as
      the level one (sprite 150)
    * `flying?/3` (`check_FlyingWeapon_overlap(weapon, target)`): the thrown sword's
      length along its angle, or its blade's bottom line
    * `punch?/3`, `kick?/3`, `sweep?/3` (`check_punch_overlap`, `check_kick_overlap`,
      `check_sweep_overlap(man, flesh)`): 17, 22 and 17 pixels ahead of the fencer, 25,
      25 and 8 above its feet
    * `divekick?/3` (`check_divekick_overlap(flesh, flesh)`): from 3 below the body's
      origin to 7 ahead and 3 above
    * `ground_pound?/3` (`checkGroundPoundOverlap(flesh, flesh)`): from 3 above the body's
      origin to 3 below
    * `impact/3` (`getImpactVelocitySwordFlesh(weapon, flesh)`): how hard a blade meets a
      body — 0 when the weapon turned around this step; 3 when it moved up or down; 4 when
      it was hidden last step; else whichever of the blade and the body moved further
      across, less what they moved together (both eased towards 0 by 0.1 until the
      other's movement is gone), when that carries it into the other; 0 otherwise
  """

  alias Cauldron2D.GameMaker.{Collide, Instance, World}
  alias Nidhox.Gml

  @level_sword 150
  @stairs_swords [151, 152]
  @noone -4

  @doc "Whether `weapon`'s blade crosses instance `target` (`check_HeldWeapon_overlap`)."
  @spec held?(World.t(), non_neg_integer(), non_neg_integer()) :: boolean()
  def held?(%World{} = world, weapon, target) do
    %Instance{x: x, y: y, sprite_index: sprite} = blade = World.fetch(world, weapon)

    width =
      if sprite in @stairs_swords,
        do: sprite_size(world, @level_sword),
        else: sprite_width(world, blade)

    mother = Gml.var(world, weapon, :mother, @noone)

    if on_stairs?(world, mother) do
      length = abs(width)
      tip = {Gml.var(world, weapon, :tipX, x), Gml.var(world, weapon, :tipY, y)}
      angle = Gml.point_direction({x, y}, tip) + 25
      from = {x + Gml.lengthdir_x(length * 0.2, angle), y + Gml.lengthdir_y(length * 0.2, angle)}
      to = {x + Gml.lengthdir_x(length, angle), y + Gml.lengthdir_y(length, angle)}
      line?(world, from, to, target)
    else
      line?(world, {x + width * 0.2, y}, {x + width, y}, target)
    end
  end

  @doc "Whether thrown sword `weapon` crosses instance `target` (`check_FlyingWeapon_overlap`)."
  @spec flying?(World.t(), non_neg_integer(), non_neg_integer()) :: boolean()
  def flying?(%World{} = world, weapon, target) do
    %Instance{x: x, y: y, image_angle: angle} = sword = World.fetch(world, weapon)
    half = sprite_width(world, sword) / 2
    from = {x + Gml.lengthdir_x(-half, angle), y + Gml.lengthdir_y(-half, angle)}
    to = {x + Gml.lengthdir_x(half, angle), y + Gml.lengthdir_y(half, angle)}
    bottom = Gml.var(world, weapon, :bottomLineY, y)

    line?(world, from, to, target) or
      line?(
        world,
        {Gml.var(world, weapon, :bottomLineX1, x), bottom},
        {Gml.var(world, weapon, :bottomLineX2, x), bottom},
        target
      )
  end

  @doc "Whether fencer `man`'s punch reaches body `flesh` (`check_punch_overlap`)."
  @spec punch?(World.t(), non_neg_integer(), non_neg_integer()) :: boolean()
  def punch?(world, man, flesh), do: ahead?(world, man, flesh, 17, 25)

  @doc "Whether fencer `man`'s kick reaches body `flesh` (`check_kick_overlap`)."
  @spec kick?(World.t(), non_neg_integer(), non_neg_integer()) :: boolean()
  def kick?(world, man, flesh), do: ahead?(world, man, flesh, 22, 25)

  @doc "Whether fencer `man`'s sweep reaches body `flesh` (`check_sweep_overlap`)."
  @spec sweep?(World.t(), non_neg_integer(), non_neg_integer()) :: boolean()
  def sweep?(world, man, flesh), do: ahead?(world, man, flesh, 17, 8)

  @doc "Whether body `kicker`'s dive kick reaches body `flesh` (`check_divekick_overlap`)."
  @spec divekick?(World.t(), non_neg_integer(), non_neg_integer()) :: boolean()
  def divekick?(world, kicker, flesh) do
    %Instance{x: x, y: y, image_xscale: xscale} = World.fetch(world, kicker)
    line?(world, {x, y + 3}, {x + xscale * 7, y - 3}, flesh)
  end

  @doc "Whether body `pounder`'s ground pound reaches body `flesh` (`checkGroundPoundOverlap`)."
  @spec ground_pound?(World.t(), non_neg_integer(), non_neg_integer()) :: boolean()
  def ground_pound?(world, pounder, flesh) do
    %Instance{x: x, y: y} = World.fetch(world, pounder)
    line?(world, {x, y - 3}, {x, y + 3}, flesh)
  end

  @doc "How hard `weapon`'s blade meets body `flesh` (`getImpactVelocitySwordFlesh`)."
  @spec impact(World.t(), non_neg_integer(), non_neg_integer()) :: number()
  def impact(%World{} = world, weapon, flesh) do
    %Instance{} = blade = World.fetch(world, weapon)

    cond do
      not Gml.eq?(Gml.var(world, weapon, :xScalePrevious, 1), blade.image_xscale) -> 0
      abs(blade.y - Gml.var(world, weapon, :previousY, blade.y)) > 1.0e-5 -> 3
      not Gml.truthy?(Gml.var(world, weapon, :visiblePrevious, 0)) -> 4
      true -> closing(world, blade, World.fetch(world, flesh))
    end
  end

  defp closing(world, %Instance{} = blade, %Instance{} = body) do
    blade_moved = blade.x - Gml.var(world, blade.id, :previousX, blade.x)
    body_moved = body.x - Gml.var(world, body.id, :previousX, body.x)

    cond do
      abs(blade_moved) - abs(body_moved) > 1.0e-5 ->
        {blade_moved, _rest} = together(blade_moved, body_moved)
        into(blade.x, body.x, blade_moved)

      abs(body_moved) - abs(blade_moved) > 1.0e-5 ->
        {body_moved, _rest} = together(body_moved, blade_moved)
        into(body.x, blade.x, body_moved)

      true ->
        0
    end
  end

  defp together(faster, slower) do
    if abs(slower) - 0.005 <= 1.0e-5,
      do: {faster, slower},
      else: together(Gml.approach(faster, 0, 0.1), Gml.approach(slower, 0, 0.1))
  end

  defp into(mover_x, other_x, moved) do
    cond do
      Gml.lt?(mover_x, other_x) and Gml.gt?(moved, 0) -> moved
      Gml.gt?(mover_x, other_x) and Gml.lt?(moved, 0) -> abs(moved)
      true -> 0
    end
  end

  defp ahead?(world, man, flesh, reach, height) do
    %Instance{x: x, y: y} = World.fetch(world, man)
    facing = Gml.var(world, man, :facingXScale, 1)
    line?(world, {x, y - height}, {x + facing * reach, y - height}, flesh)
  end

  defp line?(world, from, to, target),
    do: Collide.on_line(world, from, to, {:id, target}) != nil

  defp on_stairs?(world, mother) do
    case World.fetch(world, mother) do
      %Instance{object: object, vars: vars} ->
        World.object(world, object).name in ["YellowPlayer", "OrangePlayer"] and
          Map.get(vars, :state) in [30, 31]

      nil ->
        false
    end
  end

  defp sprite_width(world, %Instance{sprite_index: sprite, image_xscale: xscale}),
    do: sprite_size(world, sprite) * xscale

  defp sprite_size(world, sprite) do
    case World.sprite(world, sprite) do
      nil -> 0
      definition -> elem(definition.size, 0)
    end
  end
end
