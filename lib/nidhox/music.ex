defmodule Nidhox.Music do
  @moduledoc """
  Background music for NidhOX.

  Two pieces:
  - `"menu"` — ambient tension, low and steady, for the title screen and main menu
  - `"match"` — rhythmic pulse, higher tension, during fencing

  Each piece uses Strudel chains (strings) for live performance. The client
  transitions between sections via `cue/2`.
  """

  @bpm 80

  @doc """
  Background music specs, mapped by piece name.

  Each spec uses Strudel chains (strings) for live audio synthesis.
  """
  @spec specs() :: %{String.t() => map()}
  def specs do
    %{
      "menu" => menu_spec(),
      "match" => match_spec()
    }
  end

  # Menu music — ambient tension, slow and steady.
  defp menu_spec do
    %{
      bpm: @bpm,
      beats_per_bar: 4,
      layers: [:drone, :pulse, :string],
      sections: %{
        idle: %{
          drone: ~s|s("bd2*4, hh2*8").bank("RolandTR808").gain(0.3)|,
          pulse: ~s|s("bd2*8, sn*4").bank("RolandTR808").gain(0.2)|,
          string: ~s|s("fs2*2, a2*4").gain(0.1).saw(0.4).cutoff(0.45).lpf(0.35, 0.8, 0.12)|
        },
        tension: %{
          drone: ~s|s("bd2*4, hh2*8").bank("RolandTR808").gain(0.35)|,
          pulse: ~s|s("bd2*4, sn*2").bank("RolandTR808").gain(0.25)|,
          string: ~s|s("fs2, a2, c3, a2").gain(0.15).saw(0.4).cutoff(0.45).lpf(0.35, 0.8, 0.12)|
        }
      }
    }
  end

  # Match music — rhythmic pulse, urgent.
  defp match_spec do
    %{
      bpm: @bpm + 20,
      beats_per_bar: 4,
      layers: [:pulse, :bass, :string, :arpeggio],
      sections: %{
        neutral: %{
          pulse: ~s|s("bd2*4, hh4, sn*2").bank("RolandTR808").gain(0.2)|,
          bass: ~s|s("fs1*2, a1*2").sine().gain(0.25)|,
          string: ~s|s("fs2*2, a2*4").gain(0.1).saw(0.4).cutoff(0.45).lpf(0.35, 0.8, 0.12)|,
          arpeggio: ""
        },
        combat: %{
          pulse: ~s|s("bd2*2, hh8, sn*4").bank("RolandTR808").gain(0.3)|,
          bass: ~s|s("fs1*4, a1*4").sine().gain(0.3)|,
          string: ~s|s("fs2, a2, c3, fs2").gain(0.15).saw(0.4).cutoff(0.45).lpf(0.35, 0.8, 0.12)|,
          arpeggio:
            ~s|s("fs2*8, a2*4, c3*8, a2*4").gain(0.08).saw(0.4).cutoff(0.45).lpf(0.35, 0.8, 0.12)|
        }
      }
    }
  end

  @doc """
  The music cue for the current screen.

  Accepts both the old 3-argument form `(view, screen, match)` and the
  new 2-argument form `(view, screen)` where `screen` is `:title`, `:play`, etc.
  """
  @spec cue(term(), atom(), term() | nil) :: map() | nil
  def cue(_view, :title, _match), do: nil
  def cue(_view, :lobby, _match), do: nil
  def cue(_view, :summary, _match), do: nil
  def cue(_view, :guide, _match), do: nil

  def cue(view, :play, match) do
    piece =
      case Map.get(view, :menu, :play) do
        :title -> "menu"
        :menu -> "menu"
        _ -> "match"
      end

    case match do
      nil -> %{piece: piece, section: :idle, layers: %{}}
      %{winner: nil} -> %{piece: piece, section: :neutral, layers: %{}}
      %{winner: _} -> %{piece: piece, section: :tension, layers: %{}}
    end
  end

  def cue(_view, :title), do: nil
  def cue(_view, :lobby), do: nil
  def cue(_view, :summary), do: nil
  def cue(_view, :guide), do: nil

  # 2-argument: view has :menu key telling us what we're showing
  def cue(%{menu: :title}, _screen), do: nil

  def cue(%{menu: :menu}, :play) do
    %{piece: "menu", section: :idle, layers: %{}}
  end

  def cue(%{menu: :play}, :play) do
    %{piece: "match", section: :neutral, layers: %{}}
  end

  @doc "Whether `match` has active combat (someone attacking or parrying)."
  @spec combat?(term()) :: boolean()
  def combat?(%{advancing: adv, swords: swords})
      when not is_nil(adv) and length(swords) > 0,
      do: true

  def combat?(_match), do: false
end
