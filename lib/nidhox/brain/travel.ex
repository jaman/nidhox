defmodule Nidhox.Brain.Travel do
  @moduledoc """
  The computer player's moving actions, each run once a match frame while it is the
  `Brain`'s `action` (`actionStateMachine`). Each lets go of the buttons it does not
  use, presses those it does, and marks the action completed (`actionCompleted`) or
  failed (`actionFailed`) when it is over:

  | action | name | does |
  | --- | --- | --- |
  | 1 | approach edge | walks towards the opponent to the edge of its ground and takes the middle stance there; near a ledge, a step now and then |
  | 2 | back off | runs away within 120 for up to 240 frames |
  | 3 | run to death | near a ledge, a step back now and then; done after 180 frames or by chance |
  | 4 | back off guarded | steps back on the beat while within 80, now and then once more under open sky |
  | 7 | bunny hop taunt | crouched, hops on and on, for up to 60 frames |
  | 8 | climb wall | forward up a wall; jumps off its top (36) and off a ledge (62) |
  | 12 | get off wall | lets go of everything until off the wall |
  | 13 | get rather close | runs to within 72 of the opponent, for up to 180 frames |
  | 14 | get up | when knocked down (47), after 60 frames or by chance: towards its goal while leading, away from a close opponent, else up |
  | 20 | pause | stands, a step now and then, a change of height now and then; over after 60 frames, by chance, or within 64 |
  | 22 | roll under | nothing, until crouched past 32 from the opponent, in the air or alone |
  | 23 | run at wall | runs at the opponent while they stand at different heights; failed once level, on a log or after 240 frames |
  | 24 | run out of log | in a log under the opponent: runs out the far end of the log they share, or towards it from another |
  | 25 | run to death | while the opponent leads, runs back towards its own goal (player 1 right, player 2 left), jumping on the beat, for up to 60 frames |
  | 26 | run to goal | runs for its goal for up to 120 frames; unarmed, picks up a sword lying close on the way |
  | 27 | run toward opponent | runs at the opponent until within 90, for up to 180 frames |
  | 30 | wait until on ground | lets go of everything until on the ground |
  | 55 | jump back to safety | jumps away from the opponent, letting go of jump after 10 frames; done on landing after 20 |
  """

  alias Cauldron2D.GameMaker.{Collide, Instance, World}
  alias Nidhox.Brain.{Buttons, Clock, Intent, Moves, Sense}
  alias Nidhox.Gml
  alias Nidhox.Man.Query
  alias Nidhox.Objects.Match

  @noone -4
  @left 0
  @right 1
  @up 2
  @down 3
  @jump 4
  @attack 5
  @forward 8
  @back 9
  @fists 1
  @high 1
  @middle 3
  @low 2
  @knocked_down 47
  @all [0, 1, 2, 3, 5, 4]

  @doc "The world after `Brain` `self` takes its moving `action` for this frame."
  @spec run(World.t(), non_neg_integer(), number()) :: World.t()
  def run(%World{} = world, self, 1), do: approach_edge(world, self)
  def run(%World{} = world, self, 2), do: back_off(world, self)
  def run(%World{} = world, self, 3), do: edge_of_death(world, self)
  def run(%World{} = world, self, 4), do: back_off_guarded(world, self)
  def run(%World{} = world, self, 7), do: bunny_hop(world, self)
  def run(%World{} = world, self, 8), do: climb_wall(world, self)
  def run(%World{} = world, self, 12), do: get_off_wall(world, self)
  def run(%World{} = world, self, 13), do: get_rather_close(world, self)
  def run(%World{} = world, self, 14), do: get_up(world, self)
  def run(%World{} = world, self, 20), do: pause(world, self)
  def run(%World{} = world, self, 22), do: roll_under(world, self)
  def run(%World{} = world, self, 23), do: run_at_wall(world, self)
  def run(%World{} = world, self, 24), do: run_out_of_log(world, self)
  def run(%World{} = world, self, 25), do: run_to_death(world, self)
  def run(%World{} = world, self, 26), do: run_to_goal(world, self)
  def run(%World{} = world, self, 27), do: run_toward_opponent(world, self)
  def run(%World{} = world, self, 30), do: wait_until_on_ground(world, self)
  def run(%World{} = world, self, 55), do: jump_back(world, self)

  defp approach_edge(world, self) do
    world = Buttons.release_all(world, self, @all)
    other = opponent(world, self)

    if Sense.present?(other) do
      man = player(world, self)
      %Instance{x: x, y: y} = World.fetch(world, man)
      way = Sense.facing(x, World.fetch(world, other).x)

      if ground_at?(world, {x + 32 * way, y + 4}),
        do: near_ledge(world, self, man, way),
        else: world |> Moves.ideal_stance(self, man, @middle) |> complete(self)
    else
      fail(world, self)
    end
  end

  defp near_ledge(world, self, man, way) do
    %Instance{x: x, y: y} = World.fetch(world, man)

    case Gml.nearest(world, {x, y}, "Ledge") do
      nil ->
        world

      ledge ->
        step_to_ledge(world, self, World.fetch(world, ledge).x - x, way)
    end
  end

  defp step_to_ledge(world, self, gap, way) do
    {step, world} =
      if Gml.gt?(abs(gap), 48),
        do: {true, world},
        else: on_double_beat(world, self, 60)

    if step, do: Buttons.press(world, self, way_button(way)), else: world
  end

  defp way_button(way), do: if(Gml.eq?(way, 1), do: @right, else: @left)

  defp back_off(world, self) do
    world = Buttons.release_all(world, self, @all)
    other = opponent(world, self)

    cond do
      not Sense.present?(other) ->
        fail(world, self)

      Gml.lt?(distance(world, self), 120) and Gml.lt?(Gml.var(world, self, :actionCounter), 240) ->
        world |> away_from(self, other) |> Moves.jump_over(self, player(world, self))

      true ->
        complete(world, self)
    end
  end

  defp edge_of_death(world, self) do
    world = Buttons.release_all(world, self, @all)

    if Sense.present?(opponent(world, self)) do
      man = player(world, self)
      %Instance{x: x, y: y} = World.fetch(world, man)

      case Gml.nearest(world, {x, y}, "Ledge") do
        nil -> give_up_later(world, self)
        ledge -> step_back_at_ledge(world, self, abs(World.fetch(world, ledge).x - x))
      end
    else
      fail(world, self)
    end
  end

  defp step_back_at_ledge(world, self, apart) do
    {step, world} =
      if Gml.lt?(apart, 48), do: on_double_beat(world, self, 60), else: {false, world}

    if step,
      do: world |> Buttons.press(self, @back) |> give_up_later(self),
      else: complete(world, self)
  end

  defp give_up_later(world, self) do
    {done, world} =
      if Gml.gt?(Gml.var(world, self, :actionCounter), 180),
        do: {true, world},
        else: on_double_beat(world, self, 60)

    if done, do: Gml.put(world, self, %{actionCompleted: 1, actionFailed: 1}), else: world
  end

  defp back_off_guarded(world, self) do
    world = Buttons.release_all(world, self, @all)

    if Gml.lt?(distance(world, self), 80) and Gml.lt?(Gml.var(world, self, :stateCounter), 240) do
      world
      |> step_back_on_beat(self)
      |> step_back_under_sky(self)
      |> stop_now_and_then(self)
      |> Moves.jump_over(self, player(world, self))
    else
      complete(world, self)
    end
  end

  defp step_back_on_beat(world, self) do
    with true <- Clock.every?(world, self, :stateCounter, 2),
         {true, world} <- Gml.prob(world, 70) do
      Buttons.press(world, self, @back)
    else
      {false, world} -> world
      false -> world
    end
  end

  defp step_back_under_sky(world, self) do
    with true <- Gml.gt?(distance(world, self), 48),
         true <-
           Clock.between?(Gml.var(world, self, :stateCounter), Clock.period(world, self, 3.5)),
         {true, world} <- Gml.prob(world, 3) do
      open_sky(world, self)
    else
      {false, world} -> world
      false -> world
    end
  end

  defp open_sky(world, self) do
    %Instance{x: x, y: y} = World.fetch(world, player(world, self))

    with false <- ground_at?(world, {x, y - 90}),
         true <- Clock.every?(world, self, :actionCounter, 1),
         {true, world} <- Gml.prob(world, 70) do
      Buttons.press(world, self, @back)
    else
      {false, world} -> world
      true -> world
      false -> world
    end
  end

  defp stop_now_and_then(world, self) do
    with true <-
           Clock.between?(Gml.var(world, self, :actionCounter), Clock.period(world, self, 4)),
         {true, world} <- Gml.prob(world, 10) do
      complete(world, self)
    else
      {false, world} -> world
      false -> world
    end
  end

  defp bunny_hop(world, self) do
    man = player(world, self)

    world =
      world
      |> Buttons.release_all(self, [0, 1, 2])
      |> Buttons.press(self, @down)
      |> Buttons.release(self, @attack)

    world =
      if Gml.gt?(abs(Gml.var(world, man, :hspd)), 0.2),
        do: Buttons.press(world, self, @forward),
        else: world

    world =
      if Gml.gt?(Gml.var(world, self, :actionCounter), 7) and on_ground?(world, man),
        do: toggle(world, self, @jump),
        else: world

    world = Moves.jump_over(world, self, man)

    {done, world} =
      if Gml.gt?(Gml.var(world, self, :actionCounter), 60),
        do: {true, world},
        else: on_double_beat(world, self, 10)

    if done, do: complete(world, self), else: world
  end

  defp climb_wall(world, self) do
    man = player(world, self)

    if Sense.on_wall?(world, man) do
      world
      |> Buttons.press(self, @forward)
      |> on_the_wall(self, Gml.var(world, man, :state))
    else
      Gml.put(world, self, %{actionCompleted: 1, suggestedAction: 22})
    end
  end

  defp on_the_wall(world, self, 53), do: Buttons.release_all(world, self, [2, 3, 5, 4])

  defp on_the_wall(world, self, 36) do
    if Buttons.down?(world, self, @jump),
      do: Buttons.release(world, self, @jump),
      else: world |> Buttons.press(self, @jump) |> complete(self)
  end

  defp on_the_wall(world, self, 62) do
    world
    |> Buttons.press(self, @jump)
    |> Gml.put(self, %{actionCompleted: 1, actionFailed: 1})
  end

  defp on_the_wall(world, _self, _state), do: world

  defp get_off_wall(world, self) do
    if Sense.on_wall?(world, player(world, self)),
      do: Buttons.release_all(world, self, [0, 1, 2, 3, 4]),
      else: complete(world, self)
  end

  defp get_rather_close(world, self) do
    world = Buttons.release_all(world, self, @all)
    other = opponent(world, self)
    man = player(world, self)

    cond do
      not Sense.present?(other) ->
        fail(world, self)

      Gml.lt?(distance(world, self), 72) and on_ground?(world, man) ->
        complete(world, self)

      true ->
        world =
          world
          |> walk_to(self, World.fetch(world, other).x, World.fetch(world, man).x)
          |> Moves.jump_over(self, man)

        if Gml.gt?(Gml.var(world, self, :actionCounter), 180),
          do: Gml.put(world, self, %{actionCompleted: 1, actionFailed: 1}),
          else: world
    end
  end

  defp get_up(world, self) do
    world = Buttons.release_all(world, self, [0, 1, 2, 3, 4, 5])
    man = player(world, self)

    if Gml.var(world, man, :state) != @knocked_down do
      world |> complete(self) |> Intent.clear(self)
    else
      {now, world} =
        if Gml.gt?(Gml.var(world, self, :actionCounter), 60),
          do: {true, world},
          else: on_beat(world, self, 7)

      if now and not Gml.truthy?(Gml.var(world, self, :flyingSword)),
        do: rise(world, self, man),
        else: world
    end
  end

  defp rise(world, self, man) do
    player_index = Gml.var(world, self, :playerIndex)
    other = opponent(world, self)

    world =
      if Gml.eq?(Match.get(world, :leadingPlayerIndex), player_index),
        do: Buttons.press(world, self, if(Gml.eq?(player_index, 1), do: @right, else: @left)),
        else: world

    cond do
      not (Gml.lt?(distance(world, self), 48) and Sense.present?(other)) ->
        Buttons.press(world, self, @up)

      Gml.gt?(World.fetch(world, other).x, World.fetch(world, man).x) ->
        Buttons.press(world, self, @left)

      true ->
        Buttons.press(world, self, @right)
    end
  end

  defp pause(world, self) do
    world = Buttons.release_all(world, self, @all)

    world
    |> shuffle(self)
    |> Moves.jump_over(self, player(world, self))
    |> change_height(self)
    |> done_pausing(self)
  end

  defp shuffle(world, self) do
    with true <- Clock.every?(world, self, :actionCounter, 1),
         {true, world} <- Gml.prob(world, 30) do
      {back, world} = Gml.prob(world, 60)
      Buttons.press(world, self, if(back, do: @back, else: @forward))
    else
      {false, world} -> world
      false -> world
    end
  end

  defp change_height(world, self) do
    with true <- Clock.every?(world, self, :actionCounter, 3.5),
         {true, world} <- Gml.prob(world, 30) do
      {up, world} = Gml.choose(world, [1, 0])
      stance = Gml.var(world, player(world, self), :stance)

      cond do
        Gml.truthy?(up) and stance != @high -> Buttons.press(world, self, @up)
        not Gml.truthy?(up) and stance != @low -> Buttons.press(world, self, @down)
        true -> world
      end
    else
      {false, world} -> world
      false -> world
    end
  end

  defp done_pausing(world, self) do
    {done, world} =
      if Gml.gt?(Gml.var(world, self, :actionCounter), 60),
        do: {true, world},
        else: nine_beats_or_close(world, self)

    if done, do: Gml.put(world, self, %{actionCompleted: 1, actionFailed: 1}), else: world
  end

  defp nine_beats_or_close(world, self) do
    {chance, world} =
      if Clock.every?(world, self, :actionCounter, 9),
        do: Gml.prob(world, 10),
        else: {false, world}

    {chance or Gml.lt?(distance(world, self), 64), world}
  end

  defp roll_under(world, self) do
    man = player(world, self)

    if on_ground?(world, man) and Sense.present?(opponent(world, self)) and
         not (Gml.gt?(distance(world, self), 32) and Query.crouched?(world, man)),
       do: world,
       else: complete(world, self)
  end

  defp run_at_wall(world, self) do
    world = Buttons.release_all(world, self, @all)
    other = opponent(world, self)
    man = player(world, self)

    cond do
      not Sense.present?(other) or Gml.gt?(Gml.var(world, self, :actionCounter), 240) ->
        fail(world, self)

      Gml.truthy?(Gml.var(world, other, :onLog)) ->
        fail(world, self)

      not Gml.lt?(abs(World.fetch(world, other).y - World.fetch(world, man).y), 4) ->
        toward(world, self, World.fetch(world, other).x, World.fetch(world, man).x)

      true ->
        fail(world, self)
    end
  end

  defp run_out_of_log(world, self) do
    world = Buttons.release_all(world, self, @all)
    other = opponent(world, self)
    man = player(world, self)

    cond do
      not Sense.present?(other) -> fail(world, self)
      not Gml.truthy?(Gml.var(world, man, :inLog)) -> complete(world, self)
      true -> leave_log(world, self, man, other)
    end
  end

  defp leave_log(world, self, man, other) do
    %Instance{x: ox, y: oy} = World.fetch(world, other)
    %Instance{x: x, y: y} = World.fetch(world, man)

    with above when above != nil <- log_at(world, {ox, oy + 32}),
         mine when mine != nil <- log_at(world, {x, y - 16}) do
      if above != mine, do: toward(world, self, ox, x), else: away_from_x(world, self, ox, x)
    else
      nil -> fail(world, self)
    end
  end

  defp run_to_death(world, self) do
    world = Buttons.release_all(world, self, @all)
    player_index = Gml.var(world, self, :playerIndex)

    if Sense.present?(opponent(world, self)) and
         not Gml.gt?(Gml.var(world, self, :actionCounter), 60) and
         Gml.eq?(Match.get(world, :leadingPlayerIndex), Query.other_player(player_index)) do
      world = run_home(world, self, player_index)

      if Clock.every?(world, self, :stateCounter, 1),
        do: Buttons.press(world, self, @jump),
        else: world
    else
      fail(world, self)
    end
  end

  defp run_home(world, self, 1), do: Buttons.press(world, self, @right)
  defp run_home(world, self, 2), do: Buttons.press(world, self, @left)
  defp run_home(world, _self, _player_index), do: world

  defp run_to_goal(world, self) do
    world = Buttons.release_all(world, self, @all)

    if Gml.gt?(Gml.var(world, self, :actionCounter), 120) do
      Gml.put(world, self, %{actionCompleted: 1, actionFailed: 1})
    else
      man = player(world, self)
      goal = if Gml.eq?(Gml.var(world, self, :playerIndex), 1), do: @right, else: @left

      world
      |> Buttons.press(self, goal)
      |> pick_up_on_the_way(self, man)
      |> Moves.jump_over(self, man)
    end
  end

  defp pick_up_on_the_way(world, self, man) do
    %Instance{x: x, y: y} = World.fetch(world, man)

    with @fists <- Sense.weapon_type(world, man),
         sword when sword != nil <- Gml.nearest(world, {x, y}, "PickupContainer"),
         %Instance{x: sx, y: sy} <- World.fetch(world, sword),
         true <- Gml.lt?(abs(sy - y), 16),
         true <- Gml.lt?(abs(sx - x), 100) do
      world = walk_to(world, self, sx, x)
      if Gml.lt?(abs(sx - x), 32), do: Buttons.press(world, self, @down), else: world
    else
      _ -> world
    end
  end

  defp run_toward_opponent(world, self) do
    world = Buttons.release_all(world, self, @all)
    other = opponent(world, self)
    man = player(world, self)

    cond do
      Gml.lt?(distance(world, self), 90) ->
        complete(world, self)

      not Sense.present?(other) or Gml.gt?(Gml.var(world, self, :actionCounter), 180) ->
        fail(world, self)

      true ->
        world
        |> toward(self, World.fetch(world, other).x, World.fetch(world, man).x)
        |> Moves.jump_over(self, man)
    end
  end

  defp wait_until_on_ground(world, self) do
    world = Buttons.release_all(world, self, [0, 1, 3, 2, 5, 4])
    if on_ground?(world, player(world, self)), do: complete(world, self), else: world
  end

  defp jump_back(world, self) do
    man = player(world, self)
    other = opponent(world, self)

    world =
      world
      |> Buttons.release(self, @down)
      |> Buttons.release(self, @up)
      |> Buttons.press(self, @jump)

    world =
      if Sense.present?(other),
        do: away_from_x(world, self, World.fetch(world, other).x, World.fetch(world, man).x),
        else:
          Buttons.press(
            world,
            self,
            if(Gml.gt?(Gml.var(world, man, :hspd), 0), do: @right, else: @left)
          )

    counter = Gml.var(world, self, :actionCounter)
    world = if Gml.gt?(counter, 10), do: Buttons.release(world, self, @jump), else: world

    if on_ground?(world, man) and Gml.gt?(counter, 20),
      do: Gml.put(world, self, %{actionCompleted: 1, actionFailed: 1}),
      else: world
  end

  defp on_beat(world, self, chance) do
    if Clock.every?(world, self, :actionCounter, 1),
      do: Gml.prob(world, chance),
      else: {false, world}
  end

  defp on_double_beat(world, self, chance) do
    if Clock.every?(world, self, :actionCounter, 2),
      do: Gml.prob(world, chance),
      else: {false, world}
  end

  defp ground_at?(world, point) do
    case World.object_index(world, "BlockParent") do
      nil -> false
      object -> Collide.at_point(world, point, object) != nil
    end
  end

  defp log_at(world, point) do
    case World.object_index(world, "InsideLogArea") do
      nil -> nil
      object -> Collide.at_point(world, point, object)
    end
  end

  defp toggle(world, self, button) do
    if Buttons.down?(world, self, button),
      do: Buttons.release(world, self, button),
      else: Buttons.press(world, self, button)
  end

  defp away_from(world, self, other),
    do:
      away_from_x(
        world,
        self,
        World.fetch(world, other).x,
        World.fetch(world, player(world, self)).x
      )

  defp away_from_x(world, self, other_x, x) do
    if Gml.lt?(other_x, x),
      do: Buttons.press(world, self, @right),
      else: Buttons.press(world, self, @left)
  end

  defp walk_to(world, self, target_x, x) do
    if Gml.lt?(target_x, x),
      do: Buttons.press(world, self, @left),
      else: Buttons.press(world, self, @right)
  end

  defp toward(world, self, target_x, x) do
    if Gml.gt?(target_x, x),
      do: Buttons.press(world, self, @right),
      else: Buttons.press(world, self, @left)
  end

  defp complete(world, self), do: Gml.put(world, self, %{actionCompleted: 1})
  defp fail(world, self), do: Gml.put(world, self, %{actionCompleted: 1, actionFailed: 1})
  defp on_ground?(world, man), do: Gml.truthy?(Gml.var(world, man, :onGround))
  defp player(world, self), do: Gml.var(world, self, :player, @noone)
  defp opponent(world, self), do: Gml.var(world, self, :opponent, @noone)
  defp distance(world, self), do: Gml.var(world, self, :opponentDist)
end
