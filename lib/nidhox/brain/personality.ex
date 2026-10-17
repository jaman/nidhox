defmodule Nidhox.Brain.Personality do
  @moduledoc """
  The computer player's character: which personality a `Brain` plays, and how much more
  or less often that personality takes each action.

    * `pick/2` (`pickPersonality`): in a single player run the level's personality
      (`Arcade.personality/1`); in training (`System.training`) the chosen one
      (`System.trainingPersonality`); else one of the `Brain`'s `personalities` at random,
      and in a CPU battle (`System.flow` 62831853) its `difficulty` the battle's hype
      (`System.cpuBattleHype`) scaled by a random 0.8 to 1.2 and held between 0 and 1
    * `training/0` and `training_id/1`: the personalities the training menu offers, by name
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
  alias Nidhox.Objects.{Arcade, RoomCodes, System}

  @type training_name ::
          :no_divekicks
          | :no_throws
          | :divekicker
          | :run_n_lunge
          | :brawler
          | :never_lunges
          | :parry_master
          | :random

  @cpu_battle 62_831_853
  @training [
    no_divekicks: 5,
    no_throws: 6,
    divekicker: 2,
    run_n_lunge: 9,
    brawler: 1,
    never_lunges: 4,
    parry_master: 8,
    random: 5_646_466
  ]
  @run_to_goal 26
  @left_end 4
  @multipliers %{
    4_890_894 => %{
      29 => 0,
      10 => 0,
      19 => 0,
      7 => 0.25,
      9 => 0,
      11 => 0,
      21 => 0,
      28 => 0,
      26 => 0,
      2 => 5,
      4 => 4
    },
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

  @doc """
  The training menu's personalities in menu order, each as `{name, personality}`.

  The `:random` personality (5646466) draws a new personality from `5, 6, 1, 4, 2, 9, 8`
  every 720 frames.

      iex> Nidhox.Brain.Personality.training() |> Keyword.keys()
      [:no_divekicks, :no_throws, :divekicker, :run_n_lunge, :brawler, :never_lunges, :parry_master, :random]
  """
  @spec training() :: [{training_name(), integer()}, ...]
  def training, do: @training

  @doc """
  The personality for a training menu name, or the number itself when it is one of the
  personalities the menu offers.

      iex> Nidhox.Brain.Personality.training_id(:brawler)
      {:ok, 1}
      iex> Nidhox.Brain.Personality.training_id(8)
      {:ok, 8}
      iex> Nidhox.Brain.Personality.training_id(:unknown)
      :error
  """
  @spec training_id(training_name() | integer()) :: {:ok, integer()} | :error
  def training_id(name) when is_atom(name), do: Keyword.fetch(@training, name)

  def training_id(personality) when is_integer(personality),
    do: if(personality in Keyword.values(@training), do: {:ok, personality}, else: :error)

  @doc """
  The world with `Brain` `self` playing its personality (`pickPersonality`).

  A single player run gives the level's personality. Training gives
  `System.trainingPersonality`. Otherwise one of the `Brain`'s `personalities` comes up
  at random, and a CPU battle also sets `difficulty`.
  """
  @spec pick(World.t(), non_neg_integer()) :: World.t()
  def pick(%World{} = world, self) do
    case Arcade.personality(world) do
      nil -> pick_outside_run(world, self)
      personality -> Gml.put(world, self, %{personality: personality})
    end
  end

  defp pick_outside_run(world, self) do
    if Gml.truthy?(System.get(world, :training)),
      do: Gml.put(world, self, %{personality: System.get(world, :trainingPersonality, 5)}),
      else: world |> pick_random(self) |> battle_difficulty(self)
  end

  defp pick_random(world, self) do
    personalities = Gml.var(world, self, :personalities, [])
    {index, world} = Gml.irandom(world, length(personalities) - 1)
    Gml.put(world, self, %{personality: Enum.at(personalities, index)})
  end

  defp battle_difficulty(world, self) do
    if System.get(world, :flow) == @cpu_battle do
      {jitter, world} = Gml.random_range(world, 0.8, 1.2)
      hype = System.get(world, :cpuBattleHype, 0.75)
      Gml.put(world, self, %{difficulty: Gml.clamp(hype * jitter, 0, 1)})
    else
      world
    end
  end

  @doc "`{taken, world}`: whether `Brain` `self` takes `action` at `chance` in 100, by its personality."
  @spec chance(World.t(), non_neg_integer(), number(), number()) :: {boolean(), World.t()}
  def chance(%World{} = world, self, action, chance) do
    if Gml.eq?(action, @run_to_goal) and Gml.eq?(RoomCodes.room_code(world), @left_end) do
      {true, world}
    else
      multiplier =
        @multipliers |> Map.get(Gml.var(world, self, :personality), %{}) |> Map.get(action, 1)

      Gml.prob(world, chance * multiplier)
    end
  end
end
