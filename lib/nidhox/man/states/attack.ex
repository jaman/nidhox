defmodule Nidhox.Man.States.Attack do
  @moduledoc """
  A fencer's attacking states, each step as `stateBehavior` runs them:

    * lunge (48): the stance's thrust (high 335, middle 337, low 336); a fallen opponent
      near is stomped. On stairs the thrust is the stairs lunge for its facing (up the
      stairs: high 352, low 353, middle 354; down: 251, 252, 253) and the sword is held
      along the stairs (`Nidhox.Man.Stairs.hold_sword/3`). Off the ground it grabs a
      ledge or falls; the throw combination throws (72); else the thrust plays once at
      0.7 a step, 0.175 while the swords touch, and then it stands: the unarmed stance
      (78) with fists, else fencing (29, or the stairs state for its opponent's side)
    * punch (49): drawn towards a near opponent (`Nidhox.Man.Push.punch_tween/2`); 292;
      off the ground it grabs a ledge or falls; played once at 1 a step, past frame 4 with
      fists a fallen opponent is stomped and attack punches again (55); then it stands
    * second punch (55): drawn the same way; 293 played once at 1, then the unarmed
      stance (78); off the ground it grabs a ledge or falls
    * high kick (45): 271; off the ground it grabs a ledge or falls; played once at 1,
      easing by 0.1, then the unarmed stance
    * sweep (70): 334; at frame 5 an opponent hanging (36) under 18 pixels across and
      under 32 below has its hands kicked loose (18); off the ground it grabs a ledge or
      falls; played once at 0.7, then it crawls (9)
    * throw (72): 349; off the ground it grabs a ledge or falls; played once at 0.7, past
      frame 3 still holding a sword it throws it (`Nidhox.Man.Weapon.throw/2`); then it
      runs (52)
    * throw in the air (73): 348; in the air played once at 0.7, past frame 3 it throws,
      steering (0.25, 0.1); then it falls (27); landing it gets up (33)
    * stomp (69): drawn in front (depth −10); past frame 10 with spine swords its weapon
      becomes a sword; 333; at frame 8 the snap (sound 145). An opponent at its height is
      drawn under it (no distance, 0.2), and unless already falling or stabbed is stomped
      (68); it faces away from the opponent's facing. Played once at 0.3, then it crawls
      (9)
    * catching (4): 231 played once at 0.3, then it fences
    * caught (5): 232 played once at 0.3, then it falls dead (26) turned around
  """

  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Bout.Variants
  alias Nidhox.Gml
  alias Nidhox.Man.{Actions, Physics, Push, Query, Stairs, State, Weapon}
  alias Nidhox.Objects.System

  @attack 5
  @thrusts %{1 => 335, 3 => 337, 2 => 336}
  @stair_lunges %{1 => {352, 251}, 2 => {353, 252}, 3 => {354, 253}}

  @doc "The world after fencer `self`'s step in attacking state `state`."
  @spec behave(World.t(), non_neg_integer(), integer()) :: World.t()
  def behave(world, self, 48) do
    stance = State.get(world, self, :stance)

    world =
      case Map.fetch(@thrusts, stance) do
        {:ok, sprite} -> State.pose(world, self, sprite)
        :error -> world
      end

    {_stomped, world} = Actions.try_stomp(world, self)
    world = along_stairs(world, self, stance)

    world =
      if State.on_ground?(world, self), do: world, else: Physics.grab_ledge_or_fall(world, self)

    if State.combo?(world, self) do
      State.go(world, self, 72)
    else
      slowed = if Gml.truthy?(State.get(world, self, :swordCollision)), do: 0.25, else: 1.0
      {past, world} = State.animate(world, self, 0.7 * slowed, false)
      if past, do: State.go(world, self, after_lunge(world, self)), else: world
    end
  end

  def behave(world, self, 49) do
    world = world |> Push.punch_tween(self) |> State.pose(self, 292)
    grounded(world, self, &punch/2)
  end

  def behave(world, self, 55) do
    world = world |> Push.punch_tween(self) |> State.pose(self, 293)
    grounded(world, self, &once_then_unarmed(&1, &2, 1))
  end

  def behave(world, self, 45) do
    world = State.pose(world, self, 271)

    grounded(world, self, fn world, self ->
      case State.animate(world, self, 1, false) do
        {true, world} -> State.go(world, self, 78)
        {false, world} -> Physics.apply_horizontal_friction(world, self, 0.1)
      end
    end)
  end

  def behave(world, self, 70) do
    world = world |> State.pose(self, 334) |> kick_hands(self)

    grounded(world, self, fn world, self ->
      {past, world} = State.animate(world, self, 0.7, false)
      if past, do: State.go(world, self, 9), else: world
    end)
  end

  def behave(world, self, 72) do
    world = State.pose(world, self, 349)

    grounded(world, self, fn world, self ->
      case State.animate(world, self, 0.7, false) do
        {true, world} -> State.go(world, self, 52)
        {false, world} -> throw_now(world, self)
      end
    end)
  end

  def behave(world, self, 73) do
    world = State.pose(world, self, 348)

    if State.on_ground?(world, self) do
      State.go(world, self, 33)
    else
      case State.animate(world, self, 0.7, false) do
        {true, world} -> State.go(world, self, 27)
        {false, world} -> world |> throw_now(self) |> Physics.move_left_and_right(self, 0.25, 0.1)
      end
    end
  end

  def behave(world, self, 69) do
    world =
      world
      |> World.update(self, &%{&1 | depth: -10})
      |> spine_sword(self)
      |> State.pose(self, 333)
      |> snap(self)
      |> stomp_down(self)

    {past, world} = State.animate(world, self, 0.3, false)
    if past, do: State.go(world, self, 9), else: world
  end

  def behave(world, self, 4) do
    {past, world} = world |> State.pose(self, 231) |> State.animate(self, 0.3, false)
    if past, do: State.go(world, self, 29), else: world
  end

  def behave(world, self, 5) do
    {past, world} = world |> State.pose(self, 232) |> State.animate(self, 0.3, false)

    if past,
      do:
        world
        |> State.go(self, 26)
        |> State.put(self, %{facingXScale: -State.get(world, self, :facingXScale)}),
      else: world
  end

  defp along_stairs(world, self, stance) do
    case Stairs.under(world, self) do
      nil ->
        world

      stairs ->
        {up, down} = Map.get(@stair_lunges, stance, {354, 253})
        sprite = if Stairs.facing_up?(world, self, stairs), do: up, else: down
        world |> State.pose(self, sprite) |> Stairs.hold_sword(self, stairs)
    end
  end

  defp after_lunge(world, self) do
    if State.type(world, self) == 1, do: 78, else: fencing_state(world, self)
  end

  defp fencing_state(world, self) do
    case Stairs.under(world, self) do
      nil -> 29
      stairs -> if facing_opponent(world, self) == Stairs.dir(world, stairs), do: 31, else: 30
    end
  end

  defp facing_opponent(world, self) do
    %Instance{x: x} = World.fetch(world, self)

    with other when other != nil <- Query.opponent(world, self),
         false <- Query.collapsing?(world, other),
         %Instance{x: other_x} when other_x != x <- World.fetch(world, other) do
      Gml.sign(other_x - x)
    else
      _ -> State.get(world, self, :facingXScale)
    end
  end

  defp grounded(world, self, fun) do
    if State.on_ground?(world, self),
      do: fun.(world, self),
      else: Physics.grab_ledge_or_fall(world, self)
  end

  defp punch(world, self) do
    case State.animate(world, self, 1, false) do
      {true, world} ->
        State.stand(world, self)

      {false, world} ->
        if State.get(world, self, :frame) > 4 + 1.0e-5 and State.type(world, self) == 1,
          do: punch_again(world, self),
          else: world
    end
  end

  defp punch_again(world, self) do
    {_stomped, world} = Actions.try_stomp(world, self)
    if State.pressed?(world, self, @attack), do: State.go(world, self, 55), else: world
  end

  defp once_then_unarmed(world, self, speed) do
    case State.animate(world, self, speed, false) do
      {true, world} -> State.go(world, self, 78)
      {false, world} -> world
    end
  end

  defp kick_hands(world, self) do
    with true <- Gml.round(State.get(world, self, :frame)) == 5,
         other when other != nil <-
           Query.by_player(world, Query.other_player(State.get(world, self, :playerIndex))),
         36 <- Gml.var(world, other, :state),
         %Instance{x: x, y: y} <- World.fetch(world, self),
         %Instance{x: ox, y: oy} <- World.fetch(world, other),
         true <- abs(x - ox) - 18 < -1.0e-5,
         true <- abs(y - oy) - 32 < -1.0e-5,
         true <- oy - y > 1.0e-5 do
      State.go(world, other, 18)
    else
      _ -> world
    end
  end

  defp throw_now(world, self) do
    if State.get(world, self, :frame) > 3 + 1.0e-5 and State.armed?(world, self),
      do: Weapon.throw(world, self),
      else: world
  end

  defp spine_sword(world, self) do
    if State.get(world, self, :frame) > 10 + 1.0e-5 and Variants.active?(world) and
         Gml.truthy?(System.get(world, :spineSwords)),
       do: Weapon.set_type(world, self, 2),
       else: world
  end

  defp snap(world, self) do
    if Float.floor(State.get(world, self, :frame) * 1.0) == 8,
      do: State.sound(world, self, 145),
      else: world
  end

  defp stomp_down(world, self) do
    with other when other != nil <- Query.opponent(world, self),
         true <- Push.y_close?(world, self, other) do
      world = Push.tween_dist(world, other, self, 0, 0.2)

      world =
        if Query.collapsing?(world, other) or Query.stabbed?(world, other),
          do: world,
          else: State.go(world, other, 68)

      State.put(world, self, %{facingXScale: -Gml.var(world, other, :facingXScale, 1)})
    else
      _ -> world
    end
  end
end
