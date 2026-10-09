defmodule Nidhox.TournamentTest do
  use ExUnit.Case, async: true

  alias Nidhox.Tournament

  test "every player but the champion is put out by exactly two losses" do
    for count <- 3..8, seed <- 1..200 do
      :rand.seed(:exsss, {count, seed, 7})
      tournament = play(Tournament.new(count))

      losses =
        Enum.frequencies(
          for %{players: {a, b}, winner: w} <- tournament.played, do: if(w == a, do: b, else: a)
        )

      assert tournament.champion in 1..count
      assert Map.get(losses, tournament.champion, 0) <= 1
      assert Enum.all?(Enum.reject(1..count, &(&1 == tournament.champion)), &(losses[&1] == 2))
      assert length(tournament.played) in [2 * count - 2, 2 * count - 1]
    end
  end

  test "nobody plays themselves, and both finalists are the last two left" do
    for count <- 3..8 do
      tournament = play(Tournament.new(count))
      assert Enum.all?(tournament.played, fn %{players: {a, b}} -> a != b end)
      [%{bracket: :final, players: {a, b}} | _] = tournament.played
      assert tournament.champion in [a, b]
    end
  end

  defp play(tournament) do
    case Tournament.next(tournament) do
      nil -> tournament
      pair -> play(Tournament.won(tournament, elem(pair, :rand.uniform(2) - 1)))
    end
  end
end
