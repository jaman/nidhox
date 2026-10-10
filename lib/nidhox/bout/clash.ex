defmodule Nidhox.Bout.Clash do
  @moduledoc """
  Swords meeting swords, and thrown swords meeting anything, as the game's scripts
  resolve them each match frame:

    * `weapon_to_weapon/2` (`check_HeldWeapon_to_HeldWeapon`): both fencers' swords
      shown and crossing — a disarm is tried (`disarm/2`), the two are pushed apart at 1
      a step, and each blade's tip jumps by its gap to the other's plus `random_range(−1,
      1)`; `{clashed, world}`
    * `disarm/2` (`try_to_disarm`): the fencer whose sword moved up or down this step —
      only one of them — disarms the other when the blades are closer across than the
      other's sword length × 1.75 (× 1.65 unless the other is lunging), neither on
      stairs: a clang (78), the clash point, a flash, the other's sword knocked loose
      (2 back from the disarmer's facing, 4 up) and the other disarmed (13)
    * `held_to_flying/3` (`check_HeldWeapon_to_FlyingWeapons(weapon)`): a sword shown
      crossing a thrown sword knocks it down: its tip drops 5, a flash and a clash, and
      the thrown sword falls as a `DroppedWeapon` (a quarter of its speed, 3 up)
    * `flying_to_flesh/2` (`check_FlyingWeapon_to_FleshCollisionMask(flesh)`): a thrown
      sword of the other player reaching a fencer not entering, stabbed or falling
      strikes it (83) and is gone; `{struck, world}`
    * `flying_to_flying/2` (`check_FlyingWeapons_to_FlyingWeapons`): two thrown swords
      in a row of the match's list meeting both fall and clash
    * `collapse_by_flying/2` (`collapsePlayerByFlying`): the struck fencer loses its
      sword and, from frame 0, is hit in the air (37) or standing (39)
    * `clash_at/2` (`clashXY`): the `ClashPosition` moved to the point and a clash (75,
      76 or 77) heard there
    * `priority/2` (`getPriority`): where the fencer's state stands in
      `System.priorityList`, 100000000 when not in it; `pushable?/2` (`isPushable`):
      fencing or unarmed (29, 78)
  """

  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Bout.{Overlap, Sound}
  alias Nidhox.Gml
  alias Nidhox.Man.{Query, State, Weapon}
  alias Nidhox.Objects.{Challenge, Effects, System}

  @noone -4
  @clang 78
  @clashes [75, 76, 77]
  @struck 83
  @unlisted 100_000_000
  @parry 6
  @throw 7
  @dodge 8
  @popup_rise 32

  @doc "`{clashed, world}` after the fencers' swords meet (`check_HeldWeapon_to_HeldWeapon`)."
  @spec weapon_to_weapon(World.t(), non_neg_integer()) :: {boolean(), World.t()}
  def weapon_to_weapon(%World{} = world, match) do
    yellow = Gml.var(world, match, :yellowInstance, @noone)
    orange = Gml.var(world, match, :orangeInstance, @noone)
    yellow_sword = weapon(world, yellow)
    orange_sword = weapon(world, orange)

    if shown_sword?(world, yellow_sword) and shown_sword?(world, orange_sword) and
         Overlap.held?(world, yellow_sword, orange_sword) do
      {true,
       world
       |> disarm(match)
       |> push_apart(yellow, orange)
       |> jump_tips(yellow_sword, orange_sword)}
    else
      {false, world}
    end
  end

  @doc "The world after a disarm is tried between the fencers (`try_to_disarm`)."
  @spec disarm(World.t(), non_neg_integer()) :: World.t()
  def disarm(%World{} = world, match) do
    yellow = Gml.var(world, match, :yellowInstance, @noone)
    orange = Gml.var(world, match, :orangeInstance, @noone)

    case {moved?(world, yellow), moved?(world, orange)} do
      {true, false} -> try_disarm(world, yellow, orange)
      {false, true} -> try_disarm(world, orange, yellow)
      _neither_or_both -> world
    end
  end

  @doc "The world after `weapon` meets the thrown swords (`check_HeldWeapon_to_FlyingWeapons`)."
  @spec held_to_flying(World.t(), non_neg_integer(), non_neg_integer()) :: World.t()
  def held_to_flying(%World{} = world, match, weapon) do
    if shown_sword?(world, weapon) do
      world
      |> flying(match)
      |> Enum.reduce(world, fn thrown, world ->
        if World.fetch(world, thrown) != nil and coloured_flying?(world, thrown) and
             Overlap.held?(world, weapon, thrown),
           do: knock_down(world, weapon, thrown),
           else: world
      end)
    else
      world
    end
  end

  @doc "`{struck, world}` after the thrown swords meet body `flesh` (`check_FlyingWeapon_to_FleshCollisionMask`)."
  @spec flying_to_flesh(World.t(), non_neg_integer()) :: {boolean(), World.t()}
  def flying_to_flesh(%World{} = world, flesh) do
    with %Instance{} <- World.fetch(world, flesh),
         man when man != @noone <- Gml.var(world, flesh, :mother, @noone),
         true <- Gml.var(world, man, :state) != 23,
         false <- Query.stabbed?(world, man),
         false <- Query.collapsing?(world, man) do
      player = Gml.var(world, man, :playerIndex)

      world
      |> all_flying()
      |> Enum.reduce({false, world}, fn thrown, {struck, world} ->
        if World.fetch(world, thrown) != nil and Gml.var(world, thrown, :playerIndex) != player and
             Overlap.flying?(world, thrown, flesh) do
          %Instance{x: x, y: y} = World.fetch(world, thrown)

          {true,
           world
           |> Challenge.move_completed(
             Gml.var(world, thrown, :playerIndex),
             @throw,
             {x, y - @popup_rise}
           )
           |> Sound.play(@struck, {x, y})
           |> World.destroy(thrown)}
        else
          {struck, world}
        end
      end)
    else
      _ -> {false, world}
    end
  end

  @doc "The world after thrown swords meet each other (`check_FlyingWeapons_to_FlyingWeapons`)."
  @spec flying_to_flying(World.t(), non_neg_integer()) :: World.t()
  def flying_to_flying(%World{} = world, match) do
    list = flying(world, match)
    count = length(list)
    if count >= 2, do: pairs(world, list, 1, count), else: world
  end

  @doc "The world with fencer `man` struck by a thrown sword (`collapsePlayerByFlying`)."
  @spec collapse_by_flying(World.t(), non_neg_integer()) :: World.t()
  def collapse_by_flying(%World{} = world, man) do
    {_dropped, world} = Weapon.drop(world, man)
    world = State.put(world, man, %{frame: 0})
    State.go(world, man, if(State.on_ground?(world, man), do: 39, else: 37))
  end

  @doc "The world with the swords' clash at `{x, y}` (`clashXY`)."
  @spec clash_at(World.t(), {number(), number()}) :: World.t()
  def clash_at(%World{} = world, {x, y}) do
    case World.object_index(world, "ClashPosition") do
      nil ->
        world

      object ->
        world
        |> World.instances_of(object)
        |> Enum.reduce(world, fn clash, world ->
          world = World.update(world, clash, &%{&1 | x: x, y: y})
          {sound, world} = Gml.choose(world, @clashes)
          Sound.play(world, sound, {x, y})
        end)
    end
  end

  @doc "Where fencer `man`'s state stands in `System.priorityList` (`getPriority`)."
  @spec priority(World.t(), non_neg_integer()) :: number()
  def priority(%World{} = world, man) do
    if World.fetch(world, man) do
      list = System.get(world, :priorityList)
      Enum.find_index(list, &(&1 == Gml.var(world, man, :state))) || @unlisted
    else
      @unlisted
    end
  end

  @doc "Whether fencer `man` may be shoved by the other (`isPushable`)."
  @spec pushable?(World.t(), non_neg_integer()) :: boolean()
  def pushable?(%World{} = world, man),
    do: World.fetch(world, man) != nil and Gml.var(world, man, :state) in [29, 78]

  defp weapon(world, man), do: Gml.var(world, man, :weapon, @noone)

  defp shown_sword?(world, weapon) do
    case World.fetch(world, weapon) do
      %Instance{visible: true, vars: vars} -> Map.get(vars, :type, 1) != 1
      _other -> false
    end
  end

  defp push_apart(world, yellow, orange) do
    away = if Gml.lt?(World.fetch(world, yellow).x, World.fetch(world, orange).x), do: -1, else: 1

    world
    |> State.put(yellow, %{hspd: away})
    |> State.put(orange, %{hspd: -away})
  end

  defp jump_tips(world, yellow_sword, orange_sword) do
    world
    |> jump_tip(yellow_sword, orange_sword)
    |> jump_tip(orange_sword, yellow_sword)
  end

  defp jump_tip(world, sword, other) do
    %Instance{y: y} = World.fetch(world, sword)
    gap = Gml.var(world, other, :tipY) - Gml.var(world, sword, :tipY)
    {wobble, world} = Gml.random_range(world, -1, 1)
    Gml.put(world, sword, %{tipY: y + gap + wobble})
  end

  defp moved?(world, man) do
    case World.fetch(world, weapon(world, man)) do
      %Instance{y: y} -> not Gml.eq?(y, Gml.var(world, man, :weaponYPrevious, y))
      nil -> false
    end
  end

  defp try_disarm(world, disarmer, victim) do
    disarmer_sword = World.fetch(world, weapon(world, disarmer))
    victim_sword = World.fetch(world, weapon(world, victim))
    apart = abs(disarmer_sword.x - victim_sword.x)
    reach = if Gml.var(world, victim, :state) == 48, do: 1.75, else: 1.65

    if not on_stairs?(world, victim) and not on_stairs?(world, disarmer) and
         apart < abs(sprite_width(world, victim_sword) * reach) - 1.0e-5 do
      %Instance{x: vx, y: vy} = World.fetch(world, victim)
      %Instance{x: dx, y: dy} = World.fetch(world, disarmer)

      world =
        world
        |> Sound.play(@clang, {vx, vy})
        |> Challenge.move_completed(
          Gml.var(world, disarmer, :playerIndex),
          @parry,
          {dx, dy - @popup_rise}
        )
        |> clash_at({dx, dy})
        |> Effects.flash()

      {dropped, world} = Weapon.drop(world, victim)

      world =
        if dropped,
          do:
            Gml.put(world, dropped, %{
              hspd: Gml.var(world, disarmer, :facingXScale, 1) * -2,
              vspd: -4
            }),
          else: world

      State.go(world, victim, 13)
    else
      world
    end
  end

  defp knock_down(world, weapon, thrown) do
    %Instance{x: x, y: y, image_xscale: xscale} = World.fetch(world, thrown)
    %Instance{x: weapon_x, y: weapon_y} = World.fetch(world, weapon)
    blocker = Gml.var(world, Gml.var(world, weapon, :mother, @noone), :playerIndex)

    world
    |> Challenge.move_completed(blocker, @dodge, {weapon_x, weapon_y - @popup_rise})
    |> Gml.put(weapon, %{tipY: weapon_y + 5})
    |> Effects.flash()
    |> clash_at({x, y})
    |> Weapon.spawn_dropped({x, y}, Gml.var(world, thrown, :hspd) * 0.25, -3, xscale)
    |> elem(0)
    |> World.destroy(thrown)
  end

  defp pairs(world, _list, index, count) when index >= count, do: world

  defp pairs(world, list, index, count) do
    first = Enum.at(list, index)
    second = Enum.at(list, index - 1)

    cond do
      first == nil or second == nil or World.fetch(world, first) == nil or
          World.fetch(world, second) == nil ->
        world

      Overlap.flying?(world, first, second) ->
        world |> both_fall(first, second) |> pairs(list, index + 1, count)

      true ->
        pairs(world, list, index + 1, count)
    end
  end

  defp both_fall(world, first, second) do
    %Instance{x: x, y: y} = World.fetch(world, first)

    later =
      if Gml.var(world, first, :counter) < Gml.var(world, second, :counter),
        do: first,
        else: second

    %Instance{x: second_x, y: second_y} = World.fetch(world, second)

    world
    |> Challenge.move_completed(Gml.var(world, later, :playerIndex), @dodge, {second_x, second_y})
    |> fall_from(first)
    |> fall_from(second)
    |> clash_at({x, y})
    |> World.destroy(first)
    |> World.destroy(second)
  end

  defp fall_from(world, thrown) do
    %Instance{x: x, y: y, image_xscale: xscale} = World.fetch(world, thrown)

    {world, _dropped} =
      Weapon.spawn_dropped(world, {x, y}, -Gml.var(world, thrown, :hspd) * 0.25, -3, xscale)

    world
  end

  defp flying(world, match), do: Gml.var(world, match, :flyingWeapons, [])

  defp all_flying(world) do
    case World.object_index(world, "FlyingWeapon") do
      nil -> []
      object -> World.instances_of(world, object)
    end
  end

  defp coloured_flying?(world, thrown) do
    flying = World.object_index(world, "FlyingWeapon")
    object = World.fetch(world, thrown).object
    object != flying and World.descends?(world, object, flying)
  end

  defp on_stairs?(world, man) do
    case World.fetch(world, man) do
      %Instance{object: object, vars: vars} ->
        World.object(world, object).name in ["YellowPlayer", "OrangePlayer"] and
          Map.get(vars, :state) in [30, 31]

      nil ->
        false
    end
  end

  defp sprite_width(world, %Instance{sprite_index: sprite, image_xscale: xscale}) do
    case World.sprite(world, sprite) do
      nil -> 0
      definition -> elem(definition.size, 0) * xscale
    end
  end
end
