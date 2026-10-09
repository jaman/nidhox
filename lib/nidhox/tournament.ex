defmodule Nidhox.Tournament do
  @moduledoc """
  A double elimination tournament between players numbered `1..count`.

  Players start unbeaten. A loss moves an unbeaten player to the losers' bracket, and a
  second loss puts them out. Rounds alternate between the winners' bracket (the unbeaten
  players) and the losers' bracket (those beaten once), skipping a bracket with fewer
  than two players. Each round pairs its bracket's players in order; with an odd number,
  the last waits the round out and is put first for the next. Once only two players are
  left, they play the final; when the unbeaten one loses it, both have lost once and
  they play the final again. The player left last is the champion.

      tournament = Tournament.new(4)
      {1, 2} = Tournament.next(tournament)
      tournament = Tournament.won(tournament, 1)
  """

  @enforce_keys [:count]
  defstruct [
    :count,
    unbeaten: [],
    beaten: [],
    out: [],
    bracket: :winners,
    rounds: %{winners: 0, losers: 0, final: 0},
    pending: [],
    waiting: [],
    played: [],
    champion: nil
  ]

  @type player :: pos_integer()
  @type bracket :: :winners | :losers | :final
  @type match :: %{
          bracket: bracket(),
          round: pos_integer(),
          players: {player(), player()},
          winner: player()
        }
  @type t :: %__MODULE__{
          count: 3..8,
          unbeaten: [player()],
          beaten: [player()],
          out: [player()],
          bracket: bracket(),
          rounds: %{bracket() => non_neg_integer()},
          pending: [{player(), player()}],
          waiting: [player()],
          played: [match()],
          champion: player() | nil
        }

  @fewest 3
  @most 8

  @doc "The fewest players a tournament takes."
  @spec fewest() :: pos_integer()
  def fewest, do: @fewest

  @doc "The most players a tournament takes."
  @spec most() :: pos_integer()
  def most, do: @most

  @doc "A tournament between players `1..count`, its first round paired."
  @spec new(3..8) :: t()
  def new(count) when count in @fewest..@most,
    do: plan(%__MODULE__{count: count, unbeaten: Enum.to_list(1..count)}, :winners)

  @doc "The pair to play next, the first on side 1 (yellow), or `nil` once there is a champion."
  @spec next(t()) :: {player(), player()} | nil
  def next(%__MODULE__{pending: [match | _]}), do: match
  def next(%__MODULE__{pending: []}), do: nil

  @doc "Whether the next match is the final."
  @spec final?(t()) :: boolean()
  def final?(%__MODULE__{bracket: bracket}), do: bracket == :final

  @doc "The tournament after `winner` won the next match."
  @spec won(t(), player()) :: t()
  def won(%__MODULE__{pending: [{one, two} = pair | rest]} = tournament, winner)
      when winner in [one, two] do
    loser = if winner == one, do: two, else: one

    tournament
    |> record(pair, winner)
    |> beat(loser)
    |> Map.merge(%{pending: rest, waiting: tournament.waiting ++ [winner]})
    |> round_over()
  end

  @doc "The matches played in `bracket`, by round in order, each round's in order."
  @spec rounds(t(), bracket()) :: [[match()]]
  def rounds(%__MODULE__{played: played}, bracket) do
    played
    |> Enum.reverse()
    |> Enum.filter(&(&1.bracket == bracket))
    |> Enum.chunk_by(& &1.round)
  end

  defp record(tournament, players, winner) do
    match = %{
      bracket: tournament.bracket,
      round: tournament.rounds[tournament.bracket],
      players: players,
      winner: winner
    }

    %{tournament | played: [match | tournament.played]}
  end

  defp beat(%__MODULE__{unbeaten: unbeaten, beaten: beaten} = tournament, loser) do
    if loser in unbeaten,
      do: %{tournament | unbeaten: List.delete(unbeaten, loser), beaten: beaten ++ [loser]},
      else: %{tournament | beaten: List.delete(beaten, loser), out: [loser | tournament.out]}
  end

  defp round_over(%__MODULE__{pending: [_ | _]} = tournament), do: tournament

  defp round_over(%__MODULE__{bracket: bracket} = tournament) do
    tournament
    |> settle(bracket)
    |> plan(after_round(bracket))
  end

  defp settle(%__MODULE__{waiting: waiting} = tournament, :winners),
    do: %{tournament | unbeaten: Enum.filter(waiting, &(&1 in tournament.unbeaten)), waiting: []}

  defp settle(%__MODULE__{waiting: waiting} = tournament, :losers),
    do: %{tournament | beaten: Enum.filter(waiting, &(&1 in tournament.beaten)), waiting: []}

  defp settle(tournament, :final), do: %{tournament | waiting: []}

  defp after_round(:winners), do: :losers
  defp after_round(_bracket), do: :winners

  defp plan(%__MODULE__{unbeaten: unbeaten, beaten: beaten} = tournament, _bracket)
       when length(unbeaten) + length(beaten) == 1,
       do: %{tournament | pending: [], champion: hd(unbeaten ++ beaten)}

  defp plan(%__MODULE__{unbeaten: unbeaten, beaten: beaten} = tournament, _bracket)
       when length(unbeaten) + length(beaten) == 2,
       do: start(tournament, :final, [List.to_tuple(unbeaten ++ beaten)], [])

  defp plan(tournament, bracket) do
    players = players(tournament, bracket)

    if length(players) >= 2,
      do: pair(tournament, bracket, players),
      else: plan(tournament, after_round(bracket))
  end

  defp players(tournament, :winners), do: tournament.unbeaten
  defp players(tournament, :losers), do: tournament.beaten

  defp pair(tournament, bracket, players) do
    {paired, left} = Enum.split(players, length(players) - rem(length(players), 2))
    pairs = paired |> Enum.chunk_every(2) |> Enum.map(&List.to_tuple/1)
    start(tournament, bracket, pairs, left)
  end

  defp start(tournament, bracket, pairs, left),
    do: %{
      tournament
      | bracket: bracket,
        rounds: Map.update!(tournament.rounds, bracket, &(&1 + 1)),
        pending: pairs,
        waiting: left
    }
end
