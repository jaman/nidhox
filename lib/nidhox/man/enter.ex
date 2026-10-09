defmodule Nidhox.Man.Enter do
  @moduledoc """
  `processNextState`: a fencer takes the state it was set to (`nextState`), as the game's
  code does it each step before the state's behaviour.

  Nothing changes while `nextState` is −1. Stomped (68) it may only evaporate (24);
  caught on a sword (5) it may only fall dead (26); entering the screen (23) it ignores
  falling head first (27). Otherwise `state` becomes `nextState` and `nextState` −1.
  A change of state:

    * a hit (`hitFlag`) is counted as a knockdown (`knockDowns`) and cleared
    * `frame`, `buttonHeldCounter` and `stateCounter` start again; the weapon is hidden
    * standing up to fence (29) from a crouch, with its sword crossing an opponent who is
      not stabbed, falling, down or stomped, it stands on the stab instead (67)

  and then the new state's entry runs (`enter/3`), as the game's switch has them —
  sounds where the fencer stands, its speed and stance set, dust, blood, its weapon
  dropped, a kill counted for its opponent (`Nidhox.Objects.MatchStats`).
  """

  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Bout.Overlap
  alias Nidhox.Gml
  alias Nidhox.Man.{Query, State, Weapon}
  alias Nidhox.Objects.{BloodDrop, MatchStats, Particles, System}

  @noone -4
  @rings [80, 81, 82]
  @screams 95..108
  @thuds [83, 84]
  @collapses [208, 209, 210, 369]

  @doc "The world after fencer `self` takes its next state (`processNextState`)."
  @spec process(World.t(), non_neg_integer()) :: World.t()
  def process(%World{} = world, self) do
    previous = State.get(world, self, :state)
    next = Gml.var(world, self, :nextState, -1)

    if held_back?(previous, next) do
      world
    else
      world = State.put(world, self, %{state: next, nextState: -1})
      if next != previous, do: changed(world, self, previous), else: world
    end
  end

  defp held_back?(_previous, -1), do: true
  defp held_back?(68, next), do: next != 24
  defp held_back?(5, next), do: next != 26
  defp held_back?(23, 27), do: true
  defp held_back?(_previous, _next), do: false

  defp changed(world, self, previous) do
    world =
      if Gml.truthy?(State.get(world, self, :hitFlag)),
        do: State.put(world, self, %{hitFlag: 0, knockDowns: State.get(world, self, :knockDowns) + 1}),
        else: world

    world =
      world
      |> State.put(self, %{frame: 0, buttonHeldCounter: 0, stateCounter: 0})
      |> show_weapon(self, false)
      |> stand_on_stab(self)

    enter(world, self, State.get(world, self, :state), previous)
  end

  defp stand_on_stab(world, self) do
    with 29 <- State.get(world, self, :state),
         true <- Gml.truthy?(State.get(world, self, :lastCrouched)),
         other when other != nil <- Query.by_player(world, Query.other_player(State.get(world, self, :playerIndex))),
         false <- Query.stabbed?(world, other),
         false <- Query.collapsing?(world, other),
         false <- Query.knocked_down?(world, other),
         true <- Gml.var(world, other, :state) != 68,
         weapon when weapon != @noone <- State.get(world, self, :weapon),
         %Instance{} <- World.fetch(world, weapon),
         true <- Overlap.held?(world, weapon, Gml.var(world, other, :flesh, @noone)) do
      State.put(world, self, %{state: 67})
    else
      _ -> world
    end
  end

  defp enter(world, self, 1, _previous) do
    world
    |> sound(self, 21)
    |> ring_with_sword(self)
    |> State.put(self, %{stance: 3, vspd: -3, hspd: facing(world, self) * -3})
  end

  defp enter(world, self, 3, _previous),
    do: State.put(world, self, %{hspd: State.hspd(world, self) * 0.7, vspd: -1.5})

  defp enter(world, self, state, _previous) when state in [4, 67] do
    world
    |> State.put(self, %{hspd: 0, vspd: 0})
    |> Query.face_opponent(self)
    |> sound(self, 83)
  end

  defp enter(world, self, 5, _previous) do
    world
    |> State.put(self, %{hspd: 0, vspd: 0})
    |> kill_for_opponent(self)
    |> Query.face_opponent(self)
    |> drop_lower(self)
    |> onto_opponent(self)
  end

  defp enter(world, self, 8, _previous) do
    world
    |> State.put(self, %{hspd: 2 * facing(world, self), vspd: -0.75})
    |> sound(self, 112)
  end

  defp enter(world, self, 11, _previous) do
    world
    |> sound(self, 21)
    |> State.put(self, %{stance: 3, vspd: -3.4})
    |> run_jump(self)
    |> dust(self)
  end

  defp enter(world, self, 13, _previous), do: State.put(world, self, %{hspd: 0, vspd: 0})

  defp enter(world, self, 14, _previous) do
    world =
      cond do
        State.down?(world, self, 0) -> State.put(world, self, %{facingXScale: -1})
        State.down?(world, self, 1) -> State.put(world, self, %{facingXScale: 1})
        true -> world
      end

    world
    |> State.put(self, %{hspd: 3.96 * facing(world, self), vspd: 0.75})
    |> sound(self, 112)
    |> sound(self, 113)
  end

  defp enter(world, self, 15, _previous),
    do: State.put(world, self, %{vspd: -2.3, hspd: State.hspd(world, self) * 0.25})

  defp enter(world, self, 16, _previous), do: dust(world, self)

  defp enter(world, self, state, _previous) when state in [17, 33] do
    world = if state == 17, do: drop(world, self), else: world

    world =
      if state == 33 do
        {groan, world} = Gml.choose(world, [18, 19, 20])
        sound(world, self, groan)
      else
        world
      end

    State.put(world, self, %{recoveryTimer: 10})
  end

  defp enter(world, self, state, _previous) when state in [18, 19, 25], do: State.put(world, self, %{stance: 3})

  defp enter(world, self, 22, _previous) do
    world
    |> sound(self, 21)
    |> State.put(self, %{stance: 3, vspd: -3.8, hspd: facing(world, self)})
  end

  defp enter(world, self, 24, _previous) do
    world
    |> State.put(self, %{hspd: 0})
    |> sound(self, 116)
    |> sound(self, 117)
  end

  defp enter(world, self, 26, _previous),
    do: State.put(world, self, %{hspd: 0, vspd: max(State.get(world, self, :vspd), 0)})

  defp enter(world, self, state, _previous) when state in [27, 28, 77] do
    world = if state == 77, do: world |> drop(self) |> sound(self, 25) |> sound(self, 11), else: world
    world = face_motion(world, self)
    if state == 77, do: State.put(world, self, %{hspd: State.hspd(world, self) * 1.25}), else: world
  end

  defp enter(world, self, 29, previous) do
    world = world |> ring(self) |> State.put(self, %{vspd: 0}) |> show_weapon(self, true)
    world = if previous == 54, do: State.put(world, self, %{stance: 1}), else: world
    world = if previous in [9, 58], do: State.put(world, self, %{stance: 2}), else: world

    world
    |> State.put(self, %{turnAroundTimer: 0, turnAroundFlag: 1})
    |> Query.face_opponent(self)
  end

  defp enter(world, self, state, _previous) when state in [30, 31], do: show_weapon(world, self, true)

  defp enter(world, self, 32, _previous), do: world |> show_weapon(self, false) |> Query.face_opponent(self)

  defp enter(world, self, 35, _previous) do
    hspd = Gml.clamp(State.hspd(world, self) * 0.7, -2, 2)
    State.put(world, self, %{hspd: hspd, vspd: 2})
  end

  defp enter(world, self, 36, previous) do
    world = State.put(world, self, %{hspd: 0, vspd: 0})
    %Instance{x: x, y: y} = World.fetch(world, self)

    case Gml.nearest(world, {x, y}, "Ledge") do
      nil ->
        world

      ledge ->
        %Instance{x: lx, y: ly} = World.fetch(world, ledge)
        facing = Gml.clamp((lx - x) * 1000, -1, 1)

        world
        |> State.put(self, %{facingXScale: facing})
        |> World.update(self, &%{&1 | x: lx - facing * 2, y: ly + 20})
        |> State.pose(self, if(previous == 10, do: 245, else: 244))
    end
  end

  defp enter(world, self, state, _previous) when state in [37, 39] do
    world
    |> Query.face_opponent(self)
    |> State.put(self, %{hspd: 0, vspd: 0})
    |> kill_for_opponent(self)
  end

  defp enter(world, self, 38, _previous) do
    world =
      world
      |> drop(self)
      |> sound(self, 25)
      |> sound(self, 11)
      |> Query.face_opponent(self)

    world = State.put(world, self, %{hspd: -facing(world, self) * 0.8})
    Enum.reduce(1..3, world, fn _drop, world -> bleed_face(world, self) end)
  end

  defp enter(world, self, 40, _previous) do
    world
    |> State.put(self, %{vspd: -2.5, hspd: facing(world, self) * -1.75})
    |> drop(self)
  end

  defp enter(world, self, 41, _previous) do
    world =
      world
      |> drop(self)
      |> sound(self, 25)
      |> sound(self, 11)
      |> Query.face_opponent(self)

    State.put(world, self, %{vspd: -4, hspd: -facing(world, self) * 3})
  end

  defp enter(world, self, 43, _previous) do
    world
    |> sound(self, 43)
    |> ring_with_sword(self)
    |> State.put(self, %{stance: 3, vspd: -5.4})
    |> run_jump(self)
    |> dust(self)
  end

  defp enter(world, self, 44, _previous) do
    world
    |> sound(self, 21)
    |> State.put(self, %{stance: 3, vspd: -5.4})
    |> run_jump(self)
    |> dust(self)
  end

  defp enter(world, self, state, _previous) when state in [45, 70] do
    push = if state == 45, do: 1, else: 0.25
    world = Query.face_opponent(world, self)

    world
    |> State.put(self, %{hspd: State.hspd(world, self) + facing(world, self) * push})
    |> sound(self, 22)
    |> dust(self)
  end

  defp enter(world, self, 47, _previous) do
    world
    |> State.put(self, %{facingXScale: -facing(world, self), hspd: 0, vspd: 0})
    |> State.pose(self, 225)
  end

  defp enter(world, self, 48, _previous) do
    world =
      world
      |> State.put(self, %{vspd: 0})
      |> show_weapon(self, true)
      |> Query.face_opponent(self)
      |> Nidhox.Man.Physics.apply_horizontal_friction(self, 1)

    world =
      world
      |> State.put(self, %{hspd: State.hspd(world, self) + facing(world, self)})
      |> sound(self, 74)

    {swish, world} = Gml.choose(world, [110, 111])
    sound(world, self, swish)
  end

  defp enter(world, self, state, _previous) when state in [49, 55] do
    world = Query.face_opponent(world, self)

    world
    |> State.put(self, %{hspd: State.hspd(world, self) + facing(world, self)})
    |> sound(self, 22)
  end

  defp enter(world, self, 50, _previous) do
    world
    |> sound(self, 21)
    |> ring_with_sword(self)
    |> State.put(self, %{stance: 3, vspd: -1.25, hspd: facing(world, self) * -1.75})
  end

  defp enter(world, self, 52, _previous), do: State.put(world, self, %{vspd: 0})

  defp enter(world, self, 53, _previous),
    do: world |> sound(self, 26) |> State.put(self, %{stance: 2, hspd: 0})

  defp enter(world, self, 58, _previous) do
    world
    |> sound(self, 26)
    |> State.put(self, %{hspd: Gml.clamp(State.hspd(world, self) * 100, -2.75, 2.75)})
  end

  defp enter(world, self, 59, _previous) do
    world
    |> State.put(self, %{hspd: facing(world, self) * 2})
    |> sound(self, 121)
    |> dust(self)
  end

  defp enter(world, self, 61, _previous), do: sound(world, self, 26)

  defp enter(world, self, 62, _previous),
    do: world |> sound(self, 26) |> State.put(self, %{hspd: 0, vspd: 0})

  defp enter(world, self, 63, _previous) do
    world
    |> drop(self)
    |> stabbed_cry(self)
    |> State.put(self, %{stabCounter: 0})
    |> kill_for_opponent(self)
  end

  defp enter(world, self, 64, _previous) do
    world
    |> stabbed_cry(self)
    |> State.put(self, %{hspd: 0, vspd: 0})
    |> kill_for_opponent(self)
  end

  defp enter(world, self, 65, _previous) do
    world
    |> State.put(self, %{hspd: Gml.clamp(State.hspd(world, self), -2, 2)})
    |> drop(self)
    |> stabbed_cry(self)
    |> State.put(self, %{stabCounter: 0})
    |> kill_for_opponent(self)
  end

  defp enter(world, self, 66, _previous) do
    turn = Gml.round(State.get(world, self, :playerIndex) + System.get(world, :frame))
    collapse = Enum.at(@collapses, cycle(turn, 0, 3))

    State.put(world, self, %{collapseAnimation: collapse, hspd: 0, vspd: 0})
  end

  defp enter(world, self, 68, _previous),
    do: world |> State.put(self, %{hspd: 0, vspd: 0}) |> kill_for_opponent(self)

  defp enter(world, self, 69, _previous),
    do: world |> State.put(self, %{hspd: 0, vspd: 0}) |> sound(self, 120)

  defp enter(world, self, 72, _previous), do: Query.face_opponent(world, self)

  defp enter(world, self, 73, _previous), do: world |> Query.face_opponent(self) |> sound(self, 59)

  defp enter(world, self, 76, _previous) do
    world =
      world
      |> drop(self)
      |> sound(self, 25)
      |> sound(self, 11)

    State.put(world, self, %{hspd: State.hspd(world, self) * 1.25})
  end

  defp enter(world, self, 79, _previous),
    do: State.put(world, self, %{vspd: -3, hspd: facing(world, self) * 2})

  defp enter(world, _self, _state, _previous), do: world

  defp facing(world, self), do: State.get(world, self, :facingXScale)

  defp sound(world, self, sound), do: State.sound(world, self, sound)

  defp ring(world, self) do
    {ring, world} = Gml.choose(world, @rings)
    sound(world, self, ring)
  end

  defp ring_with_sword(world, self),
    do: if(State.type(world, self) == 2, do: ring(world, self), else: world)

  defp run_jump(world, self) do
    if abs(State.hspd(world, self)) - 2.3 > 1.0e-5,
      do: State.put(world, self, %{vspd: State.get(world, self, :vspd) - 0.54}),
      else: world
  end

  defp dust(world, self) do
    Enum.reduce(1..3, world, fn _puff, world ->
      %Instance{x: x, y: y} = World.fetch(world, self)
      {across, world} = Gml.random_range(world, -2, 2)
      Particles.dust_at(world, {x + across, y})
    end)
  end

  defp drop(world, self), do: world |> Weapon.drop(self) |> elem(1)

  defp drop_lower(world, self) do
    case Weapon.drop(world, self) do
      {nil, world} -> world
      {dropped, world} -> World.update(world, dropped, &%{&1 | y: &1.y + 20})
    end
  end

  defp onto_opponent(world, self) do
    case Query.by_player(world, Query.other_player(State.get(world, self, :playerIndex))) do
      nil ->
        world

      other ->
        %Instance{x: ox, y: oy} = World.fetch(world, other)
        World.update(world, self, &%{&1 | x: ox - facing(world, self) * 20, y: oy - 11})
    end
  end

  defp kill_for_opponent(world, self),
    do: MatchStats.add_kill(world, Query.other_player(State.get(world, self, :playerIndex)))

  defp stabbed_cry(world, self) do
    {thud, world} = Gml.choose(world, @thuds)
    world = sound(world, self, thud)
    {scream, world} = Gml.choose(world, Enum.to_list(@screams))
    sound(world, self, scream)
  end

  defp bleed_face(world, self) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    colour = World.fetch(world, State.get(world, self, :flesh)).image_blend
    world |> BloodDrop.bleed({x, y - 32}, colour) |> elem(1)
  end

  defp face_motion(world, self) do
    hspd = State.hspd(world, self)

    cond do
      hspd > 0 -> State.put(world, self, %{facingXScale: 1})
      hspd < 0 -> State.put(world, self, %{facingXScale: -1})
      true -> world
    end
  end

  defp show_weapon(world, self, visible) do
    case World.fetch(world, State.get(world, self, :weapon)) do
      nil -> world
      %Instance{id: weapon} -> World.update(world, weapon, &%{&1 | visible: visible})
    end
  end

  defp cycle(value, low, high) do
    range = high - low
    offset = :math.fmod((value - low) * 1.0, range * 1.0)
    trunc(if(offset < 0, do: offset + range, else: offset) + low)
  end
end
