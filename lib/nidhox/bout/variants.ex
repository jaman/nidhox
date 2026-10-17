defmodule Nidhox.Bout.Variants do
  @moduledoc """
  Which of the game's variants are on, as its code asks: a variant counts only while
  variants are active — `System.flow` is 4 (versus) or 3 (tournament) — and its switch
  on `System` is set (`variantsActive`, `lowGravityEnabled`, `throwsOnlyEnabled`,
  `babyModeEnabled`, `skippyModeEnabled`, `suddenDeathOnlyEnabled`, `turboModeEnabled`,
  `slowModeEnabled`). Turbo and slow mode count only while a `Match` exists. Sudden death
  only also counts in the CPU battle flow (62831853).

  `match_time_limit/1` is `matchTimeLimit` and `reset/1` is `variantsReset`.
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.Gml
  alias Nidhox.Objects.System
  alias Nidhox.Rules

  @cpu_battle_flow 62_831_853

  @doc "Whether variants count in the current flow (`variantsActive`)."
  @spec active?(World.t()) :: boolean()
  def active?(%World{} = world), do: System.get(world, :flow) in [3, 4]

  @doc "Whether low gravity is on (`lowGravityEnabled`)."
  @spec low_gravity?(World.t()) :: boolean()
  def low_gravity?(world), do: on?(world, :lowGravity)

  @doc "Whether only throws may be used (`throwsOnlyEnabled`)."
  @spec throws_only?(World.t()) :: boolean()
  def throws_only?(world), do: on?(world, :throwsOnly)

  @doc "Whether baby mode is on (`babyModeEnabled`)."
  @spec baby_mode?(World.t()) :: boolean()
  def baby_mode?(world), do: on?(world, :babyMode)

  @doc "Whether skippy mode is on (`skippyModeEnabled`)."
  @spec skippy_mode?(World.t()) :: boolean()
  def skippy_mode?(world), do: on?(world, :skippyMode)

  @doc "Whether matches are fought in sudden death only (`suddenDeathOnlyEnabled`)."
  @spec sudden_death_only?(World.t()) :: boolean()
  def sudden_death_only?(world),
    do:
      (active?(world) or System.get(world, :flow) == @cpu_battle_flow) and
        Gml.truthy?(System.get(world, :suddenDeathOnly))

  @doc "Whether two match frames run each step (`turboModeEnabled`)."
  @spec turbo?(World.t()) :: boolean()
  def turbo?(world), do: on?(world, :turboMode) and Gml.exists?(world, "Match")

  @doc "Whether match frames run only every other step (`slowModeEnabled`)."
  @spec slow?(World.t()) :: boolean()
  def slow?(world), do: on?(world, :slowMode) and Gml.exists?(world, "Match")

  @doc """
  The match's time limit in frames (`matchTimeLimit`): `System.time_limit` while variants
  are active or in the CPU battle flow, else 0 for no limit.
  """
  @spec match_time_limit(World.t()) :: number()
  def match_time_limit(%World{} = world) do
    if active?(world) or System.get(world, :flow) == @cpu_battle_flow,
      do: System.get(world, :time_limit),
      else: 0
  end

  @doc "The world with every variant switch and the time limit back at their start values (`variantsReset`)."
  @spec reset(World.t()) :: World.t()
  def reset(%World{} = world), do: System.put(world, Rules.system(%Rules{}))

  defp on?(world, switch), do: active?(world) and Gml.truthy?(System.get(world, switch))
end
