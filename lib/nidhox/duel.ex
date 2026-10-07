defmodule Nidhox.Duel do
  @moduledoc """
  What happens between the two fencers and the swords in play, each step.

    * A thrust meets the opponent's blade when the opponent is armed, faces the
      attacker, holds the same height and stands within reach: a parry, knocking both
      back. If the opponent moved to that height within `parry_window/0` steps, the
      attacker's sword is knocked out of its hand instead.
    * A thrust that is not parried and whose blade, from hand to point, crosses the
      opponent's body kills it.
    * A throw lets the sword fly level at high height. A flying sword that reaches a
      fencer other than its thrower kills it, unless that fencer is armed, holds its
      blade high and faces the sword, which knocks the sword down. A flying sword that
      hits something solid falls.
    * A punch lands on an armed opponent within reach and facing it, knocking the
      opponent's sword out of its hand.
    * A sword out of a hand falls until it rests on something; an unarmed fencer standing
      over a resting sword picks it up.

  `step/3` gives the fencers and swords after one step, and what happened: `{:killed,
  killer, victim}`, `{:parried, point}` and `{:disarmed, side}` events.
  """

  alias Nidhox.{Fencer, Terrain}

  @parry_window 6
  @parry_push 1.8
  @throw_release 4
  @throw_speed 5.5
  @flight_steps 40
  @gravity 0.2
  @punch_reach 14
  @pickup {8, 12}

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
  @spec step(fencers(), [sword()], Terrain.t()) :: {fencers(), [sword()], list()}
  def step(fencers, swords, terrain) do
    {fencers, swords, events} =
      Enum.reduce([1, 2], {fencers, swords, []}, fn side, acc -> attacks(acc, side) end)

    {swords, fencers, events} = fly(swords, fencers, terrain, events)
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

  defp attacks({fencers, swords, events}, side) do
    attacker = fencers[side]
    defender = fencers[other(side)]

    cond do
      Fencer.thrusting?(attacker) -> thrust({fencers, swords, events}, attacker, defender)
      throws?(attacker) -> throw({fencers, swords, events}, attacker)
      Fencer.punching?(attacker) -> punch({fencers, swords, events}, attacker, defender)
      true -> {fencers, swords, events}
    end
  end

  defp thrust({fencers, swords, events}, attacker, defender) do
    point = Fencer.point(attacker, Fencer.reach())

    cond do
      parries?(defender, attacker) and defender.age - defender.stance_changed <= @parry_window ->
        {Map.put(fencers, attacker.side, %{Fencer.knock(attacker, 0.0) | armed: false}),
         [dropped(attacker) | swords], [{:disarmed, attacker.side}, {:parried, point} | events]}

      parries?(defender, attacker) ->
        push = attacker.facing * @parry_push

        {fencers
         |> Map.put(attacker.side, Fencer.knock(attacker, -push))
         |> Map.put(defender.side, Fencer.knock(defender, push)), swords,
         [{:parried, point} | events]}

      Fencer.cut?(defender, attacker, Fencer.reach()) ->
        killed(fencers, swords, events, attacker.side, defender)

      true ->
        {fencers, swords, events}
    end
  end

  defp parries?(%Fencer{action: :dead}, _attacker), do: false

  defp parries?(%Fencer{} = defender, %Fencer{} = attacker) do
    {x, _} = attacker.position
    {dx, _} = defender.position

    defender.armed and defender.facing == -attacker.facing and defender.stance == attacker.stance and
      abs(dx - x) <= Fencer.reach() + 12
  end

  defp throws?(%Fencer{action: :throw, timer: @throw_release, armed: true}), do: true
  defp throws?(_fencer), do: false

  defp throw({fencers, swords, events}, %Fencer{position: {x, y}, facing: facing} = thrower) do
    sword = %{
      position: {x + facing * 6, y - Fencer.height(:high)},
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
      {Map.put(fencers, defender.side, %{
         Fencer.knock(defender, attacker.facing * 1.2)
         | armed: false
       }), [dropped(defender) | swords], [{:disarmed, defender.side} | events]}
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

  defp fly(swords, fencers, terrain, events) do
    {_width, height} = terrain.size

    Enum.reduce(swords, {[], fencers, events}, fn sword, {kept, fencers, events} ->
      sword = move(sword, terrain)
      {_x, y} = sword.position

      cond do
        y > height + 40 -> {kept, fencers, events}
        sword.flying -> strike(sword, kept, fencers, events)
        true -> {[sword | kept], fencers, events}
      end
    end)
  end

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
    target =
      Enum.find_value([1, 2], fn side ->
        if side != sword.thrower and Fencer.struck?(fencers[side], sword.position),
          do: fencers[side]
      end)

    case target do
      nil ->
        {[sword | kept], fencers, events}

      %Fencer{armed: true, stance: :high} = guard
      when guard.facing * elem(sword.velocity, 0) < 0 ->
        {vx, _} = sword.velocity

        {[%{sword | flying: false, velocity: {-vx * 0.3, -1.5}} | kept], fencers,
         [{:parried, sword.position} | events]}

      victim ->
        {fencers, _swords, events} = killed(fencers, [], events, sword.thrower, victim)
        {[%{sword | flying: false, velocity: {0.0, 0.0}} | kept], fencers, events}
    end
  end

  defp pick_up(fencers, swords) do
    Enum.reduce([1, 2], {fencers, swords}, fn side, {fencers, swords} ->
      fencer = fencers[side]

      case Enum.find(swords, &pickable?(fencer, &1)) do
        nil -> {fencers, swords}
        sword -> {Map.put(fencers, side, %{fencer | armed: true}), List.delete(swords, sword)}
      end
    end)
  end

  defp pickable?(
         %Fencer{armed: false, action: :ready, grounded: true, position: {x, y}},
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
