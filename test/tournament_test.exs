defmodule Nidhox.TournamentTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.GameMaker.{Random, World}
  alias Nidhox.Tournament

  test "byes fill every other first-round slot from the last, and lose once their match comes up" do
    for seed <- 1..50 do
      {tournament, _world} = Tournament.new(5, world(seed))
      [first, second | _] = tournament.rounds

      assert Enum.map([3, 5, 7], &Enum.at(first, &1)) |> Enum.sort() == [5, 6, 7]
      assert first |> Enum.reject(&(&1 in 5..7)) |> Enum.sort() == Enum.to_list(0..4)
      assert second == [-1, -1, -1, -1]
      assert tournament.playing == {Enum.at(first, 0), Enum.at(first, 1)}

      tournament = Tournament.won(tournament, Enum.at(first, 1))
      assert hd(tl(tournament.rounds)) == Enum.map([1, 2, 4, 6], &Enum.at(first, &1))
      assert tournament.playing == {Enum.at(first, 1), Enum.at(first, 2)}
    end
  end

  test "winners move up a round in turn until the last round holds the champion" do
    {tournament, _world} = Tournament.new(4, world(3))
    [[a, b, c, d] | _] = tournament.rounds

    tournament = Tournament.won(tournament, b)
    assert tournament.playing == {c, d}
    assert Enum.at(tournament.rounds, 1) == [b, -1]

    tournament = Tournament.won(tournament, c)
    assert tournament.playing == {b, c}
    assert Tournament.champion(tournament) == nil

    tournament = Tournament.won(tournament, c)
    assert Tournament.champion(tournament) == c
    assert tournament.rounds == [[a, b, c, d], [b, c], [c]]
  end

  test "every match of a tournament of eight is played, seven in all" do
    {tournament, _world} = Tournament.new(8, world(9))
    {finished, played} = play_first_wins(tournament, 0)

    assert played == 7
    assert Tournament.champion(finished) == hd(hd(tournament.rounds))
  end

  defp play_first_wins(tournament, played) do
    case Tournament.champion(tournament) do
      nil -> play_first_wins(Tournament.won(tournament, elem(tournament.playing, 0)), played + 1)
      _champion -> {tournament, played}
    end
  end

  defp world(seed),
    do: %World{
      data: nil,
      code: nil,
      objects: %{},
      sprites: %{},
      owners: %{},
      descendants: %{},
      random: Random.new(seed)
    }
end
