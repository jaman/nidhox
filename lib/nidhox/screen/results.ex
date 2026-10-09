defmodule Nidhox.Screen.Results do
  @moduledoc """
  The match's statistics after a bout, over `rMatchStats`, in `fMenu`: who won, how long
  the bout took, and each side's kills and suicides (falls out of the room), and the
  results' menu under them (`menu/0`). The statistics are `Nidhox.Bout.stats/1`'s.
  """

  @type stats :: %{
          steps: non_neg_integer(),
          kills: %{1 => non_neg_integer(), 2 => non_neg_integer()},
          suicides: %{1 => non_neg_integer(), 2 => non_neg_integer()}
        }

  alias Nidhox.Screen.{Art, Menu}

  @hz 60
  @winner {160, 40}
  @time {160, 64}
  @rows_top 88
  @row 16
  @left 96
  @right 224
  @label 160
  @menu_top {160, 130}
  @colours %{1 => {255, 214, 60}, 2 => {255, 140, 40}}

  @doc "The results' menu: CONTINUE, WATCH REPLAY, BACK TO MAIN MENU."
  @spec menu() :: Menu.t()
  def menu,
    do:
      Menu.new([{"CONTINUE", :continue}, {"WATCH REPLAY", :replay}, {"BACK TO MAIN MENU", :main}])

  @doc "The GUI items for a bout won by `winner` with `stats`, the results' `menu` under them."
  @spec items(1 | 2, stats(), Menu.t(), {number(), number()}) :: [map()]
  def items(winner, stats, %Menu{} = menu, window) do
    rows = [
      {"kills", stats.kills[1], stats.kills[2]},
      {"suicides", stats.suicides[1], stats.suicides[2]}
    ]

    [
      Art.shade(window, {0, 0, 0}, 0.6),
      Art.text("fMenu", "player #{winner} won!", @winner, window,
        halign: :center,
        colour: @colours[winner]
      ),
      Art.text("fMenu", "time #{clock(stats.steps)}", @time, window, halign: :center),
      Enum.with_index(rows) |> Enum.map(&row(&1, window)),
      Menu.items(menu, @menu_top, window)
    ]
    |> List.flatten()
  end

  defp row({{label, yellow, orange}, index}, window) do
    y = @rows_top + index * @row

    [
      Art.text("fMenu", "#{yellow}", {@left, y}, window, halign: :center, colour: @colours[1]),
      Art.text("fMenu", label, {@label, y}, window, halign: :center),
      Art.text("fMenu", "#{orange}", {@right, y}, window, halign: :center, colour: @colours[2])
    ]
  end

  defp clock(steps) do
    seconds = div(steps, @hz)

    "#{div(seconds, 60)}:#{seconds |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end
end
