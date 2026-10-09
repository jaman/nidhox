defmodule Nidhox.Objects.Arrow do
  @moduledoc """
  The game's `Arrow`: the "GO" arrow (`sGO`) at the top of the screen pointing the way
  the fencer with the right of way runs. It sits in the screen's pixels (the game's
  320 × 200 GUI surface), drawn over the play.

    * create: `xPos`, `yOffset`, `xSpeed` 0; ±1 when somebody already leads
    * end step: `xPos` held to ±0.9, then shown (`image_alpha` 1) and, with a match:
      nobody leading, hidden with `xPos` 0; player 1 leading, `xPos` 1 and frame 1;
      player 2, `xPos` −1 and frame 2. Its place: across `160 + xPos × 124 −
      sprite_width / 2`, down `(160 − |x − 160|) × 0.1 + 12`, from its place before
    * draw: outside a demonstration (`System.flow` 1), with a match neither in sudden
      death nor finished and somebody leading: in the leader's colour — in a
      tournament the colour of the tournament's player leading (`currentPlayer[leader] + 1`), in a single player run the
      computer's when player 2 leads. First its shadow in black, the whole frame at
      `(x − 1 ± sin(System.frame / 30), y − 1 + cos(System.frame / 50) / 2)` (+ for
      player 1); then the arrow in bands 5 pixels tall, band `i` (from its top) in the
      colour merged towards that colour 5% darkened by `0.5 + sin(i² / 10 +
      System.frame / 4) × 0.5`
  """

  alias Cauldron2D.GameMaker.{Colour, Draw, Instance, World}
  alias Nidhox.Bout.{Camera, PlayerColour}
  alias Nidhox.Gml
  alias Nidhox.Objects.{Match, System}

  @reach 124
  @middle 160
  @top 12
  @band 5
  @demonstration 1
  @computer 123_456
  @gui_depth -1_000_000

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Arrow_Create_0", &start/3},
      {"gml_Object_Arrow_Step_2", &end_step/3},
      {"gml_Object_Arrow_Draw_0", &draw/3}
    ]
  end

  defp start(world, self, _other) do
    x_pos =
      case Match.get(world, :leadingPlayerIndex) do
        1 -> 1
        2 -> -1
        _nobody -> 0
      end

    Gml.put(world, self, %{xPos: x_pos, yOffset: 0, xSpeed: 0, surf: -1, yellowKillStreak: 0, orangeKillStreak: 0})
  end

  defp end_step(world, self, _other) do
    world = Gml.put(world, self, %{xPos: Gml.clamp(Gml.var(world, self, :xPos), -0.9, 0.9)})
    world = World.update(world, self, &%{&1 | image_alpha: 1.0})

    if Gml.exists?(world, "Match"),
      do: world |> follow_leader(self) |> place(self),
      else: world
  end

  defp follow_leader(world, self) do
    case Match.get(world, :leadingPlayerIndex) do
      1 -> world |> Gml.put(self, %{xPos: 1}) |> World.update(self, &%{&1 | image_index: 1})
      2 -> world |> Gml.put(self, %{xPos: -1}) |> World.update(self, &%{&1 | image_index: 2})
      _nobody -> world |> Gml.put(self, %{xPos: 0}) |> World.update(self, &%{&1 | image_alpha: 0.0})
    end
  end

  defp place(world, self) do
    %Instance{x: x, sprite_index: sprite} = World.fetch(world, self)
    y_offset = (@middle - abs(x - @middle)) * 0.1
    width = sprite_width(world, sprite)

    world
    |> Gml.put(self, %{yOffset: y_offset})
    |> World.update(self, &%{&1 | y: y_offset + @top, x: @middle + Gml.var(world, self, :xPos) * @reach - width / 2})
  end

  defp draw(world, self, _other) do
    leader = Match.get(world, :leadingPlayerIndex)

    if System.get(world, :flow) != @demonstration and Gml.exists?(world, "Match") and
         not Gml.truthy?(Match.get(world, :sudden_death)) and not Gml.truthy?(Match.get(world, :finished)) and
         leader in [1, 2] do
      {colour, world} = PlayerColour.get(world, self, colour_index(world, leader))
      arrow(world, self, leader, colour)
    else
      world
    end
  end

  defp colour_index(world, leader) do
    cond do
      Gml.exists?(world, "ArcadeMode") and leader == 2 -> @computer
      (tournament = Gml.first(world, "Tournament")) != nil -> Map.get(Gml.var(world, tournament, :currentPlayer, %{}), leader, 0) + 1
      true -> leader
    end
  end

  defp arrow(world, self, leader, colour) do
    %Instance{x: x, y: y, sprite_index: sprite} = World.fetch(world, self)
    frame = System.get(world, :frame)
    toward = if leader == 1, do: 1, else: -1
    {width, height} = sprite_size(world, sprite)
    left = Camera.left(world)
    top = Camera.top(world)

    shadow =
      part(sprite, leader, {0, 0, width, height}, {left + x - 1 + toward * :math.sin(frame / 30), top + y - 1 + :math.cos(frame / 50) / 2}, {0, 0, 0})

    darker = Colour.merge(colour, {0, 0, 0}, 0.05)

    bands =
      for band <- 0..(height - 1)//@band do
        shade = 0.5 + :math.sin(band * band / 10 + frame / 4) * 0.5
        part(sprite, leader, {0, band, width, min(@band, height - band)}, {left + x, top + y + band}, Colour.merge(colour, darker, shade))
      end

    Enum.reduce([shadow | bands], world, &Draw.item(&2, &1))
  end

  defp part(sprite, frame, rectangle, position, blend),
    do: %{picture: {:part, {:sprite, sprite, frame}, rectangle}, position: position, blend: blend, depth: @gui_depth}

  defp sprite_width(world, sprite), do: world |> sprite_size(sprite) |> elem(0)

  defp sprite_size(world, sprite) do
    case World.sprite(world, sprite) do
      nil -> {0, 0}
      definition -> definition.size
    end
  end
end
