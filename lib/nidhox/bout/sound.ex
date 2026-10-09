defmodule Nidhox.Bout.Sound do
  @moduledoc """
  The game's sounds played where its code plays them (`playSoundAtLoopEffect(sound, x,
  y, …)`): the copy's sound number `sound`, placed at `{x, y}` and heard from the
  camera's centre by NidhOX's audio (`Cauldron2D.Audio`), 16 pixels to a tile.

  The game's own falloff — its emitters, the `Ear` and `nextSoundVolume` — is not
  modelled.
  """

  alias Cauldron2D.GameMaker.World

  @tile 16

  @doc "The world with sound number `sound` played at `{x, y}`."
  @spec play(World.t(), non_neg_integer(), {number(), number()}) :: World.t()
  def play(%World{} = world, sound, {x, y}) do
    case Enum.at(world.data.sounds, sound) do
      nil -> world
      %{name: name} -> World.emit(world, {{:recording, name}, {x / @tile, y / @tile}})
    end
  end
end
