defmodule Nidhox.Bout.Sound do
  @moduledoc """
  The game's sounds played where its code plays them (`playSoundAtLoopEffect(sound, x,
  y, …)`): a sound placed at `{x, y}` and heard from the camera's centre by NidhOX's
  audio (`Cauldron2D.Audio`), 16 pixels to a tile. A sound is named by its index in the
  data file (`play/3`) or by its name (`play_named/3`).

  The game's own falloff — its emitters, the `Ear` and `nextSoundVolume` — is not
  modelled.
  """

  alias Cauldron2D.GameMaker.{Data, World}

  @tile 16

  @doc "The world with sound number `sound` played at `{x, y}`."
  @spec play(World.t(), non_neg_integer(), {number(), number()}) :: World.t()
  def play(%World{} = world, sound, {x, y}) do
    case Enum.at(world.data.sounds, sound) do
      nil -> world
      %{name: name} -> World.emit(world, {{:recording, name}, {x / @tile, y / @tile}})
    end
  end

  @doc "The world with the sound called `name` played at `{x, y}`."
  @spec play_named(World.t(), String.t(), {number(), number()}) :: World.t()
  def play_named(%World{} = world, name, position) do
    case Data.index(world.data, :sounds, name) do
      nil -> world
      sound -> play(world, sound, position)
    end
  end
end
