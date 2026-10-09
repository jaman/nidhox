defmodule Nidhox.Bout.PlayerColour do
  @moduledoc """
  A player's colour, as the game's `getPlayerColor(index)` gives it, asked by instance
  `self`:

  | index | colour |
  | --- | --- |
  | 0 | black |
  | 1 | the colour picked for player 1 (`global.miscPref_p1color`), else yellow `{255, 255, 0}` |
  | 2 | the colour picked for player 2 (`global.miscPref_p2color`), else orange `{255, 160, 64}` |
  | 3–8 | `photoshopHSV` of `{77, 100, 96}`, `{156, 100, 100}`, `{189, 100, 96}`, `{348, 92, 100}`, `{300, 60, 100}`, `{240, 60, 100}` |
  | 9 | white |
  | 10 | flashing (`System.flashing`): a random hue up to 80 (of 255), white one time in four; else a hue running with `self`'s place and `System.frame` |
  | 123456 | the computer's colour in a single player run: by its personality for the run's level (`ArcadeMode.personalityMap[ArcadeMode.level]`) — 5 → 2, 6 → 3, 2 → 4, 9 → 5, 1 → 6, 4 → 7, 8 → 8, any other → 10 — or 2 when player 2's colour is picked |

  Any other index is black. A picked colour is GameMaker's `0xBBGGRR`.
  """

  alias Cauldron2D.GameMaker.{Colour, Instance, World}
  alias Nidhox.Gml
  alias Nidhox.Objects.System

  @computer 123_456
  @photoshop %{
    3 => {77, 100, 96},
    4 => {156, 100, 100},
    5 => {189, 100, 96},
    6 => {348, 92, 100},
    7 => {300, 60, 100},
    8 => {240, 60, 100}
  }
  @personalities %{5 => 2, 6 => 3, 2 => 4, 9 => 5, 1 => 6, 4 => 7, 8 => 8}
  @rainbow 10

  @doc "`{colour, world}`: colour index `index` as `getPlayerColor`, asked by instance `self`."
  @spec get(World.t(), non_neg_integer() | nil, number()) :: {{byte(), byte(), byte()}, World.t()}
  def get(%World{} = world, self, @computer), do: get(world, self, computer_index(world))
  def get(%World{} = world, _self, 0), do: {{0, 0, 0}, world}
  def get(%World{} = world, _self, 1), do: {picked(world, :miscPref_p1color, {255, 255, 0}), world}
  def get(%World{} = world, _self, 2), do: {picked(world, :miscPref_p2color, {255, 160, 64}), world}

  def get(%World{} = world, _self, index) when is_map_key(@photoshop, index) do
    {hue, saturation, value} = @photoshop[index]
    {Colour.hsv(hue / 360 * 255, saturation / 100 * 255, value / 100 * 255), world}
  end

  def get(%World{} = world, _self, 9), do: {{255, 255, 255}, world}
  def get(%World{} = world, self, @rainbow), do: rainbow(world, self)
  def get(%World{} = world, _self, _index), do: {{0, 0, 0}, world}

  @doc "Colour index `index`'s colour where nothing random is drawn: every index but 10 and the computer's."
  @spec fixed(World.t(), number()) :: {byte(), byte(), byte()}
  def fixed(%World{} = world, index), do: world |> get(nil, index) |> elem(0)

  @doc "`{colour, world}`: player `player`'s plain colour (`getColorPlayerIndex`) — yellow, orange, else a random hue."
  @spec of_player(World.t(), number()) :: {{byte(), byte(), byte()}, World.t()}
  def of_player(%World{} = world, 1), do: {{255, 255, 0}, world}
  def of_player(%World{} = world, 2), do: {{255, 160, 64}, world}

  def of_player(%World{} = world, _player) do
    {hue, world} = Gml.random(world, 255)
    {Colour.hsv(hue, 255, 255), world}
  end

  defp computer_index(world) do
    if World.global(world, :miscPref_p2color, -1) >= 0 do
      2
    else
      with arcade when arcade != nil <- Gml.first(world, "ArcadeMode"),
           personalities when is_map(personalities) <- Gml.var(world, arcade, :personalityMap, nil) do
        Map.get(@personalities, Map.get(personalities, Gml.var(world, arcade, :level)), @rainbow)
      else
        _none -> @rainbow
      end
    end
  end

  defp picked(world, preference, default) do
    case World.global(world, preference, -1) do
      picked when picked >= 0 -> bgr(trunc(picked))
      _none -> default
    end
  end

  defp bgr(colour),
    do: {Bitwise.band(colour, 0xFF), Bitwise.band(Bitwise.bsr(colour, 8), 0xFF), Bitwise.band(Bitwise.bsr(colour, 16), 0xFF)}

  defp rainbow(world, self) do
    if Gml.truthy?(System.get(world, :flashing)) do
      {hue, world} = Gml.random(world, 80)
      {saturation, world} = Gml.choose(world, [0, 255, 255, 255])
      {Colour.hsv(hue, saturation, 255), world}
    else
      {x, y} = place(world, self)
      {Colour.hsv(x + y + System.get(world, :frame) / 2, 255, 255), world}
    end
  end

  defp place(world, self) do
    case self && World.fetch(world, self) do
      %Instance{x: x, y: y} -> {x, y}
      _none -> {0, 0}
    end
  end
end
