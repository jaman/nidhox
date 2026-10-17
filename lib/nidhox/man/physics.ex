defmodule Nidhox.Man.Physics do
  @moduledoc """
  How the game's `PhysicsObject`s — the fencers among them — move and collide, as its
  code does it.

    * `create/2` (the object's create): `S_SLOPE_SLOW` 0.5; speeds, counters, ground,
      riding and acceleration 0; `previousX`, `previousY` where it stands
    * `begin_step/2` (`grandmaPhysicsBeginStep`): `XACCEL` is the change of `hspd`
      since the last step; standing (`checkBelow`), a change over 0.1 kicks up dust
      (`makeDustAt`), and what it stands on (`checkMoving`) carries it by that one's
      `hspd + conveyor` and `vspd`. Of several things it stands on, the one with the
      lowest `round(x × 100) × 1000000 + round(y × 100)` is the one that carries it
    * `end_step/2` (`grandmaPhysicsEndStep`): moved by what carries it, then by its
      speed a pixel at a time against `Block`s, the fractions kept in `h_counter` and
      `v_counter` (rounded halves to even). Across: a free pixel ahead, on the ground
      with ground two below but not one, also steps down a pixel; a blocked one with a
      free pixel above steps up it, else the move stops and user event 0 runs. Up: a
      blocked pixel stops it; down: ground below (`checkBelow`) stops it; either runs
      user event 1
    * `check_below?/4` (`checkBelow(dx, dy)`): a `Block` at the offset, or a
      `PassThroughBlock` there that it is not already inside
    * `apply_gravity/3` (`applyGravity(amount)`): off the ground, `vspd` eases towards
      8 by `amount`, halved in low gravity
    * `apply_horizontal_friction/3`: `hspd` eases towards 0 by the amount
    * `move_left_and_right/4` (`moveLeftAndRightAccelFric(accel, fric)`): holding left,
      a fencer moving right slows by `fric`, else it faces left; then `hspd` falls by
      `accel`; holding right, the same the other way
    * `collide_x/2` and `collide_y/2` (`manCollideX`, `manCollideY`): a fencer's user
      events 0 and 1. Running into a wall while holding the run button in a running
      state (`isRunState`: 52, 80, 81; or 54, 58, 43, 44, 18, 19) turns the fencer to
      the wall
    * `grab_ledge_or_fall/2` (`grabLedgeOrFall`): `tryToGrabALedge`, else falling
      (state 27)
  """

  alias Cauldron2D.GameMaker.{Collide, Instance, World}
  alias Cauldron2D.Overlap
  alias Cauldron2D.Shape
  alias Nidhox.Bout.{Input, Variants}
  alias Nidhox.Gml
  alias Nidhox.Objects.Particles

  @noone -4
  @force_out_tries 200
  @mask_height 26
  @runner_states [52, 80, 81, 54, 58, 43, 44, 18, 19]
  @falling_states [27, 10, 18]

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers,
    do: [{"gml_Object_PhysicsObject_Create_0", fn world, self, _other -> create(world, self) end}]

  @doc """
  `force_out`: instance `self`, inside a `Block`, moved to the first free place tried
  around where it stands — right, up, left and down by one pixel, then by two, and so on —
  up to `@force_out_tries` places; it stays put when none is free.
  """
  @spec force_out(World.t(), non_neg_integer()) :: World.t()
  def force_out(%World{} = world, self) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    if meeting?(world, self, {x, y}, "Block") do
      1..@force_out_tries
      |> Stream.map(&around({x, y}, &1))
      |> Enum.find(&(not meeting?(world, self, &1, "Block")))
      |> case do
        nil -> world
        {fx, fy} -> World.update(world, self, &%{&1 | x: fx, y: fy})
      end
    else
      world
    end
  end

  @doc "The world with instance `self` given its physics variables (`PhysicsObject`'s create)."
  @spec create(World.t(), non_neg_integer()) :: World.t()
  def create(%World{} = world, self) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    Gml.put(world, self, %{
      S_SLOPE_SLOW: 0.5,
      hspd: 0,
      vspd: 0,
      h_counter: 0,
      v_counter: 0,
      onGround: 0,
      ground_moving: 0,
      add_hspd: 0,
      add_vspd: 0,
      pHSPD: 0,
      XACCEL: 0,
      z: 0,
      previousX: x,
      previousY: y
    })
  end

  @doc "`grandmaPhysicsBeginStep` for instance `self`."
  @spec begin_step(World.t(), non_neg_integer()) :: World.t()
  def begin_step(%World{} = world, self) do
    hspd = Gml.var(world, self, :hspd)
    accel = hspd - Gml.var(world, self, :pHSPD)
    on_ground = check_below?(world, self)

    world =
      Gml.put(world, self, %{
        XACCEL: accel,
        pHSPD: hspd,
        onGround: if(on_ground, do: 1, else: 0),
        ground_moving: 0,
        add_hspd: 0,
        add_vspd: 0
      })

    if on_ground, do: grounded(world, self, accel), else: world
  end

  @doc "`grandmaPhysicsEndStep` for instance `self`."
  @spec end_step(World.t(), non_neg_integer()) :: World.t()
  def end_step(%World{} = world, self) do
    world =
      World.update(world, self, fn %Instance{vars: vars} = instance ->
        %{instance | x: instance.x + vars.add_hspd, y: instance.y + vars.add_vspd}
      end)

    h_counter = Gml.var(world, self, :h_counter) + Gml.var(world, self, :hspd)
    v_counter = Gml.var(world, self, :v_counter) + Gml.var(world, self, :vspd)
    across = Gml.round(h_counter)
    down = Gml.round(v_counter)
    world = Gml.put(world, self, %{h_counter: h_counter - across, v_counter: v_counter - down})

    world
    |> while_here(self, &slide_and_hit(&1, self, across))
    |> while_here(self, &drop_and_hit(&1, self, down))
    |> while_here(self, fn world ->
      %Instance{x: x, y: y} = World.fetch(world, self)
      Gml.put(world, self, %{previousX: x, previousY: y})
    end)
  end

  defp while_here(world, self, fun),
    do: if(World.fetch(world, self), do: fun.(world), else: world)

  defp slide_and_hit(world, self, across) do
    {world, hit} = slide(world, self, Gml.sign(across), abs(across))
    if hit, do: World.perform(world, self, :other, 10), else: world
  end

  defp drop_and_hit(world, self, down) do
    {world, hit} = drop(world, self, Gml.sign(down), abs(down))
    if hit, do: World.perform(world, self, :other, 11), else: world
  end

  @doc "`checkBelow(dx, dy)`: ground at `{dx, dy}` from instance `self`."
  @spec check_below?(World.t(), non_neg_integer(), number(), number()) :: boolean()
  def check_below?(%World{} = world, self, dx \\ 0, dy \\ 1) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    meeting?(world, self, {x + dx, y + dy}, "Block") or
      (meeting?(world, self, {x + dx, y + dy}, "PassThroughBlock") and
         not meeting?(world, self, {x + dx, y}, "PassThroughBlock"))
  end

  @doc "`applyGravity(amount)` for instance `self`."
  @spec apply_gravity(World.t(), non_neg_integer(), number()) :: World.t()
  def apply_gravity(%World{} = world, self, amount) do
    gravity = if Variants.low_gravity?(world), do: 0.5, else: 1

    if Gml.truthy?(Gml.var(world, self, :onGround)),
      do: world,
      else:
        Gml.put(world, self, %{
          vspd: Gml.approach(Gml.var(world, self, :vspd), 8, amount * gravity)
        })
  end

  @doc "`applyHorizontalFriction(amount)` for instance `self`."
  @spec apply_horizontal_friction(World.t(), non_neg_integer(), number()) :: World.t()
  def apply_horizontal_friction(%World{} = world, self, amount),
    do: Gml.put(world, self, %{hspd: Gml.approach(Gml.var(world, self, :hspd), 0, amount)})

  @doc "`moveLeftAndRightAccelFric(accel, fric)` for fencer `self`."
  @spec move_left_and_right(World.t(), non_neg_integer(), number(), number()) :: World.t()
  def move_left_and_right(%World{} = world, self, accel, fric) do
    player = Gml.var(world, self, :playerIndex)

    world
    |> push(self, Input.down?(world, self, player, 0), -1, accel, fric)
    |> then(&push(&1, self, Input.down?(&1, self, player, 1), 1, accel, fric))
  end

  @doc "`get_weapon_type`: the type of fencer `self`'s weapon, 1 (fists) without one."
  @spec weapon_type(World.t(), non_neg_integer()) :: number()
  def weapon_type(%World{} = world, self) do
    case World.fetch(world, Gml.var(world, self, :weapon, @noone)) do
      %Instance{vars: vars} -> Map.get(vars, :type, 1)
      nil -> 1
    end
  end

  @doc "`manCollideX`: fencer `self` run into a wall."
  @spec collide_x(World.t(), non_neg_integer()) :: World.t()
  def collide_x(%World{} = world, self) do
    state = Gml.var(world, self, :state)

    if state in [79, 23] do
      world
    else
      world
      |> against_wall(self, state)
      |> ledge_from_fall(self)
      |> Gml.put(self, %{hspd: 0})
    end
  end

  @doc "`manCollideY`: fencer `self` landed or hit a ceiling."
  @spec collide_y(World.t(), non_neg_integer()) :: World.t()
  def collide_y(%World{} = world, self) do
    if Gml.var(world, self, :state) in [79, 23],
      do: world,
      else: Gml.put(world, self, %{vspd: 0, hspd: Gml.var(world, self, :hspd) * 0.5})
  end

  @doc "`grabLedgeOrFall`: fencer `self` hangs from a ledge it can reach, or falls (state 27)."
  @spec grab_ledge_or_fall(World.t(), non_neg_integer()) :: World.t()
  def grab_ledge_or_fall(%World{} = world, self) do
    case grab_ledge(world, self) do
      {true, world} -> world
      {false, world} -> next_state(world, self, 27)
    end
  end

  @doc "`tryToGrabALedge` for fencer `self`: `{grabbed, world}`, hanging (36) when it reaches one."
  @spec try_grab_ledge(World.t(), non_neg_integer()) :: {boolean(), World.t()}
  def try_grab_ledge(%World{} = world, self), do: grab_ledge(world, self)

  @doc "Whether a `Block` holds the point `{x, y}` (`position_meeting(x, y, Block)`)."
  @spec block_at?(World.t(), {number(), number()}) :: boolean()
  def block_at?(%World{} = world, point) do
    case World.object_index(world, "Block") do
      nil -> false
      block -> Collide.at_point(world, point, block) != nil
    end
  end

  @doc """
  `pastLowestPlatform` for instance `self`: whether it is more than 16 pixels below the
  lowest `Block` or `PassThroughBlock` in the room.
  """
  @spec past_lowest_platform?(World.t(), non_neg_integer()) :: boolean()
  def past_lowest_platform?(%World{} = world, self) do
    lowest =
      ["Block", "PassThroughBlock"]
      |> Enum.flat_map(fn name ->
        case World.object_index(world, name) do
          nil -> []
          object -> World.instances_of(world, object)
        end
      end)
      |> Enum.reduce(0, &max(&2, World.fetch(world, &1).y))

    World.fetch(world, self).y - (lowest + 16) > 1.0e-5
  end

  @doc "`set_nextState(state)` for fencer `self`."
  @spec next_state(World.t(), non_neg_integer(), integer()) :: World.t()
  def next_state(world, self, state), do: Gml.put(world, self, %{nextState: state})

  defp grounded(world, self, accel) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    world = if abs(accel) - 0.1 > 0, do: Particles.dust_at(world, {x, y}), else: world

    case moving_ground(world, self) do
      nil ->
        Gml.put(world, self, %{ground_moving: @noone})

      ground ->
        Gml.put(world, self, %{
          ground_moving: ground,
          add_hspd: Gml.var(world, ground, :hspd) + Gml.var(world, ground, :conveyor),
          add_vspd: Gml.var(world, ground, :vspd)
        })
    end
  end

  defp moving_ground(world, self) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    name =
      if meeting?(world, self, {x, y + 1}, "PassThroughBlock") and
           not meeting?(world, self, {x, y}, "PassThroughBlock"),
         do: "o_block_moving",
         else: "Block"

    world
    |> touching(self, {x, y + 1}, name)
    |> Enum.min_by(&ground_rank(world, &1), fn -> nil end)
  end

  defp ground_rank(world, ground) do
    %Instance{x: x, y: y} = World.fetch(world, ground)
    Gml.round(x * 100) * 1_000_000 + Gml.round(y * 100)
  end

  defp touching(world, self, position, name) do
    with object when is_integer(object) <- World.object_index(world, name),
         %Instance{} = instance <- World.fetch(world, self),
         %Shape{} = mine <- Collide.shape(world, instance, position) do
      world
      |> World.instances_of(object)
      |> Enum.filter(&(&1 != self and overlaps?(world, mine, &1)))
    else
      _none -> []
    end
  end

  defp overlaps?(world, mine, other) do
    %Instance{x: x, y: y} = instance = World.fetch(world, other)

    case Collide.shape(world, instance, {x, y}) do
      %Shape{} = theirs -> Overlap.shapes?(mine, theirs)
      nil -> false
    end
  end

  defp slide(world, _self, _step, 0), do: {world, false}

  defp slide(world, self, step, left) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    cond do
      not meeting?(world, self, {x + step, y}, "Block") ->
        world
        |> slope_down(self, step)
        |> World.update(self, &%{&1 | x: &1.x + step})
        |> slide(self, step, left - 1)

      not meeting?(world, self, {x + step, y - 1}, "Block") ->
        world
        |> World.update(self, &%{&1 | x: &1.x + step, y: &1.y - 1})
        |> slide(self, step, left - 1)

      true ->
        {world, true}
    end
  end

  defp slope_down(world, self, step) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    if Gml.truthy?(Gml.var(world, self, :onGround)) and
         not meeting?(world, self, {x + step, y + 1}, "Block") and
         meeting?(world, self, {x + step, y + 2}, "Block"),
       do: World.update(world, self, &%{&1 | y: &1.y + 1}),
       else: world
  end

  defp drop(world, _self, _step, 0), do: {world, false}

  defp drop(world, self, step, left) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    blocked =
      if Gml.var(world, self, :vspd) <= 0,
        do: meeting?(world, self, {x, y + step}, "Block"),
        else: check_below?(world, self)

    if blocked,
      do: {world, true},
      else: world |> World.update(self, &%{&1 | y: &1.y + step}) |> drop(self, step, left - 1)
  end

  defp push(world, _self, false, _way, _accel, _fric), do: world

  defp push(world, self, true, way, accel, fric) do
    hspd = Gml.var(world, self, :hspd)

    world =
      if hspd * way < 0,
        do: Gml.put(world, self, %{hspd: Gml.approach(hspd, 0, fric)}),
        else: Gml.put(world, self, %{facingXScale: way})

    Gml.put(world, self, %{hspd: Gml.var(world, self, :hspd) + way * accel})
  end

  defp against_wall(world, self, state) do
    player = Gml.var(world, self, :playerIndex)
    hspd = Gml.var(world, self, :hspd)

    if abs(hspd) > 0 and Input.down?(world, self, player, 8) and state in @runner_states,
      do:
        wall_move(
          Gml.put(world, self, %{facingXScale: if(hspd > 0, do: 1, else: -1)}),
          self,
          hspd
        ),
      else: world
  end

  defp wall_move(world, self, hspd) do
    vspd = Gml.var(world, self, :vspd)
    %Instance{x: x, y: y} = World.fetch(world, self)
    facing = Gml.var(world, self, :facingXScale)

    cond do
      vspd <= 0 and abs(hspd) - 1 > 0 ->
        next_state(world, self, 53)

      vspd > 0 and not Gml.truthy?(Gml.var(world, self, :onGround)) and
          meeting?(world, self, {x + facing * 4, y}, "Block") ->
        next_state(world, self, 62)

      true ->
        world
    end
  end

  defp ledge_from_fall(world, self) do
    if Gml.var(world, self, :state) in @falling_states and
         not Gml.truthy?(Gml.var(world, self, :onGround)),
       do: grab_ledge(world, self) |> elem(1),
       else: world
  end

  defp grab_ledge(world, self) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    case Gml.nearest(world, {x, y}, "Ledge") do
      nil -> {false, world}
      ledge -> reach(world, self, World.fetch(world, ledge))
    end
  end

  defp reach(world, self, %Instance{x: lx, y: ly}) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    toward = if lx > x, do: 1, else: 0
    held = Input.down?(world, self, Gml.var(world, self, :playerIndex), toward)
    middle = y - @mask_height * 0.5

    if held and :math.sqrt((lx - x) * (lx - x) + (ly - middle) * (ly - middle)) < 7,
      do: {true, next_state(world, self, 36)},
      else: {false, world}
  end

  defp around({x, y}, try) do
    reach = div(try - 1, 4) + 1
    {dx, dy} = Enum.at([{1, 0}, {0, -1}, {-1, 0}, {0, 1}], rem(try - 1, 4))
    {x + dx * reach, y + dy * reach}
  end

  defp meeting?(world, self, position, name) do
    case World.object_index(world, name) do
      nil -> false
      object -> Collide.meeting?(world, self, position, object)
    end
  end
end
