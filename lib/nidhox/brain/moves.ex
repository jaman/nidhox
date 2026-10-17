defmodule Nidhox.Brain.Moves do
  @moduledoc """
  The computer player's shared moves, pressing a `Brain`'s buttons
  (`Nidhox.Brain.Buttons`) as the game's AI scripts do. `self` is the `Brain`; its
  `playerIndex`, `player`, `opponent`, `opponentDist`, `stateCounter` and `beat` are
  read as they stand.

    * `jump_over/3` (`aiPlayerJumpOverObstaclesAndGaps`): mid-jump, holds jump and keeps
      going the way it moves. Running (left or right held while moving that way), it
      jumps at a log it would otherwise run into while a log separates it from its
      opponent, at a wall 64 pixels ahead (4 above its feet), and at a gap with no ground
      32 pixels ahead; otherwise it lets go of jump
    * `ideal_stance/4` (`idealStance(man, stance)`): out of a fencing state (29, 30, 31)
      every button let go; in one, up or down towards `stance` (1 high, 3 middle, 2 low)
    * `guard_against/4` (`playerGuardAgainst`): up or down towards the height of the
      opponent's sword; whether the two swords are within 4 pixels of each other
    * `look_for_opening/4` (`playerLookForOpeningAgainst`): with the swords at different
      heights and neither ducking, now and then (20 in 100, past 8 pixels apart) a step
      towards the middle, and whether an opening is there; against a ducking opponent, down
      (by turns, to keep pressing it); otherwise a random change of height
    * `footwork/2`: on every half beat of the state (70 in 100), back when closer than
      24, forward when further than 64, else either; forward again when the opponent
      holds no sword; whether it stepped
    * `closest_weapon/3` (`playerFindClosestWeaponSafeFrom(a, b)`): the nearest sword on
      the ground (`PickupContainer`, the first twelve) on screen and in the room that is
      not at `b`'s sword point and lies where `a` can reach it before `b`; `-4` for none.
      Without `b`, simply the nearest
  """

  alias Cauldron2D.GameMaker.{Collide, Instance, World}
  alias Nidhox.Bout.{Camera, Input}
  alias Nidhox.Brain.{Buttons, Clock, Sense}
  alias Nidhox.Gml
  alias Nidhox.Man.{Physics, Query}

  @noone -4
  @left 0
  @right 1
  @up 2
  @down 3
  @jump 4
  @forward 8
  @back 9
  @high 1
  @low 2
  @middle 3
  @sword 2
  @wall_ahead 64
  @wall_height -4
  @gap_ahead 32
  @gap_depth 6
  @log_height 4
  @guard_close 4
  @opening_apart 8
  @opening_chance 20
  @footwork_chance 70
  @too_close 24
  @too_far 64
  @pickups 12
  @sword_point 12
  @point_close 16

  @doc "The world with `Brain` `self` steering fencer `man` over walls and gaps (`aiPlayerJumpOverObstaclesAndGaps`)."
  @spec jump_over(World.t(), non_neg_integer(), number()) :: World.t()
  def jump_over(%World{} = world, self, man) do
    hspd = Gml.var(world, man, :hspd)

    cond do
      Sense.jumping?(world, man) -> keep_jumping(world, self, hspd)
      Gml.eq?(hspd, 0) -> world
      true -> run_over(world, self, man, running_way(world, man, hspd))
    end
  end

  @doc "The world with `Brain` `self` moving fencer `man`'s stance towards `stance` (`idealStance`)."
  @spec ideal_stance(World.t(), non_neg_integer(), number(), 1 | 2 | 3) :: World.t()
  def ideal_stance(%World{} = world, self, man, stance) do
    if Sense.fencing_state?(Gml.var(world, man, :state)),
      do: towards(world, self, Gml.var(world, man, :stance), stance),
      else: Buttons.release_all(world, self, [@up, @down, @left, @right, @jump, 5])
  end

  @doc "`{level, world}`: `Brain` `self` matching the height of `other`'s sword with `man`'s (`playerGuardAgainst`)."
  @spec guard_against(World.t(), non_neg_integer(), number(), number()) :: {boolean(), World.t()}
  def guard_against(%World{} = world, self, man, other) do
    mine = sword_y(world, man)
    theirs = sword_y(world, other)
    world = if Gml.lt?(theirs, mine), do: Buttons.press(world, self, @up), else: world

    world =
      if Gml.gt?(theirs, mine) and Gml.var(world, man, :stance) != @low,
        do: Buttons.press(world, self, @down),
        else: world

    {Gml.lt?(abs(theirs - mine), @guard_close), world}
  end

  @doc "`{opening, world}`: `Brain` `self` looking for a way past `other` with `man` (`playerLookForOpeningAgainst`)."
  @spec look_for_opening(World.t(), non_neg_integer(), number(), number()) ::
          {boolean(), World.t()}
  def look_for_opening(%World{} = world, self, man, other) do
    mine = sword_y(world, man)
    theirs = sword_y(world, other)

    if not Gml.eq?(mine, theirs) and not Query.ducking?(world, man) and
         not Query.ducking?(world, other),
       do: heights_apart(world, self, man, abs(theirs - mine)),
       else: {false, against_ducking(world, self, man, other)}
  end

  @doc "`{stepped, world}`: `Brain` `self` stepping back and forth on the half beat (`footwork`)."
  @spec footwork(World.t(), non_neg_integer()) :: {boolean(), World.t()}
  def footwork(%World{} = world, self) do
    with true <- Clock.every?(world, self, :stateCounter, 0.5),
         {true, world} <- Gml.prob(world, @footwork_chance) do
      {step, world} = footwork_way(world, Gml.var(world, self, :opponentDist))
      world = Buttons.press(world, self, step)
      other = Gml.var(world, self, :opponent, @noone)

      if Sense.weapon_type(world, other) != @sword,
        do: {true, Buttons.press(world, self, @forward)},
        else: {true, world}
    else
      {false, world} -> {false, world}
      false -> {false, world}
    end
  end

  @doc "The nearest safe sword on the ground for fencer `a` away from fencer `b`, `-4` for none (`playerFindClosestWeaponSafeFrom`)."
  @spec closest_weapon(World.t(), number(), number()) :: number()
  def closest_weapon(%World{} = world, a, b) do
    %Instance{x: ax, y: ay} = World.fetch(world, a)

    if Sense.present?(b) do
      world
      |> Gml.all("PickupContainer")
      |> Enum.take(@pickups)
      |> Enum.sort_by(&abs(World.fetch(world, &1).x - ax))
      |> first_safe(world, a, b)
    else
      Gml.nearest(world, {ax, ay}, "PickupContainer") || @noone
    end
  end

  defp keep_jumping(world, self, hspd) do
    world = Buttons.press(world, self, @jump)

    cond do
      Gml.gt?(hspd, 0) -> Buttons.press(world, self, @right)
      Gml.lt?(hspd, 0) -> Buttons.press(world, self, @left)
      true -> world
    end
  end

  defp running_way(world, man, hspd) do
    way = Gml.clamp(hspd * 1000, -1, 1)
    player = Gml.var(world, man, :playerIndex)

    cond do
      Gml.eq?(way, -1) and not Input.down?(world, man, player, @left) -> 0
      Gml.eq?(way, 1) and not Input.down?(world, man, player, @right) -> 0
      true -> way
    end
  end

  defp run_over(world, self, man, way) do
    cond do
      Physics.check_below?(world, man, @wall_ahead * way, @wall_height) or
          log_ahead?(world, man, way) ->
        Buttons.press(world, self, @jump)

      Physics.check_below?(world, man, @gap_ahead * way, @gap_depth) ->
        Buttons.release(world, self, @jump)

      true ->
        Buttons.press(world, self, @jump)
    end
  end

  defp log_ahead?(world, man, way) do
    other =
      Query.by_player(world, Query.other_player(Gml.var(world, man, :playerIndex))) || @noone

    %Instance{x: x, y: y} = World.fetch(world, man)

    Sense.present?(other) and Sense.separated_by_log?(world, man, other) and
      not Gml.truthy?(Gml.var(world, man, :inLog)) and
      inside_log?(world, {x + @wall_ahead * way, y - @log_height})
  end

  defp inside_log?(world, point) do
    case World.object_index(world, "InsideLogArea") do
      nil -> false
      object -> Collide.at_point(world, point, object) != nil
    end
  end

  defp towards(world, self, @high, @middle), do: Buttons.press(world, self, @down)
  defp towards(world, self, @low, @middle), do: Buttons.press(world, self, @up)

  defp towards(world, self, stance, @low) when stance in [@high, @middle],
    do: Buttons.press(world, self, @down)

  defp towards(world, self, stance, @high) when stance in [@low, @middle],
    do: Buttons.press(world, self, @up)

  defp towards(world, _self, _stance, _target), do: world

  defp sword_y(world, man) do
    case World.fetch(world, Gml.var(world, man, :weapon, @noone)) do
      %Instance{y: y} -> y
      nil -> 0
    end
  end

  defp heights_apart(world, self, man, apart) do
    with true <- Gml.gt?(apart, @opening_apart),
         {true, world} <- Gml.prob(world, @opening_chance) do
      case Gml.var(world, man, :stance) do
        @high -> {true, Buttons.press(world, self, @down)}
        @low -> {false, Buttons.press(world, self, @up)}
        _middle -> {true, world}
      end
    else
      {false, world} -> {true, world}
      false -> {true, world}
    end
  end

  defp against_ducking(world, self, man, other) do
    cond do
      Query.ducking?(world, other) and Query.ducking?(world, man) ->
        Buttons.release(world, self, @down)

      Query.ducking?(world, other) ->
        keep_pressing_down(world, self, man)

      Query.ducking?(world, man) ->
        Buttons.release(world, self, @down)

      true ->
        change_height(world, self, Gml.var(world, man, :stance))
    end
  end

  defp keep_pressing_down(world, self, man) do
    cond do
      Gml.var(world, man, :stance) == @low -> world
      Buttons.down?(world, self, @down) -> Buttons.release(world, self, @down)
      true -> Buttons.press(world, self, @down)
    end
  end

  defp change_height(world, self, @high), do: Buttons.press(world, self, @down)
  defp change_height(world, self, @low), do: Buttons.press(world, self, @up)

  defp change_height(world, self, @middle) do
    {down, world} = Gml.choose(world, [0, 1])
    Buttons.press(world, self, if(down == 1, do: @down, else: @up))
  end

  defp change_height(world, _self, _stance), do: world

  defp footwork_way(world, distance) do
    cond do
      Gml.lt?(distance, @too_close) -> {@back, world}
      Gml.gt?(distance, @too_far) -> {@forward, world}
      true -> Gml.choose(world, [@forward, @back])
    end
  end

  defp first_safe(pickups, world, a, b) do
    Enum.reduce_while(pickups, @noone, fn pickup, _none ->
      cond do
        out_of_reach?(world, pickup, b) -> {:halt, @noone}
        reachable_first?(world, pickup, a, b) -> {:halt, pickup}
        true -> {:cont, @noone}
      end
    end)
  end

  defp out_of_reach?(world, pickup, b) do
    %Instance{x: x, y: y} = World.fetch(world, pickup)
    {room_width, _height} = Enum.at(world.data.rooms, world.room).size
    width = Camera.width(world)

    Gml.gt?(abs(Camera.left(world) - x) - width, 0) or
      Gml.gt?(abs(Camera.right(world) - x) - width, 0) or
      Gml.lt?(x, 0) or Gml.gt?(x, room_width) or at_sword_point?(world, {x, y}, b)
  end

  defp at_sword_point?(world, point, b) do
    weapon = Gml.var(world, b, :weapon, @noone)

    with @sword <- Sense.weapon_type(world, b),
         %Instance{x: wx, y: wy} <- World.fetch(world, weapon) do
      facing = Gml.var(world, b, :facingXScale)

      Gml.lt?(
        Sense.distance(point, {wx + facing * @sword_point, wy + facing * @sword_point}),
        @point_close
      )
    else
      _ -> false
    end
  end

  defp reachable_first?(world, pickup, a, b) do
    x = World.fetch(world, pickup).x
    ax = World.fetch(world, a).x
    bx = World.fetch(world, b).x

    (Gml.lt?(ax, x) and Gml.gt?(bx, x)) or (Gml.lt?(ax, x) and Gml.lt?(bx, ax)) or
      (Gml.gt?(ax, x) and Gml.gt?(bx, ax)) or (Gml.gt?(ax, x) and Gml.lt?(bx, x))
  end
end
