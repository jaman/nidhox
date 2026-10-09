defmodule Nidhox.Brain.Buttons do
  @moduledoc """
  The buttons a `Brain` holds for its player, in its `grid` of six (0 left, 1 right,
  2 up, 3 down, 4 jump, 5 attack). The match reads them in place of that player's
  controller when it records the frame's input, so the fencer acts on them one frame
  after the `Brain` sets them.

    * `press/3` (`press(playerIndex, button)`): the button held. Forward (8) and back
      (9) become right or left by the way the player's fencer faces (right while its
      `facingXScale` is 1). Pressing left lets go of right and the other way round, and
      pressing up lets go of down and the other way round
    * `release/3` (`release(playerIndex, button)`): the button let go, except in the
      first two frames (`System.frame` below 2)
    * `release_all/3`: `release/3` for each of the buttons given, in order
    * `down?/3` (`checkPlayerIndexButtonDown(playerIndex, button)`): whether the match
      has the button down for the player this frame
    * `held/2`: the actions the grid holds, as a controller's held set
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.Bout.Input
  alias Nidhox.Gml
  alias Nidhox.Man.Query
  alias Nidhox.Objects.System

  @empty {0, 0, 0, 0, 0, 0}
  @actions [:left, :right, :up, :down, :jump, :attack]
  @forward 8
  @back 9
  @opposite %{0 => 1, 1 => 0, 2 => 3, 3 => 2}

  @doc "A grid with no button held."
  @spec empty() :: tuple()
  def empty, do: @empty

  @doc "The world with `Brain` `self` holding `button` (`press`)."
  @spec press(World.t(), non_neg_integer(), non_neg_integer()) :: World.t()
  def press(%World{} = world, self, button) do
    button = facing(world, self, button)

    world
    |> let_go_of_opposite(self, button)
    |> set(self, button, 1)
  end

  @doc "The world with `Brain` `self` letting go of `button` (`release`)."
  @spec release(World.t(), non_neg_integer(), non_neg_integer()) :: World.t()
  def release(%World{} = world, self, button) do
    if System.get(world, :frame) < 2, do: world, else: set(world, self, button, 0)
  end

  @doc "The world with `Brain` `self` letting go of each of `buttons`, in order."
  @spec release_all(World.t(), non_neg_integer(), [non_neg_integer()]) :: World.t()
  def release_all(%World{} = world, self, buttons),
    do: Enum.reduce(buttons, world, &release(&2, self, &1))

  @doc "Whether the match has `button` down for `Brain` `self`'s player (`checkPlayerIndexButtonDown`)."
  @spec down?(World.t(), non_neg_integer(), non_neg_integer()) :: boolean()
  def down?(%World{} = world, self, button),
    do: Input.down?(world, self, Gml.var(world, self, :playerIndex), button)

  @doc "The actions `Brain` `brain`'s grid holds."
  @spec held(World.t(), non_neg_integer()) :: MapSet.t()
  def held(%World{} = world, brain) do
    grid = Gml.var(world, brain, :grid, @empty)
    for {action, index} <- Enum.with_index(@actions), elem(grid, index) == 1, into: MapSet.new(), do: action
  end

  defp let_go_of_opposite(world, self, button) when is_map_key(@opposite, button),
    do: release(world, self, Map.fetch!(@opposite, button))

  defp let_go_of_opposite(world, _self, _button), do: world

  defp set(world, self, button, value) do
    grid = Gml.var(world, self, :grid, @empty)
    Gml.put(world, self, %{grid: put_elem(grid, button, value)})
  end

  defp facing(world, self, button) when button in [@forward, @back] do
    man = Query.by_player(world, Gml.var(world, self, :playerIndex))
    right? = Gml.eq?(Gml.var(world, man, :facingXScale), 1)

    case {button, right?} do
      {@forward, true} -> 1
      {@forward, false} -> 0
      {@back, true} -> 0
      {@back, false} -> 1
    end
  end

  defp facing(_world, _self, button), do: button
end
