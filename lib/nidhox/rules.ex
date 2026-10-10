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
  none, 3:00, 3:30 … 9:30. The match counts the limit down in frames and goes into
  sudden death when it runs out.
  """

  alias Nidhox.Objects.Match

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
  @limit_wrap 36000
  @shortest_limit 10800

  defstruct switches: Map.new(@switches, &{&1, if(&1 in @on_at_start, do: 1, else: 0)}),
            time_limit: 0

  @type entry :: :time_limit | atom()
  @type t :: %__MODULE__{switches: %{atom() => 0 | 1}, time_limit: non_neg_integer()}

  @doc "Every entry of the VARIANTS menu, in its order."
  @spec entries() :: [entry()]
  def entries, do: Keyword.keys(@entries)

  @doc "`rules` after `entry` is chosen: a switch turned over, or the time limit moved on."
  @spec choose(t(), entry()) :: t()
  def choose(%__MODULE__{time_limit: limit} = rules, :time_limit) do
    stepped = rem(limit + @limit_step, @limit_wrap)
    %{rules | time_limit: if(stepped > 0, do: max(@shortest_limit, stepped), else: 0)}
  end

  def choose(%__MODULE__{switches: switches} = rules, switch) when is_map_key(switches, switch),
    do: %{rules | switches: Map.update!(switches, switch, &(1 - &1))}

  @doc "`entry`'s line on the menu: its label and its value, `ON`, `OFF`, a time or `NONE`."
  @spec label(t(), entry()) :: String.t()
  def label(%__MODULE__{time_limit: 0}, :time_limit), do: "TIME LIMIT NONE"
  def label(%__MODULE__{time_limit: limit}, :time_limit), do: "TIME LIMIT " <> Match.time(limit)

  def label(%__MODULE__{switches: switches}, switch),
    do: Keyword.fetch!(@entries, switch) <> if(switches[switch] == 1, do: " ON", else: " OFF")

  @doc "`System`'s settings for a match under `rules`: every switch and `time_limit` in frames."
  @spec system(t()) :: map()
  def system(%__MODULE__{switches: switches, time_limit: limit}),
    do: Map.put(switches, :time_limit, limit)
end
