defmodule Nidhox.Screen.Levels do
  @moduledoc """
  The level select over `rLevelSelect`, the copy's painted map, as the game's
  `VsLevelSelect` runs it.

    * its areas, in order: Clouds (`"Sky"`), Cemetery, Castle, Wilds, Mines; Castle
      selected at first, every time
    * `:up` and `:down` from either side move through them, round from the last to the
      first; `:attack` or `:start` choose the selected area once more than 4 steps have
      passed; with no move for 720 steps the select gives up for the main menu.
      Nothing goes back
    * the view eases 0.1 of the way each step towards the area's point on the map's
      camera path (path 2), its middle kept 160 from the map's sides and 100 from its
      top and bottom (`setCameraToSelectedLevel`)
    * the area's name plate (`sCastle`, `sMines`, `sWilds`, `sClouds`, `sCemetery`)
      stands on the map at the area's point of the plate path (path 3) (`drawLevelTitle`)

  Each area's point on both paths: Castle 0, Mines 1, Wilds 2, Clouds 3, Cemetery 4.
  """

  alias Cauldron2D.GameMaker.{Data, World}
  alias Nidhox.Bout.Camera

  @enforce_keys [:selected]
  defstruct [:selected, steps: 0, idle: 0]

  @type t :: %__MODULE__{selected: String.t(), steps: non_neg_integer(), idle: non_neg_integer()}

  @order ["Sky", "Cemetery", "Castle", "Wilds", "Mines"]
  @first "Castle"
  @points %{"Castle" => 0, "Mines" => 1, "Wilds" => 2, "Sky" => 3, "Cemetery" => 4}
  @plates %{
    "Cemetery" => "sCemetery",
    "Castle" => "sCastle",
    "Mines" => "sMines",
    "Sky" => "sClouds",
    "Wilds" => "sWilds"
  }
  @camera_path 2
  @plate_path 3
  @ease 0.1
  @side_margin 160
  @top_margin 100
  @wait_steps 4
  @idle_steps 720

  @doc "A level select with Castle selected."
  @spec new() :: t()
  def new, do: %__MODULE__{selected: @first}

  @doc ~s{The game's name for `area` (`getLevelName`): `"Clouds"` for `"Sky"`, else the area's own.}
  @spec name(String.t()) :: String.t()
  def name("Sky"), do: "Clouds"
  def name(area), do: area

  @doc "The area `step` places on from `area` in the level select's order, round from the last to the first."
  @spec next(String.t(), integer()) :: String.t()
  def next(area, step) do
    index = Enum.find_index(@order, &(&1 == area)) || Enum.find_index(@order, &(&1 == @first))
    Enum.at(@order, Integer.mod(index + step, length(@order)))
  end

  @doc "The selected area."
  @spec selected(t()) :: String.t()
  def selected(%__MODULE__{selected: area}), do: area

  @doc """
  What the players did this step: `{:choose, area}`, `:given_up` after 720
  steps with no move, `{:moved, levels}` or `{:stay, levels}`.
  """
  @spec input(t(), %{1 => map(), 2 => map()}) ::
          {:choose, String.t()} | :given_up | {:moved, t()} | {:stay, t()}
  def input(%__MODULE__{} = levels, players) do
    pressed = players |> Map.values() |> Enum.flat_map(&MapSet.to_list(&1.pressed))
    levels = %{levels | steps: levels.steps + 1, idle: levels.idle + 1}

    cond do
      :up in pressed ->
        {:moved, %{moved(levels, -1) | idle: 0}}

      :down in pressed ->
        {:moved, %{moved(levels, 1) | idle: 0}}

      levels.steps > @wait_steps and (:attack in pressed or :start in pressed) ->
        {:choose, levels.selected}

      levels.idle >= @idle_steps ->
        :given_up

      true ->
        {:stay, levels}
    end
  end

  @doc "`world` with its view eased towards the selected area (`setCameraToSelectedLevel`)."
  @spec pan(t(), World.t()) :: World.t()
  def pan(%__MODULE__{selected: area}, %World{} = world) do
    {x, y} = point(world, @camera_path, area)
    {room_width, room_height} = Enum.at(world.data.rooms, world.room).size
    target_x = clamp(x, @side_margin, room_width - @side_margin)
    target_y = clamp(y, @top_margin, room_height - @top_margin)
    centre_x = Camera.center_x(world)
    centre_y = Camera.center_y(world)

    world
    |> Camera.put_center_x(centre_x + (target_x - centre_x) * @ease)
    |> Camera.put_center_y(centre_y + (target_y - centre_y) * @ease)
  end

  @doc "The level select's room items: the selected area's plate on the map (`drawLevelTitle`)."
  @spec items(t(), World.t()) :: [map()]
  def items(%__MODULE__{selected: area}, %World{} = world) do
    sprite = Data.index(world.data, :sprites, Map.fetch!(@plates, area))
    %{origin: origin} = World.sprite(world, sprite)

    [
      %{
        picture: {:sprite, sprite, 0},
        position: point(world, @plate_path, area),
        origin: origin,
        depth: -1_000_000
      }
    ]
  end

  defp moved(%__MODULE__{selected: area} = levels, step),
    do: %{levels | selected: next(area, step)}

  defp point(world, path, area) do
    {x, y, _speed} =
      world.data.paths
      |> Enum.at(path)
      |> Map.fetch!(:points)
      |> Enum.at(Map.fetch!(@points, area))

    {x, y}
  end

  defp clamp(value, low, high), do: value |> max(low) |> min(high)
end
