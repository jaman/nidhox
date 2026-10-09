defmodule Nidhox.Rules do
  @moduledoc """
  How a match is played, as chosen on the level select: its variant and its time limit.

  | variant | label | `System` switch |
  | --- | --- | --- |
  | `:none` | NONE | — |
  | `:no_swords` | NO SWORDS | `noSwords` |
  | `:throws_only` | THROWS ONLY | `throwsOnly` |
  | `:sudden_death_only` | SUDDEN DEATH ONLY | `suddenDeathOnly` |
  | `:low_gravity` | LOW GRAVITY | `lowGravity` |
  | `:turbo` | TURBO MODE | `turboMode` |
  | `:slow` | SLOW MODE | `slowMode` |
  | `:boomerang` | BOOMERANG SWORDS | `boomerangSwords` |

  A time limit is in minutes, `nil` for none; the match counts it down in frames
  (`System.time_limit`) and goes into sudden death when it runs out.
  """

  defstruct variant: :none, minutes: nil

  @type variant ::
          :none
          | :no_swords
          | :throws_only
          | :sudden_death_only
          | :low_gravity
          | :turbo
          | :slow
          | :boomerang
  @type t :: %__MODULE__{variant: variant(), minutes: pos_integer() | nil}

  @variants [
    none: "NONE",
    no_swords: "NO SWORDS",
    throws_only: "THROWS ONLY",
    sudden_death_only: "SUDDEN DEATH ONLY",
    low_gravity: "LOW GRAVITY",
    turbo: "TURBO MODE",
    slow: "SLOW MODE",
    boomerang: "BOOMERANG SWORDS"
  ]
  @switches %{
    no_swords: :noSwords,
    throws_only: :throwsOnly,
    sudden_death_only: :suddenDeathOnly,
    low_gravity: :lowGravity,
    turbo: :turboMode,
    slow: :slowMode,
    boomerang: :boomerangSwords
  }
  @limits [nil, 1, 2, 3, 5]
  @hz 60

  @doc "Every variant with its label, in the order the level select offers them."
  @spec variants() :: [{variant(), String.t()}]
  def variants, do: @variants

  @doc "Every time limit, in minutes, `nil` for none, in the order the level select offers them."
  @spec limits() :: [pos_integer() | nil]
  def limits, do: @limits

  @doc """
  `System`'s settings for a match under `rules`: `time_limit` in frames (0 for none), and
  every variant switch, 1 for the variant chosen and 0 for the rest.
  """
  @spec system(t()) :: map()
  def system(%__MODULE__{variant: variant, minutes: minutes}) do
    @switches
    |> Map.new(fn {name, switch} -> {switch, if(name == variant, do: 1, else: 0)} end)
    |> Map.put(:time_limit, if(minutes, do: minutes * 60 * @hz, else: 0))
  end
end
