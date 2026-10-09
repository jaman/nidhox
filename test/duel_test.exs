defmodule Nidhox.DuelTest do
  use ExUnit.Case, async: true

  @moduletag :copy

  alias Nidhox.{Blade, Duel, Fencer, Terrain}

  @terrain %Terrain{solids: [], platforms: [], size: {400, 200}}

  defp facing_off(attacker_stance, defender_stance, opts \\ []) do
    attacker = %{
      Fencer.new(1, {100, 150}, 1)
      | stance: attacker_stance,
        action: :thrust,
        timer: 4,
        age: 100
    }

    defender = %{
      Fencer.new(2, {140, 150}, -1)
      | stance: defender_stance,
        age: 100,
        stance_changed: Keyword.get(opts, :changed, -100)
    }

    %{1 => attacker, 2 => defender}
  end

  test "a thrust at the height of a facing guard is parried and both are knocked back" do
    {fencers, _swords, events} = Duel.step(facing_off(:middle, :middle), [], @terrain)

    assert {:parried, _point} = hd(events)
    assert fencers[1].action == :ready and fencers[2].action == :ready
    assert elem(fencers[1].velocity, 0) < 0 and elem(fencers[2].velocity, 0) > 0
  end

  test "a thrust at another height kills" do
    {fencers, swords, events} = Duel.step(facing_off(:low, :high), [], @terrain)

    assert events == [{:killed, 1, 2}]
    assert fencers[2].action == :dead
    assert length(swords) == 1
  end

  test "moving to the attacker's height just before the thrust disarms the attacker" do
    window = Duel.parry_window()

    {fencers, swords, events} =
      Duel.step(facing_off(:middle, :middle, changed: 100 - window), [], @terrain)

    assert {:disarmed, 1} in events
    refute fencers[1].armed
    assert fencers[2].armed
    assert length(swords) == 1
  end

  test "a high guard facing a thrown sword knocks it down" do
    guard = %{Fencer.new(2, {200, 150}, -1) | stance: :high}
    thrower = %{Fencer.new(1, {100, 150}, 1) | armed: false}

    sword = %{
      position: {170, 150 - Blade.high()},
      velocity: {5.5, 0.0},
      flying: true,
      thrower: 1,
      age: 0
    }

    {fencers, [knocked], events} = Duel.step(%{1 => thrower, 2 => guard}, [sword], @terrain)

    assert {:parried, _point} = hd(events)
    refute knocked.flying
    assert fencers[2].action == :ready
  end

  test "blades at the same height stop each other; blades at different heights pass" do
    close = fn one, two ->
      %{
        1 => %{Fencer.new(1, {100, 150}, 1) | stance: one, age: 100},
        2 => %{Fencer.new(2, {124, 150}, -1) | stance: two, age: 100}
      }
    end

    {apart, _swords, []} = Duel.step(close.(:middle, :middle), [], @terrain)
    {{x1, _}, {x2, _}} = {apart[1].position, apart[2].position}
    assert x1 < 100 and x2 > 124

    {passed, _swords, []} = Duel.step(close.(:high, :low), [], @terrain)
    assert passed[1].position == {100, 150} and passed[2].position == {124, 150}
  end

  test "a divekick landing on a standing fencer knocks it down and bounces the kicker" do
    kicker = %{
      Fencer.new(1, {100, 140}, 1)
      | action: :divekick,
        grounded: false,
        velocity: {3.5, 3.5}
    }

    standing = Fencer.new(2, {106, 150}, -1)

    {fencers, _swords, events} = Duel.step(%{1 => kicker, 2 => standing}, [], @terrain)

    assert {:floored, 2} in events
    assert fencers[2].action == :floored
    assert fencers[1].action == :ready and elem(fencers[1].velocity, 0) < 0
  end

  test "a sweep knocks down a fencer within the leg's reach" do
    [active | _] = Enum.to_list(Fencer.sweep_active())
    sweeper = %{Fencer.new(1, {100, 150}, 1) | action: :sweep, timer: active}

    {fencers, _swords, events} =
      Duel.step(%{1 => sweeper, 2 => Fencer.new(2, {110, 150}, -1)}, [], @terrain)

    assert {:floored, 2} in events
    assert fencers[2].action == :floored
  end

  test "tearing out a knocked-down fencer's heart kills it" do
    tearing = %{Fencer.new(1, {100, 150}, 1) | action: :heart, timer: Fencer.heart_kill()}
    floored = %{Fencer.new(2, {110, 150}, -1) | action: :floored, timer: 10}

    {fencers, _swords, events} = Duel.step(%{1 => tearing, 2 => floored}, [], @terrain)

    assert {:killed, 1, 2} in events
    assert fencers[2].action == :dead
  end

  test "moving a blade into the opponent's crossing blade disarms the opponent" do
    mover = %{Fencer.new(1, {100, 150}, 1) | stance: :middle, age: 100, stance_changed: 100}
    holder = %{Fencer.new(2, {140, 150}, -1) | stance: :middle, age: 100}

    {fencers, swords, events} = Duel.step(%{1 => mover, 2 => holder}, [], @terrain)

    assert {:disarmed, 2} in events
    refute fencers[2].armed
    assert length(swords) == 1
  end
end
