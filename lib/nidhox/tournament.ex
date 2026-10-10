defmodule Nidhox.Tournament do
  @moduledoc """
  A single elimination tournament, as the game's `Tournament` keeps one
  (`tournamentInitPlayers`, `tournament_match_winner`, `byesLoseMatch`).

  Players are numbered from 0; the game shows player `n` as `n + 1` in its colour
  `getPlayerColor(n + 1)`. The bracket is a list of rounds (`bracketHistory`): the first
  as wide as the smallest power of two that holds every player, each next one half as
  wide, the last one wide. A round's slot is a player, or −1 while its match is
  undecided. The places a power of two leaves over are byes, numbered after the
  players.

    * the first round: the players and the byes each shuffled, then filled from its last
      slot back — every other slot from the last a bye while byes remain, every other
      slot a player
    * the match being played (`currentPlayer`): slots `position` and `position + 1` of
      round `round` (`currentBracket`, `bracketPosition`), from the first round's first
      two
    * a won match puts its winner in the next round, in the slot half its own (rounded
      down); while that round still has an undecided slot after its first, the match
      after is the next two of this round, else the first two of the next round
    * a match against a bye is won at once by the player facing it

  The champion is the last round's player.

      {tournament, world} = Tournament.new(4, world)
      {first, _second} = tournament.playing
      tournament = Tournament.won(tournament, first)
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.Gml

  @enforce_keys [:rounds, :byes, :playing]
  defstruct [:rounds, :byes, :playing, round: 0, position: 0]

  @undecided -1

  @type player :: non_neg_integer()
  @type slot :: player() | -1
  @type t :: %__MODULE__{
          rounds: [[slot()], ...],
          byes: [player()],
          playing: {slot() | nil, slot() | nil},
          round: non_neg_integer(),
          position: non_neg_integer()
        }

  @doc """
  A tournament between players `0..count - 1`, the first match set and any match
  against a bye won, with the shuffles drawn from `world`'s random numbers; also the
  world after the draws.
  """
  @spec new(pos_integer(), World.t()) :: {t(), World.t()}
  def new(count, %World{} = world) when count > 1 do
    size = width(count)
    {byes, world} = shuffle(Enum.to_list((size - 1)..count//-1), world)
    {players, world} = shuffle(Enum.to_list(0..(count - 1)), world)

    first = seeded(size, byes, players)
    later = Stream.iterate(div(size, 2), &div(&1, 2)) |> Enum.take_while(&(&1 >= 1))

    tournament = %__MODULE__{
      rounds: [first | Enum.map(later, &List.duplicate(@undecided, &1))],
      byes: byes,
      playing: pair(first, 0)
    }

    {byes_lose(tournament), world}
  end

  @doc "The tournament after `winner`, one of the two playing, won the match."
  @spec won(t(), player()) :: t()
  def won(%__MODULE__{} = tournament, winner) do
    current = Enum.at(tournament.rounds, tournament.round)

    case {champion(tournament), Enum.find_index(current, &(&1 == winner))} do
      {nil, index} when is_integer(index) -> tournament |> advanced(winner, index) |> byes_lose()
      _decided -> tournament
    end
  end

  @doc "The champion, or `nil` until the last match is won."
  @spec champion(t()) :: player() | nil
  def champion(%__MODULE__{rounds: rounds}) do
    case List.last(rounds) do
      [@undecided] -> nil
      [champion] -> champion
    end
  end

  @doc "Whether `player` is a bye."
  @spec bye?(t(), slot() | nil) :: boolean()
  def bye?(%__MODULE__{byes: byes}, player), do: player in byes

  @doc "The round after round `round`, the first after the last (`ds_list_next_value`)."
  @spec next_round(t(), non_neg_integer()) :: non_neg_integer()
  def next_round(%__MODULE__{rounds: rounds}, round), do: rem(round + 1, length(rounds))

  defp width(count), do: Stream.iterate(1, &(&1 * 2)) |> Enum.find(&(&1 >= count))

  defp seeded(size, byes, players) do
    {slots, _left} =
      Enum.map_reduce(0..(size - 1), {byes, players}, fn
        from_end, {[bye | byes], players} when rem(from_end, 2) == 0 -> {bye, {byes, players}}
        _from_end, {byes, [player | players]} -> {player, {byes, players}}
      end)

    Enum.reverse(slots)
  end

  defp advanced(tournament, winner, index) do
    next = next_round(tournament, tournament.round)
    rounds = List.update_at(tournament.rounds, next, &List.replace_at(&1, div(index, 2), winner))
    tournament = %{tournament | rounds: rounds}

    tournament =
      if Gml.truthy?(first_undecided(Enum.at(rounds, next))),
        do: %{tournament | position: tournament.position + 2},
        else: %{tournament | round: next, position: 0}

    %{tournament | playing: pair(Enum.at(rounds, tournament.round), tournament.position)}
  end

  defp byes_lose(%__MODULE__{playing: {first, second}} = tournament) do
    next = Enum.at(tournament.rounds, next_round(tournament, tournament.round))
    {first_through?, second_through?} = {first in next, second in next}

    tournament =
      if not first_through? and bye?(tournament, first), do: won(tournament, second), else: tournament

    if not second_through? and bye?(tournament, second), do: won(tournament, first), else: tournament
  end

  defp first_undecided(round), do: Enum.find_index(round, &(&1 == @undecided)) || @undecided

  defp pair(round, position), do: {Enum.at(round, position), Enum.at(round, position + 1)}

  defp shuffle(list, world) do
    {shuffled, world} =
      (length(list) - 1)..1//-1
      |> Enum.reduce({List.to_tuple(list), world}, fn last, {slots, world} ->
        {other, world} = Gml.irandom(world, last)
        {slots |> put_elem(last, elem(slots, other)) |> put_elem(other, elem(slots, last)), world}
      end)

    {Tuple.to_list(shuffled), world}
  end
end
