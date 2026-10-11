defmodule Nidhox.Man.States.Stand do
  @moduledoc """
  A fencer's standing states, each step as `stateBehavior` runs them:

    * fencing (29): on stairs below, the stairs state for its facing (31 facing right, 30
      left). Still, the stance's standing pose cycles at 0.4 a step (high 197, middle
      199, low 198). Moving towards its facing, or within 64 pixels of its opponent, the
      forward walk (high 194, middle 196, low 195) shows the frame `|hspd| ÷ 3` of the way
      through; moving away further off, the pushed-back walk (230, 232, 231) cycles at
      `|hspd| × 0.5`. Off the ground it grabs a ledge or falls. On the ground `hspd` is
      held to ±1 while swords touch, else ±3; the throw combination throws (72); up held,
      throws allowed, counts towards cocking the sword (54, past 9 steps); down held
      counts towards crawling or sliding (past 9 steps). Pressing up raises the stance,
      or from high readies a throw (32); pressing down lowers it, or from low (or held
      past 9 steps) crawls (9). It then steps (`footwork` 2, friction 0.1), restarting
      its frame when it starts moving; a direction held more than 10 steps runs (52);
      jump jumps (43); attack stomps a fallen opponent, else lunges or butts
    * unarmed stance (78): stands (187) or walks (186), cycling at 0.4; down crawls;
      steps (`footwork` 4, friction 0.035); a direction held more than 7 steps runs;
      jump jumps; attack stomps or punches (49)
    * throw ready (32): still (frame 0, 167) or walking (206), cycling at 0.4; `hspd`
      held to ±2; letting go of up fences; steps (`footwork` 2, friction 0.1); a
      direction held more than 10 steps runs with the sword cocked (54); jump jumps
      cocked (44); attack throws (72)
    * crane stance (7): frame 0 of 166; off the ground falls (27); letting go of up
      stands (78); attack kicks (8); holding jump jumps (43)
    * crane kick (8): 166 played once at 1 a step, then stands (78), or falls (27) in the
      air
    * stairs (30 down, 31 up): off the ground grabs a ledge or falls; off the stairs
      fences; faces its opponent, switching stairs state when that turns it; poses (30:
      184; 31: high 204, else 205); `stairYModifier` 0; gravity 3.3; jump jumps (43);
      else steps on the stairs (`stairStepping`) and up or down shifts the stance
    * entering the screen (23): runs (257 at up to 2.25 a step, else 255) cycling at
      0.75 with footsteps; kept no lower than the respawn point nearest 16 pixels ahead;
      faces the camera's middle (`facingXScale` its offset held to ±1). Inside the
      camera's edges by 12 pixels with ground 64 below at 0, 4, … 24 pixels ahead, it
      crawls holding down, else stands; otherwise it turns to the camera's middle and
      speeds by 10 that way
  """

  alias Cauldron2D.GameMaker.{Collide, Instance, World}
  alias Nidhox.Bout.Camera
  alias Nidhox.Gml
  alias Nidhox.Man.{Actions, Physics, Query, State}

  @left 0
  @right 1
  @up 2
  @down 3
  @jump 4
  @attack 5
  @stairs "Stairs"
  @still %{1 => 197, 3 => 199, 2 => 198}
  @forward %{1 => 194, 3 => 196, 2 => 195}
  @pushed %{1 => 230, 3 => 232, 2 => 231}
  @walk_frames_sprite 196
  @walk_speed 3
  @near 64
  @held_counts 9
  @to_run 10
  @unarmed_to_run 7
  @entry_margin 12

  @doc "The world after fencer `self`'s step in standing state `state`."
  @spec behave(World.t(), non_neg_integer(), integer()) :: World.t()
  def behave(world, self, 29) do
    world
    |> onto_stairs(self)
    |> walk_pose(self)
    |> grounded(self, &fence/2)
  end

  def behave(world, self, 78), do: grounded(world, self, &unarmed/2)

  def behave(world, self, 32) do
    {_past, world} = State.animate(world, self, 0.4, true)

    world =
      if Gml.eq?(abs(State.hspd(world, self)), 0),
        do: world |> State.put(self, %{frame: 0}) |> State.pose(self, 167),
        else: State.pose(world, self, 206)

    grounded(world, self, &ready/2)
  end

  def behave(world, self, 7) do
    world = world |> State.put(self, %{frame: 0}) |> State.pose(self, 166)

    cond do
      not State.on_ground?(world, self) -> State.go(world, self, 27)
      not State.down?(world, self, @up) -> State.go(world, self, 78)
      State.pressed?(world, self, @attack) -> State.go(world, self, 8)
      State.down?(world, self, @jump) -> State.go(world, self, 43)
      true -> world
    end
  end

  def behave(world, self, 8) do
    {past, world} = world |> State.pose(self, 166) |> State.animate(self, 1, false)

    cond do
      not past -> world
      State.on_ground?(world, self) -> State.go(world, self, 78)
      true -> State.go(world, self, 27)
    end
  end

  def behave(world, self, state) when state in [30, 31],
    do: grounded(world, self, &stairs(&1, &2, state))

  def behave(world, self, 23) do
    sprite = if abs(State.hspd(world, self)) - 2.25 <= 1.0e-5, do: 257, else: 255
    {_past, world} = world |> State.pose(self, sprite) |> State.animate(self, 0.75, true)

    world
    |> Actions.footsteps(self)
    |> below_respawn(self)
    |> face_camera(self)
    |> settle_or_enter(self)
  end

  defp grounded(world, self, fun) do
    if State.on_ground?(world, self),
      do: fun.(world, self),
      else: Physics.grab_ledge_or_fall(world, self)
  end

  defp onto_stairs(world, self) do
    if meeting_below?(world, self, @stairs),
      do:
        State.go(
          world,
          self,
          if(Gml.eq?(State.get(world, self, :facingXScale), 1), do: 31, else: 30)
        ),
      else: world
  end

  defp walk_pose(world, self) do
    hspd = State.hspd(world, self)
    stance = State.get(world, self, :stance)

    if Gml.eq?(hspd, 0) do
      {_past, world} = State.animate(world, self, 0.4, true)
      State.pose(world, self, Map.get(@still, stance, 199))
    else
      {pushed, world} = walk_frame(world, self, hspd)
      sprites = if pushed, do: @pushed, else: @forward
      State.pose(world, self, Map.get(sprites, stance, 196))
    end
  end

  defp walk_frame(world, self, hspd) do
    facing = State.get(world, self, :facingXScale)

    if Gml.eq?(Gml.clamp(hspd * 100_000, -1, 1), facing) or Query.player_dist(world) <= @near do
      frames = frames(world, @walk_frames_sprite)
      {false, State.put(world, self, %{frame: abs(hspd) / @walk_speed * frames})}
    else
      {_past, world} = State.animate(world, self, abs(hspd) * 0.5, true)
      {true, world}
    end
  end

  defp fence(world, self) do
    limit = if Gml.truthy?(State.get(world, self, :swordCollision)), do: 1, else: 3

    world =
      world
      |> State.put(self, %{hspd: Gml.clamp(State.hspd(world, self), -limit, limit)})
      |> Actions.turn_around_timer(self)

    if State.combo?(world, self),
      do: State.go(world, self, 72),
      else: world |> hold_up_or_down(self) |> stance_buttons(self)
  end

  defp hold_up_or_down(world, self) do
    cond do
      State.down?(world, self, @up) and not Actions.throws_disabled?(world) ->
        world = count_held(world, self)

        if State.get(world, self, :buttonHeldCounter) > @held_counts,
          do: world |> State.sound(self, 79) |> State.go(self, 54),
          else: world

      State.down?(world, self, @down) ->
        world |> count_held(self) |> slide_when_held(self)

      true ->
        State.put(world, self, %{buttonHeldCounter: 0})
    end
  end

  defp slide_when_held(world, self) do
    if State.get(world, self, :buttonHeldCounter) > @held_counts do
      case Actions.slide_or_crawl(world, self) do
        {true, world} -> {:done, world}
        {false, world} -> world
      end
    else
      world
    end
  end

  defp stance_buttons({:done, world}, _self), do: world

  defp stance_buttons(world, self) do
    cond do
      State.pressed?(world, self, @up) ->
        if State.get(world, self, :stance) == 1 and not Actions.throws_disabled?(world),
          do: State.go(world, self, 32),
          else: Actions.shift_stance(world, self, 2)

      State.pressed?(world, self, @down) ->
        world = count_held(world, self)

        cond do
          State.get(world, self, :buttonHeldCounter) > @held_counts ->
            State.go(world, self, 9)

          State.get(world, self, :stance) != 2 ->
            world |> Actions.shift_stance(self, 3) |> step(self)

          true ->
            State.go(world, self, 9)
        end

      true ->
        step(world, self)
    end
  end

  defp step(world, self) do
    before = State.hspd(world, self)
    world = Actions.footwork(world, self, 2, 0.1)

    world =
      if Gml.eq?(before, 0) and not Gml.eq?(State.hspd(world, self), 0),
        do: State.put(world, self, %{frame: 0}),
        else: world

    world = count_run(world, self)

    if State.get(world, self, :runButtonHeldCounter) > @to_run,
      do: world |> State.sound(self, 47) |> State.go(self, 52),
      else: world |> jump(self, 43) |> attack(self)
  end

  defp jump(world, self, state),
    do: if(State.pressed?(world, self, @jump), do: State.go(world, self, state), else: world)

  defp attack(world, self) do
    if State.pressed?(world, self, @attack) do
      case Actions.try_stomp(world, self) do
        {true, world} -> world
        {false, world} -> State.go(world, self, Actions.lunge_or_butt(world, self))
      end
    else
      world
    end
  end

  defp unarmed(world, self) do
    {_past, world} = State.animate(world, self, 0.4, true)

    world =
      world
      |> State.pose(self, if(Gml.eq?(State.hspd(world, self), 0), do: 187, else: 186))
      |> Actions.turn_around_timer(self)

    if State.down?(world, self, @down) do
      State.go(world, self, 9)
    else
      world = world |> Actions.footwork(self, 4, 0.035) |> count_run(self)

      cond do
        State.get(world, self, :runButtonHeldCounter) > @unarmed_to_run ->
          State.go(world, self, 52)

        State.pressed?(world, self, @jump) ->
          State.go(world, self, 43)

        State.pressed?(world, self, @attack) ->
          punch(world, self)

        true ->
          world
      end
    end
  end

  defp punch(world, self) do
    case Actions.try_stomp(world, self) do
      {true, world} -> world
      {false, world} -> State.go(world, self, 49)
    end
  end

  defp ready(world, self) do
    world =
      world
      |> State.put(self, %{hspd: Gml.clamp(State.hspd(world, self), -2, 2)})
      |> Actions.turn_around_timer(self)

    if State.down?(world, self, @up),
      do: world |> Actions.footwork(self, 2, 0.1) |> count_run(self) |> run_or_jump(self),
      else: State.go(world, self, 29)
  end

  defp run_or_jump(world, self) do
    if State.get(world, self, :runButtonHeldCounter) > @to_run do
      State.go(world, self, 54)
    else
      world = jump(world, self, 44)
      if State.pressed?(world, self, @attack), do: State.go(world, self, 72), else: world
    end
  end

  defp stairs(world, self, state) do
    if meeting_below?(world, self, @stairs) do
      world = Query.face_opponent(world, self)
      facing = State.get(world, self, :facingXScale)

      cond do
        state == 30 and Gml.eq?(facing, 1) -> State.go(world, self, 31)
        state == 31 and Gml.eq?(facing, -1) -> State.go(world, self, 30)
        true -> on_stairs(world, self, state)
      end
    else
      State.go(world, self, 29)
    end
  end

  defp on_stairs(world, self, state) do
    world =
      world
      |> State.pose(self, stairs_sprite(state, State.get(world, self, :stance)))
      |> State.put(self, %{stairYModifier: 0})
      |> Physics.apply_gravity(self, 3.3)

    if State.pressed?(world, self, @jump) do
      State.go(world, self, 43)
    else
      world = stair_stepping(world, self)

      world =
        if State.pressed?(world, self, @up), do: Actions.shift_stance(world, self, 2), else: world

      if State.pressed?(world, self, @down), do: Actions.shift_stance(world, self, 3), else: world
    end
  end

  defp stairs_sprite(30, _stance), do: 184
  defp stairs_sprite(31, 1), do: 204
  defp stairs_sprite(31, _stance), do: 205

  defp stair_stepping(world, self) do
    world = Actions.footwork(world, self, 1.5, 0.1)
    world = State.put(world, self, %{hspd: Gml.clamp(State.hspd(world, self), -1.5, 1.5)})
    %Instance{x: x} = World.fetch(world, self)
    flesh = World.fetch(world, State.get(world, self, :flesh))
    count = frames(world, flesh.sprite_index)
    State.put(world, self, %{frame: Integer.mod(Gml.round(x / 2), count)})
  end

  defp below_respawn(world, self) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    facing = State.get(world, self, :facingXScale)

    case Gml.nearest(world, {x + facing * 16, y - 16}, "RespawnPoint") do
      nil -> world
      point -> World.update(world, self, &%{&1 | y: min(&1.y, World.fetch(world, point).y)})
    end
  end

  defp face_camera(world, self) do
    %Instance{x: x} = World.fetch(world, self)
    State.put(world, self, %{facingXScale: Gml.clamp(Camera.center_x(world) - x, -1, 1)})
  end

  defp settle_or_enter(world, self) do
    %Instance{x: x} = World.fetch(world, self)

    inside =
      not Gml.lt?(x, Camera.left(world) + @entry_margin) and
        not Gml.gt?(x, Camera.right(world) - @entry_margin) and
        ground_ahead?(world, self)

    cond do
      inside and State.down?(world, self, @down) -> State.go(world, self, 9)
      inside -> State.stand(world, self)
      true -> enter(world, self, x)
    end
  end

  defp ground_ahead?(world, self) do
    facing = State.get(world, self, :facingXScale)
    Enum.all?(0..24//4, &Physics.check_below?(world, self, &1 * facing, 64))
  end

  defp enter(world, self, x) do
    center = Camera.center_x(world)

    world =
      cond do
        Gml.gt?(x, center) -> State.put(world, self, %{facingXScale: -1})
        Gml.lt?(x, center) -> State.put(world, self, %{facingXScale: 1})
        true -> world
      end

    State.put(world, self, %{
      hspd: State.hspd(world, self) + State.get(world, self, :facingXScale) * 10
    })
  end

  defp count_held(world, self),
    do:
      State.put(world, self, %{buttonHeldCounter: State.get(world, self, :buttonHeldCounter) + 1})

  defp count_run(world, self) do
    if State.down?(world, self, @left) or State.down?(world, self, @right),
      do:
        State.put(world, self, %{
          turnAroundFlag: 1,
          runButtonHeldCounter: State.get(world, self, :runButtonHeldCounter) + 1
        }),
      else: State.put(world, self, %{runButtonHeldCounter: 0})
  end

  defp meeting_below?(world, self, name) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    case World.object_index(world, name) do
      nil -> false
      object -> Collide.meeting?(world, self, {x, y + 1}, object)
    end
  end

  defp frames(world, sprite) do
    case World.sprite(world, sprite) do
      nil -> 1
      definition -> length(definition.frames)
    end
  end
end
