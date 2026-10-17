defmodule Nidhox.Matchmaking do
  @moduledoc """
  The game's rules for choosing an opponent's lobby to join while searching
  (`mtmkPick`, `mtmkRank`), and its list of declined opponents (`netDeclineAdd`,
  `netDeclinedAt`, `netDeclinedClear`).

  A candidate is a lobby that is open and has a free place, as a map:

    * `:owner` — the owner's id, an integer
    * `:ping` — the round trip to it in milliseconds, or `nil` when unknown
    * `:region` — `"1"` when its owner searches only their own region, else `"0"`
    * `:anyping` — whether its owner has searched for 10 seconds and takes far
      opponents

  `pick/2` gives the candidate to join, or `nil` to host and wait. Times are in
  milliseconds of one clock.

      Nidhox.Matchmaking.pick(candidates, %{now: now, since: started, declined: declined,
        global?: false, hosting: nil})
  """

  @near_ms 200
  @far_wait_ms 10_000
  @skip_ms 30_000
  @forget_ms 600_000

  @type candidate :: %{
          owner: integer(),
          ping: number() | nil,
          region: String.t(),
          anyping: boolean()
        }

  @type declined :: [%{id: integer(), at: integer()}]

  @type search :: %{
          now: integer(),
          since: integer(),
          declined: declined(),
          global?: boolean(),
          hosting: integer() | nil
        }

  @doc """
  The candidate to join from `candidates`, or `nil`, with the declined list pruned of
  entries 10 minutes old.

  `search` gives the time now, when the search started, the declined list, whether the
  player searches beyond their region (`global?`), and this player's own lobby id when
  they host one (`hosting`). Opponents declined in the last 30 seconds are skipped; one
  declined before that is joined only when no other candidate qualifies. A host does
  not join a lobby whose id is above its own, so that of two hosts only one joins the
  other.
  """
  @spec pick([candidate()], search()) :: {candidate() | nil, declined()}
  def pick(candidates, search) do
    declined = Enum.reject(search.declined, &(search.now - &1.at >= @forget_ms))
    waited = search.now - search.since

    {fresh, old} =
      Enum.reduce(candidates, {[], []}, fn candidate, {fresh, old} ->
        case declined_at(declined, candidate.owner) do
          nil -> {[candidate | fresh], old}
          at when search.now - at >= @skip_ms -> {fresh, [candidate | old]}
          _recent -> {fresh, old}
        end
      end)

    pick =
      rank(Enum.reverse(fresh), waited, search.global?) ||
        rank(Enum.reverse(old), waited, search.global?)

    {yielded(pick, search.hosting), declined}
  end

  defp yielded(%{owner: owner}, hosting) when is_integer(hosting) and owner > hosting, do: nil
  defp yielded(pick, _hosting), do: pick

  defp rank(candidates, waited, global?) do
    {near, far, unknown} =
      Enum.reduce(candidates, {nil, nil, []}, fn candidate, {near, far, unknown} ->
        case candidate.ping do
          nil -> {near, far, [candidate | unknown]}
          ping when ping <= @near_ms -> {lower(near, candidate), far, unknown}
          _far -> {near, far_pick(far, candidate, waited, global?), unknown}
        end
      end)

    near || random(Enum.reverse(unknown)) || far
  end

  defp lower(nil, candidate), do: candidate
  defp lower(best, candidate) when candidate.ping < best.ping, do: candidate
  defp lower(best, _candidate), do: best

  defp far_pick(far, _candidate, _waited, false), do: far
  defp far_pick(far, %{region: "1"}, _waited, true), do: far

  defp far_pick(far, %{anyping: false}, waited, true) when waited < @far_wait_ms,
    do: far

  defp far_pick(far, candidate, _waited, true), do: lower(far, candidate)

  defp random([]), do: nil
  defp random(unknown), do: Enum.random(unknown)

  @doc """
  `declined` with opponent `id` declined at `now`. Nothing is added for `nil`, or while
  the player plays through an invite (`invited?`).
  """
  @spec decline(declined(), integer() | nil, integer(), boolean()) :: declined()
  def decline(declined, nil, _now, _invited?), do: declined
  def decline(declined, _id, _now, true), do: declined

  def decline(declined, id, now, false) do
    if Enum.any?(declined, &(&1.id == id)),
      do: Enum.map(declined, &if(&1.id == id, do: %{&1 | at: now}, else: &1)),
      else: declined ++ [%{id: id, at: now}]
  end

  @doc "When opponent `id` was last declined, or `nil`."
  @spec declined_at(declined(), integer()) :: integer() | nil
  def declined_at(declined, id) do
    declined
    |> Enum.reverse()
    |> Enum.find_value(fn entry -> if entry.id == id, do: entry.at end)
  end

  @doc "The colour the game shows a ping in: green to 50 ms, orange to 100 ms, red above."
  @spec ping_colour(number()) :: {0..255, 0..255, 0..255}
  def ping_colour(ping) when ping > 100, do: {255, 64, 64}
  def ping_colour(ping) when ping > 50, do: {255, 208, 64}
  def ping_colour(_ping), do: {128, 255, 64}
end
