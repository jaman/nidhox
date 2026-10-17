defmodule Nidhox.Bout.Clash do
  @moduledoc """
  Swords meeting swords, and thrown swords meeting anything, as the game's scripts
  resolve them each match frame:

    * `weapon_to_weapon/2` (`check_HeldWeapon_to_HeldWeapon`): both fencers' swords
      shown and crossing — a disarm is tried (`disarm/2`), the two are pushed apart at 1
      a step, and each blade's tip jumps by its gap to the other's, both measured from the blade's
      height less the fencer's `stairYModifier`, plus `random_range(−1,
      1)`; `{clashed, world}`
    * `disarm/2` (`try_to_disarm`): the fencer whose sword moved up or down in the
      fencer's own frame (`weaponYRel`) this step — only one of them — disarms the other when the blades are closer across than the
      other's sword length × 1.75 (× 1.65 unless the other is lunging): a clang (53), the clash point, a flash, the other's sword knocked loose
      (2 back from the disarmer's facing, 4 up) and the other disarmed (13)
    * `held_to_flying/3` (`check_HeldWeapon_to_FlyingWeapons(weapon)`): a sword shown
      crossing a thrown sword knocks it down: its tip drops to 5 below the blade's height
      (less the fencer's `stairYModifier`), a flash and a clash, and
      the thrown sword falls as a `DroppedWeapon` (a quarter of its speed, 3 up)
    * `flying_to_flesh/2` (`check_FlyingWeapon_to_FleshCollisionMask(flesh)`): a thrown
      sword of the other player reaching a fencer not entering, stabbed or falling
      strikes it (98) and is gone, unless the room is the online lobby (`weapons_harmless?/1`); `{struck, world}`
    * `flying_to_flying/2` (`check_FlyingWeapons_to_FlyingWeapons`): two thrown swords
      in a row of the match's list meeting both fall and clash
    * `collapse_by_flying/2` (`collapsePlayerByFlying`): the struck fencer loses its
      sword and, from frame 0, is hit in the air (37) or standing (39)
    * `clash_at/2` (`clashXY`): the `ClashPosition` moved to the point and a clash (107,
      108 or 109) heard there
    * `priority/2` (`getPriority`): where the fencer's state stands in
      `System.priorityList`, 99999999 when not in it; `pushable?/2` (`isPushable`):
      fencing (29, 30, 31) or unarmed (78)
  """

  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Bout.{Overlap, Sound}
  alias Nidhox.Gml
  alias Nidhox.Man.{Query, State, Weapon}
  alias Nidhox.Objects.{Challenge, Effects, System}

  @noone -4
  @clang 53
  @clashes [107, 108, 109]
  @struck 98
  @unlisted 99_999_999
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
      |> Enum.reduce(world, &knock_down_if_held(&2, weapon, &1))
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
         false <- Query.collapsing?(world, man),
         false <- weapons_harmless?(world) do
      player = Gml.var(world, man, :playerIndex)

      world
      |> all_flying()
      |> Enum.reduce({false, world}, &strike_flesh(&2, &1, player, flesh))
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

  @doc "Whether swords hurt nobody in the current room: the online lobby (`weaponsHarmless`)."
  @spec weapons_harmless?(World.t()) :: boolean()
  def weapons_harmless?(%World{data: data, room: room}),
    do: Enum.at(data.rooms, room).name == "rOnlineLobby"

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
    do: World.fetch(world, man) != nil and Gml.var(world, man, :state) in [29, 30, 31, 78]

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
    own_y = lifted_y(world, sword)
    other_y = lifted_y(world, other)
    own_tip = Gml.var(world, sword, :tipY) - own_y
    other_tip = Gml.var(world, other, :tipY) - other_y
    {wobble, world} = Gml.random_range(world, -1, 1)
    Gml.put(world, sword, %{tipY: own_y + (other_tip - own_tip) + wobble})
  end

  defp lifted_y(world, sword) do
    %Instance{y: y} = World.fetch(world, sword)
    y + Gml.var(world, Gml.var(world, sword, :mother, @noone), :stairYModifier, 0)
  end

  defp moved?(world, man),
    do:
      not Gml.eq?(
        Gml.var(world, man, :weaponYRel, 0),
        Gml.var(world, man, :weaponYRelPrevious, 0)
      )

  defp try_disarm(world, disarmer, victim) do
    disarmer_sword = World.fetch(world, weapon(world, disarmer))
    victim_sword = World.fetch(world, weapon(world, victim))
    apart = abs(disarmer_sword.x - victim_sword.x)
    reach = if Gml.var(world, victim, :state) == 48, do: 1.75, else: 1.65

    if apart < abs(sprite_width(world, victim_sword) * reach) - 1.0e-5 do
      %Instance{x: vx, y: vy} = World.fetch(world, victim)
      %Instance{x: dx, y: dy} = World.fetch(world, disarmer)

      world =
        world
        |> Challenge.move_completed(
          Gml.var(world, disarmer, :playerIndex),
          @parry,
          {dx, dy - @popup_rise}
        )
        |> Sound.play(@clang, {vx, vy})
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

  defp knock_down_if_held(world, weapon, thrown) do
    if World.fetch(world, thrown) != nil and coloured_flying?(world, thrown) and
         Overlap.held?(world, weapon, thrown),
       do: knock_down(world, weapon, thrown),
       else: world
  end

  defp strike_flesh({struck, world}, thrown, player, flesh) do
    if World.fetch(world, thrown) != nil and Gml.var(world, thrown, :playerIndex) != player and
         Overlap.flying?(world, thrown, flesh),
       do: {true, struck_by(world, thrown)},
       else: {struck, world}
  end

  defp struck_by(world, thrown) do
    %Instance{x: x, y: y} = World.fetch(world, thrown)

    world
    |> Challenge.move_completed(
      Gml.var(world, thrown, :playerIndex),
      @throw,
      {x, y - @popup_rise}
    )
    |> Sound.play(@struck, {x, y})
    |> World.destroy(thrown)
  end

  defp knock_down(world, weapon, thrown) do
    %Instance{x: x, y: y, image_xscale: xscale} = World.fetch(world, thrown)
    %Instance{x: weapon_x, y: weapon_y} = World.fetch(world, weapon)
    blocker = Gml.var(world, Gml.var(world, weapon, :mother, @noone), :playerIndex)

    world
    |> Challenge.move_completed(blocker, @dodge, {weapon_x, weapon_y - @popup_rise})
    |> Gml.put(weapon, %{tipY: lifted_y(world, weapon) + 5})
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

    %Instance{x: later_x, y: later_y} = World.fetch(world, later)

    world
    |> Challenge.move_completed(Gml.var(world, later, :playerIndex), @dodge, {later_x, later_y})
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

  defp sprite_width(world, %Instance{sprite_index: sprite, image_xscale: xscale}) do
    case World.sprite(world, sprite) do
      nil -> 0
      definition -> elem(definition.size, 0) * xscale
    end
  end
end
