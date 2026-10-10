defmodule Nidhox.Objects.Ear do
  @moduledoc """
  The game's `Ear`, made by `System` and kept across rooms: where sounds are heard
  from, and the keeper of the sounds that follow an instance (`specialSounds`).

    * create: no sounds following anything
    * begin step: to the camera's centre (`cameraCenterX`, `cameraCenterY`); each
      following sound moved to where its instance is, or let go once the instance is gone

  `attach/3` (`playSoundAtLoopEffect(sound, x, y, 1, 1, owner)`) starts the copy's sound
  number `sound` going round and round at instance `owner` and following it.
  `position/1` is where the `Ear` is, the camera's centre when there is none.
  """

  alias Cauldron2D.Audio
  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Bout.Camera
  alias Nidhox.Gml

  @tile 16

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Ear_Create_0", fn world, self, _other -> Gml.put(world, self, %{z: 0, specialSounds: []}) end},
      {"gml_Object_Ear_Step_1", &follow/3}
    ]
  end

  @doc "Where the `Ear` is, `{x, y}`."
  @spec position(World.t()) :: {number(), number()}
  def position(%World{} = world) do
    case Gml.first(world, "Ear") do
      nil -> {Camera.center_x(world), Camera.center_y(world)}
      ear -> with %Instance{x: x, y: y} <- World.fetch(world, ear), do: {x, y}
    end
  end

  @doc "`{key, world}` with the copy's sound number `sound` going round at instance `owner` and following it."
  @spec attach(World.t(), non_neg_integer(), non_neg_integer()) :: {term(), World.t()}
  def attach(%World{} = world, owner, sound) do
    key = {:attached, owner, sound}
    %Instance{x: x, y: y} = World.fetch(world, owner)

    world =
      case Enum.at(world.data.sounds, sound) do
        nil -> world
        %{name: name} -> World.emit(world, Audio.keyed(key, {:recording, name}, at(x, y), loop: true))
      end

    case Gml.first(world, "Ear") do
      nil -> {key, world}
      ear -> {key, Gml.put(world, ear, %{specialSounds: Gml.var(world, ear, :specialSounds, []) ++ [{key, owner}]})}
    end
  end

  @doc "The world with following sound `key` stopped and no longer kept (`audio_stop_sound`)."
  @spec detach(World.t(), term()) :: World.t()
  def detach(%World{} = world, key) do
    world = World.emit(world, Audio.stopped(key))

    case Gml.first(world, "Ear") do
      nil -> world
      ear -> Gml.put(world, ear, %{specialSounds: Enum.reject(Gml.var(world, ear, :specialSounds, []), &match?({^key, _owner}, &1))})
    end
  end

  defp follow(world, self, _other) do
    world = World.update(world, self, &%{&1 | x: Camera.center_x(world), y: Camera.center_y(world)})
    {kept, world} = Enum.flat_map_reduce(Gml.var(world, self, :specialSounds, []), world, &keep_following/2)
    Gml.put(world, self, %{specialSounds: kept})
  end

  defp keep_following({key, owner} = sound, world) do
    case World.fetch(world, owner) do
      %Instance{x: x, y: y} -> {[sound], World.emit(world, Audio.moved(key, at(x, y)))}
      nil -> {[], World.emit(world, Audio.stopped(key))}
    end
  end

  defp at(x, y), do: {x / @tile, y / @tile}
end
