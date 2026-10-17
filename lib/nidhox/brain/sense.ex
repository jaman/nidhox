defmodule Nidhox.Brain.Sense do
  @moduledoc """
  What the computer player reads off the fencers, as the game's AI scripts read it.
  Fencers are instance ids; `-4` (`noone`) stands for no fencer.

    * `present?/1`: whether an instance id is set (above 0.5, as `if (instance)` reads)
    * `holding_high_ground?/2` (`playerHoldingHighGround`): the fencer stands still
      (`vspd` 0) ahead of its opponent while leading, or with nobody leading, and is more
      than 8 pixels above it or the opponent is moving up or down
    * `stuck_in_low_ground?/2` (`playerStuckInLowGround`): the opponent holds the high
      ground over it
    * `separated_by_log?/3` (`menSeparatedByLog`): one is in a log while the other is on
      it, or only one of them is on a log
    * `in_front?/3` (`manInFrontOfMan(a, b)`): `b` leads and `a` is past `b` on `b`'s way
      to its goal (player 1 to the right, player 2 to the left)
    * `running_to_goal?/2` (`manRunningTowardsGoalSide`): moving towards its own goal
    * `on_wall?/2` (`playerIsOnWall`): running up a wall (53), on one (62) or hanging
      from an edge (36)
    * `jumping?/2` (`playerIsJumping`): in states 43, 44, 18, 19, 14, 15, 27, 10 or 11
    * `fencing_state?/1` (`isFencingState`): state 29, 30 or 31
    * `fencing?/2` (`isOnGroundFencingInSomeWay`): on the ground with a sword, in a
      fencing state, lunging (48) or at least not ducking
    * `under_low_area?/2` (`playerUnderLowArea`): a `Block` 32 pixels above it
    * `dangerous_sword/2` (`dangerousFlyingSwordNearby`): the first of the other
      player's thrown swords within 64 pixels of the fencer's chest (13 above its feet)
      and within 32 of it up or down; `-4` for none
    * `facing/2` (`getFacingFromXtoX`): `-1`, `0` or `1` from one x towards another
  """

  alias Cauldron2D.GameMaker.{Collide, Instance, World}
  alias Nidhox.Gml
  alias Nidhox.Man.Query
  alias Nidhox.Objects.Match

  @noone -4
  @high_ground 8
  @wall_states [53, 62, 36]
  @jump_states [43, 44, 18, 19, 14, 15, 27, 10, 11]
  @fencing_states [29, 30, 31]
  @lunging 48
  @sword 2
  @low_area 32
  @chest 13
  @sword_reach 64
  @sword_height 32
  @thrown %{1 => "OrangeFlyingWeapon", 2 => "YellowFlyingWeapon"}

  @doc "Whether instance id `id` is set."
  @spec present?(number()) :: boolean()
  def present?(id), do: Gml.truthy?(id)

  @doc "Whether fencer `man` holds the high ground (`playerHoldingHighGround`)."
  @spec holding_high_ground?(World.t(), number()) :: boolean()
  def holding_high_ground?(%World{} = world, man) do
    leader = Match.get(world, :leadingPlayerIndex)
    other = if present?(man), do: Query.opponent(world, man) || @noone, else: @noone

    present?(man) and Gml.eq?(Gml.var(world, man, :vspd), 0) and not Gml.eq?(leader, man) and
      present?(other) and (in_front?(world, man, other) or Gml.eq?(leader, 0)) and
      above_or_moving?(world, man, other)
  end

  @doc "Whether fencer `man`'s opponent holds the high ground (`playerStuckInLowGround`)."
  @spec stuck_in_low_ground?(World.t(), number()) :: boolean()
  def stuck_in_low_ground?(%World{} = world, man) do
    other =
      Query.by_player(world, Query.other_player(Gml.var(world, man, :playerIndex))) || @noone

    holding_high_ground?(world, other)
  end

  @doc "Whether a log separates fencers `a` and `b` (`menSeparatedByLog`)."
  @spec separated_by_log?(World.t(), number(), number()) :: boolean()
  def separated_by_log?(%World{} = world, a, b) do
    a_in = Gml.var(world, a, :inLog)
    a_on = Gml.var(world, a, :onLog)
    b_in = Gml.var(world, b, :inLog)
    b_on = Gml.var(world, b, :onLog)

    (Gml.eq?(a_in, 1) and Gml.eq?(b_on, 1)) or (Gml.eq?(a_on, 1) and Gml.eq?(b_in, 1)) or
      not Gml.eq?(a_on, b_on)
  end

  @doc "Whether fencer `b` leads and fencer `a` is past `b` towards `b`'s goal (`manInFrontOfMan`)."
  @spec in_front?(World.t(), number(), number()) :: boolean()
  def in_front?(%World{} = world, a, b) do
    with %Instance{x: ax} <- World.fetch(world, a),
         %Instance{x: bx} <- World.fetch(world, b),
         player = Gml.var(world, b, :playerIndex),
         true <- Gml.eq?(player, Match.get(world, :leadingPlayerIndex)) do
      if Gml.eq?(player, 1), do: Gml.gt?(ax, bx), else: Gml.lt?(ax, bx)
    else
      _ -> false
    end
  end

  @doc "Whether fencer `man` is moving towards its own goal (`manRunningTowardsGoalSide`)."
  @spec running_to_goal?(World.t(), number()) :: boolean()
  def running_to_goal?(%World{} = world, man) do
    hspd = Gml.var(world, man, :hspd)

    case Gml.var(world, man, :playerIndex) do
      1 -> Gml.gt?(hspd, 0)
      2 -> Gml.lt?(hspd, 0)
      _other -> false
    end
  end

  @doc "Whether fencer `man` is on a wall (`playerIsOnWall`)."
  @spec on_wall?(World.t(), number()) :: boolean()
  def on_wall?(%World{} = world, man), do: Gml.var(world, man, :state, -1) in @wall_states

  @doc "Whether fencer `man` is in the air from a jump (`playerIsJumping`)."
  @spec jumping?(World.t(), number()) :: boolean()
  def jumping?(%World{} = world, man), do: Gml.var(world, man, :state, -1) in @jump_states

  @doc "Whether `state` is a fencing state (`isFencingState`): 29, 30 or 31."
  @spec fencing_state?(number()) :: boolean()
  def fencing_state?(state), do: state in @fencing_states

  @doc "Whether fencer `man` stands fencing in some way (`isOnGroundFencingInSomeWay`)."
  @spec fencing?(World.t(), number()) :: boolean()
  def fencing?(%World{} = world, man) do
    state = Gml.var(world, man, :state)

    Gml.truthy?(Gml.var(world, man, :onGround)) and weapon_type(world, man) == @sword and
      (fencing_state?(state) or state == @lunging or not Query.ducking?(world, man))
  end

  @doc "Whether a `Block` is 32 pixels above fencer `man` (`playerUnderLowArea`)."
  @spec under_low_area?(World.t(), number()) :: boolean()
  def under_low_area?(%World{} = world, man) do
    with %Instance{x: x, y: y} <- World.fetch(world, man),
         block when is_integer(block) <- World.object_index(world, "Block") do
      Collide.meeting?(world, man, {x, y - @low_area}, block)
    else
      _ -> false
    end
  end

  @doc "The other player's thrown sword close to fencer `man`, `-4` for none (`dangerousFlyingSwordNearby`)."
  @spec dangerous_sword(World.t(), number()) :: number()
  def dangerous_sword(%World{} = world, man) do
    %Instance{x: x, y: y} = World.fetch(world, man)
    chest = {x, y - @chest}
    thrown = Map.get(@thrown, Gml.var(world, man, :playerIndex), Map.fetch!(@thrown, 2))

    world
    |> Gml.all(thrown)
    |> Enum.find(@noone, fn sword ->
      %Instance{x: sx, y: sy} = World.fetch(world, sword)

      Gml.lt?(distance(chest, {sx, sy}), @sword_reach) and
        Gml.lt?(abs(y - @chest - sy), @sword_height)
    end)
  end

  @doc "`-1`, `0` or `1` from `from_x` towards `to_x` (`getFacingFromXtoX`)."
  @spec facing(number(), number()) :: number()
  def facing(from_x, to_x), do: Gml.clamp(100_000 * (to_x - from_x), -1, 1)

  @doc "Fencer `man`'s weapon type: 1 fists, 2 sword, 0 without a weapon."
  @spec weapon_type(World.t(), number()) :: number()
  def weapon_type(%World{} = world, man),
    do: Gml.var(world, Gml.var(world, man, :weapon, @noone), :type)

  @doc "The distance between two points (`point_distance`)."
  @spec distance({number(), number()}, {number(), number()}) :: float()
  def distance({x1, y1}, {x2, y2}), do: :math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))

  defp above_or_moving?(world, man, other) do
    Gml.lt?(World.fetch(world, man).y, World.fetch(world, other).y - @high_ground) or
      not Gml.eq?(Gml.var(world, other, :vspd), 0)
  end
end
