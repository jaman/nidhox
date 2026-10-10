defmodule Nidhox.Objects.MainMenu do
  @moduledoc """
  What the game's `MainMenu` (in `rMainMenu`) does beyond NidhOX's own menus, and its
  title music (`MainMenuMusic`), as the game's code runs them.

    * `MainMenu` create: its alarm 0 at 180 frames, and a wind surface at
      alpha 0.1 (`Nidhox.Objects.Wind.create/2`); alarm 0: a `MainMenuMusic` made
    * `MainMenuMusic` create: its track by `System.level` — Castle (20)
      `music_CastleTitle`, Mines (21) and Sky (22) `music_CloudsTitle`, Wilds (23)
      `music_WildsTitle`, any other `music_Cemetery_Melody` — played looping
      (`audio_play_sound(track, 1, true)`); step: the track at `System.musicVol`
      (`audio_sound_gain`); destroy and room end: the track stopped

  The track sounds at the client's music level (`Cauldron2D.Audio.keyed/4`'s `music:
  true`), so the music plays only in `rMainMenu`, from three seconds after it is entered.
  """

  alias Cauldron2D.Audio
  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Gml
  alias Nidhox.Objects.{System, Wind}

  @music_delay 180
  @title_alpha 0.1
  @tracks %{20 => 134, 21 => 153, 22 => 153, 23 => 147}
  @other_track 0

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_MainMenu_Create_0", &menu_start/3},
      {"gml_Object_MainMenu_Alarm_0", &music_made/3},
      {"gml_Object_MainMenuMusic_Create_0", &music_start/3},
      {"gml_Object_MainMenuMusic_Step_0", &music_step/3},
      {"gml_Object_MainMenuMusic_Destroy_0", &music_stop/3},
      {"gml_Object_MainMenuMusic_Other_5", &music_stop/3}
    ]
  end

  defp menu_start(world, self, _other) do
    world
    |> World.update(self, &Instance.put_alarm(&1, 0, @music_delay))
    |> Wind.create(@title_alpha)
  end

  defp music_made(world, _self, _other),
    do: world |> World.create(World.object_index(world, "MainMenuMusic"), {0, 0}) |> elem(0)

  defp music_start(world, self, _other) do
    track = Map.get(@tracks, round(System.get(world, :level)), @other_track)
    gain = System.get(world, :musicVol, 1)
    %{name: name} = Enum.at(world.data.sounds, track)

    world
    |> Gml.put(self, %{z: 0, sound: track, gain: gain})
    |> World.emit(
      Audio.keyed(key(self), {:recording, name}, {:level, gain, 0.0}, loop: true, music: true)
    )
  end

  defp music_step(world, self, _other) do
    gain = System.get(world, :musicVol, 1)

    if gain == Gml.var(world, self, :gain),
      do: world,
      else:
        world
        |> Gml.put(self, %{gain: gain})
        |> World.emit(Audio.moved(key(self), {:level, gain, 0.0}))
  end

  defp music_stop(world, self, _other), do: World.emit(world, Audio.stopped(key(self)))

  defp key(self), do: {:main_menu_music, self}
end
