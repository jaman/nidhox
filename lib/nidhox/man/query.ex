defmodule Nidhox.Man.Query do
  @moduledoc """
  What the game's code asks about a fencer (a `Man`, `YellowPlayer` or `OrangePlayer`):

    * `ducking?/2` (`isDucking`): crawling (9) or sliding (58)
    * `crouched?/2` (`isCrouched`): in state 9, 58, 70, 33, 47 or 61
    * `stabbed?/2` (`isAlreadyStabbed`): in or about to enter state 65, 63, 64, 37, 39
      or 5
    * `collapsing?/2` (`isAlreadyCollapsing`): in or about to enter state 66, 20, 26,
      24 or 39
    * `knocked_down?/2` (`isKnockedDown`): in state 47
    * `attacking?/2` (`isAttacking`): in state 48, 49, 70, 14, 55, 45, 72 or 73
    * `other_player/1` (`otherPlayerIndex`, `findOppositeIndex`): 2 for 1, 1 for 2
    * `by_player/2` (`findManByPlayerIndex`): the fencer of a player, `nil` for none
    * `opponent/2` (`playerGetOtherPlayer`): yellow's is orange and orange's yellow
    * `face_opponent/2` (`faceOpponent`): turned towards the opponent, unless it is
      collapsing
    * `player_dist/1` (`playerDist`): how far apart the two fencers are across, the
      view's width while either is missing
  """

  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Gml

  @yellow "YellowPlayer"
  @orange "OrangePlayer"

  @doc "Whether fencer `id` is crawling or sliding (`isDucking`)."
  @spec ducking?(World.t(), non_neg_integer()) :: boolean()
  def ducking?(world, id), do: state(world, id) in [9, 58]

  @doc "Whether fencer `id` is low (`isCrouched`)."
  @spec crouched?(World.t(), non_neg_integer()) :: boolean()
  def crouched?(world, id), do: state(world, id) in [9, 58, 70, 33, 47, 61]

  @doc "Whether fencer `id` is being stabbed (`isAlreadyStabbed`)."
  @spec stabbed?(World.t(), non_neg_integer()) :: boolean()
  def stabbed?(world, id), do: either?(world, id, [65, 63, 64, 37, 39, 5])

  @doc "Whether fencer `id` is collapsing (`isAlreadyCollapsing`)."
  @spec collapsing?(World.t(), non_neg_integer()) :: boolean()
  def collapsing?(world, id), do: either?(world, id, [66, 20, 26, 24, 39])

  @doc "Whether fencer `id` is knocked down (`isKnockedDown`)."
  @spec knocked_down?(World.t(), non_neg_integer()) :: boolean()
  def knocked_down?(world, id), do: state(world, id) == 47

  @doc "Whether fencer `id` is attacking (`isAttacking`)."
  @spec attacking?(World.t(), non_neg_integer()) :: boolean()
  def attacking?(world, id), do: state(world, id) in [48, 49, 70, 14, 55, 45, 72, 73]

  @doc "The other player's index (`otherPlayerIndex`)."
  @spec other_player(integer()) :: integer()
  def other_player(1), do: 2
  def other_player(2), do: 1

  @doc "The fencer of player `player` (`findManByPlayerIndex`), `nil` for none."
  @spec by_player(World.t(), integer()) :: non_neg_integer() | nil
  def by_player(%World{} = world, player) do
    with object when is_integer(object) <- World.object_index(world, "Man") do
      world
      |> World.instances_of(object)
      |> Enum.find(&(Gml.var(world, &1, :playerIndex, -1) == player))
    end
  end

  @doc "Fencer `id`'s opponent (`playerGetOtherPlayer`), `nil` for none."
  @spec opponent(World.t(), non_neg_integer()) :: non_neg_integer() | nil
  def opponent(%World{} = world, id) do
    name = World.object(world, World.fetch(world, id).object).name

    case name do
      @yellow -> first(world, @orange)
      @orange -> first(world, @yellow)
      _other -> nil
    end
  end

  @doc "Fencer `id` turned towards its opponent unless that one is collapsing (`faceOpponent`)."
  @spec face_opponent(World.t(), non_neg_integer()) :: World.t()
  def face_opponent(%World{} = world, id) do
    with other when other != nil <- opponent(world, id),
         false <- collapsing?(world, other) do
      %Instance{x: other_x} = World.fetch(world, other)
      %Instance{x: x} = World.fetch(world, id)
      Gml.put(world, id, %{facingXScale: if(other_x > x, do: 1, else: -1)})
    else
      _ -> world
    end
  end

  @doc "How far apart the two fencers stand across (`playerDist`); the view's width without both."
  @spec player_dist(World.t()) :: number()
  def player_dist(%World{} = world) do
    with yellow when yellow != nil <- first(world, @yellow),
         orange when orange != nil <- first(world, @orange) do
      abs(World.fetch(world, yellow).x - World.fetch(world, orange).x)
    else
      _missing -> Nidhox.Bout.Camera.right(world) - Nidhox.Bout.Camera.left(world)
    end
  end

  defp either?(world, id, states),
    do: state(world, id) in states or Gml.var(world, id, :nextState, -1) in states

  defp state(world, id), do: Gml.var(world, id, :state, -1)

  defp first(world, name) do
    with object when is_integer(object) <- World.object_index(world, name),
         [id | _] <- World.instances_of(world, object) do
      id
    else
      _none -> nil
    end
  end
end
