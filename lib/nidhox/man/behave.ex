defmodule Nidhox.Man.Behave do
  @moduledoc """
  `stateBehavior(state)`: what a fencer does in its state each step, by the state's
  family — standing (`Nidhox.Man.States.Stand`), moving (`Move`), in the air (`Air`),
  attacking (`Attack`), hurt (`Hurt`) — and then, whatever the state, `stateCounter`
  counts the step. A state no family has does nothing but count.
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.Man.State
  alias Nidhox.Man.States.{Air, Attack, Hurt, Move, Stand}

  @stand [29, 78, 32, 7, 8, 30, 31, 23]
  @move [52, 80, 81, 54, 9, 58, 59, 61, 62, 53, 36, 22, 11, 10, 50, 51]
  @air [43, 44, 18, 19, 27, 28, 1, 2, 3, 35, 14, 15, 16, 79]
  @attack [48, 49, 55, 45, 70, 72, 73, 69, 4, 5]
  @hurt [
    13,
    17,
    38,
    40,
    41,
    47,
    33,
    76,
    77,
    65,
    63,
    64,
    66,
    20,
    26,
    24,
    39,
    37,
    67,
    68,
    46,
    82,
    83
  ]

  @doc "The world after fencer `self`'s behaviour in its state `state` (`stateBehavior`)."
  @spec run(World.t(), non_neg_integer(), integer()) :: World.t()
  def run(%World{} = world, self, state) do
    world = family(world, self, state)

    if World.fetch(world, self),
      do: State.put(world, self, %{stateCounter: State.get(world, self, :stateCounter) + 1}),
      else: world
  end

  defp family(world, self, state) when state in @stand, do: Stand.behave(world, self, state)
  defp family(world, self, state) when state in @move, do: Move.behave(world, self, state)
  defp family(world, self, state) when state in @air, do: Air.behave(world, self, state)
  defp family(world, self, state) when state in @attack, do: Attack.behave(world, self, state)
  defp family(world, self, state) when state in @hurt, do: Hurt.behave(world, self, state)
  defp family(world, _self, _state), do: world
end
