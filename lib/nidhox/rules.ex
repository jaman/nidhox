defmodule Nidhox.Rules do
  @moduledoc """
  How a bout is played: its variant, chosen on the level select, its time limit, and
  whether it is in sudden death.

  | variant | label | what changes |
  | --- | --- | --- |
  | `:none` | NONE | nothing |
  | `:no_swords` | NO SWORDS | fencers fight and come back unarmed |
  | `:divekick_only` | DIVEKICK ONLY | unarmed, and a divekick kills |
  | `:throws_only` | THROWS ONLY | a thrust does not kill; a thrown sword does |
  | `:sudden_death_only` | SUDDEN DEATH ONLY | the bout is fought in the area's sudden death room |
  | `:low_gravity` | LOW GRAVITY | fencers fall at `@low_gravity` of their weight |
  | `:turbo` | TURBO MODE | the bout runs `@turbo` steps for each |
  | `:slow` | SLOW MODE | the bout runs one step in every `@slow` |
  | `:boomerang` | BOOMERANG SWORDS | a thrown sword turns back to its thrower once its flight is spent |

  A time limit is in minutes, `nil` for none; once it runs out with nobody having won,
  the bout goes on in the area's sudden death room, where the first kill wins
  (`sudden_death`).
  """

  defstruct variant: :none, minutes: nil, sudden_death: false

  @type variant ::
          :none
          | :no_swords
          | :divekick_only
          | :throws_only
          | :sudden_death_only
          | :low_gravity
          | :turbo
          | :slow
          | :boomerang
  @type t :: %__MODULE__{
          variant: variant(),
          minutes: pos_integer() | nil,
          sudden_death: boolean()
        }

  @variants [
    none: "NONE",
    no_swords: "NO SWORDS",
    divekick_only: "DIVEKICK ONLY",
    throws_only: "THROWS ONLY",
    sudden_death_only: "SUDDEN DEATH ONLY",
    low_gravity: "LOW GRAVITY",
    turbo: "TURBO MODE",
    slow: "SLOW MODE",
    boomerang: "BOOMERANG SWORDS"
  ]
  @limits [nil, 1, 2, 3, 5]
  @low_gravity 0.5
  @turbo 2
  @slow 2
  @hz 60

  @doc "Every variant with its label, in the order the level select offers them."
  @spec variants() :: [{variant(), String.t()}]
  def variants, do: @variants

  @doc "Every time limit, in minutes, `nil` for none, in the order the level select offers them."
  @spec limits() :: [pos_integer() | nil]
  def limits, do: @limits

  @doc "Whether fencers start and come back with swords in hand."
  @spec armed?(t()) :: boolean()
  def armed?(%__MODULE__{variant: variant}), do: variant not in [:no_swords, :divekick_only]

  @doc "How much of their weight fencers fall with."
  @spec gravity(t()) :: number()
  def gravity(%__MODULE__{variant: :low_gravity}), do: @low_gravity
  def gravity(%__MODULE__{}), do: 1.0

  @doc "Whether a thrust that reaches a body kills."
  @spec thrusts_kill?(t()) :: boolean()
  def thrusts_kill?(%__MODULE__{variant: variant}), do: variant != :throws_only

  @doc "Whether a divekick that lands kills, rather than knocking down."
  @spec kicks_kill?(t()) :: boolean()
  def kicks_kill?(%__MODULE__{variant: variant}), do: variant == :divekick_only

  @doc "Whether a thrown sword turns back to its thrower."
  @spec boomerang?(t()) :: boolean()
  def boomerang?(%__MODULE__{variant: variant}), do: variant == :boomerang

  @doc "Whether the bout starts in the area's sudden death room."
  @spec sudden_death_only?(t()) :: boolean()
  def sudden_death_only?(%__MODULE__{variant: variant}), do: variant == :sudden_death_only

  @doc "How many bout steps run on game step number `step`: two in turbo, one in every second in slow, else one."
  @spec steps(t(), non_neg_integer()) :: non_neg_integer()
  def steps(%__MODULE__{variant: :turbo}, _step), do: @turbo
  def steps(%__MODULE__{variant: :slow}, step), do: if(rem(step, @slow) == 0, do: 1, else: 0)
  def steps(%__MODULE__{}, _step), do: 1

  @doc "The steps after which time runs out, `nil` for no limit."
  @spec limit_steps(t()) :: pos_integer() | nil
  def limit_steps(%__MODULE__{minutes: nil}), do: nil
  def limit_steps(%__MODULE__{minutes: minutes}), do: minutes * 60 * @hz
end
