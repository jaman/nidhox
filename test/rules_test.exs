defmodule Nidhox.RulesTest do
  use ExUnit.Case, async: true

  alias Nidhox.Rules

  test "the time limit steps from none through 3:00 to 9:30 in half minutes, then back to none" do
    limits =
      %Rules{}
      |> Stream.iterate(&Rules.choose(&1, :time_limit))
      |> Enum.take(16)
      |> Enum.map(& &1.time_limit)

    assert limits == [0 | Enum.to_list(10_800..34_200//1_800)] ++ [0]
  end
end
