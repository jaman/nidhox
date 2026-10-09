defmodule Nidhox.Music do
  @moduledoc """
  The music of the player's copy of the game, one `Cauldron2D.Audio.Music` piece per
  area, played from the copy's own recordings.

  Each piece, `"nidhox/<area>"`, has two sections:

    * `:title` — the area's title track, for the title, the menus and the results
    * `:bout` — the layers of the area's music, for the bout, mixed as `cue/3` says

  | area | stems (`music_<name>_…`) | title |
  | --- | --- | --- |
  | Cemetery | `Cemetery_Melody`, `_Drums` | `Cemetery_Distant` |
  | Castle | `Castle_Drms1`, `_Drms2`, `_Synth1`, `_Synth2` | `CastleTitle` |
  | Mines | `Mines_BasicDrums`, `_Drums4Part2`, `_MechanicalLayer`, `_Synth1`, `_Synth2`, `_Synth4Part2`, `_Synth4Part3` | `MinesTitle` |
  | Sky | `Clouds_Drums`, `_SynthsPart1`–`4` | `CloudsTitle` |
  | Wilds | `Forest_Drums`, `_Synth1`–`3` | `WildsTitle` |

  Each recording is `Nidhox.Recordings`' of that name, decoded the first time its
  section is cued and fitted to the stage's 44.1 kHz stereo; one the copy
  lacks is silence.
  """

  alias Nidhox.Recordings

  @rate 44_100

  @areas %{
    "Cemetery" => {["Cemetery_Melody", "Cemetery_Drums"], "Cemetery_Distant"},
    "Castle" =>
      {["Castle_Drms1", "Castle_Drms2", "Castle_Synth1", "Castle_Synth2"], "CastleTitle"},
    "Mines" =>
      {[
         "Mines_BasicDrums",
         "Mines_Drums4Part2",
         "Mines_MechanicalLayer",
         "Mines_Synth1",
         "Mines_Synth2",
         "Mines_Synth4Part2",
         "Mines_Synth4Part3"
       ], "MinesTitle"},
    "Sky" =>
      {[
         "Clouds_Drums",
         "Clouds_SynthsPart1",
         "Clouds_SynthsPart2",
         "Clouds_SynthsPart3",
         "Clouds_SynthsPart4"
       ], "CloudsTitle"},
    "Wilds" => {["Forest_Drums", "Forest_Synth1", "Forest_Synth2", "Forest_Synth3"], "WildsTitle"}
  }

  @doc "Every area's piece, by name, as `Cauldron2D.Client.Game`'s `music/0` gives them."
  @spec specs() :: [{String.t(), Cauldron2D.Audio.Music.spec()}]
  def specs, do: Enum.map(@areas, fn {area, stems} -> {piece(area), spec(stems)} end)

  @doc """
  The cue for a frame on `screen` in `area` with the bout `progress` from its centre
  (`Nidhox.Bout.progress/1`, `0.0`–`1.0`): the area's `:bout` section while the bout is
  being fought, paused or about to begin, its `:title` section otherwise. The tutorial
  has none: its `Tutorial` plays its own music.

  In the bout, the stems play in the table's order: the first alone in the centre, one
  more joining with each step towards an end room, every one of them in the end rooms.
  Each playing stem is at `1 / n` of the level for `n` playing, so together they never
  go past full scale; the rest are silent.
  """
  @spec cue(String.t(), atom(), number()) :: Cauldron2D.Audio.Music.cue() | nil
  def cue(area, screen, progress \\ 0.0)

  def cue(_area, :tutorial, _progress), do: nil

  def cue(area, screen, progress) when is_map_key(@areas, area) do
    if screen in [:en_garde, :bout, :paused],
      do: %{piece: piece(area), section: :bout, layers: gains(area, progress)},
      else: %{piece: piece(area), section: :title}
  end

  def cue(_area, _screen, _progress), do: nil

  defp gains(area, progress) do
    {stems, _title} = Map.fetch!(@areas, area)
    count = length(stems)
    playing = min(count, 1 + floor(progress * (count - 1) + 1.0e-9))

    stems
    |> Enum.with_index()
    |> Map.new(fn {stem, index} ->
      {layer(stem), if(index < playing, do: 1 / playing, else: 0.0)}
    end)
  end

  defp piece(area), do: "nidhox/" <> String.downcase(area)

  defp spec({stems, title}) do
    layers = Enum.map(stems, &layer/1)

    %{
      bpm: 120,
      beats_per_bar: 4,
      layers: [:title | layers],
      sections: %{
        title: %{title: fn -> recording(title) end},
        bout: Map.new(stems, &{layer(&1), fn -> recording(&1) end})
      },
      fingerprint: Enum.join([title | stems], ","),
      render: :on_cue
    }
  end

  defp layer(stem), do: stem |> String.downcase() |> String.to_atom()

  defp recording(stem) do
    case Recordings.wave("music_" <> stem) do
      {:ok, wave} -> fit(wave)
      {:error, _missing} -> <<>>
    end
  end

  defp fit(%{rate: rate, channels: channels, pcm: pcm}) do
    pcm
    |> stereo(channels)
    |> resample(rate)
  end

  defp stereo(pcm, 2), do: pcm
  defp stereo(pcm, 1), do: for(<<s::binary-2 <- pcm>>, into: <<>>, do: s <> s)

  defp stereo(pcm, channels) do
    extra = channels * 2 - 4

    for <<left::binary-2, right::binary-2, _rest::binary-size(^extra) <- pcm>>,
      into: <<>>,
      do: left <> right
  end

  defp resample(pcm, @rate), do: pcm

  defp resample(pcm, rate) do
    frames = div(byte_size(pcm), 4)
    out = div(frames * @rate, rate)

    for index <- 0..(out - 1)//1, into: <<>> do
      source = min(div(index * rate, @rate), frames - 1)
      binary_part(pcm, source * 4, 4)
    end
  end
end
