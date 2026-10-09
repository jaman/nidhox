defmodule Nidhox.Brain.Intent do
  @moduledoc """
  What a `Brain` means to do: its `state` (a plan, 101–109) and its `action` (a move
  within it, 1–30 and 55), changed as the game's AI scripts change them.

    * `clear/2` (`clearAction`): no action (`action` −1, `actionCounter` 0, not
      completed or failed, no suggestion) and every button let go
    * `set/3` (`setAction`): a new action, cleared first; the same action again changes
      nothing
    * `random_melee/2` (`randomMeleeAction`): cleared, then one of dive kick (9), getting
      close (13), sweep kick (28), finding a sword (10), punching (21), backing off on
      guard (4), pausing (20) or jumping over the opponent (16)
    * `next_state/3` (`set_nextAIState`): the plan to take next
    * `advance/2` (`processNextAiState`): the next plan taken when it differs from this
      one — `stateCounter` 0 and no action (`action` −1, `actionCounter` −1)
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.Brain.Buttons
  alias Nidhox.Gml

  @melee [9, 13, 28, 10, 21, 4, 20, 16]

  @doc "The world with `Brain` `self` doing nothing (`clearAction`)."
  @spec clear(World.t(), non_neg_integer()) :: World.t()
  def clear(%World{} = world, self) do
    world
    |> Gml.put(self, %{action: -1, actionCounter: 0, actionCompleted: 0, actionSuggestion: -1, actionFailed: 0})
    |> Buttons.release_all(self, [0, 1, 2, 3, 5, 4])
  end

  @doc "The world with `Brain` `self` taking `action` (`setAction`)."
  @spec set(World.t(), non_neg_integer(), number()) :: World.t()
  def set(%World{} = world, self, action) do
    if Gml.eq?(Gml.var(world, self, :action), action),
      do: world,
      else: world |> clear(self) |> Gml.put(self, %{action: action})
  end

  @doc "The world with `Brain` `self` taking a random close-quarters action (`randomMeleeAction`)."
  @spec random_melee(World.t(), non_neg_integer()) :: World.t()
  def random_melee(%World{} = world, self) do
    world = clear(world, self)
    {action, world} = Gml.choose(world, @melee)
    set(world, self, action)
  end

  @doc "The world with `Brain` `self` to take plan `state` next (`set_nextAIState`)."
  @spec next_state(World.t(), non_neg_integer(), number()) :: World.t()
  def next_state(%World{} = world, self, state), do: Gml.put(world, self, %{nextState: state})

  @doc "The world with `Brain` `self` on its next plan, when it has a different one (`processNextAiState`)."
  @spec advance(World.t(), non_neg_integer()) :: World.t()
  def advance(%World{} = world, self) do
    next = Gml.var(world, self, :nextState, -1)

    if not Gml.eq?(Gml.var(world, self, :state), next) and not Gml.eq?(next, -1),
      do:
        Gml.put(world, self, %{
          state: next,
          stateCounter: 0,
          action: -1,
          actionCounter: -1,
          actionCompleted: 0,
          actionSuggestion: -1
        }),
      else: world
  end
end
