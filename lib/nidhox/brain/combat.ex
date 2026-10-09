defmodule Nidhox.Brain.Combat do
  @moduledoc """
  The computer player's fighting actions, each run once a match frame while it is the
  `Brain`'s `action` (`actionStateMachine`). Each lets go of the buttons it does not
  use, presses those it does, and marks the action completed (`actionCompleted`) or
  failed (`actionFailed`) when it is over:

  | action | name | does |
  | --- | --- | --- |
  | 5 | block dive kick | steps back on the quarter beat, high stance on the beat; under a diving opponent, thrusts up (not personality 6); done once either lands, failed after 180 frames or unarmed |
  | 6 | block thrown sword | with a sword, raises the stance against a high sword or, in the air, hands over to a throw (suggests 29); unarmed, ducks a high sword or jumps a low one within 64 |
  | 9 | dive kick | on the ground, walks up within 100 and jumps (failed under a ceiling); in the air, holds jump, steers to keep 50 degrees from the opponent and kicks when close or above it |
  | 10 | find weapon | runs to the nearest safe sword and ducks over it within 48; failed without one |
  | 11 | finish him | walks up and punches within 24 a knocked down opponent |
  | 15 | guard | footwork, then matches the opponent's sword height on the beat until level |
  | 16 | jump over other player | while leading behind the opponent, runs at it, jumps and kicks on the way down |
  | 17 | kick | nothing, until it is no longer on the ground within 64 |
  | 18 | look for opening | footwork, then on the beat changes height until there is an opening (suggests 19) |
  | 19 | lunge | thrusts by turns until lunging (48) |
  | 21 | punch | unarmed against an unarmed opponent, walks up and punches every fourth frame within 28 |
  | 28 | sweep kick | walks up, ducks within 54 and kicks within 32 |
  | 29 | throw sword | holds up; jumps to the opponent's height and throws (up and attack) when level or falling above it |

  Action 9, 19, 21, 28 and 29 wait for the first move in arcade mode (`firstMoveMade`).
  """

  alias Cauldron2D.GameMaker.{Collide, Instance, World}
  alias Nidhox.Brain.{Buttons, Clock, Moves, Sense}
  alias Nidhox.Gml
  alias Nidhox.Objects.{Match, NidhoggHead}

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
  @sword 2
  @high 1
  @low 2
  @fencing 29
  @knocked_down 47
  @lunging 48
  @dive_states [14, 15, 16]

  @doc "The world after `Brain` `self` takes its fighting `action` for this frame."
  @spec run(World.t(), non_neg_integer(), number()) :: World.t()
  def run(%World{} = world, self, 5), do: block_dive_kick(world, self)
  def run(%World{} = world, self, 6), do: block_thrown_sword(world, self)
  def run(%World{} = world, self, 9), do: dive_kick(world, self)
  def run(%World{} = world, self, 10), do: find_weapon(world, self)
  def run(%World{} = world, self, 11), do: finish_him(world, self)
  def run(%World{} = world, self, 15), do: guard(world, self)
  def run(%World{} = world, self, 16), do: jump_over_other_player(world, self)
  def run(%World{} = world, self, 17), do: kick(world, self)
  def run(%World{} = world, self, 18), do: look_for_opening(world, self)
  def run(%World{} = world, self, 19), do: lunge(world, self)
  def run(%World{} = world, self, 21), do: punch(world, self)
  def run(%World{} = world, self, 28), do: sweep_kick(world, self)
  def run(%World{} = world, self, 29), do: throw_sword(world, self)

  defp block_dive_kick(world, self) do
    world = Buttons.release_all(world, self, [0, 1, 2, 3, 5, 4])
    other = opponent(world, self)

    if Sense.present?(other) do
      quarter = max(Clock.period(world, self, 0.25), 1)
      count = Gml.var(world, self, :actionCounter)
      world = if Gml.eq?(Gml.round(:math.fmod(count, quarter)), 0), do: Buttons.press(world, self, @back), else: world

      world =
        if Clock.every?(world, self, :actionCounter, 1),
          do: Moves.ideal_stance(world, self, player(world, self), @high),
          else: world

      under_dive(world, self, other)
    else
      done(world, self, true)
    end
  end

  defp under_dive(world, self, other) do
    man = player(world, self)

    cond do
      on_ground?(world, other) or not on_ground?(world, man) ->
        done(world, self, false)

      Gml.gt?(Gml.var(world, self, :actionCounter), 180) or Sense.weapon_type(world, man) != @sword ->
        done(world, self, true)

      truthy_point_distance?(world, man, other) and Gml.lt?(distance(world, self), 24) and
          not Gml.eq?(Gml.var(world, self, :personality), 6) ->
        world |> Buttons.press(self, @up) |> Buttons.press(self, @attack)

      true ->
        world
    end
  end

  defp truthy_point_distance?(world, man, other) do
    %Instance{x: x, y: y} = World.fetch(world, man)
    %Instance{x: ox, y: oy} = World.fetch(world, other)
    flag = if Gml.lt?(oy, 48), do: 1, else: 0
    Gml.truthy?(Sense.distance({x, y - 26}, {ox, flag}))
  end

  defp block_thrown_sword(world, self) do
    sword = Gml.var(world, self, :flyingSword, @noone)

    if Gml.eq?(sword, @noone) do
      Gml.put(world, self, %{actionCompleted: 1})
    else
      world
      |> Buttons.release_all(self, [0, 1, 2, 3, 5, 4])
      |> block_sword(self, sword, player(world, self))
    end
  end

  defp block_sword(world, self, sword, man) do
    %Instance{x: sx, y: sy} = World.fetch(world, sword)
    %Instance{x: x, y: y} = World.fetch(world, man)

    cond do
      Sense.weapon_type(world, man) == @sword -> parry_sword(world, self, man, {sx, sy}, {x, y})
      Gml.lt?(sy, y - 14) -> Buttons.press(world, self, @down)
      Gml.lt?(abs(sx - x), 64) -> Buttons.press(world, self, @jump)
      true -> world
    end
  end

  defp parry_sword(world, self, man, {sx, sy}, {x, y}) do
    weapon_y = World.fetch(world, Gml.var(world, man, :weapon)).y

    cond do
      Gml.var(world, man, :state) == @fencing and Gml.lt?(sy, weapon_y - 3) ->
        Moves.ideal_stance(world, self, man, @high)

      not on_ground?(world, man) and Gml.lt?(abs(sy - y), 40) and Gml.lt?(abs(sx - x), 72) ->
        Gml.put(world, self, %{actionCompleted: 1, suggestedAction: 29})

      true ->
        world
    end
  end

  defp dive_kick(world, self) do
    man = player(world, self)
    other = opponent(world, self)

    cond do
      Gml.eq?(Gml.var(world, self, :personality), 5) or not first_move_made?(world) -> done(world, self, true)
      Gml.var(world, man, :state) in @dive_states -> done(world, self, false)
      not Sense.present?(other) -> done(world, self, true)
      Sense.under_low_area?(world, other) or Sense.under_low_area?(world, man) -> done(world, self, true)
      true -> world |> Buttons.release_all(self, [0, 1, 2, 3, 5, 4]) |> dive(self, man, other)
    end
  end

  defp dive(world, self, man, other) do
    if on_ground?(world, man) do
      take_off(world, self, man, other)
    else
      world = Buttons.press(world, self, @jump)
      if Gml.var(world, man, :state) != 14 and Sense.present?(other), do: steer_dive(world, self, man, other), else: world
    end
  end

  defp take_off(world, self, man, other) do
    %Instance{x: x, y: y} = World.fetch(world, man)

    cond do
      Gml.gt?(distance(world, self), 100) ->
        world |> walk_to(self, World.fetch(world, other).x, x) |> Moves.jump_over(self, man)

      blocked?(world, {x, y - 84}) ->
        Gml.put(world, self, %{actionCompleted: 1, actionFailed: 1})

      Buttons.down?(world, self, @jump) ->
        world

      true ->
        Buttons.press(world, self, @jump)
    end
  end

  defp steer_dive(world, self, man, other) do
    %Instance{x: x, y: y} = World.fetch(world, man)
    %Instance{x: ox, y: oy} = World.fetch(world, other)
    across = Gml.point_direction({x, y}, {ox, y})
    target = Gml.point_direction({x, y}, {ox - 8 * Gml.var(world, other, :facingXScale), oy - 13})
    angle = abs(NidhoggHead.tween(across, target))
    close = Sense.distance({x, y}, {ox, oy - 11})

    world =
      cond do
        not Gml.gt?(abs(angle - 50), 2) -> world
        Gml.lt?(angle, 50) -> Buttons.press(world, self, @forward)
        true -> Buttons.press(world, self, @back)
      end

    kick_now(world, self, man, Gml.lt?(close, 32), angle, Gml.lt?(y, oy))
  end

  defp kick_now(world, self, man, true, _angle, _above), do: kick_at(world, self, man)

  defp kick_now(world, self, man, false, angle, above) do
    off = abs(angle - 50)

    cond do
      Gml.lt?(Gml.var(world, man, :vspd), 0) ->
        if Gml.lt?(off, 30) and above, do: kick_at(world, self, man), else: world

      Gml.lt?(off, 45) and above ->
        kick_at(world, self, man)

      true ->
        Gml.put(world, self, %{actionCompleted: 1})
    end
  end

  defp kick_at(world, self, man) do
    world = Buttons.press(world, self, @attack)
    toward(world, self, World.fetch(world, opponent(world, self)).x, World.fetch(world, man).x)
  end

  defp find_weapon(world, self) do
    man = player(world, self)

    if Sense.weapon_type(world, man) != @fists do
      Gml.put(world, self, %{actionCompleted: 1})
    else
      world = Buttons.release_all(world, self, [0, 1, 2, 3, 5, 4])

      case Moves.closest_weapon(world, man, opponent(world, self)) do
        @noone -> done(world, self, true)
        sword -> run_to_sword(world, self, man, World.fetch(world, sword).x)
      end
    end
  end

  defp run_to_sword(world, self, man, sword_x) do
    x = World.fetch(world, man).x
    world = if Gml.lt?(abs(sword_x - x), 48), do: Buttons.press(world, self, @down), else: world

    world
    |> walk_to(self, sword_x, x)
    |> Moves.jump_over(self, man)
  end

  defp finish_him(world, self) do
    man = player(world, self)
    other = opponent(world, self)

    if Gml.var(world, man, :state) == @knocked_down or not Sense.present?(other) or
         Gml.var(world, other, :state) != @knocked_down do
      Gml.put(world, self, %{actionCompleted: 1})
    else
      world = Buttons.release_all(world, self, [0, 1, 2, 3, 4])

      if Gml.lt?(distance(world, self), 24),
        do: toggle(world, self, @attack),
        else: world |> walk_to(self, World.fetch(world, other).x, World.fetch(world, man).x) |> Moves.jump_over(self, man)
    end
  end

  defp guard(world, self) do
    world = Buttons.release_all(world, self, [0, 1, 2, 3, 4])
    man = player(world, self)
    other = opponent(world, self)

    cond do
      Gml.var(world, man, :state) != @fencing -> done(world, self, true)
      not Sense.present?(other) -> done(world, self, true)
      Sense.weapon_type(world, man) != @sword -> done(world, self, false)
      true -> world |> step_away(self) |> hold_guard(self, man, other)
    end
  end

  defp step_away(world, self) do
    with {true, world} <- Moves.footwork(world, self),
         {true, world} <- Gml.prob(world, 70) do
      Buttons.press(world, self, @back)
    else
      {false, world} -> world
    end
  end

  defp hold_guard(world, self, man, other) do
    cond do
      not Sense.fencing?(world, man) ->
        Gml.put(world, self, %{actionCompleted: 1})

      Clock.every?(world, self, :actionCounter, 1) ->
        guard_on_beat(world, self, man, other)

      true ->
        world
    end
  end

  defp guard_on_beat(world, self, man, other) do
    {chance, world} = Gml.prob(world, 50)

    if chance or first_move_made?(world) do
      case Moves.guard_against(world, self, man, other) do
        {true, world} -> Gml.put(world, self, %{actionCompleted: 1})
        {false, world} -> world
      end
    else
      world
    end
  end

  defp jump_over_other_player(world, self) do
    world = Buttons.release_all(world, self, [0, 1, 3, 2, 5, 4])
    man = player(world, self)
    other = opponent(world, self)
    leader = Gml.var(world, self, :playerIndex)

    cond do
      not Sense.present?(other) -> Gml.put(world, self, %{actionCompleted: 1})
      not Gml.eq?(Match.get(world, :leadingPlayerIndex), leader) -> done(world, self, true)
      not Sense.in_front?(world, other, man) -> Gml.put(world, self, %{actionCompleted: 1})
      true -> leap_over(world, self, man, leader)
    end
  end

  defp leap_over(world, self, man, player_index) do
    {go, world} = go_now(world, self)
    world = if go and Gml.eq?(player_index, 1), do: Buttons.press(world, self, @right), else: world
    world = if Gml.eq?(player_index, 2), do: Buttons.press(world, self, @left), else: world
    world = Moves.jump_over(world, self, man)

    if Gml.gt?(Gml.var(world, man, :vspd), 0) and not Gml.eq?(Gml.var(world, self, :personality), 5),
      do: Buttons.press(world, self, @attack),
      else: world
  end

  defp go_now(world, self) do
    count = Gml.var(world, self, :actionCounter)

    cond do
      Gml.gt?(count, 240) -> {true, world}
      Clock.between?(count, Clock.period(world, self, 4)) -> Gml.prob(world, 10)
      true -> {false, world}
    end
  end

  defp kick(world, self) do
    world = Buttons.release_all(world, self, [0, 1, 3, 2, 5, 4])
    man = player(world, self)

    if on_ground?(world, man) and not Gml.gt?(distance(world, self), 64) and
         not Gml.eq?(Gml.var(world, man, :state), 45) and Sense.present?(opponent(world, self)),
       do: world,
       else: Gml.put(world, self, %{actionCompleted: 1})
  end

  defp look_for_opening(world, self) do
    world = Buttons.release_all(world, self, [0, 1, 2, 3, 4])
    man = player(world, self)
    other = opponent(world, self)

    cond do
      not Sense.present?(other) -> done(world, self, true)
      Gml.var(world, man, :state) != @fencing -> done(world, self, true)
      true -> world |> step_in(self) |> seek_opening(self, man, other)
    end
  end

  defp step_in(world, self) do
    with {true, world} <- Moves.footwork(world, self),
         {true, world} <- Gml.prob(world, 70) do
      Buttons.press(world, self, @forward)
    else
      {false, world} -> world
    end
  end

  defp seek_opening(world, self, man, other) do
    cond do
      Sense.fencing?(world, man) -> opening_on_beat(world, self, man, other)
      Gml.var(world, man, :stance) == @low -> Gml.put(world, self, %{actionCompleted: 1})
      Clock.every?(world, self, :actionCounter, 1) -> duck_now_and_then(world, self)
      true -> world
    end
  end

  defp duck_now_and_then(world, self) do
    {duck, world} = Gml.choose(world, [0, 1])
    if Gml.truthy?(duck), do: Buttons.press(world, self, @down), else: world
  end

  defp opening_on_beat(world, self, man, other) do
    if Clock.every?(world, self, :actionCounter, 1) do
      case Moves.look_for_opening(world, self, man, other) do
        {true, world} -> Gml.put(world, self, %{actionCompleted: 1, actionSuggestion: 19})
        {false, world} -> world
      end
    else
      world
    end
  end

  defp lunge(world, self) do
    cond do
      not first_move_made?(world) -> done(world, self, true)
      Gml.var(world, player(world, self), :state) == @lunging -> Gml.put(world, self, %{actionCompleted: 1})
      true -> toggle(world, self, @attack)
    end
  end

  defp punch(world, self) do
    man = player(world, self)
    other = opponent(world, self)

    cond do
      not first_move_made?(world) ->
        done(world, self, true)

      not on_ground?(world, man) or Gml.var(world, man, :state) == 38 ->
        done(world, self, true)

      Gml.var(world, man, :state) == 55 or not Sense.present?(other) or Sense.weapon_type(world, man) != @fists ->
        Gml.put(world, self, %{actionCompleted: 1})

      Gml.var(world, other, :state) == @knocked_down or Sense.weapon_type(world, other) != @fists ->
        Gml.put(world, self, %{actionCompleted: 1})

      true ->
        swing(world, self, man, other)
    end
  end

  defp swing(world, self, man, other) do
    world = Buttons.release_all(world, self, [2, 3, 0, 1, 4])

    world =
      if Gml.lt?(distance(world, self), 28) and Clock.on?(Gml.var(world, self, :actionCounter), 4),
        do: toggle(world, self, @attack),
        else: world

    world
    |> walk_to(self, World.fetch(world, other).x, World.fetch(world, man).x)
    |> Moves.jump_over(self, man)
  end

  defp sweep_kick(world, self) do
    man = player(world, self)
    other = opponent(world, self)

    cond do
      not first_move_made?(world) ->
        done(world, self, true)

      true ->
        world = Buttons.release_all(world, self, [0, 1, 5, 4, 3])

        if Gml.var(world, man, :state) == 70 or not Sense.present?(other),
          do: Gml.put(world, self, %{actionCompleted: 1}),
          else: sweep(world, self, man, other)
    end
  end

  defp sweep(world, self, man, other) do
    world = if on_ground?(world, other), do: world, else: Gml.put(world, self, %{actionCompleted: 1, actionFailed: 1})

    if Sense.weapon_type(world, other) == @sword and Gml.var(world, other, :stance) == @low do
      done(world, self, true)
    else
      world = toward(world, self, World.fetch(world, other).x, World.fetch(world, man).x)

      cond do
        Gml.lt?(distance(world, self), 32) -> world |> Buttons.press(self, @down) |> toggle(self, @attack)
        Gml.lt?(distance(world, self), 54) -> Buttons.press(world, self, @down)
        true -> world
      end
    end
  end

  defp throw_sword(world, self) do
    cond do
      not first_move_made?(world) ->
        done(world, self, true)

      Gml.eq?(Gml.var(world, self, :personality), 6) ->
        Gml.put(world, self, %{actionfailed: 1, actionCompleted: 1})

      true ->
        world
        |> Buttons.release_all(self, [0, 1, 3])
        |> Buttons.press(self, @up)
        |> aim(self)
    end
  end

  defp aim(world, self) do
    man = player(world, self)
    other = opponent(world, self)
    personality = Gml.var(world, self, :personality)

    cond do
      Sense.weapon_type(world, man) != @sword or Gml.gt?(Gml.var(world, self, :actionCounter), 180) ->
        Gml.put(world, self, %{actionCompleted: 1})

      not Sense.present?(other) ->
        done(world, self, true)

      not Gml.eq?(personality, 1) and (Sense.under_low_area?(world, other) or Sense.under_low_area?(world, man)) ->
        done(world, self, true)

      Buttons.down?(world, self, @attack) ->
        Buttons.release(world, self, @attack)

      true ->
        world |> Moves.jump_over(self, man) |> line_up(self, man, other, personality)
    end
  end

  defp line_up(world, self, man, other, personality) do
    %Instance{y: y} = World.fetch(world, man)
    %Instance{y: oy} = World.fetch(world, other)

    {now, world} =
      cond do
        Gml.lt?(abs(oy - y), 11) -> {true, world}
        on_ground?(world, man) -> {false, toggle(world, self, @jump)}
        true -> {Gml.lt?(oy, y) and Gml.gt?(Gml.var(world, man, :vspd), 0), Buttons.press(world, self, @jump)}
      end

    now = now or (not Gml.lt?(Gml.var(world, man, :vspd), 0) and Gml.eq?(personality, 1))

    if now,
      do: world |> Buttons.press(self, @up) |> Buttons.press(self, @attack),
      else: world
  end

  defp toggle(world, self, button) do
    if Buttons.down?(world, self, button),
      do: Buttons.release(world, self, button),
      else: Buttons.press(world, self, button)
  end

  defp walk_to(world, self, target_x, x) do
    if Gml.lt?(target_x, x), do: Buttons.press(world, self, @left), else: Buttons.press(world, self, @right)
  end

  defp toward(world, self, target_x, x) do
    if Gml.gt?(target_x, x), do: Buttons.press(world, self, @right), else: Buttons.press(world, self, @left)
  end

  defp blocked?(world, point) do
    case World.object_index(world, "BlockParent") do
      nil -> false
      object -> Collide.at_point(world, point, object) != nil
    end
  end

  defp first_move_made?(world) do
    case Gml.first(world, "ArcadeMode") do
      nil -> true
      arcade -> Gml.truthy?(Gml.var(world, arcade, :playerAttacked))
    end
  end

  defp done(world, self, failed),
    do: Gml.put(world, self, if(failed, do: %{actionCompleted: 1, actionFailed: 1}, else: %{actionCompleted: 1}))

  defp on_ground?(world, man), do: Gml.truthy?(Gml.var(world, man, :onGround))
  defp player(world, self), do: Gml.var(world, self, :player, @noone)
  defp opponent(world, self), do: Gml.var(world, self, :opponent, @noone)
  defp distance(world, self), do: Gml.var(world, self, :opponentDist)
end
