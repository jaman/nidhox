defmodule Nidhox.Brain.Act do
  @moduledoc """
  The computer player's action for this frame (`actionStateMachine`): without a fencer
  the action fails; once completed it does nothing more; otherwise the `Brain`'s
  `action` runs — a moving one (`Nidhox.Brain.Travel`) or a fighting one
  (`Nidhox.Brain.Combat`). No action (−1) does nothing.
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.Brain.{Combat, Sense, Travel}
  alias Nidhox.Gml

  @noone -4
  @travel [1, 2, 3, 4, 7, 8, 12, 13, 14, 20, 22, 23, 24, 25, 26, 27, 30, 55]
  @combat [5, 6, 9, 10, 11, 15, 16, 17, 18, 19, 21, 28, 29]

  @doc "The world after `Brain` `self`'s action for this frame (`actionStateMachine`)."
  @spec run(World.t(), non_neg_integer()) :: World.t()
  def run(%World{} = world, self) do
    world =
      if Sense.present?(Gml.var(world, self, :player, @noone)),
        do: world,
        else: Gml.put(world, self, %{actionFailed: 1, actionCompleted: 1})

    if Gml.truthy?(Gml.var(world, self, :actionCompleted)),
      do: world,
      else: act(world, self, Gml.var(world, self, :action))
  end

  defp act(world, self, action) when action in @travel, do: Travel.run(world, self, action)
  defp act(world, self, action) when action in @combat, do: Combat.run(world, self, action)
  defp act(world, _self, _action), do: world
end
