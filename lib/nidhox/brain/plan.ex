defmodule Nidhox.Brain.Plan do
  @moduledoc """
  The computer player's plans (`aiStateMachine`), run each match frame before its
  action (`Nidhox.Brain.Act`). `run/2` first watches the fencers on the beat — every
  `round(beat)` frames of `System.frame + stateCounter`, some on 1.5 or 1.75 beats, one
  15 frames late — and may change the action or the next plan:

    * a cloud under its feet more than half gone: jump back to safety (55)
    * holding the high ground: plan 104; the opponent holding it over it: plan 107
    * leading with a log between them: plan 105
    * knocked down (47): get up (14); a thrown sword close: block it (6); on a wall:
      climb (8)
    * (on 1.75 beats, outside challenge mode) no opponent, or a collapsing or stabbed
      one: plan 105. An opponent in the air within 100 that is not hopping up or down
      (10, 11): block its dive kick with a sword (5), or dive kick (9). Leading and
      apart (past 64, or with a log between them): plan 105. The opponent leading,
      running for its goal past 64 and not behind it: throw the sword (29) or go
      and die (plan 106); in sudden death or while someone leads, a throw (29) at
      such an opponent too
    * the opponent knocked down while it is not: finish it (11); now and then (0.001 in
      100) a throw (29)

  In a log with the opponent on it while not leading, once its action is done: run out
  of the log (24). Outside plan 105, on the beat, a pause (20) at `90 × (1 − difficulty)`
  in 100. Then the plan itself:

  | plan | name | while in it |
  | --- | --- | --- |
  | 109 | wait for a new player | no action; jump every 120 frames; plan 102 once the opponent stands |
  | 108 | wait for control | no action; plan 102 once its fencer stands (not entering, collapsing or stabbed) |
  | 104 | hold the high ground | plan 102 when it no longer holds it; else approach the edge (1), pause (20), back off (4) or run to death (3), sweep kick (28) at an opponent on a wall; dive kick (9), approach (1) or find a sword (10) unarmed |
  | 107 | take the high ground | plan 102 once standing out of the low ground; climbs, throws, backs off, runs at the wall and dive kicks in turn |
  | 106 | suicide | while the opponent leads, run to death (25) when it runs for its goal; else plan 102 |
  | 102 | close the gap | run at the opponent (27); there, thrust now and then (19 at 30) and fence (103) with a sword or brawl (101) without |
  | 103 | fence | brawl when it loses its sword; close the gap past 90; guard (15) against a lunge off the half beat, throw (29), dive kick (9) and sweep kick (28) now and then; else guard, look for an opening (18), lunge (19), back off (4), pause (20) or jump over (16) |
  | 101 | brawl | fence once it has a sword; else melee actions in turn |
  | 105 | run to the goal | fence or brawl when the opponent stands ahead; close the gap when not leading; else run to the goal (26), now and then taunting (7) |

  Whether an action is taken is the personality's chance (`Nidhox.Brain.Personality`).
  """

  alias Cauldron2D.GameMaker.{Collide, Instance, World}
  alias Nidhox.Brain.{Buttons, Clock, Intent, Personality, Sense}
  alias Nidhox.Gml
  alias Nidhox.Man.Query
  alias Nidhox.Objects.{Match, System}

  @noone -4
  @fists 1
  @sword 2
  @knocked_down 47
  @lunging 48
  @hop_states [11, 10]
  @low 2
  @entering 23

  @doc "The world after `Brain` `self`'s plans for this frame (`aiStateMachine`)."
  @spec run(World.t(), non_neg_integer()) :: World.t()
  def run(%World{} = world, self) do
    world
    |> watch(self)
    |> leave_log(self)
    |> pause_now_and_then(self)
    |> plan(self, Gml.var(world, self, :state))
  end

  defp watch(world, self) do
    if Sense.present?(player(world, self)) do
      world
      |> on_beat(self, 1, 0, &step_off_cloud/2)
      |> on_beat(self, 1, 0, &take_high_ground/2)
      |> on_beat(self, 1, 15, &low_ground_or_log/2)
      |> on_beat(self, 1, 0, &knocked_down/2)
      |> on_beat(self, 1.5, 0, &thrown_sword/2)
      |> on_beat(self, 1, 0, &wall/2)
      |> outside_challenge(&on_beat(&1, self, 1.75, 0, fn world, self -> chase(world, self) end))
      |> on_beat(self, 1, 0, &finish/2)
      |> on_beat(self, 1, 0, &throw_now_and_then/2)
    else
      world
    end
  end

  defp on_beat(world, self, times, late, fun) do
    count = System.get(world, :frame) + Gml.var(world, self, :stateCounter) + late
    if Clock.on?(count, Clock.period(world, self, times)), do: fun.(world, self), else: world
  end

  defp outside_challenge(world, fun),
    do: if(Gml.exists?(world, "ChallengeMode"), do: world, else: fun.(world))

  defp step_off_cloud(world, self) do
    %Instance{x: x, y: y} = World.fetch(world, player(world, self))

    with object when is_integer(object) <- World.object_index(world, "NewCloudBlock"),
         cloud when cloud != nil <- Collide.at_point(world, {x, y + 16}, object),
         true <- Gml.lt?(1 - Gml.var(world, cloud, :frame) / (frames(world, cloud) - 1), 0.5) do
      Intent.set(world, self, 55)
    else
      _ -> world
    end
  end

  defp take_high_ground(world, self) do
    if Sense.holding_high_ground?(world, player(world, self)),
      do: Intent.next_state(world, self, 104),
      else: world
  end

  defp low_ground_or_log(world, self) do
    man = player(world, self)
    other = opponent(world, self)

    if Sense.present?(other) do
      world =
        if Sense.stuck_in_low_ground?(world, man),
          do: Intent.next_state(world, self, 107),
          else: world

      if leading?(world, self) and Sense.separated_by_log?(world, man, other),
        do: Intent.next_state(world, self, 105),
        else: world
    else
      world
    end
  end

  defp knocked_down(world, self) do
    if Gml.var(world, player(world, self), :state) == @knocked_down,
      do: Intent.set(world, self, 14),
      else: world
  end

  defp thrown_sword(world, self) do
    if Gml.eq?(Gml.var(world, self, :flyingSword, @noone), @noone),
      do: world,
      else: Intent.set(world, self, 6)
  end

  defp wall(world, self) do
    if Sense.on_wall?(world, player(world, self)), do: Intent.set(world, self, 8), else: world
  end

  defp chase(world, self) do
    other = opponent(world, self)

    cond do
      not Sense.present?(other) ->
        Intent.next_state(world, self, 105)

      Query.collapsing?(world, other) or Query.stabbed?(world, other) ->
        world |> Intent.next_state(self, 105) |> race(self)

      true ->
        world |> dive_at(self) |> race(self)
    end
  end

  defp dive_at(world, self) do
    other = opponent(world, self)
    state = Gml.var(world, other, :state)

    if Gml.lt?(distance(world, self), 100) and not Gml.truthy?(Gml.var(world, other, :onGround)) and
         state not in @hop_states do
      if Sense.weapon_type(world, player(world, self)) == @sword,
        do: Intent.set(world, self, 5),
        else: chance_set(world, self, 9, 100)
    else
      world
    end
  end

  defp race(world, self) do
    world
    |> run_ahead(self)
    |> chased(self)
    |> overtaken(self)
  end

  defp run_ahead(world, self) do
    man = player(world, self)
    other = opponent(world, self)
    apart = Gml.gt?(distance(world, self), 64) or Sense.separated_by_log?(world, man, other)

    if leading?(world, self) and apart and
         (not Sense.in_front?(world, other, man) or Sense.separated_by_log?(world, man, other)),
       do: Intent.next_state(world, self, 105),
       else: world
  end

  defp chased(world, self) do
    if Gml.eq?(Match.get(world, :leadingPlayerIndex), other_player(world, self)) and
         runaway?(world, self),
       do: throw_or_die(world, self),
       else: world
  end

  defp throw_or_die(world, self) do
    with @sword <- Sense.weapon_type(world, player(world, self)),
         {true, world} <- Personality.chance(world, self, 29, 100) do
      Intent.set(world, self, 29)
    else
      {false, world} -> Intent.next_state(world, self, 106)
      _fists -> Intent.next_state(world, self, 106)
    end
  end

  defp overtaken(world, self) do
    nobody =
      Gml.eq?(Match.get(world, :leadingPlayerIndex), 0) and
        not Gml.truthy?(Match.get(world, :sudden_death))

    if not nobody and not leading?(world, self) and runaway?(world, self) and
         Sense.weapon_type(world, player(world, self)) == @sword,
       do: chance_set(world, self, 29, 100),
       else: world
  end

  defp runaway?(world, self) do
    man = player(world, self)
    other = opponent(world, self)

    Gml.gt?(distance(world, self), 64) and not Sense.in_front?(world, man, other) and
      Sense.running_to_goal?(world, other)
  end

  defp finish(world, self) do
    other = opponent(world, self)

    if Gml.var(world, player(world, self), :state) != @knocked_down and Sense.present?(other) and
         Gml.var(world, other, :state) == @knocked_down,
       do: chance_set(world, self, 11, 100),
       else: world
  end

  defp throw_now_and_then(world, self) do
    if Sense.weapon_type(world, player(world, self)) == @sword,
      do: chance_set(world, self, 29, 0.001),
      else: world
  end

  defp leave_log(world, self) do
    man = player(world, self)
    other = opponent(world, self)

    if Sense.present?(man) and Sense.present?(other) and
         (Gml.truthy?(Gml.var(world, self, :actionCompleted)) or
            Gml.truthy?(Gml.var(world, self, :actionFailed))) and
         Gml.truthy?(Gml.var(world, man, :inLog)) and Gml.truthy?(Gml.var(world, other, :onLog)) and
         not leading?(world, self),
       do: Intent.set(world, self, 24),
       else: world
  end

  defp pause_now_and_then(world, self) do
    with false <- Gml.eq?(Gml.var(world, self, :state), 105),
         true <- Clock.on?(System.get(world, :frame), Clock.period(world, self, 1)),
         {true, world} <- Gml.prob(world, 90 * (1 - Gml.var(world, self, :difficulty))) do
      Intent.set(world, self, 20)
    else
      {false, world} -> world
      _ -> world
    end
  end

  defp plan(world, self, 109) do
    world = Intent.clear(world, self)

    world =
      if Clock.on?(System.get(world, :frame), 120), do: Buttons.press(world, self, 4), else: world

    if standing?(world, opponent(world, self)),
      do: Intent.next_state(world, self, 102),
      else: world
  end

  defp plan(world, self, 108) do
    world = Intent.clear(world, self)
    man = player(world, self)

    if Sense.present?(man) and Gml.var(world, man, :state) != @entering and standing?(world, man),
      do: Intent.next_state(world, self, 102),
      else: world
  end

  defp plan(world, self, 104) do
    if Sense.holding_high_ground?(world, player(world, self)),
      do: when_free(world, self, &high_ground/3),
      else: Intent.next_state(world, self, 102)
  end

  defp plan(world, self, 107) do
    man = player(world, self)

    if Gml.truthy?(Gml.var(world, man, :onGround)) and not Sense.stuck_in_low_ground?(world, man),
      do: Intent.next_state(world, self, 102),
      else: when_free(world, self, &low_ground/3)
  end

  defp plan(world, self, 106) do
    cond do
      Gml.exists?(world, "ChallengeMode") ->
        Intent.next_state(world, self, 102)

      not Gml.eq?(Match.get(world, :leadingPlayerIndex), other_player(world, self)) ->
        Intent.next_state(world, self, 102)

      true ->
        when_free(world, self, &suicide/3)
    end
  end

  defp plan(world, self, 102), do: when_free(world, self, &close_gap/3)
  defp plan(world, self, 103), do: fence(world, self)

  defp plan(world, self, 101) do
    if Sense.weapon_type(world, player(world, self)) != @fists,
      do: Intent.next_state(world, self, 103),
      else: when_free(world, self, &brawl/3)
  end

  defp plan(world, self, 105), do: run_to_goal(world, self)
  defp plan(world, _self, _state), do: world

  defp when_free(world, self, fun) do
    action = Gml.var(world, self, :action)

    if Gml.truthy?(Gml.var(world, self, :actionCompleted)) or Gml.eq?(action, -1),
      do: fun.(world, self, action),
      else: world
  end

  defp high_ground(world, self, 1) do
    if Gml.truthy?(Gml.var(world, self, :actionFailed)) do
      Intent.clear(world, self)
    else
      {action, world} = Gml.choose(world, [20, 4, 3])
      world = Intent.set(world, self, action)

      if Sense.on_wall?(world, opponent(world, self)),
        do: chance_set(world, self, 28, 100),
        else: world
    end
  end

  defp high_ground(world, self, _action) do
    choices =
      if Sense.weapon_type(world, player(world, self)) == @fists,
        do: [9, 1, 10],
        else: [20, 1, 3, 4]

    {action, world} = Gml.choose(world, choices)
    chance_set(world, self, action, 100)
  end

  defp low_ground(world, self, 8) do
    with @sword <- Sense.weapon_type(world, player(world, self)),
         {true, world} <- Gml.prob(world, 50) do
      first_taken(world, self, [{19, 40}, {15, 70}], 18)
    else
      {false, world} -> chance_set(world, self, 28, 100)
      _fists -> chance_set(world, self, 28, 100)
    end
  end

  defp low_ground(world, self, 29), do: Intent.set(world, self, 30)

  defp low_ground(world, self, 30) do
    if Sense.weapon_type(world, player(world, self)) == @fists do
      Intent.set(world, self, 10)
    else
      case Personality.chance(world, self, 29, 30) do
        {true, world} -> Intent.set(world, self, 29)
        {false, world} -> back_off_or_wall(world, self, 50)
      end
    end
  end

  defp low_ground(world, self, 10) do
    if Gml.truthy?(Gml.var(world, self, :actionFailed)),
      do: Intent.set(world, self, 2),
      else: chance_set(world, self, 29, 100)
  end

  defp low_ground(world, self, 2) do
    case Gml.prob(world, 25) do
      {true, world} -> Intent.set(world, self, 23)
      {false, world} -> dive_or_arm(world, self)
    end
  end

  defp low_ground(world, self, 9) do
    if Gml.truthy?(Gml.var(world, self, :actionFailed)) or
         Gml.truthy?(Gml.var(world, self, :actionCompleted)),
       do: Intent.set(world, self, 2),
       else: world
  end

  defp low_ground(world, self, _action) do
    world = Intent.clear(world, self)
    {action, world} = Gml.choose(world, [2, 4, 20, 9])
    chance_set(world, self, action, 100)
  end

  defp back_off_or_wall(world, self, percent) do
    case Gml.prob(world, percent) do
      {true, world} -> Intent.set(world, self, 2)
      {false, world} -> Intent.set(world, self, 23)
    end
  end

  defp dive_or_arm(world, self) do
    case Personality.chance(world, self, 9, 30) do
      {true, world} ->
        Intent.set(world, self, 9)

      {false, world} ->
        if Sense.weapon_type(world, player(world, self)) == @fists,
          do: chance_set(world, self, 10, 100),
          else: chance_set(world, self, 29, 100)
    end
  end

  defp suicide(world, self, _action) do
    if Sense.running_to_goal?(world, opponent(world, self)),
      do: Intent.set(world, self, 25),
      else: Intent.next_state(world, self, 102)
  end

  defp close_gap(world, self, 27) do
    if Gml.truthy?(Gml.var(world, self, :actionFailed)) do
      world |> Intent.clear(self) |> Intent.set(self, 27)
    else
      {thrust, world} = Personality.chance(world, self, 19, 30)
      world = if thrust, do: Buttons.press(world, self, 5), else: world
      next = if Sense.weapon_type(world, player(world, self)) == @sword, do: 103, else: 101
      Intent.next_state(world, self, next)
    end
  end

  defp close_gap(world, self, _action), do: world |> Intent.clear(self) |> Intent.set(self, 27)

  defp fence(world, self) do
    man = player(world, self)

    cond do
      not Sense.fencing?(world, man) and not Query.ducking?(world, man) and
          Sense.weapon_type(world, man) != @sword ->
        Intent.next_state(world, self, 101)

      Gml.gt?(distance(world, self), 90) ->
        Intent.next_state(world, self, 102)

      true ->
        fence_on_beat(world, self)
    end
  end

  defp fence_on_beat(world, self) do
    with {:no, world} <- guard_lunge(world, self),
         {:no, world} <- beat_throw(world, self),
         {:no, world} <- beat_action(world, self, 1, 9, 4),
         {:no, world} <- beat_action(world, self, 1, 28, 4) do
      when_free(world, self, &fencing/3)
    else
      {:yes, world} -> world
    end
  end

  defp guard_lunge(world, self) do
    count = Gml.var(world, self, :stateCounter)

    if Clock.between?(count, Clock.period(world, self, 0.5)) and
         Gml.var(world, opponent(world, self), :state) == @lunging,
       do: take_action(world, self, 15, 60),
       else: {:no, world}
  end

  defp beat_action(world, self, times, action, chance) do
    if Clock.every?(world, self, :stateCounter, times),
      do: take_action(world, self, action, chance),
      else: {:no, world}
  end

  defp take_action(world, self, action, chance) do
    case Personality.chance(world, self, action, chance) do
      {true, world} -> {:yes, Intent.set(world, self, action)}
      {false, world} -> {:no, world}
    end
  end

  defp beat_throw(world, self) do
    with true <- Clock.every?(world, self, :stateCounter, 1),
         {true, world} <- Personality.chance(world, self, 29, 6) do
      if throw_opening?(world, self), do: {:yes, Intent.set(world, self, 29)}, else: {:no, world}
    else
      {false, world} -> {:no, world}
      false -> {:no, world}
    end
  end

  defp throw_opening?(world, self) do
    other = opponent(world, self)

    Gml.var(world, other, :stance) == @low or
      (Gml.lt?(World.fetch(world, other).y, World.fetch(world, player(world, self)).y) and
         Gml.lt?(distance(world, self), 48))
  end

  defp fencing(world, self, 15) do
    if Gml.truthy?(Gml.var(world, self, :actionCompleted)),
      do: first_taken(world, self, [{18, 50}, {15, 70}], 4),
      else: world
  end

  defp fencing(world, self, 18) do
    if Gml.truthy?(Gml.var(world, self, :actionCompleted)),
      do: world |> Personality.chance(self, 19, 90) |> follow_up(self),
      else: world
  end

  defp fencing(world, self, 19) do
    if Gml.truthy?(Gml.var(world, self, :actionCompleted)),
      do: Intent.clear(world, self),
      else: world
  end

  defp fencing(world, self, _action),
    do: first_taken(world, self, [{15, 40}, {18, 60}, {4, 70}, {20, 85}], 16)

  defp follow_up({true, world}, self) do
    if Gml.lt?(distance(world, self), 64),
      do: Intent.set(world, self, 19),
      else: first_taken(world, self, [{15, 30}], 4)
  end

  defp follow_up({false, world}, self), do: first_taken(world, self, [{15, 30}], 4)

  defp brawl(world, self, action) when action in [2, 4, 20] do
    world =
      case Personality.chance(world, self, 9, 70) do
        {true, world} -> Intent.set(world, self, 9)
        {false, world} -> Intent.random_melee(world, self)
      end

    chance_set(world, self, 7, 10)
  end

  defp brawl(world, self, 21), do: Intent.random_melee(world, self)

  defp brawl(world, self, 10) do
    if Gml.truthy?(Gml.var(world, self, :actionFailed)),
      do: Intent.set(world, self, 13),
      else: world
  end

  defp brawl(world, self, 13), do: Intent.random_melee(world, self)

  defp brawl(world, self, 9) do
    if Gml.truthy?(Gml.var(world, self, :actionFailed)),
      do: Intent.random_melee(world, self),
      else: Intent.set(world, self, 30)
  end

  defp brawl(world, self, 30), do: Intent.clear(world, self)

  defp brawl(world, self, _action) do
    case Personality.chance(world, self, 10, 30) do
      {true, world} -> Intent.set(world, self, 10)
      {false, world} -> Intent.random_melee(world, self)
    end
  end

  defp run_to_goal(world, self) do
    if Gml.exists?(world, "ChallengeMode") do
      Intent.next_state(world, self, 109)
    else
      man = player(world, self)
      other = opponent(world, self)

      cond do
        not standing?(world, other) ->
          when_free(world, self, &goal/3)

        Sense.in_front?(world, other, man) and not Sense.separated_by_log?(world, other, man) ->
          face(world, self)

        not leading?(world, self) ->
          Intent.next_state(world, self, 102)

        true ->
          when_free(world, self, &goal/3)
      end
    end
  end

  defp face(world, self) do
    next = if Sense.weapon_type(world, player(world, self)) != @sword, do: 101, else: 103
    Intent.next_state(world, self, next)
  end

  defp goal(world, self, _action) do
    world = world |> Intent.clear(self) |> Intent.set(self, 26)
    chance_set(world, self, 7, 10)
  end

  defp first_taken(world, self, [], last), do: Intent.set(world, self, last)

  defp first_taken(world, self, [{action, chance} | rest], last) do
    case Personality.chance(world, self, action, chance) do
      {true, world} -> Intent.set(world, self, action)
      {false, world} -> first_taken(world, self, rest, last)
    end
  end

  defp chance_set(world, self, action, chance) do
    case Personality.chance(world, self, action, chance) do
      {true, world} -> Intent.set(world, self, action)
      {false, world} -> world
    end
  end

  defp standing?(world, man),
    do:
      Sense.present?(man) and not Query.stabbed?(world, man) and not Query.collapsing?(world, man)

  defp leading?(world, self),
    do: Gml.eq?(Match.get(world, :leadingPlayerIndex), Gml.var(world, self, :playerIndex))

  defp other_player(world, self), do: Query.other_player(Gml.var(world, self, :playerIndex))
  defp player(world, self), do: Gml.var(world, self, :player, @noone)
  defp opponent(world, self), do: Gml.var(world, self, :opponent, @noone)
  defp distance(world, self), do: Gml.var(world, self, :opponentDist)

  defp frames(world, id) do
    case World.sprite(world, World.fetch(world, id).sprite_index) do
      nil -> 1
      definition -> length(definition.frames)
    end
  end
end
