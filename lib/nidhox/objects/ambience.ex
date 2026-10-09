defmodule Nidhox.Objects.Ambience do
  @moduledoc """
  The rooms' standing sounds, from the objects the copy places for them, each sounding
  the copy's own recording (`{:recording, name}` in `Nidhox.Sounds`) round and round
  under the key `{:ambience, object}` while the room has an instance of the object:

  | object | recording | where it sounds |
  | --- | --- | --- |
  | `CenterRoomNoises` | `sfxWind` | everywhere, at `@wind` |
  | `CenterRoomNoises` | `sfxEdgeOfCenter` | twice: `@edge` pixels in from each end of the room, at the camera's middle height |
  | `BGFireRoomNoise` | `sfxFireBackground` | everywhere, at `@fire` |
  | `DroneSounds` | `sfxDrone` | everywhere, at `@drone` |
  | `WaterfallSounds` | `sfxWaterfall` | at the instance |
  | `WaterfallRoomEdges` | `sndWaterfallEdge` | at the instance |

  An instance's creation starts its sound unless the same object's is already
  sounding, so a sound carries on unbroken from one room into the next that has it.
  `settle/1`, after every step, stops each sound whose object the room no longer has.
  The sounding objects are kept in the world's global `:ambience`.

  A swinging chandelier's creak (`creak/2`), one of `sfxChandelier1`–`3`, sounds round
  and round at it the same way.

  The sounds are `Cauldron2D.Audio` events in the world's outbox; a placed sound is at
  the instance's position in tiles of `@tile` pixels.
  """

  alias Cauldron2D.Audio
  alias Cauldron2D.GameMaker.Instance
  alias Cauldron2D.GameMaker.World

  @tile 16
  @wind 0.45
  @fire 0.5
  @drone 0.4
  @fade 0.4
  @edge 160
  @creaks ["sfxChandelier1", "sfxChandelier2", "sfxChandelier3"]

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_CenterRoomNoises_Create_0", &centre_room/3},
      {"gml_Object_BGFireRoomNoise_Create_0", everywhere("sfxFireBackground", @fire)},
      {"gml_Object_DroneSounds_Create_0", everywhere("sfxDrone", @drone)},
      {"gml_Object_WaterfallSounds_Create_0", placed("sfxWaterfall")},
      {"gml_Object_WaterfallRoomEdges_Create_0", placed("sndWaterfallEdge")}
    ]
  end

  @doc "The world with every sounding ambience whose object the room no longer has stopped."
  @spec settle(World.t()) :: World.t()
  def settle(%World{} = world) do
    sounding = World.global(world, :ambience, MapSet.new())
    {kept, gone} = Enum.split_with(sounding, &present?(world, &1))

    gone
    |> Enum.reduce(world, &World.emit(&2, Audio.stopped({:ambience, &1}, @fade)))
    |> World.put_global(:ambience, MapSet.new(kept))
  end

  defp centre_room(world, self, _other) do
    {width, _height} = Enum.at(world.data.rooms, world.room).size
    middle = camera_center_y(world)

    world
    |> sound(self, "sfxEdgeOfCenter", {@edge / @tile, middle / @tile}, :left)
    |> sound(self, "sfxEdgeOfCenter", {(width - @edge) / @tile, middle / @tile}, :right)
    |> sound(self, "sfxWind", {:level, @wind, 0.0}, :wind)
  end

  defp camera_center_y(%World{views: [%{view: {_x, y, _width, height}} | _]}), do: y + height / 2
  defp camera_center_y(%World{}), do: 100

  defp everywhere(recording, level),
    do: fn world, self, _other -> sound(world, self, recording, {:level, level, 0.0}) end

  defp placed(recording) do
    fn world, self, _other ->
      %Instance{x: x, y: y} = World.fetch(world, self)
      sound(world, self, recording, {x / @tile, y / @tile})
    end
  end

  defp sound(world, self, recording, at, part \\ nil) do
    name = World.object(world, World.fetch(world, self).object).name
    object = if part, do: {name, part}, else: name
    sounding = World.global(world, :ambience, MapSet.new())

    if MapSet.member?(sounding, object) do
      world
    else
      world
      |> World.emit(
        Audio.keyed({:ambience, object}, {:recording, recording}, at, loop: true, fade: @fade)
      )
      |> World.put_global(:ambience, MapSet.put(sounding, object))
    end
  end

  defp present?(world, {object, _part}), do: present?(world, object)

  defp present?(world, object) do
    case World.object_index(world, object) do
      nil -> false
      index -> Enum.any?(world.order, &(world.instances[&1].object == index))
    end
  end

  @doc "The world with chandelier `self`'s creak, one of `sfxChandelier1`–`3`, sounding round and round at it."
  @spec creak(World.t(), non_neg_integer()) :: World.t()
  def creak(%World{} = world, self) do
    recording = Enum.at(@creaks, :erlang.phash2(self, length(@creaks)))
    placed(recording).(world, self, nil)
  end
end
