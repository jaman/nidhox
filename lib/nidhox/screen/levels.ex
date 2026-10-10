defmodule Nidhox.Screen.Levels do
  @moduledoc """
  The level select over `rLevelSelect`, the copy's painted map of every area: the view
  pans across the map to the selected area, and that area's name plate from the copy
  (`sCemetery`, `sCastle`, `sMines`, `sClouds`, `sWilds`) stands at the top of the
  screen.

  Under the plate are the rows VARIANTS and BEGIN; for a tournament (`new/3` with
  `:tournament`), PLAYERS (`Nidhox.Tournament.fewest/0` to `most/0`, `players/1`),
  VARIANTS and START TOURNAMENT. Either side moves between the area and the rows with
  `:up` and `:down`, changes the area or the players with `:left` and `:right`, wrapping
  around, chooses with `:start` or `:attack` from any of them, and goes back with
  `:jump`. Choosing VARIANTS opens the game's VARIANTS menu over the map: every entry of
  `Nidhox.Rules` with its value, `:up` and `:down` moving, `:start` or `:attack`
  choosing (`Nidhox.Rules.choose/2`), `:jump` going back to the rows; the rules it
  leaves are `rules/1`'s. The view's place on the map
  for each area is `@views`' top-left corner; it moves `@ease` of the way there each
  step, and `new/2` puts it there at once.
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.{Rules, Tournament}
  alias Nidhox.Screen.Art

  @enforce_keys [:areas]
  defstruct [
    :areas,
    rows: [:variants, :begin],
    selected: 0,
    row: 0,
    rules: %Rules{},
    variants: nil,
    players: 4
  ]

  @type row :: :players | :variants | :begin | :start
  @type t :: %__MODULE__{
          areas: [String.t()],
          rows: [row()],
          selected: non_neg_integer(),
          row: non_neg_integer(),
          rules: Rules.t(),
          variants: non_neg_integer() | nil,
          players: pos_integer()
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
  @variants_heading {160, 18}
  @variants_top 36
  @variants_spacing 11

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
  def rules(%__MODULE__{rules: rules}), do: rules

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

  @doc "The level select's GUI items: the selected area's name plate and the rows, or the VARIANTS menu."
  @spec items(t(), {number(), number()}) :: [map()]
  def items(%__MODULE__{variants: nil} = levels, window),
    do: [
      Art.centred(Map.fetch!(@plates, selected(levels)), 0, @plate, window) | rows(levels, window)
    ]

  def items(%__MODULE__{variants: at, rules: rules}, window) do
    entries =
      Rules.entries()
      |> Enum.with_index()
      |> Enum.flat_map(fn {entry, index} ->
        Art.text(
          "fMenu",
          Rules.label(rules, entry),
          {160, @variants_top + index * @variants_spacing},
          window,
          halign: :center,
          colour: if(index == at, do: @chosen, else: @other)
        )
      end)

    [
      Art.shade(window, {0, 0, 0}, 0.75)
      | Art.text("fMenu", "VARIANTS", @variants_heading, window, halign: :center)
    ] ++
      entries
  end

  defp towards(_from, to, :snap), do: to
  defp towards(from, to, :ease), do: from + (to - from) * @ease

  defp pressed(%__MODULE__{variants: at} = levels, _side, pressed) when at != nil do
    last = length(Rules.entries()) - 1

    cond do
      :start in pressed or :attack in pressed ->
        {:stay, %{levels | rules: Rules.choose(levels.rules, Enum.at(Rules.entries(), at))}}

      :jump in pressed ->
        {:stay, %{levels | variants: nil}}

      :up in pressed ->
        {:stay, %{levels | variants: max(at - 1, 0)}}

      :down in pressed ->
        {:stay, %{levels | variants: min(at + 1, last)}}

      true ->
        nil
    end
  end

  defp pressed(levels, side, pressed) do
    cond do
      (:start in pressed or :attack in pressed) and row(levels) == :variants ->
        {:stay, %{levels | variants: 0}}

      :start in pressed or :attack in pressed ->
        {:choose, selected(levels), side}

      :jump in pressed ->
        {:back, side}

      :up in pressed ->
        {:stay, %{levels | row: max(levels.row - 1, 0)}}

      :down in pressed ->
        {:stay, %{levels | row: min(levels.row + 1, length(levels.rows))}}

      :left in pressed ->
        {:stay, change(levels, -1)}

      :right in pressed ->
        {:stay, change(levels, 1)}

      true ->
        nil
    end
  end

  defp rows_for(:versus), do: [:variants, :begin]
  defp rows_for(:tournament), do: [:players, :variants, :start]

  defp row(%__MODULE__{row: 0}), do: :area
  defp row(%__MODULE__{rows: rows, row: row}), do: Enum.at(rows, row - 1)

  defp change(%__MODULE__{row: 0} = levels, step), do: move(levels, step)

  defp change(levels, step), do: change_row(row(levels), levels, step)

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

  defp label(:variants, _levels), do: "VARIANTS"

  defp label(:begin, _levels), do: "BEGIN"
  defp label(:start, _levels), do: "START TOURNAMENT"

  defp move(%__MODULE__{areas: areas, selected: selected} = levels, step),
    do: %{levels | selected: Integer.mod(selected + step, length(areas))}
end
