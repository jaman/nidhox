defmodule Nidhox.Objects.FlyingWeapon do
  @moduledoc """
  The game's `FlyingWeapon` and its `YellowFlyingWeapon` (player 1) and
  `OrangeFlyingWeapon` (player 2): a thrown sword flying straight, spinning, until it
  strikes a wall. A `PhysicsObject` without gravity, run by the match's frame as user
  event 2; listed in the match's `flyingWeapons` while it lasts.

    * create: the physics variables, `type` 2, `playerIndex` 0 (1 or 2 for the coloured
      ones), `previousAngle` and `head` −1, the sword's sprite, its blade's bottom line
      at its position, a whoosh (56 or 57), `timer` 360, `counter` 0, `reverseTimer` 30,
      `reverse` 0, `startHSpd` 0
    * user event 2: counts on; turned by `hspd × 10` degrees; the bottom line of its
      blade (`bottomLineY`, `bottomLineX1`, `bottomLineX2`) found from its half-length
      along its angle, pointing the side its tip is on, with the last step's movement;
      gone when `timer` runs out; the physics end step; with boomerang swords, after 30
      steps it turns back, easing to its starting speed the other way by 0.2 a step
    * user event 0 (a wall): a clang (58), and it drops back off the wall as a
      `DroppedWeapon` at a quarter of its speed, 1 upwards; then it is gone
    * leaving the room: gone; destroyed: dropped from the match's list
  """

  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Bout.{Sound, Variants}
  alias Nidhox.Gml
  alias Nidhox.Man.{Physics, Weapon}
  alias Nidhox.Objects.{DroppedWeapon, System}
  alias Nidhox.Tutorial.Lessons

  @whoosh [56, 57]
  @clang 58

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_FlyingWeapon_Create_0", &start/3},
      {"gml_Object_YellowFlyingWeapon_Create_0", &coloured(&1, &2, &3, 1)},
      {"gml_Object_OrangeFlyingWeapon_Create_0", &coloured(&1, &2, &3, 2)},
      {"gml_Object_FlyingWeapon_Other_12", &update/3},
      {"gml_Object_FlyingWeapon_Other_10", &wall/3},
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
    |> Sound.play(whoosh, {x, y})
    |> Gml.put(self, %{timer: 360, counter: 0, reverseTimer: 30, reverse: 0, startHSpd: 0})
    |> listed(self)
  end

  defp coloured(world, self, _other, player) do
    world
    |> World.inherited(self, World.object(world, World.fetch(world, self).object).name, :create, 0)
    |> Gml.put(self, %{playerIndex: player})
  end

  defp listed(world, self) do
    case match(world) do
      nil -> world
      match -> Gml.put(world, match, %{flyingWeapons: Gml.var(world, match, :flyingWeapons, []) ++ [self]})
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

    if Gml.truthy?(timer) do
      world
      |> Physics.end_step(self)
      |> boomerang(self)
    else
      World.destroy(world, self)
    end
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
      do: Gml.put(world, self, %{reverseTimer: 0, reverse: 1, startHSpd: Gml.var(world, self, :hspd)}),
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
    %Instance{xprevious: x, y: y, image_xscale: xscale} = World.fetch(world, self)
    hspd = Gml.var(world, self, :hspd)

    world
    |> Sound.play(@clang, {World.fetch(world, self).x, y})
    |> Weapon.spawn_dropped({x, y}, -hspd * 0.25, -1, xscale)
    |> elem(0)
    |> missed_learner(self)
    |> World.destroy(self)
  end

  defp missed_learner(world, self) do
    if Gml.var(world, self, :playerIndex) != 1, do: Lessons.block(world, 1), else: world
  end

  defp gone(world, self, _other), do: World.destroy(world, self)

  defp finish(world, self, _other) do
    case match(world) do
      nil -> world
      match -> Gml.put(world, match, %{flyingWeapons: List.delete(Gml.var(world, match, :flyingWeapons, []), self)})
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
