defmodule Nidhox.DuelTest do
  use ExUnit.Case, async: true

  alias Nidhox.{Duel, Fencer, Terrain}

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
      Fencer.new(2, {112, 150}, -1)
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
      position: {196, 150 - Fencer.height(:high)},
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
end
