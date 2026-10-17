defmodule Nidhox.Man.Weapon do
  @moduledoc """
  A fencer's weapon as the game's scripts handle it. The weapon is the fencer's
  `HeldWeapon` instance (`weapon`), its `type` 1 for fists and 2 for a sword.

    * `set_type/3` (`set_weapon_type`)
    * `x_pos/2` (`lookup_weapon_x_pos`): 8 pixels ahead of the fencer, 2 fewer going down
      stairs (31) and 5 more going up (30); lunging (48) or in the unarmed stance (78), the
      fist (`fistX`) or sword (`swordX`) reach for the frame, the sword's one more from
      high
    * `y_pos/2` (`lookup_weapon_y_pos`): fists 19 above the feet; a sword 6 above
      crouched, 34 in the air, by stance while fencing, lunging or on stairs (30, 31)
      (high 25, middle 19, low 12), 34 cocked to throw (54); 19 otherwise. The world comes
      back as given
    * `drop/2` (`drop_weapon`): a sword falls from where it is held as a
      `DroppedWeapon` with the fencer's speed (2 more upwards), and the fencer is left
      with its fists
    * `spawn_dropped/5` (`spawn_DroppedWeapon`): a `DroppedWeapon` at a point with a
      speed, its `image_xscale` held to ±1
    * `throw/2` (`throwSword`): the fencer lets go of its sword (fists), plays the throw
      (115, 114), faces its opponent and sends a flying sword of its colour from its
      weapon's reach, 25 above its feet, at a quarter of its own speed plus 4 ahead, with
      the weapon's type as the fists leave it; the flying sword follows the slope of stairs
      near the fencer; the fencer then moves 1.5 forward
    * `spawn_pickup/3` (`spawn_PickupContainer`): a sword lying on the ground
    * `try_pickup/2` (`tryToPickup`): the lying sword the fencer's body crosses that lies
      furthest left, the highest of those, is taken up — the weapon becomes its type, the
      sword is gone, `stance` is 2 and the pick-up sound (73) plays
  """

  alias Cauldron2D.GameMaker.{Collide, Instance, World}
  alias Nidhox.Gml
  alias Nidhox.Man.{Actions, Query, Stairs}

  @noone -4
  @fist_x [0, 1, 2, 3, 4, 4, 5, 5, 5, 5, 4, 4, 3, 0]
  @sword_x [3, 5, 7, 11, 13, 17, 17, 17, 17, 13, 11, 7, 5, 3, 0, 0]
  @reach 8
  @attacking [48, 78]
  @stance_y %{1 => 25, 3 => 19, 2 => 12}

  @doc "The world with fencer `man`'s weapon of type `type` (`set_weapon_type`)."
  @spec set_type(World.t(), non_neg_integer(), number()) :: World.t()
  def set_type(world, man, type) do
    case weapon(world, man) do
      nil -> world
      weapon -> Gml.put(world, weapon, %{type: type})
    end
  end

  @doc "Where across fencer `man`'s weapon is held (`lookup_weapon_x_pos`)."
  @spec x_pos(World.t(), non_neg_integer()) :: number()
  def x_pos(world, man) do
    %Instance{x: x, vars: vars} = World.fetch(world, man)
    facing = Map.get(vars, :facingXScale, 1)
    stairs = stairs_offset(Map.get(vars, :state))
    x + stairs * facing + reach(world, man, vars) * facing
  end

  @doc "`{y, world}`: where down fencer `man`'s weapon is held (`lookup_weapon_y_pos`)."
  @spec y_pos(World.t(), non_neg_integer()) :: {number(), World.t()}
  def y_pos(world, man) do
    %Instance{y: y} = World.fetch(world, man)
    {y - held_height(world, man), world}
  end

  @doc "`{dropped, world}`: fencer `man`'s sword let fall (`drop_weapon`); `nil` with fists."
  @spec drop(World.t(), non_neg_integer()) :: {non_neg_integer() | nil, World.t()}
  def drop(world, man) do
    with weapon when weapon != nil <- weapon(world, man),
         %Instance{vars: %{type: type}} = held when type != 1 <- World.fetch(world, weapon) do
      %Instance{vars: vars} = World.fetch(world, man)

      {world, dropped} =
        spawn_dropped(
          world,
          {held.x, held.y},
          Map.get(vars, :hspd, 0),
          Map.get(vars, :vspd, 0) - 2,
          held.image_xscale
        )

      world =
        world
        |> Gml.put(dropped, %{type: type})
        |> World.update(dropped, &%{&1 | image_xscale: held.image_xscale})
        |> set_type(man, 1)

      {dropped, world}
    else
      _fists -> {nil, world}
    end
  end

  @doc "`{world, id}`: a new `DroppedWeapon` at `{x, y}` moving `{hspd, vspd}` (`spawn_DroppedWeapon`)."
  @spec spawn_dropped(World.t(), {number(), number()}, number(), number(), number()) ::
          {World.t(), non_neg_integer()}
  def spawn_dropped(world, {x, y}, hspd, vspd, xscale) do
    {world, id} = World.create(world, World.object_index(world, "DroppedWeapon"), {x, y})

    world =
      world
      |> Gml.put(id, %{hspd: hspd, vspd: vspd})
      |> World.update(id, &%{&1 | image_xscale: Gml.clamp(xscale, -1, 1)})

    {world, id}
  end

  @doc "The world after fencer `man` throws its sword (`throwSword`)."
  @spec throw(World.t(), non_neg_integer()) :: World.t()
  def throw(world, man) do
    world =
      world
      |> set_type(man, 1)
      |> Actions.play(man, 115)
      |> Actions.play(man, 114)
      |> Query.face_opponent(man)

    type = World.fetch(world, weapon(world, man)).vars |> Map.get(:type, 1)
    vars = World.fetch(world, man).vars
    facing = Map.get(vars, :facingXScale, 1)
    hspd = Map.get(vars, :hspd, 0)
    {world, _flying} = spawn_flying(world, man, hspd * 0.25 + 4 * facing, type)
    step = if Gml.truthy?(facing), do: 1.5, else: -1.5
    Gml.put(world, man, %{hspd: Map.get(World.fetch(world, man).vars, :hspd, 0) + step})
  end

  @doc "`{world, id}`: a sword lying at `{x, y}` facing `xscale` (`spawn_PickupContainer`)."
  @spec spawn_pickup(World.t(), {number(), number()}, number()) :: {World.t(), non_neg_integer()}
  def spawn_pickup(world, {x, y}, xscale) do
    {world, id} = World.create(world, World.object_index(world, "PickupContainer"), {x, y})
    {World.update(world, id, &%{&1 | image_xscale: xscale}), id}
  end

  @doc "The world after fencer `man` takes up a lying sword its body crosses (`tryToPickup`)."
  @spec try_pickup(World.t(), non_neg_integer()) :: World.t()
  def try_pickup(world, man) do
    flesh = Gml.var(world, man, :flesh, @noone)

    case world
         |> pickups()
         |> Enum.filter(&crossing?(world, &1, flesh))
         |> leftmost_highest(world) do
      nil ->
        world

      pickup ->
        type = Gml.var(world, pickup, :type, 2)

        world
        |> set_type(man, type)
        |> World.destroy(pickup)
        |> Gml.put(man, %{stance: 2})
        |> Actions.play(man, 73)
    end
  end

  defp spawn_flying(world, man, hspd, type) do
    %Instance{y: y, vars: vars} = World.fetch(world, man)

    object =
      case Map.get(vars, :playerIndex) do
        1 -> World.object_index(world, "YellowFlyingWeapon")
        2 -> World.object_index(world, "OrangeFlyingWeapon")
        _other -> World.object_index(world, "FlyingWeapon")
      end

    {world, id} = World.create(world, object, {x_pos(world, man), y - 25})

    world =
      world
      |> Gml.put(id, %{hspd: hspd, type: type})
      |> follow_stairs(man, id, hspd)

    %Instance{x: fx, y: fy} = World.fetch(world, id)

    world =
      if block_at?(world, {fx, fy}),
        do: World.update(world, id, &%{&1 | x: &1.x - hspd}),
        else: world

    {world, id}
  end

  defp follow_stairs(world, man, flying, hspd) do
    case Stairs.near(world, man) do
      nil ->
        world

      stairs ->
        slope = Stairs.slope(world, stairs)
        %Instance{x: man_x} = World.fetch(world, man)

        world
        |> World.update(flying, &%{&1 | y: &1.y + slope * (&1.x - man_x)})
        |> Gml.put(flying, %{vspd: hspd * slope})
    end
  end

  defp leftmost_highest([], _world), do: nil

  defp leftmost_highest(pickups, world),
    do: Enum.min_by(pickups, &pickup_order(world, &1))

  defp pickup_order(world, pickup) do
    %Instance{x: x, y: y} = World.fetch(world, pickup)
    Gml.round(x * 100) * 1_000_000 + Gml.round(y * 100)
  end

  defp weapon(world, man) do
    case Gml.var(world, man, :weapon, @noone) do
      id when is_integer(id) and id >= 0 -> if World.fetch(world, id), do: id
      _none -> nil
    end
  end

  defp stairs_offset(31), do: -2
  defp stairs_offset(30), do: 5
  defp stairs_offset(_state), do: 0

  defp reach(world, man, vars) do
    if Map.get(vars, :state) in @attacking,
      do: @reach + attack_reach(world, man, vars),
      else: @reach
  end

  defp attack_reach(world, man, vars) do
    flesh = World.fetch(world, Map.get(vars, :flesh, @noone))
    frames = if flesh, do: frames(world, flesh.sprite_index), else: 1
    index = vars |> Map.get(:frame, 0) |> Gml.clamp(0, frames - 1) |> floor()

    case world |> World.fetch(weapon(world, man) || @noone) |> type_of() do
      1 -> Enum.at(@fist_x, index, 0)
      2 -> sword_reach(index, Map.get(vars, :stance))
      _other -> 0
    end
  end

  defp sword_reach(index, stance) do
    case Enum.at(@sword_x, index) do
      nil -> 0
      reach -> reach + if(stance == 1, do: 2, else: 1)
    end
  end

  defp type_of(nil), do: nil
  defp type_of(%Instance{vars: vars}), do: Map.get(vars, :type, 1)

  defp held_height(world, man) do
    %Instance{vars: vars} = World.fetch(world, man)
    stance = Map.get(vars, :stance, 3)

    case world |> World.fetch(weapon(world, man) || @noone) |> type_of() do
      2 -> sword_height(world, man, vars, stance)
      _fists -> 19
    end
  end

  defp sword_height(world, man, vars, stance) do
    cond do
      Query.crouched?(world, man) -> 6
      not Gml.truthy?(Map.get(vars, :onGround, 0)) -> 34
      true -> standing_height(Map.get(vars, :state), stance)
    end
  end

  defp standing_height(state, stance) when state in [29, 48, 31, 30],
    do: Map.get(@stance_y, stance, 19)

  defp standing_height(54, _stance), do: 34
  defp standing_height(_state, _stance), do: 19

  defp pickups(world) do
    case World.object_index(world, "PickupContainer") do
      nil -> []
      object -> World.instances_of(world, object)
    end
  end

  defp crossing?(world, pickup, flesh) do
    %Instance{x: x, y: y} = World.fetch(world, pickup)
    width = sprite_width(world, pickup)

    flesh != @noone and World.fetch(world, flesh) != nil and
      Collide.on_line(world, {x, y - 3}, {x + width, y - 3}, {:id, flesh}) != nil
  end

  defp block_at?(world, point) do
    case World.object_index(world, "Block") do
      nil -> false
      block -> Collide.at_point(world, point, block) != nil
    end
  end

  defp sprite_width(world, id) do
    %Instance{sprite_index: sprite, image_xscale: xscale} = World.fetch(world, id)

    case World.sprite(world, sprite) do
      nil -> 0
      definition -> elem(definition.size, 0) * xscale
    end
  end

  defp frames(world, sprite) do
    case World.sprite(world, sprite) do
      nil -> 1
      definition -> length(definition.frames)
    end
  end
end
