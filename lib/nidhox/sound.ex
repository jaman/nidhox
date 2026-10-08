defmodule Nidhox.Sound do
  @moduledoc """
  Sound effect definitions for NidhOX.

  Each effect is defined as a `TuningFork.GM` specification: a drum kit
  with notes, effects, and volumes. The client's `sounds/0` returns a
  function that maps effect names to these specs.

  Effects:
  - `:clash` — sword vs sword ring (metallic percussion)
  - `:kill` — death scream (noise burst)
  - `:footstep` — footstep thump (filtered noise)
  - `:pickup` — sword pickup (short tonal chirp)
  """

  alias TuningFork.GM

  @doc "Sound effects for NidhOX, mapped by name."
  @spec effects() :: %{atom() => GM.spec()}
  def effects do
    %{
      clash: clash(),
      kill: kill(),
      footstep: footstep(),
      pickup: pickup()
    }
  end

  # Sword vs sword metallic ring — tuned percussion.
  defp clash do
    [
      kit: kit(),
      channels: %{
        1 => [
          [note: "B5", amp: 0.6, pan: 0.0],
          [note: "D6", amp: 0.3, pan: 0.0]
        ]
      }
    ]
  end

  # Death scream — noise burst for impact.
  defp kill do
    [
      kit: kit(),
      channels: %{
        1 => [
          [note: "B1", amp: 0.5, pan: 0.0, length: 0.3]
        ],
        2 => [
          [note: "B4", amp: 0.15, length: 0.15, effect: [reverb: 0.3]]
        ]
      }
    ]
  end

  # Footstep — low thump, filtered.
  defp footstep do
    [
      kit: kit(),
      channels: %{
        1 => [
          [note: "B0", amp: 0.25, pan: 0.0]
        ]
      }
    ]
  end

  # Pickup — short tonal chirp.
  defp pickup do
    [
      kit: kit(),
      channels: %{
        1 => [
          [note: "E5", amp: 0.2, pan: 0.0, length: 0.08]
        ]
      }
    ]
  end

  # Standard drum kit.
  defp kit do
    [
      master: [reverb: 0.1],
      drums: [
        [id: 1, note: "B3", amp: 0.8, pan: 0.0],
        [id: 2, note: "B2", amp: 0.5, pan: 0.0],
        [id: 3, note: "B1", amp: 0.4, pan: 0.0],
        [id: 4, note: "C#4", amp: 0.3, pan: 0.0],
        [id: 5, note: "D5", amp: 0.2, pan: 0.0],
        [id: 6, note: "B4", amp: 0.15, pan: 0.0]
      ]
    ]
  end
end
