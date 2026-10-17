defmodule Nidhox.Tutorial.Lessons do
  @moduledoc """
  The tutorial's lessons (the `Tutorial`'s `currentMove`), their instructions and what
  completes each. The learner is the yellow fencer, the partner the orange one, played
  by the computer at no difficulty with the personality that only stands and backs off
  (4890894) — except in the thrown sword lesson, where it plays the thrower
  (38968458) and throws its sword whenever it holds one.

  `check/4` runs the current lesson for one frame: it sets the lesson's marks (`check`,
  three of them) and `COMPLETED_MOVE` once the lesson is done. `line/1` gives a lesson's
  instruction as the game builds it (`tutorialBuildMoveStrings`): its key in the
  `"tutorial"` section, its English, and the menu buttons (`Nidhox.Glyphs`) whose glyphs
  fill its `{0}` and `{1}`. The instructions below name those buttons in their place.

  | lesson | instruction | done once |
  | --- | --- | --- |
  | 7 | HOLD left OR right TO RUN | it has run (52) faster than 2 both left and right |
  | 14 | PRESS attack WHILE UNARMED TO PUNCH | it has punched (49) and the partner has been hit in the face (38) and knocked down (47) |
  | 15 | PRESS attack NEAR A KNOCKED DOWN OPPONENT TO REMOVE HEART | it is tearing out a heart (69) |
  | 8 | PRESS jump TO JUMP | it is dropping down (18) |
  | 3 | PRESS attack IN THE AIR TO DIVEKICK | it has dive kicked (14) and skidded (15) |
  | 4 | HOLD down TO DUCK | it crawls (9) |
  | 16 | PRESS attack WHILE DUCKING TO SWEEP THE LEG | it has sweep kicked (70) and the partner has tripped (76) |
  | 13 | PRESS down TO PICK UP SWORDS | unarmed, it then holds a sword; the partner drops whatever it holds |
  | 17 | TAP left OR right TO FENCE | fencing on the ground, it has tapped left and right |
  | 11 | PRESS up AND down TO CHANGE YOUR SWORD HEIGHT | it has held its sword high, middle and low |
  | 10 | PRESS attack WITH A SWORD TO LUNGE | it lunges (48) while the partner is stabbed standing (65) |
  | 12 | IN CLOSE QUARTERS MOVING UP OR DOWN INTO A SWORD WILL DISARM | the partner is disarmed (13) |
  | 18 | PRESS up AND attack TO THROW YOUR SWORD | it throws (72, 73) |
  | 2 | BLOCK THROWN SWORDS WITH YOUR SWORD, DUCK UNDER THEM, OR JUMP OVER THEM | a thrown sword was blocked or missed it (`block/2`) |
  | 1 | THE ARROW SHOWS THE RIGHT OF WAY. TO GET IT, KILL YOUR OPPONENT. IF YOU HAVE IT, RUN! | the partner is gone; the learner then leads |
  | 6 | THAT'S IT! follow that arrow! | 240 frames have passed |
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.Bout.Input
  alias Nidhox.Brain.{Intent, Sense}
  alias Nidhox.Gml
  alias Nidhox.Man.Weapon

  @noone -4
  @standing 4_890_894
  @thrower 38_968_458
  @fists 1
  @sword 2
  @order [7, 14, 15, 8, 3, 4, 16, 13, 17, 11, 10, 12, 18, 2, 1, 6]
  @lines %{
    17 => {"tutorial_tap_left_right", "TAP {0} OR {1} TO FENCE", [0, 1]},
    7 => {"tutorial_hold_left_right", "HOLD {0} OR {1} TO RUN", [0, 1]},
    11 => {"tutorial_move_sword", "PRESS {0} AND {1} TO CHANGE YOUR SWORD HEIGHT", [2, 3]},
    4 => {"tutorial_duck", "HOLD {0} TO DUCK", [3]},
    8 => {"tutorial_jump", "PRESS {0} TO JUMP", [4]},
    10 => {"tutorial_lunge", "PRESS {0} WITH A SWORD TO LUNGE", [5]},
    12 => {"tutorial_parry", "IN CLOSE QUARTERS MOVING UP OR DOWN INTO A SWORD WILL DISARM", []},
    13 => {"tutorial_pick_up_sword", "PRESS {0} TO PICK UP SWORDS", [3]},
    18 => {"tutorial_throw_sword", "PRESS {0} AND {1} TO THROW YOUR SWORD", [2, 5]},
    2 =>
      {"tutorial_block_thrown_sword",
       "BLOCK THROWN SWORDS WITH YOUR SWORD, DUCK UNDER THEM, OR JUMP OVER THEM", []},
    3 => {"tutorial_dive_kick", "PRESS {0} IN THE AIR TO DIVEKICK", [5]},
    15 => {"tutorial_stomp", "PRESS {0} NEAR A KNOCKED DOWN OPPONENT TO REMOVE HEART", [5]},
    16 => {"tutorial_sweep_kick", "PRESS {0} WHILE DUCKING TO SWEEP THE LEG", [5]},
    14 => {"tutorial_punch", "PRESS {0} WHILE UNARMED TO PUNCH", [5]},
    1 =>
      {"tutorial_arrows",
       "THE ARROW SHOWS THE RIGHT OF WAY. TO GET IT, KILL YOUR OPPONENT. IF YOU HAVE IT, RUN!",
       []},
    6 => {"tutorial_finished", "THAT'S IT! follow that arrow!", []}
  }
  @block_lesson 2

  @doc "The lessons in the order the tutorial teaches them."
  @spec order() :: [pos_integer()]
  def order, do: @order

  @doc "Lesson `move`'s instruction: `{key, english, buttons}`."
  @spec line(pos_integer()) :: {String.t(), String.t(), [non_neg_integer()]}
  def line(move), do: Map.fetch!(@lines, move)

  @doc "The world after lesson `move` is checked for `Tutorial` `self`, learner `yellow` and partner `orange` (`-4` for none)."
  @spec check(World.t(), non_neg_integer(), number(), number()) :: World.t()
  def check(%World{} = world, self, yellow, orange) do
    move = Gml.var(world, self, :currentMove)

    world =
      if move in [1, 6],
        do: world,
        else: partner(world, if(move == @block_lesson, do: @thrower, else: @standing))

    lesson(world, self, move, yellow, orange)
  end

  @doc """
  The world after player `player` blocked or got past a thrown sword
  (`challengeMode_move_completed(player, 8)`): in the thrown sword lesson, that player's
  mark set.
  """
  @spec block(World.t(), integer()) :: World.t()
  def block(%World{} = world, player) do
    world
    |> Gml.all("Tutorial")
    |> Enum.reduce(world, fn tutorial, world ->
      if Gml.var(world, tutorial, :currentMove) == @block_lesson,
        do: mark(world, tutorial, trunc(player)),
        else: world
    end)
  end

  defp partner(world, personality) do
    world |> Gml.all("Brain") |> Enum.reduce(world, &Gml.put(&2, &1, %{personality: personality}))
  end

  defp lesson(world, self, 17, yellow, _orange) do
    world =
      if Sense.fencing?(world, yellow) do
        player = Gml.var(world, yellow, :playerIndex)

        world
        |> mark_if(self, 0, Input.pressed?(world, yellow, player, 0))
        |> mark_if(self, 1, Input.pressed?(world, yellow, player, 1))
      else
        world |> unmark(self, 0) |> unmark(self, 1)
      end

    complete_if(world, self, marked?(world, self, [0, 1]))
  end

  defp lesson(world, self, 7, yellow, _orange) do
    hspd = Gml.var(world, yellow, :hspd)

    world =
      if state(world, yellow) == 52 and Gml.gt?(abs(hspd), 2) do
        world
        |> mark_if(self, 0, Gml.lt?(hspd, 0))
        |> mark_if(self, 1, Gml.gt?(hspd, 0))
      else
        world
      end

    complete_if(world, self, marked?(world, self, [0, 1]))
  end

  defp lesson(world, self, 8, yellow, _orange),
    do: complete_if(world, self, state(world, yellow) == 18)

  defp lesson(world, self, 4, yellow, _orange),
    do: complete_if(world, self, state(world, yellow) == 9)

  defp lesson(world, self, 11, yellow, _orange) do
    stance = Gml.var(world, yellow, :stance)

    world
    |> mark_if(self, 0, stance == 1)
    |> mark_if(self, 1, stance == 3)
    |> mark_if(self, 2, stance == 2)
    |> then(&complete_if(&1, self, marked?(&1, self, [0, 1, 2])))
  end

  defp lesson(world, self, 10, yellow, orange) do
    complete_if(
      world,
      self,
      present?(orange) and state(world, yellow) == 48 and state(world, orange) == 65
    )
  end

  defp lesson(world, self, 12, _yellow, orange),
    do: complete_if(world, self, present?(orange) and state(world, orange) == 13)

  defp lesson(world, self, 13, yellow, orange) do
    world =
      if state(world, yellow) == 23, do: world |> unmark(self, 0) |> unmark(self, 1), else: world

    world =
      case Sense.weapon_type(world, yellow) do
        @fists -> world |> mark(self, 0) |> unmark(self, 1)
        @sword -> mark(world, self, 1)
        _other -> world
      end

    world = complete_if(world, self, marked?(world, self, [0, 1]))
    if present?(orange), do: drop(world, orange), else: world
  end

  defp lesson(world, self, 18, yellow, _orange),
    do: complete_if(world, self, state(world, yellow) in [72, 73])

  defp lesson(world, self, 2, yellow, orange) do
    world = throw_at_learner(world, orange)
    marked = marked?(world, self, [trunc(Gml.var(world, yellow, :playerIndex))])

    if marked do
      world = complete_if(world, self, true)
      world |> Gml.all("Brain") |> Enum.reduce(world, &World.destroy(&2, &1))
    else
      world
    end
  end

  defp lesson(world, self, 3, yellow, _orange) do
    world
    |> mark_if(self, 0, state(world, yellow) == 14)
    |> mark_if(self, 1, state(world, yellow) == 15)
    |> then(&complete_if(&1, self, marked?(&1, self, [0, 1])))
  end

  defp lesson(world, self, 15, yellow, _orange),
    do: complete_if(world, self, state(world, yellow) == 69)

  defp lesson(world, self, 16, yellow, orange) do
    world
    |> mark_if(self, 0, state(world, yellow) == 70)
    |> mark_if(self, 1, present?(orange) and state(world, orange) == 76)
    |> then(&complete_if(&1, self, marked?(&1, self, [0, 1])))
  end

  defp lesson(world, self, 14, yellow, orange) do
    world
    |> mark_if(self, 0, state(world, yellow) == 49)
    |> mark_if(self, 1, present?(orange) and state(world, orange) == 38)
    |> mark_if(self, 2, present?(orange) and state(world, orange) == 47)
    |> then(&complete_if(&1, self, marked?(&1, self, [0, 1, 2])))
  end

  defp lesson(world, self, 1, _yellow, _orange) do
    if Gml.exists?(world, "OrangePlayer") do
      world
    else
      world
      |> lead_learner()
      |> complete_if(self, true)
    end
  end

  defp lesson(world, self, 6, _yellow, _orange),
    do: complete_if(world, self, Gml.gt?(Gml.var(world, self, :moveCounter), 240))

  defp lesson(world, _self, _move, _yellow, _orange), do: world

  defp throw_at_learner(world, orange) do
    world
    |> Gml.all("Brain")
    |> Enum.reduce(world, fn brain, world ->
      if present?(orange) and Sense.weapon_type(world, orange) == @sword,
        do: Intent.set(world, brain, 29),
        else: world
    end)
  end

  defp lead_learner(world) do
    case Gml.first(world, "Match") do
      nil -> world
      match -> Gml.put(world, match, %{leadingPlayerIndex: 1})
    end
  end

  defp drop(world, man) do
    {_dropped, world} = Weapon.drop(world, man)
    world
  end

  defp mark_if(world, self, index, true), do: mark(world, self, index)
  defp mark_if(world, _self, _index, false), do: world

  defp mark(world, self, index), do: put_mark(world, self, index, 1)
  defp unmark(world, self, index), do: put_mark(world, self, index, 0)

  defp put_mark(world, self, index, value) do
    marks = Gml.var(world, self, :check, %{})
    Gml.put(world, self, %{check: Map.put(marks, index, value)})
  end

  defp marked?(world, self, indices) do
    marks = Gml.var(world, self, :check, %{})
    Enum.all?(indices, &Gml.truthy?(Map.get(marks, &1, 0)))
  end

  defp complete_if(world, self, true), do: Gml.put(world, self, %{COMPLETED_MOVE: 1})
  defp complete_if(world, _self, false), do: world

  defp present?(id), do: Sense.present?(id) and id != @noone
  defp state(world, man), do: Gml.var(world, man, :state, -1)
end
