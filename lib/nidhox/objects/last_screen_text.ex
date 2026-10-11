defmodule Nidhox.Objects.LastScreenText do
  @moduledoc """
  The game's `LastScreenText`, placed in the last room of an area's side, as its code
  runs it.

    * create: `timer` 120
    * step: `timer` counts down; below 0 it is gone
    * draw, while there is a `Match`: it moves to the camera's centre, shaken by
      `random_range(−1, 1)` each way, and draws "Final Screen" in font 1 (`fMenu`),
      centred both ways (`lastScreenStyle`): first, for `i` 0 and 1, a shadow in
      `make_color_hsv(0, 0, 60 + 80i / 2)` moved `lengthdir_x(2 − i,
      point_direction(x, y, cameraCenterX, cameraBottom))` across (plus
      `random_range(0, 0)`) and `2 − i` down, then the text itself in white
  """

  alias Cauldron2D.GameMaker.{Colour, Draw, Instance, World}
  alias Nidhox.Bout.Camera
  alias Nidhox.Gml

  @text "Final Screen"
  @font 1
  @life 120
  @shake 1.0
  @layers 2
  @spread 0
  @white {255, 255, 255}

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_LastScreenText_Create_0",
       fn world, self, _other -> Gml.put(world, self, %{timer: @life}) end},
      {"gml_Object_LastScreenText_Step_0", &count_down/3},
      {"gml_Object_LastScreenText_Draw_0", &draw/3}
    ]
  end

  defp count_down(world, self, _other) do
    timer = Gml.var(world, self, :timer) - 1
    world = Gml.put(world, self, %{timer: timer})
    if timer < 0, do: World.destroy(world, self), else: world
  end

  defp draw(world, self, _other) do
    if Gml.exists?(world, "Match"), do: draw_text(world, self), else: world
  end

  defp draw_text(world, self) do
    {shake_x, world} = Gml.random_range(world, -@shake, @shake)
    {shake_y, world} = Gml.random_range(world, -@shake, @shake)
    x = Camera.center_x(world) + shake_x
    y = Camera.center_y(world) + shake_y
    world = World.update(world, self, &%{&1 | x: x, y: y})
    direction = Gml.point_direction({x, y}, {Camera.center_x(world), Camera.bottom(world)})

    world =
      Enum.reduce(0..(@layers - 1), world, fn layer, world ->
        length = (1 - layer / @layers) * @layers
        {jitter, world} = Gml.random_range(world, -@spread, @spread)
        grey = Colour.hsv(0, 0, layer / @layers * 80 + 60)
        position = {x + Gml.lengthdir_x(length, direction) + jitter, y + length}
        Draw.text(world, @font, @text, position, style(grey))
      end)

    %Instance{x: x, y: y} = World.fetch(world, self)
    Draw.text(world, @font, @text, {x, y}, style(@white))
  end

  defp style(colour), do: [halign: :center, valign: :middle, colour: colour, alpha: 1.0]
end
