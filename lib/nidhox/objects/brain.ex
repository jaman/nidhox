defmodule Nidhox.Objects.Brain do
  @moduledoc """
  The game's `Brain`: the computer playing one player (`playerIndex`), made by the
  match for a demonstration (both players) and a single player game (player 2). It
  holds that player's buttons (`Nidhox.Brain.Buttons`), which the match reads in place
  of a controller.

    * create: no player yet (`playerIndex` −1), the fence plan (103) and no next one,
      no buttons held, `stateCounter` 0, a `beat` of 10, 20 or 30 frames and its alarm
      in 40, 50 or 60; no fencer, opponent or thrown sword (−4) and the opponent a
      room's width away; no action; `lastOnGroundY` −1; `difficulty` 0.75; the
      personalities 10, 6, 5, 11, 4, 2, 1, 8 and 9, one of them picked
      (`Nidhox.Brain.Personality`)
    * alarm 0: a new `beat` — the larger of 2 or 5 and 28, 30, 34 or 38 less
      `difficulty × 30` — and the alarm again in 30, 60, 80, 90 or 110 frames
    * room start: another personality picked
    * user event 0, once a match frame (`Nidhox.Bout.Frame`): its fencer (`player`) and
      the opponent's found; without a fencer, or while it is entering (23), collapsing,
      stabbed or in state 28, or once the match is finished, the next plan is to wait
      for control (108); `lastOnGroundY` follows the fencer on the ground; the
      opponent's distance across (10000 without both) and a dangerous thrown sword
      (`flyingSword`). Then the next plan taken (`Nidhox.Brain.Intent.advance/2`), the
      plans (`Nidhox.Brain.Plan`), the action dropped when the personality would not
      take it, the action (`Nidhox.Brain.Act`), and both counters (`stateCounter`,
      `actionCounter`) one on. In the tutorial's twelfth move up and down are let go

  The `Brain`'s debug drawing (shown with the 0 key) is not drawn.
  """

  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Brain.{Act, Buttons, Intent, Personality, Plan, Sense}
  alias Nidhox.Gml
  alias Nidhox.Man.Query
  alias Nidhox.Objects.Match

  @noone -4
  @personalities [10, 6, 5, 11, 4, 2, 1, 8, 9]
  @waiting 108
  @entering 23
  @far 10_000
  @tutorial_move 12

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Brain_Create_0", &create/3},
      {"gml_Object_Brain_Alarm_0", &new_beat/3},
      {"gml_Object_Brain_Other_4", fn world, self, _other -> Personality.pick(world, self) end},
      {"gml_Object_Brain_Other_10", &think/3}
    ]
  end

  @doc "The `Brain` playing `player`, `nil` for none (`findBrainWithPlayerIndex`)."
  @spec for_player(World.t(), integer()) :: non_neg_integer() | nil
  def for_player(%World{} = world, player),
    do: world |> Gml.all("Brain") |> Enum.find(&Gml.eq?(Gml.var(world, &1, :playerIndex), player))

  defp create(world, self, _other) do
    {beat, world} = Gml.choose(world, [10, 20, 30])
    {alarm, world} = Gml.choose(world, [40, 50, 60])
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
      player: @noone,
      opponent: @noone,
      opponentDist: room_width,
      flyingSword: @noone
    })
    |> World.update(self, &Instance.put_alarm(&1, 0, alarm))
    |> Intent.clear(self)
    |> Gml.put(self, %{lastOnGroundY: -1, difficulty: 0.75, personalities: @personalities})
    |> Personality.pick(self)
  end

  defp new_beat(world, self, _other) do
    {least, world} = Gml.choose(world, [2, 5])
    {most, world} = Gml.choose(world, [28, 30, 34, 38])
    {alarm, world} = Gml.choose(world, [30, 60, 80, 90, 110])

    world
    |> Gml.put(self, %{beat: max(least, most - Gml.var(world, self, :difficulty) * 30)})
    |> World.update(self, &Instance.put_alarm(&1, 0, alarm))
  end

  defp think(world, self, _other) do
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
      not Sense.present?(man) -> world |> Intent.next_state(self, @waiting) |> Gml.put(self, %{lastOnGroundY: -1})
      Gml.exists?(world, "ChallengeMode") -> world
      true -> world |> follow_ground(self, man) |> wait_for_control(self, man)
    end
  end

  defp follow_ground(world, self, man) do
    if Gml.truthy?(Gml.var(world, man, :onGround)),
      do: Gml.put(world, self, %{lastOnGroundY: World.fetch(world, man).y}),
      else: world
  end

  defp wait_for_control(world, self, man) do
    state = Gml.var(world, man, :state)

    if state == @entering or Query.collapsing?(world, man) or Query.stabbed?(world, man) or state == 28 or
         Gml.truthy?(Match.get(world, :finished)),
       do: Intent.next_state(world, self, @waiting),
       else: world
  end

  defp find_opponent(world, self, player) do
    man = Gml.var(world, self, :player, @noone)
    other = Query.by_player(world, Query.other_player(player)) || @noone
    world = Gml.put(world, self, %{opponent: other, opponentDist: @far, flyingSword: @noone})
    world = if Sense.present?(man), do: Gml.put(world, self, %{flyingSword: Sense.dangerous_sword(world, man)}), else: world

    if Sense.present?(man) and Sense.present?(other),
      do: Gml.put(world, self, %{opponentDist: abs(World.fetch(world, man).x - World.fetch(world, other).x)}),
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
