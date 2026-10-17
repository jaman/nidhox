defmodule Nidhox.Objects.FlyingWeapon do
  @moduledoc """
  The game's `FlyingWeapon` and its `YellowFlyingWeapon` (player 1) and
  `OrangeFlyingWeapon` (player 2): a thrown sword flying straight, spinning, until it
  strikes a wall. A `PhysicsObject` without gravity, run by the match's frame as user
  event 2; listed in the match's `flyingWeapons` while it lasts.

    * create: the physics variables, `type` 2, `playerIndex` 0 (1 or 2 for the coloured
      ones), `previousAngle` and `head` −1, the sword's sprite, its blade's bottom line
      at its position, a whoosh (`sfxFlyingSword1` or `sfxFlyingSword2`), `timer` 360,
      `counter` 0, `reverseTimer` 30, `reverse` 0, `startHSpd` 0
    * user event 2: counts on; turned by `hspd × 10` degrees; the bottom line of its
      blade (`bottomLineY`, `bottomLineX1`, `bottomLineX2`) found from its half-length
      along its angle, pointing the side its tip is on, with the last step's movement;
      marked to be gone when `timer` runs out or it is more than 64 pixels left of, right
      of or below the room. A `Stairs` on its path (`x`, `y` to `x + hspd`, `y + vspd`)
      is a wall (user event 0). Otherwise the physics end step runs; with boomerang
      swords, after 30 steps `playerIndex` becomes 0 and it turns back, easing to its
      starting speed the other way by 0.2 a step. A weapon marked to be gone is removed
      at the end of the step
    * user event 0 (a wall across its path): `sfxFlyingSwordHitWall`, and it drops back
      off the wall from where it was (`previousX`) as a `DroppedWeapon` at a quarter of
      its speed turned round, 1 upwards; a throw that dodged the opponent counts as a
      dodge in the challenge and in the tutorial (the tutorial only when the sword is
      within 41 pixels of the first fencer's entry point, 13 pixels above it); then it is
      gone
    * user event 1 (a floor or ceiling): the same sound and a `DroppedWeapon` from where
      it was above or below (`previousY`) at a quarter of its speed, 1 upwards; then it
      is gone
    * leaving the room: gone; destroyed: dropped from the match's list
  """

  alias Cauldron2D.GameMaker.{Collide, Instance, World}
  alias Nidhox.Bout.{Sound, Variants}
  alias Nidhox.Gml
  alias Nidhox.Man.{Physics, Weapon}
  alias Nidhox.Objects.{Challenge, DroppedWeapon, System}

  @whoosh ["sfxFlyingSword1", "sfxFlyingSword2"]
  @clang "sfxFlyingSwordHitWall"
  @dodge 8
  @room_margin 64
  @tutorial_reach 41
  @tutorial_offset 13

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_FlyingWeapon_Create_0", &start/3},
      {"gml_Object_YellowFlyingWeapon_Create_0", &coloured(&1, &2, &3, 1)},
      {"gml_Object_OrangeFlyingWeapon_Create_0", &coloured(&1, &2, &3, 2)},
      {"gml_Object_FlyingWeapon_Other_12", &update/3},
      {"gml_Object_FlyingWeapon_Other_10", &wall/3},
      {"gml_Object_FlyingWeapon_Other_11", &floor/3},
      {"gml_Object_FlyingWeapon_Other_0", &gone/3},
      {"gml_Object_FlyingWeapon_Destroy_0", &finish/3}
    ]
  end

  defp start(world, self, _other) do
    world =
      world
      |> World.inherited(self, "FlyingWeapon", :create, 0)
      |> Gml.put(self, %{type: 2, playerIndex: 0, previousAngle: -1, head: -1})
      |> DroppedWeapon.pick_graphic(self)

    %Instance{x: x, y: y} = World.fetch(world, self)
    {whoosh, world} = Gml.choose(world, @whoosh)

    world
    |> Gml.put(self, %{bottomLineY: y, bottomLineX1: x, bottomLineX2: x})
    |> Sound.play_named(whoosh, {x, y})
    |> Gml.put(self, %{timer: 360, counter: 0, reverseTimer: 30, reverse: 0, startHSpd: 0})
    |> listed(self)
  end

  defp coloured(world, self, _other, player) do
    world
    |> World.inherited(
      self,
      World.object(world, World.fetch(world, self).object).name,
      :create,
      0
    )
    |> Gml.put(self, %{playerIndex: player})
  end

  defp listed(world, self) do
    case match(world) do
      nil ->
        world

      match ->
        Gml.put(world, match, %{
          flyingWeapons: Gml.var(world, match, :flyingWeapons, []) ++ [self]
        })
    end
  end

  defp update(world, self, _other) do
    world =
      world
      |> Gml.put(self, %{counter: Gml.var(world, self, :counter) + 1})
      |> DroppedWeapon.pick_graphic(self)

    hspd = Gml.var(world, self, :hspd)
    %Instance{image_angle: angle} = World.fetch(world, self)

    world =
      world
      |> Gml.put(self, %{previousAngle: angle})
      |> World.update(self, &%{&1 | image_angle: angle - hspd * 10})
      |> bottom_line(self, hspd)

    timer = Gml.var(world, self, :timer) - 1
    world = Gml.put(world, self, %{timer: timer})
    gone? = not Gml.truthy?(timer) or outside_room?(world, self)

    world
    |> carry_on(self)
    |> then(&if(gone?, do: World.destroy(&1, self), else: &1))
  end

  defp carry_on(world, self) do
    if stairs_ahead?(world, self) do
      World.perform(world, self, :other, 10)
    else
      world
      |> Physics.end_step(self)
      |> boomerang(self)
    end
  end

  defp stairs_ahead?(world, self) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    hspd = Gml.var(world, self, :hspd)
    vspd = Gml.var(world, self, :vspd)

    case World.object_index(world, "Stairs") do
      nil -> false
      stairs -> Collide.on_line(world, {x, y}, {x + hspd, y + vspd}, stairs) != nil
    end
  end

  defp outside_room?(world, self) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    {width, height} = world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size)

    x < -@room_margin or x > width + @room_margin or y > height + @room_margin
  end

  defp bottom_line(world, self, hspd) do
    %Instance{x: x, y: y, image_angle: angle} = World.fetch(world, self)
    half = sprite_width(world, self) * 0.5
    side = if Gml.gt?(normalised(angle), 180), do: 1, else: -1
    radians = angle * :math.pi() / 180
    x1 = x + half * side * :math.cos(radians) + hspd

    Gml.put(world, self, %{
      bottomLineY: y - half * side * :math.sin(radians),
      bottomLineX1: x1,
      bottomLineX2: x1 - hspd * 2
    })
  end

  defp normalised(angle) when angle < 0, do: normalised(angle + 360)
  defp normalised(angle) when angle > 360, do: normalised(angle - 360)
  defp normalised(angle), do: angle

  defp boomerang(world, self) do
    if World.fetch(world, self) != nil and Variants.active?(world) and
         Gml.truthy?(System.get(world, :boomerangSwords)) do
      world |> count_down_reverse(self) |> return(self)
    else
      world
    end
  end

  defp count_down_reverse(world, self) do
    timer = Gml.var(world, self, :reverseTimer) - 1

    if Gml.eq?(timer, 0),
      do:
        Gml.put(world, self, %{
          reverseTimer: 0,
          playerIndex: 0,
          reverse: 1,
          startHSpd: Gml.var(world, self, :hspd)
        }),
      else: Gml.put(world, self, %{reverseTimer: timer})
  end

  defp return(world, self) do
    if Gml.truthy?(Gml.var(world, self, :reverse)) do
      hspd = Gml.approach(Gml.var(world, self, :hspd), -Gml.var(world, self, :startHSpd), 0.2)
      Gml.put(world, self, %{hspd: hspd})
    else
      world
    end
  end

  defp wall(world, self, _other) do
    %Instance{x: x, y: y, image_xscale: xscale} = World.fetch(world, self)
    hspd = Gml.var(world, self, :hspd)

    world
    |> Sound.play_named(@clang, {x, y})
    |> Weapon.spawn_dropped({Gml.var(world, self, :previousX, x), y}, -hspd * 0.25, -1, xscale)
    |> elem(0)
    |> dodged(self)
    |> World.destroy(self)
  end

  defp floor(world, self, _other) do
    %Instance{x: x, y: y, image_xscale: xscale} = World.fetch(world, self)
    hspd = Gml.var(world, self, :hspd)

    world
    |> Sound.play_named(@clang, {x, y})
    |> Weapon.spawn_dropped({x, Gml.var(world, self, :previousY, y)}, hspd * 0.25, -1, xscale)
    |> elem(0)
    |> World.destroy(self)
  end

  defp dodged(world, self) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    thrower = Gml.var(world, self, :playerIndex)

    world
    |> challenger_dodged(thrower, {x, y})
    |> learner_dodged(thrower, {x, y})
  end

  defp challenger_dodged(world, thrower, at) do
    case Gml.first(world, "ChallengeMode") do
      nil ->
        world

      challenge ->
        challenger = Gml.var(world, challenge, :playerIndex)

        if thrower != challenger,
          do: Challenge.move_completed(world, challenger, @dodge, at),
          else: world
    end
  end

  defp learner_dodged(world, thrower, {_x, y} = at) do
    if Gml.exists?(world, "Tutorial") and thrower != 1 and near_entry?(world, y),
      do: Challenge.move_completed(world, 1, @dodge, at),
      else: world
  end

  defp near_entry?(world, y) do
    case Gml.first(world, "YellowPlayerRoomEntryPoint") do
      nil -> false
      entry -> abs(y - World.fetch(world, entry).y - @tutorial_offset) < @tutorial_reach
    end
  end

  defp gone(world, self, _other), do: World.destroy(world, self)

  defp finish(world, self, _other) do
    case match(world) do
      nil ->
        world

      match ->
        Gml.put(world, match, %{
          flyingWeapons: List.delete(Gml.var(world, match, :flyingWeapons, []), self)
        })
    end
  end

  defp match(world) do
    with object when is_integer(object) <- World.object_index(world, "Match"),
         [match | _] <- World.instances_of(world, object) do
      match
    else
      _none -> nil
    end
  end

  defp sprite_width(world, id) do
    %Instance{sprite_index: sprite, image_xscale: xscale} = World.fetch(world, id)

    case World.sprite(world, sprite) do
      nil -> 0
      definition -> elem(definition.size, 0) * xscale
    end
  end
end
