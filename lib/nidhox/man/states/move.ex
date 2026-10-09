defmodule Nidhox.Man.States.Move do
  @moduledoc """
  A fencer's moving states, each step as `stateBehavior` runs them:

    * run (52): at full speed (2.5) the run (255); faster than 1.3 hunched (257); faster
      than 0.1 starting (267), its frames cycling at `|hspd| × 0.3`; slower resting (266),
      its frame `|hspd| ÷ 0.1` of the way through. Pressing against its motion it skids
      (259) at the frame `|hspd| ÷ 2.5` of the way through. With a sword the throw
      combination throws (72). Footsteps and skids sound; off the ground it grabs a ledge
      or falls; it runs (`moveLeftAndRightAccelFric` 0.2, 0.2), lands in a crawl or slide
      holding down, jumps (43), and with nothing held eases by 0.2 into its stance; up held
      with a sword, throws allowed, cocks the sword (54); attack stomps or punches (49) or
      lunges or butts
    * running cocked (54): footsteps; the cocked run (256) cycling at `|hspd| × 0.25`,
      skidding (259, `|hspd| ÷ 2.25` of the way) when pressing against its motion; runs,
      easing by 0.1 with nothing held; letting go of up runs (52); attack stomps or throws
      (72); jump jumps cocked (44); with nothing held it eases by 0.2 into throw ready (32)
    * crawl (9): 237 cycling at `|hspd| × 0.36`; letting go of down stands; crawls
      (`moveLeftAndRightAccelFric` 0.25, 0.1), counting `buttonHeldCounter` while barely
      moving; a pressed direction turns it; with nothing held it eases by 0.1 and faces its
      opponent; jump jumps from the crouch (11); attack stomps or sweeps (70); unarmed
      holding down it picks up a sword
    * slide (58): 260 cycling at `|hspd| × 0.3`; letting go of down stands; pressing
      against its motion crawls; while faster than 0.55 it eases by 0.03 with nothing
      held, jumps from the crouch (11), sweeps (70), or kicks up dust and picks up a sword
      unarmed holding down; slower it crawls
    * hop up (59): `hspd` 3 ahead; 261 played once at 0.6. Pressing forward or down marks
      another hop (`buttonHeldCounter` 1). While it plays: jump jumps (43), unarmed it
      picks up a sword, back runs (52), attack punches or lunges. When it ends the speed
      halves and a marked hop plays again with down let go, else it runs
    * slide start (61): 264 played once at 0.6 then slides (58); letting go of down hops
      (59); unarmed it picks up a sword; attack stomps or sweeps
    * wall slide (62): 263; gravity 0.02475, `vspd` held to at most 2; dust. Against a
      wall ahead holding forward, jump pushes off (1); else it drops off backwards (18).
      On the ground it runs
    * run up a wall (53): 258 with dust at its feet; a ledge in reach is grabbed. With no
      wall 10 pixels up ahead it grabs a ledge (keeping 0.75 of its facing as speed,
      `vspd` 0) or drops from the crouch (10). Against the wall it climbs (`vspd` −2):
      down slides down the wall (62, not in baby mode); jump pushes off (1); letting go of
      forward falls back (18) at half `vspd` and 2 back; else when 258 has played once at
      0.6 it slides down at half `vspd`
    * hanging (36): its pose played once at 0.6, then idle (246). Holding back it leans
      away (248), else up looks up (247). Down lets go into a wall slide (62, not in baby
      mode); jump climbs up (22), or holding back flips off (1)
    * climb up (22) and jump from the crouch (11): 242 and 239 cycling at 0.4; up held with
      a sword, throws allowed, readies a throw in the air (19); falling it drops from the
      crouch (10); else it steers (0.25, 0.1)
    * drop from the crouch (10): 238; past the lowest platform it falls (27); up held with
      a sword, throws allowed, readies a throw in the air (19); cycling at 0.4, it steers in
      the air, and on landing lands in a crawl or slide, else crawls
    * push off (50): 253 played once at 0.6, then falls (27)
    * roll landing (51): 254 played once at 0.6, then runs (52); holding down slides from
      the start (61); off the ground it grabs a ledge or falls
  """

  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Gml
  alias Nidhox.Man.{Actions, Physics, State, Weapon}
  alias Nidhox.Objects.Particles

  @left 0
  @right 1
  @up 2
  @down 3
  @jump 4
  @attack 5
  @forward 8
  @back 9
  @run_max 2.5
  @cocked_max 2.25
  @skid 259
  @resting 266

  @doc "The world after fencer `self`'s step in moving state `state`."
  @spec behave(World.t(), non_neg_integer(), integer()) :: World.t()
  def behave(world, self, 52) do
    world = world |> run_pose(self) |> run_frame(self) |> skid(self, @run_max)

    if State.armed?(world, self) and State.combo?(world, self),
      do: State.go(world, self, 72),
      else: world |> Actions.footsteps(self) |> Actions.skids(self) |> grounded(self, &run/2)
  end

  def behave(world, self, 54) do
    world = Actions.footsteps(world, self)
    {_past, world} = State.animate(world, self, abs(State.hspd(world, self)) * 0.25, true)

    world
    |> State.pose(self, 256)
    |> skid(self, @cocked_max)
    |> grounded(self, &run_cocked/2)
  end

  def behave(world, self, 9) do
    {_past, world} = world |> State.pose(self, 237) |> State.animate(self, abs(State.hspd(world, self)) * 0.36, true)

    cond do
      not State.on_ground?(world, self) -> Physics.grab_ledge_or_fall(world, self)
      not State.down?(world, self, @down) -> State.stand(world, self)
      true -> crawl(world, self)
    end
  end

  def behave(world, self, 58) do
    {_past, world} = world |> State.pose(self, 260) |> State.animate(self, abs(State.hspd(world, self)) * 0.3, true)

    cond do
      not State.on_ground?(world, self) -> Physics.grab_ledge_or_fall(world, self)
      not State.down?(world, self, @down) -> State.stand(world, self)
      against_motion?(world, self) -> State.go(world, self, 9)
      abs(State.hspd(world, self)) - 0.55 >= -1.0e-5 -> slide(world, self)
      true -> State.go(world, self, 9)
    end
  end

  def behave(world, self, 59) do
    world =
      world
      |> State.put(self, %{hspd: State.get(world, self, :facingXScale) * 3})
      |> State.pose(self, 261)

    if State.on_ground?(world, self), do: hop(world, self), else: Physics.grab_ledge_or_fall(world, self)
  end

  def behave(world, self, 61) do
    world = State.pose(world, self, 264)

    if State.on_ground?(world, self) do
      {past, world} = State.animate(world, self, 0.6, false)
      world = if past, do: State.go(world, self, 58), else: world
      world = if State.down?(world, self, @down), do: world, else: State.go(world, self, 59)
      world = if State.type(world, self) == 1, do: Weapon.try_pickup(world, self), else: world
      sweep_or_stomp(world, self)
    else
      Physics.grab_ledge_or_fall(world, self)
    end
  end

  def behave(world, self, 62) do
    world =
      world
      |> State.pose(self, 263)
      |> Physics.apply_gravity(self, 0.02475)

    world = State.put(world, self, %{vspd: min(State.get(world, self, :vspd), 2)})
    %Instance{x: x, y: y} = World.fetch(world, self)
    world = Particles.dust_at(world, {x, y})

    if State.on_ground?(world, self), do: State.go(world, self, 52), else: wall_slide(world, self)
  end

  def behave(world, self, 53) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    facing = State.get(world, self, :facingXScale)
    world = world |> State.pose(self, 258) |> Particles.dust_at({x + facing, y})

    case Physics.try_grab_ledge(world, self) do
      {true, world} -> world
      {false, world} -> run_up(world, self, facing)
    end
  end

  def behave(world, self, 36) do
    sprite = World.fetch(world, State.get(world, self, :flesh)).sprite_index
    {past, world} = world |> State.pose(self, sprite) |> State.animate(self, 0.6, false)
    world = if past, do: world |> State.put(self, %{frame: 0}) |> State.pose(self, 246), else: world

    world
    |> hang_pose(self)
    |> hang_buttons(self)
  end

  def behave(world, self, state) when state in [22, 11] do
    sprite = if state == 22, do: 242, else: 239
    {_past, world} = world |> State.pose(self, sprite) |> State.animate(self, 0.4, true)
    climb_or_steer(world, self)
  end

  def behave(world, self, 10) do
    world = State.pose(world, self, 238)

    cond do
      Physics.past_lowest_platform?(world, self) -> State.go(world, self, 27)
      cocks_in_air?(world, self) -> State.go(world, self, 19)
      true -> drop_from_crouch(world, self)
    end
  end

  def behave(world, self, 50) do
    {past, world} = world |> State.pose(self, 253) |> State.animate(self, 0.6, false)
    if past, do: State.go(world, self, 27), else: world
  end

  def behave(world, self, 51) do
    {past, world} = world |> State.pose(self, 254) |> State.animate(self, 0.6, false)

    cond do
      past -> State.go(world, self, 52)
      State.down?(world, self, @down) -> State.go(world, self, 61)
      not State.on_ground?(world, self) -> Physics.grab_ledge_or_fall(world, self)
      true -> world
    end
  end

  defp grounded(world, self, fun) do
    if State.on_ground?(world, self),
      do: fun.(world, self),
      else: Physics.grab_ledge_or_fall(world, self)
  end

  defp run_pose(world, self) do
    speed = abs(State.hspd(world, self))

    sprite =
      cond do
        abs(speed - @run_max) <= 1.0e-5 -> 255
        speed - (@run_max - (@run_max - 0.1) * 0.5) > 1.0e-5 -> 257
        speed - 0.1 > 1.0e-5 -> 267
        true -> @resting
      end

    State.pose(world, self, sprite)
  end

  defp run_frame(world, self) do
    speed = abs(State.hspd(world, self))

    if World.fetch(world, State.get(world, self, :flesh)).sprite_index == @resting do
      State.put(world, self, %{frame: speed / 0.1 * frames(world, @resting)})
    else
      {_past, world} = State.animate(world, self, speed * 0.3, true)
      world
    end
  end

  defp skid(world, self, top_speed) do
    hspd = State.hspd(world, self)
    frame = abs(hspd) / top_speed * frames(world, @skid)

    if (Gml.gt?(hspd, 0) and State.down?(world, self, @left)) or
         (Gml.lt?(hspd, 0) and State.down?(world, self, @right)),
       do: world |> State.put(self, %{frame: frame}) |> State.pose(self, @skid),
       else: world
  end

  defp run(world, self) do
    world = Physics.move_left_and_right(world, self, 0.2, 0.2)

    case Actions.slide_or_crawl(world, self) do
      {true, world} -> world
      {false, world} -> run_buttons(world, self)
    end
  end

  defp run_buttons(world, self) do
    cond do
      State.pressed?(world, self, @jump) ->
        State.go(world, self, 43)

      not State.down?(world, self, @left) and not State.down?(world, self, @right) ->
        world = Physics.apply_horizontal_friction(world, self, 0.2)
        if abs(State.hspd(world, self)) - 4 < -1.0e-5, do: State.stand(world, self), else: run_attack(world, self)

      true ->
        run_attack(world, self)
    end
  end

  defp run_attack(world, self) do
    cond do
      readies_throw?(world, self) ->
        world |> State.sound(self, 79) |> State.go(self, 54)

      State.pressed?(world, self, @attack) ->
        {_stomped, world} = Actions.try_stomp(world, self)
        attack = if State.type(world, self) == 1, do: 49, else: Actions.lunge_or_butt(world, self)
        State.go(world, self, attack)

      true ->
        world
    end
  end

  defp readies_throw?(world, self) do
    State.down?(world, self, @up) and State.armed?(world, self) and
      not Actions.throws_disabled?(world)
  end

  defp run_cocked(world, self) do
    world = Physics.move_left_and_right(world, self, 0.2, 0.2)
    world = if idle?(world, self), do: Physics.apply_horizontal_friction(world, self, 0.1), else: world

    if State.down?(world, self, @up) do
      world |> cocked_attack(self) |> cocked_jump(self)
    else
      State.go(world, self, 52)
    end
  end

  defp cocked_attack(world, self) do
    if State.pressed?(world, self, @attack) do
      case Actions.try_stomp(world, self) do
        {true, world} -> world
        {false, world} -> {:done, State.go(world, self, 72)}
      end
    else
      world
    end
  end

  defp cocked_jump({:done, world}, _self), do: world

  defp cocked_jump(world, self) do
    cond do
      State.pressed?(world, self, @jump) ->
        State.go(world, self, 44)

      idle?(world, self) ->
        world = Physics.apply_horizontal_friction(world, self, 0.2)
        if abs(State.hspd(world, self)) - 4 < -1.0e-5, do: State.go(world, self, 32), else: world

      true ->
        world
    end
  end

  defp crawl(world, self) do
    world = Physics.move_left_and_right(world, self, 0.25, 0.1)

    world =
      if abs(State.hspd(world, self)) - 0.2 >= -1.0e-5,
        do: State.put(world, self, %{buttonHeldCounter: 0}),
        else: State.put(world, self, %{buttonHeldCounter: State.get(world, self, :buttonHeldCounter) + 1})

    world = if State.pressed?(world, self, @left), do: State.put(world, self, %{facingXScale: -1}), else: world
    world = if State.pressed?(world, self, @right), do: State.put(world, self, %{facingXScale: 1}), else: world

    world =
      if idle?(world, self),
        do: world |> Physics.apply_horizontal_friction(self, 0.1) |> Nidhox.Man.Query.face_opponent(self),
        else: world

    cond do
      State.pressed?(world, self, @jump) -> State.go(world, self, 11)
      State.pressed?(world, self, @attack) -> sweep_or_stomp(world, self)
      true -> pick_up_holding_down(world, self)
    end
  end

  defp slide(world, self) do
    world = if idle?(world, self), do: Physics.apply_horizontal_friction(world, self, 0.03), else: world

    cond do
      State.pressed?(world, self, @jump) ->
        State.go(world, self, 11)

      State.pressed?(world, self, @attack) ->
        State.go(world, self, 70)

      true ->
        %Instance{x: x, y: y} = World.fetch(world, self)
        world |> Particles.dust_at({x, y}) |> pick_up_holding_down(self)
    end
  end

  defp pick_up_holding_down(world, self) do
    if State.type(world, self) == 1 and State.down?(world, self, @down),
      do: Weapon.try_pickup(world, self),
      else: world
  end

  defp sweep_or_stomp(world, self) do
    if State.pressed?(world, self, @attack) do
      case Actions.try_stomp(world, self) do
        {true, world} -> world
        {false, world} -> State.go(world, self, 70)
      end
    else
      world
    end
  end

  defp against_motion?(world, self) do
    hspd = State.hspd(world, self)

    (Gml.gt?(hspd, 0) and State.down?(world, self, @left)) or
      (Gml.lt?(hspd, 0) and State.down?(world, self, @right))
  end

  defp hop(world, self) do
    world =
      if State.pressed?(world, self, @forward) or State.pressed?(world, self, @down),
        do: State.put(world, self, %{buttonHeldCounter: 1}),
        else: world

    case State.animate(world, self, 0.6, false) do
      {false, world} -> hopping(world, self)
      {true, world} -> landed_hop(world, self)
    end
  end

  defp hopping(world, self) do
    world = if State.pressed?(world, self, @jump), do: State.go(world, self, 43), else: world
    world = if State.type(world, self) == 1, do: Weapon.try_pickup(world, self), else: world
    world = if State.down?(world, self, @back), do: State.go(world, self, 52), else: world

    if State.pressed?(world, self, @attack) do
      attack = if State.type(world, self) == 1, do: 49, else: Actions.lunge_or_butt(world, self)
      State.go(world, self, attack)
    else
      world
    end
  end

  defp landed_hop(world, self) do
    world = State.put(world, self, %{hspd: State.hspd(world, self) * 0.5})

    if Gml.truthy?(State.get(world, self, :buttonHeldCounter)) and not State.down?(world, self, @down),
      do: State.put(world, self, %{buttonHeldCounter: 0, frame: 0}),
      else: State.go(world, self, 52)
  end

  defp wall_slide(world, self) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    facing = State.get(world, self, :facingXScale)

    if Physics.block_at?(world, {x + facing * 4, y}) and State.down?(world, self, @forward) do
      if State.pressed?(world, self, @jump), do: State.go(world, self, 1), else: world
    else
      world
      |> State.put(self, %{hspd: -facing})
      |> State.go(self, 18)
    end
  end

  defp run_up(world, self, facing) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    if Physics.block_at?(world, {x + facing * 4, y - 10}) do
      climb(State.put(world, self, %{vspd: -2}), self, facing)
    else
      case Physics.try_grab_ledge(world, self) do
        {true, world} -> State.put(world, self, %{hspd: facing * 0.75, vspd: 0})
        {false, world} -> State.go(world, self, 10)
      end
    end
  end

  defp climb(world, self, facing) do
    cond do
      State.down?(world, self, @down) and not Nidhox.Bout.Variants.baby_mode?(world) ->
        State.go(world, self, 62)

      State.pressed?(world, self, @jump) ->
        State.go(world, self, 1)

      not State.down?(world, self, @forward) ->
        world
        |> State.put(self, %{vspd: State.get(world, self, :vspd) * 0.5, hspd: facing * -2})
        |> State.go(self, 18)

      true ->
        case State.animate(world, self, 0.6, false) do
          {true, world} ->
            world
            |> State.put(self, %{vspd: State.get(world, self, :vspd) * 0.5})
            |> State.go(self, 62)

          {false, world} ->
            world
        end
    end
  end

  defp hang_pose(world, self) do
    sprite = World.fetch(world, State.get(world, self, :flesh)).sprite_index

    cond do
      State.down?(world, self, @back) ->
        if sprite in [246, 247], do: State.pose(world, self, 248), else: world

      State.down?(world, self, @up) ->
        if sprite in [246, 248], do: State.pose(world, self, 247), else: world

      true ->
        world
    end
  end

  defp hang_buttons(world, self) do
    cond do
      State.pressed?(world, self, @down) and not Nidhox.Bout.Variants.baby_mode?(world) ->
        State.go(world, self, 62)

      State.pressed?(world, self, @jump) ->
        State.go(world, self, if(State.down?(world, self, @back), do: 1, else: 22))

      true ->
        world
    end
  end

  defp cocks_in_air?(world, self) do
    State.down?(world, self, @up) and State.type(world, self) == 2 and
      not Actions.throws_disabled?(world)
  end

  defp climb_or_steer(world, self) do
    cond do
      cocks_in_air?(world, self) ->
        State.go(world, self, 19)

      State.get(world, self, :vspd) > 1.0e-5 ->
        State.go(world, self, 10)

      true ->
        Physics.move_left_and_right(world, self, 0.25, 0.1)
    end
  end

  defp drop_from_crouch(world, self) do
    {_past, world} = State.animate(world, self, 0.4, true)

    if State.on_ground?(world, self) do
      case Actions.slide_or_crawl(world, self) do
        {true, world} -> world
        {false, world} -> State.go(world, self, 9)
      end
    else
      Physics.move_left_and_right(world, self, 0.25, 0.1)
    end
  end

  defp idle?(world, self), do: not State.down?(world, self, @left) and not State.down?(world, self, @right)

  defp frames(world, sprite) do
    case World.sprite(world, sprite) do
      nil -> 1
      definition -> length(definition.frames)
    end
  end
end
