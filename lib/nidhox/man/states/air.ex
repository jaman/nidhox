defmodule Nidhox.Man.States.Air do
  @moduledoc """
  A fencer's airborne states, each step as `stateBehavior` runs them:

    * jump (43): moving at 1 or faster across, the jump (282) up to 2, else forward
      (283, played once at 0.6) while `|vspd|` is 4 or more, else the roll (284, cycling
      at 0.8); slower, straight up (285, played once at 1). With a sword the throw
      combination throws in the air (73). Jump let go cuts `vspd` to 0.96 of itself.
      Falling, it drops (18); rising, up held with a sword, throws allowed, readies a throw
      in the air (19), attack dive-kicks (14) unless dive kicks are off, else it steers
      (`moveLeftAndRightAccelFric` 0.25, 0.1)
    * jump cocked (44): frame 0 of 348; rising, letting go of up jumps on (18), attack
      throws in the air (73), else it steers and faces its opponent; falling it drops
      cocked (19)
    * drop (18): 262; past the lowest platform, a cry (sound 57) and a fall (27). With a
      sword the throw combination throws in the air (73). Cycling at 0.4: in the air up
      held with a sword, throws allowed, readies a throw (19, sound 102), attack dive-kicks
      (14) unless dive kicks are off, else it steers; landing, a crawl or slide holding
      down, else a thud (sound 71) and the landing skid (16)
    * drop cocked (19): frame 0 of 348; in the air letting go of up drops (18), attack
      throws (73), else it steers and faces its opponent; landing runs cocked (54)
    * fall head first (27): 263, reaching for ledges; in the air played once at 0.7;
      landing it gets up (33), holding down slides (58)
    * fall flat (28): 263; in the air played once at 0.7; landing it lies down (47)
    * flip off (1): gravity 0.33; 228 played once at 0.6, then drops (18)
    * flip up (2): 229 played once at 0.6, then the landing skid (16)
    * bounce (3): 230; while rising, gravity 0.33; then a flat fall (28)
    * ground pound (35): 265; landing bounces (3); gravity 0.33
    * dive kick (14): counts `buttonHeldCounter`; 248; with a sword the throw combination
      throws in the air (73). Played once at 0.4; in the air with no speed across it
      slides down a wall (62); landing skids (16), holding down slides from the start (61)
    * dive kick over (15): 249; in the air played once at 0.6 then drops (18); landing
      runs (52)
    * landing skid (16): 250; attack stomps a fallen opponent. Otherwise it plays once at
      0.6 then runs (52); holding down slides from the start (61); jump jumps (43);
      attack punches (49) or lunges or butts. After an attack press, off the ground it
      grabs a ledge or falls; with no press it does so when no other rule applied
    * warping in (79): 361; gravity 0.33; played once at 0.3 then drops (18)
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.Man.{Actions, Physics, Query, State}

  @up 2
  @down 3
  @jump 4
  @attack 5

  @doc "The world after fencer `self`'s step in airborne state `state`."
  @spec behave(World.t(), non_neg_integer(), integer()) :: World.t()
  def behave(world, self, 43) do
    world = jump_pose(world, self)

    if State.armed?(world, self) and State.combo?(world, self),
      do: State.go(world, self, 73),
      else: rising(world, self)
  end

  def behave(world, self, 44) do
    world = world |> State.pose(self, 348) |> State.put(self, %{frame: 0})

    cond do
      State.get(world, self, :vspd) > 1.0e-5 -> State.go(world, self, 19)
      not State.down?(world, self, @up) -> State.go(world, self, 18)
      State.pressed?(world, self, @attack) -> State.go(world, self, 73)
      true -> steer_facing(world, self)
    end
  end

  def behave(world, self, 18) do
    world = State.pose(world, self, 262)

    cond do
      Physics.past_lowest_platform?(world, self) ->
        world |> State.sound(self, 57) |> State.go(self, 27)

      State.armed?(world, self) and State.combo?(world, self) ->
        State.go(world, self, 73)

      true ->
        {_past, world} = State.animate(world, self, 0.4, true)
        if State.on_ground?(world, self), do: land(world, self), else: in_air(world, self)
    end
  end

  def behave(world, self, 19) do
    world = world |> State.pose(self, 348) |> State.put(self, %{frame: 0})

    cond do
      State.on_ground?(world, self) -> State.go(world, self, 54)
      not State.down?(world, self, @up) -> State.go(world, self, 18)
      State.pressed?(world, self, @attack) -> State.go(world, self, 73)
      true -> steer_facing(world, self)
    end
  end

  def behave(world, self, 27) do
    {_grabbed, world} = world |> State.pose(self, 263) |> Physics.try_grab_ledge(self)

    cond do
      not State.on_ground?(world, self) -> world |> State.animate(self, 0.7, false) |> elem(1)
      State.down?(world, self, @down) -> State.go(world, self, 58)
      true -> State.go(world, self, 33)
    end
  end

  def behave(world, self, 28) do
    world = State.pose(world, self, 263)

    if State.on_ground?(world, self),
      do: State.go(world, self, 47),
      else: world |> State.animate(self, 0.7, false) |> elem(1)
  end

  def behave(world, self, 1) do
    {past, world} =
      world
      |> Physics.apply_gravity(self, 0.33)
      |> State.pose(self, 228)
      |> State.animate(self, 0.6, false)

    if past, do: State.go(world, self, 18), else: world
  end

  def behave(world, self, 2) do
    {past, world} = world |> State.pose(self, 229) |> State.animate(self, 0.6, false)
    if past, do: State.go(world, self, 16), else: world
  end

  def behave(world, self, 3) do
    world = State.pose(world, self, 230)

    if State.get(world, self, :vspd) < -1.0e-5,
      do: Physics.apply_gravity(world, self, 0.33),
      else: State.go(world, self, 28)
  end

  def behave(world, self, 35) do
    world = State.pose(world, self, 265)
    world = if State.on_ground?(world, self), do: State.go(world, self, 3), else: world
    Physics.apply_gravity(world, self, 0.33)
  end

  def behave(world, self, 14) do
    world =
      world
      |> State.put(self, %{buttonHeldCounter: State.get(world, self, :buttonHeldCounter) + 1})
      |> State.pose(self, 248)

    if State.armed?(world, self) and State.combo?(world, self),
      do: State.go(world, self, 73),
      else: dive(world, self)
  end

  def behave(world, self, 15) do
    world = State.pose(world, self, 249)

    if State.on_ground?(world, self) do
      State.go(world, self, 52)
    else
      {past, world} = State.animate(world, self, 0.6, false)
      if past, do: State.go(world, self, 18), else: world
    end
  end

  def behave(world, self, 16) do
    world = State.pose(world, self, 250)

    if State.pressed?(world, self, @attack) do
      case Actions.try_stomp(world, self) do
        {true, world} -> world
        {false, world} -> skid(world, self)
      end
    else
      skid(world, self)
    end
  end

  def behave(world, self, 79) do
    {past, world} =
      world
      |> State.pose(self, 361)
      |> Physics.apply_gravity(self, 0.33)
      |> State.animate(self, 0.3, false)

    if past, do: State.go(world, self, 18), else: world
  end

  defp jump_pose(world, self) do
    speed = abs(State.hspd(world, self))

    cond do
      speed - 1 < -1.0e-5 ->
        world |> State.pose(self, 285) |> State.animate(self, 1, false) |> elem(1)

      speed - 2 <= 1.0e-5 ->
        State.pose(world, self, 282)

      abs(State.get(world, self, :vspd)) - 4 >= -1.0e-5 ->
        world |> State.pose(self, 283) |> State.animate(self, 0.6, false) |> elem(1)

      true ->
        world |> State.pose(self, 284) |> State.animate(self, 0.8, true) |> elem(1)
    end
  end

  defp rising(world, self) do
    world =
      if State.down?(world, self, @jump),
        do: world,
        else: State.put(world, self, %{vspd: State.get(world, self, :vspd) * 0.96})

    if State.get(world, self, :vspd) > 1.0e-5,
      do: State.go(world, self, 18),
      else: in_air(world, self)
  end

  defp in_air(world, self) do
    cond do
      State.armed?(world, self) and State.down?(world, self, @up) and
          not Actions.throws_disabled?(world) ->
        world |> State.sound(self, 102) |> State.go(self, 19)

      not Actions.divekicks_disabled?(world) and State.pressed?(world, self, @attack) ->
        State.go(world, self, 14)

      true ->
        Physics.move_left_and_right(world, self, 0.25, 0.1)
    end
  end

  defp land(world, self) do
    case Actions.slide_or_crawl(world, self) do
      {true, world} -> world
      {false, world} -> world |> State.sound(self, 71) |> State.go(self, 16)
    end
  end

  defp steer_facing(world, self) do
    world
    |> Physics.move_left_and_right(self, 0.25, 0.1)
    |> Query.face_opponent(self)
  end

  defp dive(world, self) do
    {_past, world} = State.animate(world, self, 0.4, false)

    cond do
      not State.on_ground?(world, self) ->
        if abs(State.hspd(world, self)) <= 1.0e-5, do: State.go(world, self, 62), else: world

      State.down?(world, self, @down) ->
        State.go(world, self, 61)

      true ->
        State.go(world, self, 16)
    end
  end

  defp skid(world, self) do
    {past, world} = State.animate(world, self, 0.6, false)

    cond do
      past ->
        State.go(world, self, 52)

      State.down?(world, self, @down) ->
        State.go(world, self, 61)

      State.pressed?(world, self, @jump) ->
        State.go(world, self, 43)

      State.pressed?(world, self, @attack) ->
        world |> State.go(self, skid_attack(world, self)) |> leave_ledge_or_fall(self)

      true ->
        leave_ledge_or_fall(world, self)
    end
  end

  defp leave_ledge_or_fall(world, self) do
    if State.on_ground?(world, self),
      do: world,
      else: Physics.grab_ledge_or_fall(world, self)
  end

  defp skid_attack(world, self),
    do: if(State.type(world, self) == 1, do: 49, else: Actions.lunge_or_butt(world, self))
end
