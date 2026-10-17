defmodule Nidhox.Objects.Brain do
  @moduledoc """
  The game's `Brain`: the computer playing one player (`playerIndex`), made by the
  match for a demonstration (both players), a single player game (player 2) and training
  (`start_training/4`). It holds that player's buttons (`Nidhox.Brain.Buttons`), which
  the match reads in place of a controller.

    * create: no player yet (`playerIndex` −1), the fence plan (103) and no next one,
      no buttons held, `stateCounter` 0, a `beat` of 10, 20 or 30 frames and a
      `beatTimer` of 40, 50 or 60 frames; no fencer, opponent or thrown sword (−4) and
      the opponent a room's width away; no action; `lastOnGroundY` −1; `difficulty`
      0.75; the personalities 10, 6, 5, 11, 4, 2, 1, 8 and 9, one of them picked
      (`Nidhox.Brain.Personality`)
    * room start: another personality picked
    * step, in a single player run (`Nidhox.Objects.Arcade`): `difficulty` the run's
      (`getArcadeModeDifficulty`) times `System.aiDifficulty`; in training
      `System.trainingDifficulty`. On a level against, or in training as, personality
      5646466, every 720th frame a new personality `choose(5, 6, 1, 4, 2, 9, 8)`
    * user event 0, once a match frame (`Nidhox.Bout.Frame`): `beatTimer` one down,
      and at 0 a new `beat` — the larger of 2 or 5 and 28, 30, 34 or 38 less
      `difficulty × 30` — and the timer again at 30, 60, 80, 90 or 110 frames. Then
      its fencer (`player`) and the opponent's found; without a fencer, or while it is
      entering (23), collapsing, stabbed or in state 28, or once the match is finished,
      the next plan is to wait for control (108); `lastOnGroundY` follows the fencer on
      the ground; the opponent's distance across (10000 without both) and a dangerous
      thrown sword (`flyingSword`). Then the next plan taken
      (`Nidhox.Brain.Intent.advance/2`), the plans (`Nidhox.Brain.Plan`), the action
      dropped when the personality would not take it, the action (`Nidhox.Brain.Act`),
      and both counters (`stateCounter`, `actionCounter`) one on. In the tutorial's
      twelfth move up and down are let go

  The `Brain`'s debug drawing (shown with the 0 key) is not drawn.
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.Brain.{Act, Buttons, Intent, Personality, Plan, Sense}
  alias Nidhox.Gml
  alias Nidhox.Man.Query
  alias Nidhox.Objects.{Arcade, Match, System}

  @noone -4
  @personalities [10, 6, 5, 11, 4, 2, 1, 8, 9]
  @waiting 108
  @entering 23
  @far 10_000
  @changing 5_646_466
  @change_period 720
  @tutorial_move 12

  @type player :: 1 | 2

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Brain_Create_0", &create/3},
      {"gml_Object_Brain_Other_4", fn world, self, _other -> Personality.pick(world, self) end},
      {"gml_Object_Brain_Step_0", &step/3},
      {"gml_Object_Brain_Other_10", &think/3}
    ]
  end

  @doc "The `Brain` playing `player`, `nil` for none (`findBrainWithPlayerIndex`)."
  @spec for_player(World.t(), integer()) :: non_neg_integer() | nil
  def for_player(%World{} = world, player),
    do: world |> Gml.all("Brain") |> Enum.find(&Gml.eq?(Gml.var(world, &1, :playerIndex), player))

  @doc """
  A new `Brain` playing `player` (`createBrainForPlayer`): `{world, brain}`.

  The `Brain` picks its personality as it is made, so `System` must already hold any
  training choice (`start_training/4` does both).
  """
  @spec create_for_player(World.t(), player()) :: {World.t(), non_neg_integer()}
  def create_for_player(%World{} = world, player) do
    {world, brain} = World.create(world, World.object_index(world, "Brain"), {0, 0})
    {Gml.put(world, brain, %{playerIndex: player}), brain}
  end

  @doc """
  A new `Brain` playing `player` as the training menu's `personality` at `difficulty`:
  `{:ok, {world, brain}}`, or `{:error, :unknown_personality}`.

  `personality` is a name from `Nidhox.Brain.Personality.training/0` (`:no_divekicks`,
  `:no_throws`, `:divekicker`, `:run_n_lunge`, `:brawler`, `:never_lunges`,
  `:parry_master` or `:random`) or the number that name stands for. `difficulty` runs
  from 0 to 1 and the `Brain` follows it on every step; the training menu offers 0.0 to
  1.0 in steps of 0.1 and starts at 0.5.

  The call sets `System.training` to 1, `System.trainingPersonality` and
  `System.trainingDifficulty`, so every `Brain` made while training is on plays that
  personality, and a `Brain` made before it keeps the one it has. The world needs a
  `System`. Set `System.training` back to 0 when training ends.

      {:ok, {world, brain}} =
        Nidhox.Objects.Brain.start_training(world, 2, :parry_master, 0.7)
  """
  @spec start_training(World.t(), player(), Personality.training_name() | integer(), number()) ::
          {:ok, {World.t(), non_neg_integer()}} | {:error, :unknown_personality}
  def start_training(%World{} = world, player, personality, difficulty) do
    case Personality.training_id(personality) do
      {:ok, id} ->
        world =
          System.put(world, %{
            training: 1,
            trainingPersonality: id,
            trainingDifficulty: difficulty
          })

        {:ok, create_for_player(world, player)}

      :error ->
        {:error, :unknown_personality}
    end
  end

  defp step(world, self, _other) do
    world
    |> follow_difficulty(self)
    |> change_personality(self)
  end

  defp follow_difficulty(world, self) do
    cond do
      Gml.exists?(world, "ArcadeMode") ->
        difficulty = Arcade.difficulty(world) * System.get(world, :aiDifficulty, 1)
        Gml.put(world, self, %{difficulty: difficulty})

      training?(world) ->
        Gml.put(world, self, %{difficulty: System.get(world, :trainingDifficulty, 0.5)})

      true ->
        world
    end
  end

  defp change_personality(world, self) do
    if changing?(world) and Gml.eq?(:math.fmod(System.get(world, :frame), @change_period), 0) do
      {personality, world} = Gml.choose(world, [5, 6, 1, 4, 2, 9, 8])
      Gml.put(world, self, %{personality: personality})
    else
      world
    end
  end

  defp changing?(world) do
    cond do
      Gml.exists?(world, "ArcadeMode") ->
        level = Gml.var(world, Gml.first(world, "ArcadeMode"), :level)
        Arcade.contains?(world, level, @changing)

      training?(world) ->
        Gml.eq?(System.get(world, :trainingPersonality, 5), @changing)

      true ->
        false
    end
  end

  defp training?(world), do: Gml.truthy?(System.get(world, :training))

  defp create(world, self, _other) do
    {beat, world} = Gml.choose(world, [10, 20, 30])
    {beat_timer, world} = Gml.choose(world, [40, 50, 60])
    {room_width, _height} = Enum.at(world.data.rooms, world.room).size

    world
    |> Gml.put(self, %{
      playerIndex: -1,
      state: 103,
      nextState: -1,
      grid: Buttons.empty(),
      stateCounter: 0,
      stepDelay: 0,
      beat: beat,
      beatTimer: beat_timer,
      player: @noone,
      opponent: @noone,
      opponentDist: room_width,
      flyingSword: @noone
    })
    |> Intent.clear(self)
    |> Gml.put(self, %{lastOnGroundY: -1, difficulty: 0.75, personalities: @personalities})
    |> Personality.pick(self)
  end

  defp tick_beat(world, self) do
    timer = Gml.var(world, self, :beatTimer, 0) - 1
    world = Gml.put(world, self, %{beatTimer: timer})
    if timer <= 0, do: new_beat(world, self), else: world
  end

  defp new_beat(world, self) do
    {least, world} = Gml.choose(world, [2, 5])
    {most, world} = Gml.choose(world, [28, 30, 34, 38])
    {timer, world} = Gml.choose(world, [30, 60, 80, 90, 110])

    Gml.put(world, self, %{
      beat: max(least, most - Gml.var(world, self, :difficulty) * 30),
      beatTimer: timer
    })
  end

  defp think(world, self, _other) do
    world = tick_beat(world, self)
    player = Gml.var(world, self, :playerIndex)

    if Gml.truthy?(player) do
      world
      |> find_fencer(self, player)
      |> find_opponent(self, player)
      |> Intent.advance(self)
      |> Plan.run(self)
      |> keep_action(self)
      |> Act.run(self)
      |> count(self)
      |> tutorial_stance(self)
    else
      world
    end
  end

  defp find_fencer(world, self, player) do
    man = Query.by_player(world, player) || @noone
    world = Gml.put(world, self, %{player: man})

    cond do
      not Sense.present?(man) ->
        world |> Intent.next_state(self, @waiting) |> Gml.put(self, %{lastOnGroundY: -1})

      Gml.exists?(world, "ChallengeMode") ->
        world

      true ->
        world |> follow_ground(self, man) |> wait_for_control(self, man)
    end
  end

  defp follow_ground(world, self, man) do
    if Gml.truthy?(Gml.var(world, man, :onGround)),
      do: Gml.put(world, self, %{lastOnGroundY: World.fetch(world, man).y}),
      else: world
  end

  defp wait_for_control(world, self, man) do
    state = Gml.var(world, man, :state)

    if state == @entering or Query.collapsing?(world, man) or Query.stabbed?(world, man) or
         state == 28 or
         Gml.truthy?(Match.get(world, :finished)),
       do: Intent.next_state(world, self, @waiting),
       else: world
  end

  defp find_opponent(world, self, player) do
    man = Gml.var(world, self, :player, @noone)
    other = Query.by_player(world, Query.other_player(player)) || @noone
    world = Gml.put(world, self, %{opponent: other, opponentDist: @far, flyingSword: @noone})

    world =
      if Sense.present?(man),
        do: Gml.put(world, self, %{flyingSword: Sense.dangerous_sword(world, man)}),
        else: world

    if Sense.present?(man) and Sense.present?(other),
      do:
        Gml.put(world, self, %{
          opponentDist: abs(World.fetch(world, man).x - World.fetch(world, other).x)
        }),
      else: world
  end

  defp keep_action(world, self) do
    case Personality.chance(world, self, Gml.var(world, self, :action), 100) do
      {true, world} -> world
      {false, world} -> Intent.clear(world, self)
    end
  end

  defp count(world, self) do
    Gml.put(world, self, %{
      stateCounter: Gml.var(world, self, :stateCounter) + 1,
      actionCounter: Gml.var(world, self, :actionCounter) + 1
    })
  end

  defp tutorial_stance(world, self) do
    case Gml.first(world, "Tutorial") do
      nil ->
        world

      tutorial ->
        if Gml.eq?(Gml.var(world, tutorial, :currentMove), @tutorial_move),
          do: Buttons.release_all(world, self, [2, 3]),
          else: world
    end
  end
end
