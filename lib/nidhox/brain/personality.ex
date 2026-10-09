defmodule Nidhox.Brain.Personality do
  @moduledoc """
  The computer player's character: which personality a `Brain` plays, and how much more
  or less often that personality takes each action.

    * `pick/2` (`pickPersonality`): one of the `Brain`'s `personalities`, at random
    * `chance/4` (`charBasedProbActionDefault(action, chance)`): whether the `Brain`
      takes `action` this time — always for running to the goal (26) in a left end room
      (`roomCode` 4), else `prob(chance × multiplier)`, the multiplier being the
      personality's for that action, 1 when it has none

  | personality | multipliers (action: multiplier) |
  | --- | --- |
  | 4890894 | 29: 0, 10: 0, 19: 0, 7: 0.25, 9: 0, 11: 0, 21: 0, 28: 0, 26: 0, 2: 5, 4: 4 |
  | 38968458 | 29: 1e8, 10: 1000, 7: 0.25, 2: 1e4, 4: 1e4, 26: 0, 13: 0, 15: 0, 18: 0, 19: 0, 9: 0, 20: 2, 27: 0 |
  | 5 | 9: 0, 29: 0.1, 10: 0.3, 7: 0, 19: 0.5, 15: 0.5 |
  | 6 | 29: 0 |
  | 11 | 29: 10, 10: 3 |
  | 2 | 9: 6 |
  | 10 | 20: 6, 7: 6 |
  | 4 | 19: 0 |
  | 8 | 18: 0.5, 15: 6, 19: 0.1, 4: 0, 29: 0.1, 10: 10 |
  | 1 | 29: 1e4, 10: 0 |
  | 9 | 29: 0.25, 19: 10, 2: 10, 18: 0.25, 15: 0.25, 10: 10 |
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.Gml
  alias Nidhox.Objects.RoomCodes

  @run_to_goal 26
  @left_end 4
  @multipliers %{
    4_890_894 => %{29 => 0, 10 => 0, 19 => 0, 7 => 0.25, 9 => 0, 11 => 0, 21 => 0, 28 => 0, 26 => 0, 2 => 5, 4 => 4},
    38_968_458 => %{
      29 => 1.0e8,
      10 => 1000,
      7 => 0.25,
      2 => 1.0e4,
      4 => 1.0e4,
      26 => 0,
      13 => 0,
      15 => 0,
      18 => 0,
      19 => 0,
      9 => 0,
      20 => 2,
      27 => 0
    },
    5 => %{9 => 0, 29 => 0.1, 10 => 0.3, 7 => 0, 19 => 0.5, 15 => 0.5},
    6 => %{29 => 0},
    11 => %{29 => 10, 10 => 3},
    2 => %{9 => 6},
    10 => %{20 => 6, 7 => 6},
    4 => %{19 => 0},
    8 => %{18 => 0.5, 15 => 6, 19 => 0.1, 4 => 0, 29 => 0.1, 10 => 10},
    1 => %{29 => 1.0e4, 10 => 0},
    9 => %{29 => 0.25, 19 => 10, 2 => 10, 18 => 0.25, 15 => 0.25, 10 => 10}
  }

  @doc "The world with `Brain` `self` playing one of its `personalities`, picked at random."
  @spec pick(World.t(), non_neg_integer()) :: World.t()
  def pick(%World{} = world, self) do
    personalities = Gml.var(world, self, :personalities, [])
    {index, world} = Gml.irandom(world, length(personalities) - 1)
    Gml.put(world, self, %{personality: Enum.at(personalities, index)})
  end

  @doc "`{taken, world}`: whether `Brain` `self` takes `action` at `chance` in 100, by its personality."
  @spec chance(World.t(), non_neg_integer(), number(), number()) :: {boolean(), World.t()}
  def chance(%World{} = world, self, action, chance) do
    if Gml.eq?(action, @run_to_goal) and Gml.eq?(RoomCodes.room_code(world), @left_end) do
      {true, world}
    else
      multiplier = @multipliers |> Map.get(Gml.var(world, self, :personality), %{}) |> Map.get(action, 1)
      Gml.prob(world, chance * multiplier)
    end
  end
end
