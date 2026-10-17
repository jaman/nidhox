defmodule Nidhox.Screen.Levels do
  @moduledoc """
  The level select over `rLevelSelect`, the copy's painted map, as the game's
  `VsLevelSelect` runs it.

    * its areas, the released levels in order: Clouds (`"Sky"`), Cemetery, Castle,
      Wilds, Mines; Castle selected at first unless `new/2` is given another
    * menu buttons from either side (`Nidhox.Screen.MainMenu.any_pressed?/2`): up and
      down move through the areas, round from the last to the first; select or start
      chooses the selected area once more than 4 steps have passed; back asks to leave
      (`:back`)
    * in CPU BATTLE (`new/2` with an `auto_start` count) the area is chosen by itself
      when the count, taken down by one a step, reaches 0
    * the view eases 0.1 of the way each step towards the area's point on the map's
      camera path (path 2), its middle kept 160 from the map's sides and 100 from its
      top and bottom (`setCameraToSelectedLevel`)
    * the area's name plate (`sCastle`, `sMines`, `sWilds`, `sClouds`, `sCemetery`)
      stands on the map at the area's point of the plate path (path 3) (`drawLevelTitle`)

  Each area's point on both paths: Castle 0, Mines 1, Wilds 2, Clouds 3, Cemetery 4.
  """

  alias Cauldron2D.GameMaker.{Data, World}
  alias Nidhox.Bout.Camera
  alias Nidhox.Screen.MainMenu

  @enforce_keys [:selected]
  defstruct [:selected, steps: 0, auto_start: -1]

  @type t :: %__MODULE__{
          selected: String.t(),
          steps: non_neg_integer(),
          auto_start: integer()
        }

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
  @camera_path "pLevelSelectCamera"
  @plate_path "pLevelTitles"
  @ease 0.1
  @side_margin 160
  @top_margin 100
  @wait_steps 4

  @doc "A level select with `selected` selected, choosing it by itself after `auto_start` steps when that is above 0."
  @spec new(String.t(), integer()) :: t()
  def new(selected \\ @first, auto_start \\ -1),
    do: %__MODULE__{selected: selected, auto_start: auto_start}

  @doc "The released levels' areas, in the level select's order (`releasedLevels`)."
  @spec released() :: [String.t()]
  def released, do: @order

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

  @doc """
  What the players did this step: `{:choose, area}`, `:back`, `{:moved, levels}` or
  `{:stay, levels}`.
  """
  @spec input(t(), %{1 => map(), 2 => map()}) ::
          {:choose, String.t()} | :back | {:moved, t()} | {:stay, t()}
  def input(%__MODULE__{} = levels, players) do
    levels = %{levels | steps: levels.steps + 1, auto_start: levels.auto_start - 1}

    cond do
      MainMenu.any_pressed?(players, 2) ->
        {:moved, moved(levels, -1)}

      MainMenu.any_pressed?(players, 3) ->
        {:moved, moved(levels, 1)}

      levels.steps > @wait_steps and
          (MainMenu.any_pressed?(players, 8) or MainMenu.any_pressed?(players, 10)) ->
        {:choose, levels.selected}

      levels.auto_start == 0 ->
        {:choose, levels.selected}

      MainMenu.any_pressed?(players, 9) ->
        :back

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
      |> Enum.at(Data.index(world.data, :paths, path))
      |> Map.fetch!(:points)
      |> Enum.at(Map.fetch!(@points, area))

    {x, y}
  end

  defp clamp(value, low, high), do: value |> max(low) |> min(high)
end
