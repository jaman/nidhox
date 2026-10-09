defmodule Nidhox.Duel do
  @moduledoc """
  What happens between the two fencers and the swords in play, each step.

    Blades and bodies are `Nidhox.Blade`'s: what each fencer's pose draws.

    * A thrust whose blade crosses the opponent's blade is parried, knocking both back.
      If the opponent moved to that height within `parry_window/0` steps, the
      attacker's sword is knocked out of its hand instead.
    * A thrust that is not parried and whose blade crosses the opponent's body kills it.
    * Blades held at the same height stop each other: when they cross by more than
      `@crossing` pixels, and neither fencer is thrusting, both fencers are pushed back
      until they cross by no more.
    * A throw lets the sword fly level from the height of a high guard's hand. A flying sword that meets a
      blade held facing it is knocked down; one that reaches the body of a fencer other
      than its thrower kills it. A flying sword that hits something solid falls.
    * A punch lands on an armed opponent within reach and facing it, knocking the
      opponent's sword out of its hand.
    * A divekick whose foot (`@foot` pixels ahead, at the feet) lands on a standing
      fencer's body knocks it down, and the kicker bounces off.
    * A sweep landing on a fencer standing on the ground within the leg's reach — the
      furthest the copy's `sManSweepTheLeg` reaches — knocks it down.
    * Tearing out a knocked-down fencer's heart kills it.
    * A fencer moving its blade up or down into the opponent's crossing blade knocks the
      opponent's sword out of its hand.
    * A sword out of a hand falls until it rests on something; an unarmed fencer ducking
      over a resting sword picks it up, and one standing catches a sword falling past its
      hands (`@catching`: within so many pixels across, between so many above its feet).

  The bout's `Nidhox.Rules` change some of this: a thrust that does not kill, a divekick
  that kills, a thrown sword that turns back once its flight is spent and is caught by
  its thrower's hand (`@hand` pixels up from its feet).

  Events also include `{:floored, side}` and `{:heart, side}`.

  `step/3` gives the fencers and swords after one step, and what happened: `{:killed,
  killer, victim}`, `{:parried, point}` and `{:disarmed, side}` events.
  """

  alias Nidhox.{Assets, Blade, Fencer, Rules, Terrain}

  @parry_window 6
  @foot 6
  @hand 20
  @crossing 6
  @parry_push 1.8
  @throw_release 4
  @throw_speed 5.5
  @flight_steps 40
  @gravity 0.2
  @punch_reach 14
  @pickup {8, 12}
  @catching {10, 30, 10}

  @type sword :: %{
          position: {number(), number()},
          velocity: {number(), number()},
          flying: boolean(),
          thrower: 1 | 2 | nil,
          age: non_neg_integer()
        }
  @type fencers :: %{1 => Fencer.t(), 2 => Fencer.t()}

  @doc "The steps before a parry within which moving to the attacker's height disarms it."
  @spec parry_window() :: pos_integer()
  def parry_window, do: @parry_window

  @doc "The fencers, the swords, and what happened, one step on."
  @spec step(fencers(), [sword()], Terrain.t(), Rules.t()) :: {fencers(), [sword()], list()}
  def step(fencers, swords, terrain, rules \\ %Rules{}) do
    {fencers, swords, events} =
      Enum.reduce([1, 2], {fencers, swords, []}, fn side, acc -> attacks(acc, side, rules) end)

    fencers = hold_apart(fencers, terrain)
    {swords, fencers, events} = fly(swords, fencers, terrain, events, rules)
    {fencers, swords} = pick_up(fencers, swords)
    {fencers, swords, Enum.reverse(events)}
  end

  @doc "A sword falling from a fencer's hand where it stands."
  @spec dropped(Fencer.t()) :: sword()
  def dropped(%Fencer{position: {x, y}, facing: facing}),
    do: %{
      position: {x, y - 20},
      velocity: {-facing * 1.5, -2.5},
      flying: false,
      thrower: nil,
      age: 0
    }

  defp attacks({fencers, swords, events}, side, rules) do
    attacker = fencers[side]
    defender = fencers[other(side)]

    cond do
      attacker.action == :divekick -> kick({fencers, swords, events}, attacker, defender, rules)
      Fencer.sweeping?(attacker) -> sweep({fencers, swords, events}, attacker, defender)
      heart?(attacker) -> heart({fencers, swords, events}, attacker, defender)
      moved_into?(attacker, defender) -> disarm({fencers, swords, events}, defender)
      Fencer.thrusting?(attacker) -> thrust({fencers, swords, events}, attacker, defender, rules)
      throws?(attacker) -> throw({fencers, swords, events}, attacker)
      Fencer.punching?(attacker) -> punch({fencers, swords, events}, attacker, defender)
      true -> {fencers, swords, events}
    end
  end

  defp thrust({fencers, swords, events}, attacker, defender, rules) do
    blade = Blade.of(attacker)
    guarded? = Blade.crossing(blade, Blade.of(defender)) > 0
    point = if blade, do: Blade.tip(blade), else: attacker.position

    cond do
      guarded? and defender.age - defender.stance_changed <= @parry_window ->
        {Map.put(fencers, attacker.side, Fencer.disarm(attacker, 0.0)),
         [dropped(attacker) | swords], [{:disarmed, attacker.side}, {:parried, point} | events]}

      guarded? ->
        push = attacker.facing * @parry_push

        {fencers
         |> Map.put(attacker.side, Fencer.knock(attacker, -push))
         |> Map.put(defender.side, Fencer.knock(defender, push)), swords,
         [{:parried, point} | events]}

      Rules.thrusts_kill?(rules) and Blade.hits?(blade, Blade.body(defender)) ->
        killed(fencers, swords, events, attacker.side, defender)

      true ->
        {fencers, swords, events}
    end
  end

  defp kick(
         {fencers, swords, events},
         %Fencer{position: {x, y}, facing: facing} = attacker,
         defender,
         rules
       ) do
    cond do
      not standing?(defender) or not inside?(Blade.body(defender), {x + facing * @foot, y - 2}) ->
        {fencers, swords, events}

      Rules.kicks_kill?(rules) ->
        {fencers, swords, events} = killed(fencers, swords, events, attacker.side, defender)
        {Map.put(fencers, attacker.side, Fencer.bounce(attacker)), swords, events}

      true ->
        {fencers
         |> Map.put(defender.side, Fencer.knock_down(defender))
         |> Map.put(attacker.side, Fencer.bounce(attacker)), swords,
         [{:floored, defender.side} | events]}
    end
  end

  defp sweep(
         {fencers, swords, events},
         %Fencer{position: {x, _}, facing: facing},
         %Fencer{position: {dx, _}} = defender
       ) do
    if standing?(defender) and defender.grounded and (dx - x) * facing >= 0 and
         (dx - x) * facing <= sweep_reach() do
      {Map.put(fencers, defender.side, Fencer.knock_down(defender)), swords,
       [{:floored, defender.side} | events]}
    else
      {fencers, swords, events}
    end
  end

  defp heart?(%Fencer{action: :heart, timer: timer}), do: timer == Fencer.heart_kill()
  defp heart?(_fencer), do: false

  defp heart({fencers, swords, events}, attacker, %Fencer{action: :floored} = victim) do
    {fencers, swords, events} = killed(fencers, swords, events, attacker.side, victim)
    {fencers, swords, [{:heart, victim.side} | events]}
  end

  defp heart(acc, _attacker, _victim), do: acc

  defp moved_into?(
         %Fencer{armed: true, stance_changed: changed, age: age} = attacker,
         %Fencer{armed: true} = defender
       )
       when changed == age,
       do: Blade.crossing(Blade.of(attacker), Blade.of(defender)) > 0

  defp moved_into?(_attacker, _defender), do: false

  defp disarm({fencers, swords, events}, defender) do
    {Map.put(fencers, defender.side, Fencer.disarm(defender, 0.0)), [dropped(defender) | swords],
     [{:disarmed, defender.side} | events]}
  end

  defp standing?(%Fencer{action: action}), do: action not in [:dead, :floored]

  defp sweep_reach do
    for frame <- 0..(Assets.frame_count("sManSweepTheLeg") - 1), reduce: 0 do
      reach -> max(reach, elem(Assets.bounds({"sManSweepTheLeg", frame}), 2))
    end
  end

  defp throws?(%Fencer{action: :throw, timer: @throw_release, armed: true}), do: true
  defp throws?(_fencer), do: false

  defp throw({fencers, swords, events}, %Fencer{position: {x, y}, facing: facing} = thrower) do
    sword = %{
      position: {x + facing * 6, y - Blade.high()},
      velocity: {facing * @throw_speed, 0.0},
      flying: true,
      thrower: thrower.side,
      age: 0
    }

    {Map.put(fencers, thrower.side, %{thrower | armed: false}), [sword | swords], events}
  end

  defp punch({fencers, swords, events}, attacker, %Fencer{armed: true, action: action} = defender)
       when action != :dead do
    {x, _} = attacker.position
    {dx, _} = defender.position

    if ((dx - x) * attacker.facing) in 0..@punch_reach and defender.facing == -attacker.facing do
      {Map.put(fencers, defender.side, Fencer.disarm(defender, attacker.facing * 1.2)),
       [dropped(defender) | swords], [{:disarmed, defender.side} | events]}
    else
      {fencers, swords, events}
    end
  end

  defp punch(acc, _attacker, _defender), do: acc

  defp killed(fencers, swords, events, killer, %Fencer{} = victim) do
    swords = if victim.armed, do: [dropped(victim) | swords], else: swords

    {Map.put(fencers, victim.side, Fencer.kill(victim)), swords,
     [{:killed, killer, victim.side} | events]}
  end

  defp fly(swords, fencers, terrain, events, rules) do
    {_width, height} = terrain.size

    Enum.reduce(swords, {[], fencers, events}, fn sword, {kept, fencers, events} ->
      sword =
        if returning?(sword, rules),
          do: return(sword, fencers[sword.thrower]),
          else: move(sword, terrain)

      {_x, y} = sword.position

      cond do
        y > height + 40 ->
          {kept, fencers, events}

        returned?(sword, fencers) ->
          {kept, Map.update!(fencers, sword.thrower, &Fencer.catch_sword/1), events}

        sword.flying ->
          strike(sword, kept, fencers, events)

        true ->
          {[sword | kept], fencers, events}
      end
    end)
  end

  defp returning?(%{flying: true, thrower: thrower, age: age}, rules) when thrower != nil,
    do: Rules.boomerang?(rules) and age > @flight_steps

  defp returning?(_sword, _rules), do: false

  defp return(%{position: {x, y}} = sword, %Fencer{position: {tx, ty}, action: action})
       when action != :dead do
    {dx, dy} = {tx - x, ty - @hand - y}
    distance = max(:math.sqrt(dx * dx + dy * dy), 1.0)
    velocity = {dx / distance * @throw_speed, dy / distance * @throw_speed}

    %{
      sword
      | position: {x + elem(velocity, 0), y + elem(velocity, 1)},
        velocity: velocity,
        age: sword.age + 1
    }
  end

  defp return(sword, _thrower), do: %{sword | flying: false, age: sword.age + 1}

  defp returned?(%{flying: true, thrower: thrower, age: age, position: {x, y}}, fencers)
       when thrower != nil and age > @flight_steps do
    case fencers[thrower] do
      %Fencer{armed: false, action: action, position: {tx, ty}} when action != :dead ->
        abs(x - tx) <= @hand and abs(y - (ty - @hand)) <= @hand

      _other ->
        false
    end
  end

  defp returned?(_sword, _fencers), do: false

  defp move(%{flying: true} = sword, terrain) do
    {x, y} = sword.position
    {vx, vy} = sword.velocity
    vy = if sword.age > @flight_steps, do: vy + @gravity, else: vy
    next = {x + vx, y + vy}

    if Terrain.solid?(terrain, next),
      do: %{sword | flying: false, velocity: {-vx * 0.2, -1.0}, age: sword.age + 1},
      else: %{sword | position: next, velocity: {vx, vy}, age: sword.age + 1}
  end

  defp move(%{flying: false} = sword, terrain) do
    {x, y} = sword.position
    {vx, vy} = sword.velocity
    vy = vy + @gravity
    below = {x + vx, y + vy + 1}

    if vy > 0 and Terrain.solid?(terrain, below),
      do: %{sword | velocity: {0.0, 0.0}, age: sword.age + 1},
      else: %{
        sword
        | position: {x + vx * 0.98, y + vy},
          velocity: {vx * 0.98, vy},
          age: sword.age + 1
      }
  end

  defp strike(sword, kept, fencers, events) do
    {vx, _vy} = sword.velocity

    guard =
      Enum.find([1, 2], fn side ->
        blade = Blade.of(fencers[side])
        blade != nil and blade.facing * vx < 0 and Blade.touches?(blade, sword.position)
      end)

    target =
      Enum.find_value([1, 2], fn side ->
        if side != sword.thrower and inside?(Blade.body(fencers[side]), sword.position),
          do: fencers[side]
      end)

    case {guard, target} do
      {side, _target} when side != nil ->
        {[%{sword | flying: false, velocity: {-vx * 0.3, -1.5}} | kept], fencers,
         [{:parried, sword.position} | events]}

      {nil, nil} ->
        {[sword | kept], fencers, events}

      {nil, victim} ->
        {fencers, _swords, events} = killed(fencers, [], events, sword.thrower, victim)
        {[%{sword | flying: false, velocity: {0.0, 0.0}} | kept], fencers, events}
    end
  end

  defp inside?(nil, _point), do: false

  defp inside?({left, top, right, bottom}, {x, y}),
    do: x >= left and x <= right and y >= top and y <= bottom

  defp hold_apart(fencers, terrain) do
    one = fencers[1]
    two = fencers[2]
    crossing = Blade.crossing(Blade.of(one), Blade.of(two))

    if crossing > @crossing and not Fencer.thrusting?(one) and not Fencer.thrusting?(two) do
      back = (crossing - @crossing) / 2
      %{fencers | 1 => step_back(one, back, terrain), 2 => step_back(two, back, terrain)}
    else
      fencers
    end
  end

  defp step_back(
         %Fencer{position: position, facing: facing, velocity: {_vx, vy}} = fencer,
         back,
         terrain
       ) do
    {position, _velocity, _grounded} = Terrain.move(terrain, position, {-facing * back, 0.0})
    %{fencer | position: position, velocity: {0.0, vy}}
  end

  defp pick_up(fencers, swords) do
    Enum.reduce([1, 2], {fencers, swords}, fn side, {fencers, swords} ->
      fencer = fencers[side]

      cond do
        sword = Enum.find(swords, &pickable?(fencer, &1)) ->
          {Map.put(fencers, side, %{fencer | armed: true}), List.delete(swords, sword)}

        sword = Enum.find(swords, &catchable?(fencer, &1)) ->
          {Map.put(fencers, side, Fencer.catch_sword(fencer)), List.delete(swords, sword)}

        true ->
          {fencers, swords}
      end
    end)
  end

  defp catchable?(
         %Fencer{armed: false, action: :ready, position: {x, y}},
         %{flying: false, velocity: {_vx, vy}, position: {sx, sy}}
       )
       when vy > 0 do
    {reach_x, top, bottom} = @catching
    abs(sx - x) <= reach_x and sy >= y - top and sy <= y - bottom
  end

  defp catchable?(_fencer, _sword), do: false

  defp pickable?(
         %Fencer{armed: false, action: :duck, grounded: true, position: {x, y}},
         %{flying: false, velocity: {vx, vy}, position: {sx, sy}}
       )
       when vx == 0 and vy == 0 do
    {reach_x, reach_y} = @pickup
    abs(sx - x) <= reach_x and abs(sy - y) <= reach_y
  end

  defp pickable?(_fencer, _sword), do: false

  defp other(1), do: 2
  defp other(2), do: 1
end
