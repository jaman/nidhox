defmodule Nidhox.Man.States.Attack do
  @moduledoc """
  A fencer's attacking states, each step as `stateBehavior` runs them:

    * lunge (48): the stance's thrust (high 170, middle 172, low 171); a fallen opponent
      near is stomped; off the ground it grabs a ledge or falls; the throw combination
      throws (72); else the thrust plays once at 0.7 a step, 0.175 while the swords touch,
      and then it stands
    * punch (49): drawn towards a near opponent (`Nidhox.Man.Push.punch_tween/2`); 164;
      off the ground it grabs a ledge or falls; played once at 1 a step, past frame 4 with
      fists a fallen opponent is stomped and attack punches again (55); then it stands
    * second punch (55): drawn the same way; 165 played once at 1, then the unarmed
      stance (78); off the ground it grabs a ledge or falls
    * high kick (45): 163; off the ground it grabs a ledge or falls; played once at 1,
      easing by 0.1, then the unarmed stance
    * sweep (70): 169; at frame 5 an opponent hanging (36) under 18 pixels across and
      under 32 below has its hands kicked loose (18); off the ground it grabs a ledge or
      falls; played once at 0.7, then it crawls (9)
    * throw (72): 174; off the ground it grabs a ledge or falls; played once at 0.7, past
      frame 3 still holding a sword it throws it (`Nidhox.Man.Weapon.throw/2`); then it
      runs (52)
    * throw in the air (73): 173; in the air played once at 0.7, past frame 3 it throws,
      steering (0.25, 0.1); then it falls (27); landing it gets up (33)
    * stomp (69): drawn in front (depth −10); past frame 10 with spine swords its weapon
      becomes a sword; 234; at frame 8 the snap (2). An opponent at its height is drawn
      under it (no distance, 0.2), and unless already falling or stabbed is stomped (68);
      it faces away from the opponent's facing. Played once at 0.3, then it crawls (9)
    * catching (4): 159 played once at 0.3, then it fences
    * caught (5): 160 played once at 0.3, then it falls dead (26) turned around
  """

  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Bout.Variants
  alias Nidhox.Gml
  alias Nidhox.Man.{Actions, Physics, Push, Query, State, Weapon}
  alias Nidhox.Objects.System

  @attack 5
  @thrusts %{1 => 170, 3 => 172, 2 => 171}

  @doc "The world after fencer `self`'s step in attacking state `state`."
  @spec behave(World.t(), non_neg_integer(), integer()) :: World.t()
  def behave(world, self, 48) do
    world = State.pose(world, self, Map.get(@thrusts, State.get(world, self, :stance), 172))
    {_stomped, world} = Actions.try_stomp(world, self)

    world =
      if State.on_ground?(world, self), do: world, else: Physics.grab_ledge_or_fall(world, self)

    if State.combo?(world, self) do
      State.go(world, self, 72)
    else
      slowed = if Gml.truthy?(State.get(world, self, :swordCollision)), do: 0.25, else: 1.0
      {past, world} = State.animate(world, self, 0.7 * slowed, false)
      if past, do: State.stand(world, self), else: world
    end
  end

  def behave(world, self, 49) do
    world = world |> Push.punch_tween(self) |> State.pose(self, 164)
    grounded(world, self, &punch/2)
  end

  def behave(world, self, 55) do
    world = world |> Push.punch_tween(self) |> State.pose(self, 165)
    grounded(world, self, &once_then_unarmed(&1, &2, 1))
  end

  def behave(world, self, 45) do
    world = State.pose(world, self, 163)

    grounded(world, self, fn world, self ->
      case State.animate(world, self, 1, false) do
        {true, world} -> State.go(world, self, 78)
        {false, world} -> Physics.apply_horizontal_friction(world, self, 0.1)
      end
    end)
  end

  def behave(world, self, 70) do
    world = world |> State.pose(self, 169) |> kick_hands(self)

    grounded(world, self, fn world, self ->
      {past, world} = State.animate(world, self, 0.7, false)
      if past, do: State.go(world, self, 9), else: world
    end)
  end

  def behave(world, self, 72) do
    world = State.pose(world, self, 174)

    grounded(world, self, fn world, self ->
      case State.animate(world, self, 0.7, false) do
        {true, world} -> State.go(world, self, 52)
        {false, world} -> throw_now(world, self)
      end
    end)
  end

  def behave(world, self, 73) do
    world = State.pose(world, self, 173)

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
      |> State.pose(self, 234)
      |> snap(self)
      |> stomp_down(self)

    {past, world} = State.animate(world, self, 0.3, false)
    if past, do: State.go(world, self, 9), else: world
  end

  def behave(world, self, 4) do
    {past, world} = world |> State.pose(self, 159) |> State.animate(self, 0.3, false)
    if past, do: State.go(world, self, 29), else: world
  end

  def behave(world, self, 5) do
    {past, world} = world |> State.pose(self, 160) |> State.animate(self, 0.3, false)

    if past,
      do:
        world
        |> State.go(self, 26)
        |> State.put(self, %{facingXScale: -State.get(world, self, :facingXScale)}),
      else: world
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
      do: State.sound(world, self, 2),
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
