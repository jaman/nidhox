defmodule Nidhox.Objects.Sun do
  @moduledoc """
  The clouds' `Sun` and its parent `ParallaxObject`, as the game's code runs them.

    * `ParallaxObject` create: `overrideDepth` −1, so the camera moves it by its own
      depth (`Nidhox.Bout.CameraFollow`)
    * `Sun` create: the parent's create, no `canvas` yet
    * `Sun` step: it sinks as it moves off the room's middle: `y = ystart + |x −
      room_width / 2| × 64 / room_width / 2`
    * `Sun` draw: without its canvas, a 200 × 200 surface cleared to white at alpha 0
      gets a white disc (`draw_ellipse(0, 0, 200, 200, false)`) written to its alpha
      only (`draw_set_colour_write_enable(false, false, false, true)`). Then, with
      `bright` `clamp(0.8 + sin(frame / 100) × 0.2, 0.6, 1)`, for `i` from 4 down to 2
      the canvas is drawn centred on the sun (`draw_surface_center_ext`), scaled
      `i / 2 + |sin(frame / 30)| × 0.025` across and `i / 2 + |cos(frame / 30)| ×
      0.025` down, turned `sin(frame / 60) × 10 × i / 2` degrees, in
      `make_color_hsv(sin(frame / 70 × i) × 20, 100, bright × 255 − 5i)`
    * destroy, room end and game end: its canvas freed
  """

  alias Cauldron2D.GameMaker.{Colour, Draw, Instance, Surfaces, World}
  alias Nidhox.Gml
  alias Nidhox.Objects.System

  @size 200
  @white {255, 255, 255}
  @alpha_only {false, false, false, true}
  @rings [4, 3, 2]

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_ParallaxObject_Create_0",
       fn world, self, _other -> Gml.put(world, self, %{overrideDepth: -1}) end},
      {"gml_Object_Sun_Create_0", &start/3},
      {"gml_Object_Sun_Step_0", &sink/3},
      {"gml_Object_Sun_Draw_0", &draw/3},
      {"gml_Object_Sun_Destroy_0", &free/3},
      {"gml_Object_Sun_Other_5", &free/3},
      {"gml_Object_Sun_Other_3", &free/3}
    ]
  end

  defp start(world, self, _other) do
    world
    |> World.inherited(self, "Sun", :create, 0)
    |> Gml.put(self, %{canvas: -1})
  end

  defp sink(world, self, _other) do
    room_width = world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size) |> elem(0)

    World.update(
      world,
      self,
      &%{&1 | y: &1.ystart + abs(&1.x - room_width / 2) * 64 / room_width / 2}
    )
  end

  defp draw(world, self, _other) do
    {world, canvas} = canvas(world, self)
    frame = System.get(world, :frame)
    bright = Gml.clamp(0.8 + :math.sin(frame / 100) * 0.2, 0.6, 1)
    %Instance{x: x, y: y} = World.fetch(world, self)

    Enum.reduce(@rings, world, fn ring, world ->
      Draw.item(
        world,
        Surfaces.item(world, canvas, {x, y},
          origin: {@size / 2, @size / 2},
          scale:
            {ring * 0.5 + abs(:math.sin(frame / 30)) * 0.025,
             ring * 0.5 + abs(:math.cos(frame / 30)) * 0.025},
          angle: -(:math.sin(frame / 60) * 10 * ring / 2),
          blend: Colour.hsv(:math.sin(frame / 70 * ring) * 20, 100, bright * 255 - ring * 5),
          alpha: 1.0
        )
      )
    end)
  end

  defp canvas(world, self) do
    canvas = Gml.var(world, self, :canvas, -1)

    if Surfaces.exists?(world, canvas) do
      {world, canvas}
    else
      {world, canvas} = Surfaces.create(world, @size, @size)

      world =
        world
        |> Surfaces.clear(canvas, @white, 0)
        |> Surfaces.draw(
          canvas,
          [%{picture: {:ellipse, {@size, @size}, :filled}, position: {0, 0}, blend: @white}],
          write: @alpha_only
        )
        |> Gml.put(self, %{canvas: canvas})

      {world, canvas}
    end
  end

  defp free(world, self, _other) do
    canvas = Gml.var(world, self, :canvas, -1)
    if Surfaces.exists?(world, canvas), do: Surfaces.free(world, canvas), else: world
  end
end
