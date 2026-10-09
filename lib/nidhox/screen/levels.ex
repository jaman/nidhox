defmodule Nidhox.Screen.Levels do
  @moduledoc """
  The level select over `rLevelSelect`, the copy's painted map of every area: the view
  pans across the map to the selected area, and that area's name plate from the copy
  (`sCemetery`, `sCastle`, `sMines`, `sClouds`, `sWilds`) stands at the top of the
  screen.

  Under the plate are the rows VARIANTS, TIME LIMIT and BEGIN (`rules/1`); for a
  tournament (`new/3` with `:tournament`), PLAYERS (`Nidhox.Tournament.fewest/0` to
  `most/0`, `players/1`), VARIANTS, TIME LIMIT and START TOURNAMENT. Either side
  moves between the area and the rows with `:up` and `:down`, changes the area or the
  row's value with `:left` and `:right`, wrapping around, chooses with `:start` or
  `:attack` from any of them, and goes back with `:jump`. The view's place on the map
  for each area is `@views`' top-left corner; it moves `@ease` of the way there each
  step, and `new/2` puts it there at once.
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.{Rules, Tournament}
  alias Nidhox.Screen.Art

  @enforce_keys [:areas]
  defstruct [
    :areas,
    rows: [:variant, :limit, :begin],
    selected: 0,
    row: 0,
    variant: 0,
    limit: 0,
    players: 4
  ]

  @type row :: :players | :variant | :limit | :begin | :start
  @type t :: %__MODULE__{
          areas: [String.t()],
          rows: [row()],
          selected: non_neg_integer(),
          row: non_neg_integer(),
          players: pos_integer(),
          variant: non_neg_integer(),
          limit: non_neg_integer()
        }

  @plates %{
    "Cemetery" => "sCemetery",
    "Castle" => "sCastle",
    "Mines" => "sMines",
    "Sky" => "sClouds",
    "Wilds" => "sWilds"
  }
  @views %{
    "Cemetery" => {0, 40},
    "Castle" => {220, 110},
    "Mines" => {470, 200},
    "Sky" => {420, 0},
    "Wilds" => {640, 90}
  }
  @plate {160, 26}
  @ease 0.12
  @rows_top 140
  @row_spacing 14
  @chosen {255, 255, 255}
  @other {150, 150, 150}

  @doc """
  A level select over `areas` with `area` selected, or the first when it is not among
  them, for a `:versus` bout or a `:tournament`.
  """
  @spec new([String.t()], String.t() | nil, :versus | :tournament) :: t()
  def new([_ | _] = areas, area, mode \\ :versus),
    do: %__MODULE__{
      areas: areas,
      rows: rows_for(mode),
      selected: Enum.find_index(areas, &(&1 == area)) || 0
    }

  @doc "How many players the tournament is for."
  @spec players(t()) :: pos_integer()
  def players(%__MODULE__{players: players}), do: players

  @doc "The rules the level select's rows set (`Nidhox.Rules`)."
  @spec rules(t()) :: Rules.t()
  def rules(%__MODULE__{variant: variant, limit: limit}) do
    %Rules{
      variant: Rules.variants() |> Enum.at(variant) |> elem(0),
      minutes: Enum.at(Rules.limits(), limit)
    }
  end

  @doc "The selected area."
  @spec selected(t()) :: String.t()
  def selected(%__MODULE__{areas: areas, selected: index}), do: Enum.at(areas, index)

  @doc """
  What the players did this step: `{:choose, area, side}`, `{:back, side}`, or
  `{:stay, levels}` with the selection moved if they moved it.
  """
  @spec input(t(), %{1 => map(), 2 => map()}) ::
          {:choose, String.t(), 1 | 2} | {:back, 1 | 2} | {:stay, t()}
  def input(%__MODULE__{} = levels, players) do
    case Enum.find_value([1, 2], &pressed(levels, &1, players[&1].pressed)) do
      nil -> {:stay, levels}
      outcome -> outcome
    end
  end

  @doc """
  `world` in `rLevelSelect` with its view moved towards the selected area's place on the
  map, `:ease` moving `@ease` of the way and `:snap` all of it.
  """
  @spec pan(t(), World.t(), :ease | :snap) :: World.t()
  def pan(
        %__MODULE__{} = levels,
        %World{views: [%{view: {x, y, width, height}} | _]} = world,
        mode
      ) do
    {to_x, to_y} = Map.fetch!(@views, selected(levels))
    World.put_view(world, 0, {towards(x, to_x, mode), towards(y, to_y, mode), width, height})
  end

  @doc "The level select's GUI items: the selected area's name plate."
  @spec items(t(), {number(), number()}) :: [map()]
  def items(%__MODULE__{} = levels, window),
    do: [
      Art.centred(Map.fetch!(@plates, selected(levels)), 0, @plate, window) | rows(levels, window)
    ]

  defp towards(_from, to, :snap), do: to
  defp towards(from, to, :ease), do: from + (to - from) * @ease

  defp pressed(levels, side, pressed) do
    cond do
      :start in pressed or :attack in pressed -> {:choose, selected(levels), side}
      :jump in pressed -> {:back, side}
      :up in pressed -> {:stay, %{levels | row: max(levels.row - 1, 0)}}
      :down in pressed -> {:stay, %{levels | row: min(levels.row + 1, length(levels.rows))}}
      :left in pressed -> {:stay, change(levels, -1)}
      :right in pressed -> {:stay, change(levels, 1)}
      true -> nil
    end
  end

  defp rows_for(:versus), do: [:variant, :limit, :begin]
  defp rows_for(:tournament), do: [:players, :variant, :limit, :start]

  defp change(%__MODULE__{row: 0} = levels, step), do: move(levels, step)

  defp change(%__MODULE__{rows: rows, row: row} = levels, step),
    do: change_row(Enum.at(rows, row - 1), levels, step)

  defp change_row(:variant, %__MODULE__{variant: variant} = levels, step),
    do: %{levels | variant: Integer.mod(variant + step, length(Rules.variants()))}

  defp change_row(:limit, %__MODULE__{limit: limit} = levels, step),
    do: %{levels | limit: Integer.mod(limit + step, length(Rules.limits()))}

  defp change_row(:players, %__MODULE__{players: players} = levels, step) do
    span = Tournament.most() - Tournament.fewest() + 1

    %{
      levels
      | players: Tournament.fewest() + Integer.mod(players - Tournament.fewest() + step, span)
    }
  end

  defp change_row(_row, levels, _step), do: levels

  defp rows(%__MODULE__{rows: rows} = levels, window) do
    rows
    |> Enum.map(&label(&1, levels))
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {words, row} ->
      colour = if row == levels.row, do: @chosen, else: @other

      Art.text("fMenu", words, {160, @rows_top + (row - 1) * @row_spacing}, window,
        halign: :center,
        colour: colour
      )
    end)
  end

  defp label(:players, levels), do: "PLAYERS: #{levels.players}"

  defp label(:variant, levels) do
    variant = rules(levels).variant
    "VARIANTS: " <> (Rules.variants() |> List.keyfind(variant, 0) |> elem(1))
  end

  defp label(:limit, levels) do
    minutes = rules(levels).minutes
    "TIME LIMIT: " <> if(minutes, do: "#{minutes} MIN", else: "NONE")
  end

  defp label(:begin, _levels), do: "BEGIN"
  defp label(:start, _levels), do: "START TOURNAMENT"

  defp move(%__MODULE__{areas: areas, selected: selected} = levels, step),
    do: %{levels | selected: Integer.mod(selected + step, length(areas))}
end
