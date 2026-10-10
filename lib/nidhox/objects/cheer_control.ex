defmodule Nidhox.Objects.CheerControl do
  @moduledoc """
  The game's `CheerControl`: a crowd cheering (`sfxCheer`, round and round) where it
  stands, kept within 80 pixels of the screen's edges. The tutorial makes one for its
  last lesson.

    * create: the cheer started at it while a match is on (`playSoundAtLoopEffect`,
      following it through the `Ear`, `Nidhox.Objects.Ear.attach/3`, which lets it go
      once it is gone)
    * step: across at its starting place held 80 pixels inside the screen; the cheer at
      `System.sfxVol` × the share of the spectators (`o_crowd`, `Nidhox.Objects.Crowd`)
      not sitting (`sound_fade`). With no spectators that share is 0 / 0, which leaves the
      level as it is
  """

  alias Cauldron2D.Audio
  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Bout.Camera
  alias Nidhox.Gml
  alias Nidhox.Objects.{Ear, System}

  @cheer 127
  @sitting 57
  @inside 80

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_CheerControl_Create_0", &create/3},
      {"gml_Object_CheerControl_Step_0", &hold_on_screen/3}
    ]
  end

  defp create(world, self, _other) do
    world = Gml.put(world, self, %{z: 0, sound: -1})

    if Gml.exists?(world, "Match") do
      {sound, world} = Ear.attach(world, self, @cheer)
      Gml.put(world, self, %{sound: sound})
    else
      world
    end
  end

  defp hold_on_screen(world, self, _other) do
    %Instance{xstart: start} = World.fetch(world, self)
    x = Gml.clamp(start, Camera.left(world) + @inside, Camera.right(world) - @inside)
    world |> World.update(self, &%{&1 | x: x}) |> follow_crowd(self, Gml.all(world, "o_crowd"))
  end

  defp follow_crowd(world, _self, []), do: world

  defp follow_crowd(world, self, crowd) do
    standing = Enum.count(crowd, &(not Gml.eq?(Gml.var(world, &1, :state), @sitting)))

    case Gml.var(world, self, :sound) do
      -1 -> world
      sound -> World.emit(world, Audio.moved(sound, {:level, System.get(world, :sfxVol, 1) * standing / length(crowd), 0.0}))
    end
  end
end
