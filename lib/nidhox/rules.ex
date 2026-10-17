defmodule Nidhox.Rules do
  @moduledoc """
  How a match is played, as the game's VARIANTS menu sets it: a time limit and every
  variant switch of `System`, each on or off on its own.

  | entry | label | `System` |
  | --- | --- | --- |
  | `:time_limit` | TIME LIMIT | `time_limit` |
  | `:divekicks` | DIVEKICKS | `divekicks`, on to start with |
  | `:throws` | THROWS | `throws`, on to start with |
  | `:noSwords` | NO SWORDS | `noSwords` |
  | `:throwsOnly` | THROWS ONLY | `throwsOnly` |
  | `:babyMode` | BABY MODE | `babyMode` |
  | `:lowGravity` | LOW GRAVITY | `lowGravity` |
  | `:suddenDeathOnly` | SUDDEN DEATH ONLY | `suddenDeathOnly` |
  | `:skippyMode` | SKIPPY MODE | `skippyMode` |
  | `:turboMode` | TURBO MODE | `turboMode` |
  | `:slowMode` | SLOW MODE | `slowMode` |
  | `:spineSwords` | SPINE SWORDS | `spineSwords` |
  | `:boomerangSwords` | BOOMERANG SWORDS | `boomerangSwords` |
  | `:trails` | TRAILS | `trails` |

  Choosing a switch turns it on or off. Choosing TIME LIMIT adds 1800 frames (30
  seconds) to it, back to none past 36000, and any limit is at least 10800 (3 minutes):
  none, 3:00, 3:30 … 9:30. Moving it the other way (`step_time_limit/2`) takes 1800 off,
  to none from 10800 and to 9:30 from none. The match counts the limit down in frames and
  goes into sudden death when it runs out.
  """

  @entries [
    time_limit: "TIME LIMIT",
    divekicks: "DIVEKICKS",
    throws: "THROWS",
    noSwords: "NO SWORDS",
    throwsOnly: "THROWS ONLY",
    babyMode: "BABY MODE",
    lowGravity: "LOW GRAVITY",
    suddenDeathOnly: "SUDDEN DEATH ONLY",
    skippyMode: "SKIPPY MODE",
    turboMode: "TURBO MODE",
    slowMode: "SLOW MODE",
    spineSwords: "SPINE SWORDS",
    boomerangSwords: "BOOMERANG SWORDS",
    trails: "TRAILS"
  ]
  @switches @entries |> Keyword.delete(:time_limit) |> Keyword.keys()
  @on_at_start [:divekicks, :throws]
  @limit_step 1800
  @limit_wrap 36_000
  @shortest_limit 10_800

  defstruct switches: Map.new(@switches, &{&1, if(&1 in @on_at_start, do: 1, else: 0)}),
            time_limit: 0

  @type entry :: :time_limit | atom()
  @type t :: %__MODULE__{switches: %{atom() => 0 | 1}, time_limit: non_neg_integer()}

  @doc "`rules` after `entry` is chosen: a switch turned over, or the time limit moved on."
  @spec choose(t(), entry()) :: t()
  def choose(%__MODULE__{time_limit: limit} = rules, :time_limit),
    do: %{rules | time_limit: step_time_limit(limit, 1)}

  def choose(%__MODULE__{switches: switches} = rules, switch) when is_map_key(switches, switch),
    do: %{rules | switches: Map.update!(switches, switch, &(1 - &1))}

  @doc "`rules` with each of `entries` back as the rules start: the switches on or off as at first, no time limit."
  @spec reset(t(), [entry()]) :: t()
  def reset(%__MODULE__{} = rules, entries) do
    initial = %__MODULE__{}

    Enum.reduce(entries, rules, fn
      :time_limit, rules ->
        %{rules | time_limit: 0}

      switch, rules when is_map_key(initial.switches, switch) ->
        %{rules | switches: Map.put(rules.switches, switch, initial.switches[switch])}

      _other, rules ->
        rules
    end)
  end

  @doc "Whether `entry` is on in `rules`; the time limit is on when set."
  @spec on?(t(), entry()) :: boolean()
  def on?(%__MODULE__{time_limit: limit}, :time_limit), do: limit > 0
  def on?(%__MODULE__{switches: switches}, switch), do: Map.get(switches, switch) == 1

  @doc """
  The time limit after one step from `limit` (`stepTimeLimit`): forward when `direction`
  is above 0, back otherwise.
  """
  @spec step_time_limit(non_neg_integer(), number()) :: non_neg_integer()
  def step_time_limit(limit, direction) when direction > 0 do
    stepped = rem(limit + @limit_step, @limit_wrap)
    if stepped > 0, do: max(@shortest_limit, stepped), else: 0
  end

  def step_time_limit(0, _direction), do: @limit_wrap - @limit_step
  def step_time_limit(limit, _direction) when limit <= @shortest_limit, do: 0
  def step_time_limit(limit, _direction), do: limit - @limit_step

  @doc "`System`'s settings for a match under `rules`: every switch and `time_limit` in frames."
  @spec system(t()) :: map()
  def system(%__MODULE__{switches: switches, time_limit: limit}),
    do: Map.put(switches, :time_limit, limit)
end
