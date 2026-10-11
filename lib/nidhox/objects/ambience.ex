defmodule Nidhox.Objects.Ambience do
  @moduledoc """
  The rooms' standing sounds, as the game's code plays them, each looping
  (`playSoundAtLoopEffect(sound, x, y, 1, …)`):

    * `CenterRoomNoises` create: the edge of the centre (sound 94) 160 pixels in from
      each end of the room at the camera's middle height (`leftSound`, `rightSound`),
      and the wind (93) following the `Ear` (`wind`)
    * `BGFireRoomNoise` create: the background fire (92) following the `Ear` (`fire`)
    * `WaterfallRoomEdges` create: the waterfall's edge (123) 160 pixels in from each
      end at the camera's middle height
    * these three stop their sounds in user event 0, which their destroy and room end
      run, so each room starts its own
    * `WaterfallSounds` and `DroneSounds` create: the waterfall (122) or the drone (128)
      following the instance (`Nidhox.Objects.Ear.attach/3`, let go once it is gone),
      which then moves to the camera's middle height

  A sound at a place is a `Cauldron2D.Audio` event at it in tiles of 16 pixels.
  """

  alias Cauldron2D.Audio
  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Bout.Camera
  alias Nidhox.Gml
  alias Nidhox.Objects.Ear

  @tile 16
  @edge 160
  @centre_edge 94
  @wind 93
  @fire 92
  @waterfall_edge 123
  @waterfall 122
  @drone 128

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_CenterRoomNoises_Create_0", &centre_room/3},
      {"gml_Object_CenterRoomNoises_Other_10",
       fn world, self, _other -> hush(world, self, [:leftSound, :rightSound, :wind]) end},
      {"gml_Object_BGFireRoomNoise_Create_0", &fire_room/3},
      {"gml_Object_BGFireRoomNoise_Other_10",
       fn world, self, _other -> hush(world, self, [:fire]) end},
      {"gml_Object_WaterfallRoomEdges_Create_0", &waterfall_edges/3},
      {"gml_Object_WaterfallRoomEdges_Other_10",
       fn world, self, _other -> hush(world, self, [:leftSound, :rightSound]) end},
      {"gml_Object_WaterfallSounds_Create_0",
       fn world, self, _other -> follow(world, self, @waterfall) end},
      {"gml_Object_DroneSounds_Create_0",
       fn world, self, _other -> follow(world, self, @drone) end}
    ] ++
      for object <- ["CenterRoomNoises", "BGFireRoomNoise", "WaterfallRoomEdges"],
          event <- ["Destroy_0", "Other_5"] do
        {"gml_Object_#{object}_#{event}",
         fn world, self, _other -> World.perform(world, self, :other, 10) end}
      end
  end

  defp centre_room(world, self, _other) do
    world = edges(world, self, @centre_edge)
    {wind, world} = Ear.attach(world, Gml.first(world, "Ear"), @wind)
    Gml.put(world, self, %{wind: wind})
  end

  defp fire_room(world, self, _other) do
    {fire, world} = Ear.attach(world, Gml.first(world, "Ear"), @fire)
    Gml.put(world, self, %{fire: fire})
  end

  defp waterfall_edges(world, self, _other), do: edges(world, self, @waterfall_edge)

  defp edges(world, self, sound) do
    middle = Camera.center_y(world)
    left = {self, :left}
    right = {self, :right}

    world
    |> loop(left, sound, {@edge, middle})
    |> loop(right, sound, {Camera.room_width(world) - @edge, middle})
    |> Gml.put(self, %{leftSound: left, rightSound: right})
  end

  defp loop(world, key, sound, {x, y}) do
    case Enum.at(world.data.sounds, sound) do
      nil ->
        world

      %{name: name} ->
        World.emit(
          world,
          Audio.keyed(key, {:recording, name}, {x / @tile, y / @tile}, loop: true)
        )
    end
  end

  defp hush(world, self, names) do
    Enum.reduce(names, world, fn name, world ->
      case Gml.var(world, self, name, nil) do
        nil -> world
        key -> Ear.detach(world, key)
      end
    end)
  end

  defp follow(world, self, sound) do
    {loop, world} = Ear.attach(world, self, sound)

    world
    |> Gml.put(self, %{z: 0, soundLoop: loop})
    |> World.update(self, fn %Instance{} = instance -> %{instance | y: Camera.center_y(world)} end)
  end
end
