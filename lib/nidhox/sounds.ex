defmodule Nidhox.Sounds do
  @moduledoc """
  The sound effects of the player's copy of the game, as `TuningFork` voices, and the
  sound each kind of NidhOX event makes.

  An event the client plays is `{:nidhox, kind, variant}`, placed or not; `voice/1`
  gives its voice, `nil` for an event it does not know or a sound the copy lacks. Each
  kind is a family of the copy's sounds, `variant` picking one of them:

  | kind | sounds |
  | --- | --- |
  | `:scream` | `sfxScream1`–`14` |
  | `:stab` | `sfxStab1`–`2` |
  | `:clash` | `sfxSwordOnSword1`–`3` |
  | `:disarm` | `sfxDisarm` |
  | `:thrust` | `sfxThrust1`–`2` |
  | `:throw` | `sfxThrowSword` |
  | `:sword_ground` | `sfxSwordHitGround1`–`4` |
  | `:pickup` | `sfxPickUpSword` |
  | `:jump` | `sfxJump1`–`2` |
  | `:land` | `sfxLand1`–`2` |
  | `:run_step` | `sfxRunStep1`–`7` |
  | `:walk_step` | `sfxFenceStep1`–`4` |
  | `:room` | `sfxChangeLevel1`–`9` |
  | `:start` | `sfxStartMatch` |
  | `:cheer` | `sfxCheer` |
  | `:roar` | `sfxNidhoggNyah` |
  | `:bite` | `sfxBite` |
  | `:slurp` | `sfxSlurp` |
  | `:divekick` | `sfxClothDivekick1` |
  | `:floored` | `sfxHandGround` |
  | `:heart` | `sfxTearOutHeart` |
  | `:blood` | `sfxBloodHiss` |

  A sound is decoded the first time it is asked for and kept; `warm/1` decodes them all
  ahead of play.
  """

  alias Nidhox.{Assets, Recordings}
  alias TuningFork.{Sample, Voice}

  @families %{
    scream: {"sfxScream", 14},
    stab: {"sfxStab", 2},
    clash: {"sfxSwordOnSword", 3},
    disarm: {"sfxDisarm", 0},
    thrust: {"sfxThrust", 2},
    throw: {"sfxThrowSword", 0},
    sword_ground: {"sfxSwordHitGround", 4},
    pickup: {"sfxPickUpSword", 0},
    jump: {"sfxJump", 2},
    land: {"sfxLand", 2},
    run_step: {"sfxRunStep", 7},
    walk_step: {"sfxFenceStep", 4},
    room: {"sfxChangeLevel", 9},
    start: {"sfxStartMatch", 0},
    cheer: {"sfxCheer", 0},
    roar: {"sfxNidhoggNyah", 0},
    bite: {"sfxBite", 0},
    slurp: {"sfxSlurp", 0},
    divekick: {"sfxClothDivekick1", 0},
    floored: {"sfxHandGround", 0},
    heart: {"sfxTearOutHeart", 0},
    blood: {"sfxBloodHiss", 0}
  }

  @doc """
  Decode and keep every sound of every family, and the recordings `names`, so none is
  decoded while the game plays. Run it in a process of its own; it takes as long as
  decoding the copy's sounds does.
  """
  @spec warm([String.t()]) :: :ok
  def warm(names) do
    families =
      for {stem, count} <- Map.values(@families),
          variant <- if(count == 0, do: [nil], else: 1..count),
          do: if(variant, do: "#{stem}#{variant}", else: stem)

    Enum.each(families ++ names, &named/1)
  end

  @doc "The kinds of event that make a sound."
  @spec kinds() :: [atom()]
  def kinds, do: Map.keys(@families)

  @doc "The event of `kind`, its variant picked by `seed` from the family's sounds."
  @spec event(atom(), non_neg_integer()) :: {:nidhox, atom(), non_neg_integer()}
  def event(kind, seed) do
    {_name, count} = Map.fetch!(@families, kind)
    {:nidhox, kind, if(count == 0, do: 0, else: rem(seed, count) + 1)}
  end

  @doc """
  The voice an event makes, `nil` for one that makes none: `event/2`'s events, and
  `{:recording, name}` for the copy's recording `name` itself.
  """
  @spec voice(term()) :: Voice.t() | nil
  def voice({:recording, name}) when is_binary(name), do: named(name)

  def voice({:nidhox, kind, variant}) when is_map_key(@families, kind) do
    {stem, _count} = @families[kind]
    named(if variant == 0, do: stem, else: "#{stem}#{variant}")
  end

  def voice(_event), do: nil

  @doc "The voice of the copy's recording called `name` (`Nidhox.Recordings`), `nil` when it has none."
  @spec named(String.t()) :: Voice.t() | nil
  def named(name) do
    key = {__MODULE__, name}

    case :persistent_term.get(key, :unread) do
      :unread ->
        voice = decode(name)
        :persistent_term.put(key, voice)
        voice

      voice ->
        voice
    end
  end

  defp decode(name) do
    with true <- Assets.loaded?(),
         {:ok, wave} <- Recordings.wave(name) do
      sample =
        Sample.from_pcm(wave.pcm,
          rate: wave.rate,
          channels: wave.channels,
          root: 440.0,
          name: name
        )

      Voice.new(sample: sample, freq: 440.0, gain: 0.8)
    else
      _missing -> nil
    end
  end
end
