defmodule Nidhox.Objects.DialogBox do
  @moduledoc """
  The game's `DialogBox`: a line of instructions typed out a letter at a time near the
  top of the screen, as the tutorial shows its lessons.

    * `show/2` (`showDialog(text)`): every `DialogBox` gone and a new one typing `text`
    * create: a clear canvas the screen's width less 64 across and 64 down; in `fMenu`,
      `LETTER_WIDTH` the width of an `A` and `LINE_HEIGHT` its height less 2; margins of
      16 across and 6 down; lines `LINE_WIDTH` the canvas's width less six margins long
    * user event 0: the text broken into lines at the last space that fits
      (`string_width_wrap`, `#` between lines), and the typing begun
    * step, every other frame once begun: the next letter drawn onto the canvas in white
      at the margins, `NEXT_X_POSITION` across and `LINE` lines down, moving on by
      `LETTER_WIDTH`; a `#` starts the next line
    * draw: the canvas centred across the screen 32 pixels below its top, swaying
      (0.66 pixels on `cos(frame / 20)` across and `sin(frame / 30)` down), tinted yellow
      and white every third frame; a lost canvas is made again, clear
  """

  alias Cauldron2D.GameMaker.{Draw, Surfaces, Text, World}
  alias Nidhox.Bout.Camera
  alias Nidhox.Gml
  alias Nidhox.Objects.System

  @font "fMenu"
  @height 64
  @inset 64
  @margin_x 16
  @margin_y 6
  @top 32
  @sway 0.66
  @yellow {255, 255, 0}
  @white {255, 255, 255}
  @line_break "#"

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_DialogBox_Create_0", &create/3},
      {"gml_Object_DialogBox_Other_10", &begin/3},
      {"gml_Object_DialogBox_Step_0", &type/3},
      {"gml_Object_DialogBox_Draw_0", &draw/3}
    ]
  end

  @doc "The world with a `DialogBox` typing `text` and no other (`showDialog`)."
  @spec show(World.t(), String.t()) :: World.t()
  def show(%World{} = world, text) do
    world = world |> Gml.all("DialogBox") |> Enum.reduce(world, &World.destroy(&2, &1))
    {world, box} = World.create(world, World.object_index(world, "DialogBox"), {0, 0})

    world
    |> Gml.put(box, %{textToAdd: text})
    |> World.perform(box, :other, 10)
  end

  defp create(world, self, _other) do
    {world, canvas} = new_canvas(world)
    letter_width = Text.width(world.data, @font, "A")
    line_height = Text.height(world.data, @font, "A") - 2
    {canvas_width, _height} = Surfaces.size(world, canvas)

    Gml.put(world, self, %{
      canvas: canvas,
      textToAdd: "TEST",
      textAdded: "",
      readyToDraw: 0,
      LETTER_WIDTH: letter_width,
      LINE_HEIGHT: line_height,
      MARGIN_X: @margin_x,
      MARGIN_Y: @margin_y,
      LINE_WIDTH: canvas_width - @margin_x * 6,
      LINE: 0,
      NEXT_X_POSITION: 0
    })
  end

  defp begin(world, self, _other) do
    text = Gml.var(world, self, :textToAdd, "")
    wrapped = wrap(world, text, Gml.var(world, self, :LINE_WIDTH))
    Gml.put(world, self, %{textToAdd: wrapped, readyToDraw: 1})
  end

  defp type(world, self, _other) do
    if Gml.truthy?(Gml.var(world, self, :readyToDraw)) and rem(trunc(System.get(world, :frame)), 2) == 0,
      do: next_letter(world, self),
      else: world
  end

  defp next_letter(world, self) do
    world = line_breaks(world, self)

    case Gml.var(world, self, :textToAdd, "") do
      "" -> world
      text -> letter(world, self, String.first(text))
    end
  end

  defp line_breaks(world, self) do
    case Gml.var(world, self, :textToAdd, "") do
      @line_break <> rest ->
        world
        |> Gml.put(self, %{
          LINE: Gml.var(world, self, :LINE) + 1,
          NEXT_X_POSITION: 0,
          textAdded: Gml.var(world, self, :textAdded, "") <> @line_break,
          textToAdd: rest
        })
        |> line_breaks(self)

      _letter ->
        world
    end
  end

  defp letter(world, self, letter) do
    position =
      {Gml.var(world, self, :MARGIN_X) + Gml.var(world, self, :NEXT_X_POSITION),
       Gml.var(world, self, :MARGIN_Y) + Gml.var(world, self, :LINE_HEIGHT) * Gml.var(world, self, :LINE)}

    items = Text.items(world.data, @font, letter, position, colour: @white)
    canvas = canvas(world, self)
    world = if Surfaces.exists?(world, canvas), do: Surfaces.draw(world, canvas, items), else: world

    Gml.put(world, self, %{
      textAdded: Gml.var(world, self, :textAdded, "") <> letter,
      textToAdd: world |> Gml.var(self, :textToAdd, "") |> String.slice(1..-1//1),
      NEXT_X_POSITION: Gml.var(world, self, :NEXT_X_POSITION) + Gml.var(world, self, :LETTER_WIDTH)
    })
  end

  defp draw(world, self, _other) do
    {world, canvas} = live_canvas(world, self)
    frame = System.get(world, :frame)
    {canvas_width, _height} = Surfaces.size(world, canvas)
    tint = if rem(trunc(frame), 3) == 0, do: @white, else: @yellow
    x = Camera.left(world) + (Camera.width(world) - canvas_width) * 0.5 + :math.cos(frame / 20) * @sway
    y = Camera.top(world) + @top + :math.sin(frame / 30) * @sway

    Draw.item(world, Surfaces.item(world, canvas, {x, y}, blend: tint))
  end

  defp live_canvas(world, self) do
    canvas = canvas(world, self)

    if Surfaces.exists?(world, canvas) do
      {world, canvas}
    else
      {world, canvas} = new_canvas(world)
      {Gml.put(world, self, %{canvas: canvas}), canvas}
    end
  end

  defp new_canvas(world) do
    {world, canvas} = Surfaces.create(world, Camera.width(world) - @inset, @height)
    {Surfaces.clear(world, canvas, @white, 0), canvas}
  end

  defp canvas(world, self), do: Gml.var(world, self, :canvas, -1)

  defp wrap(world, text, width), do: wrap(world, text, width, 1, -1, "")

  defp wrap(world, current, width, at, space, output) do
    if String.length(current) >= at do
      {current, at, space, output} = break_line(world, current, width, at, space, output)
      space = if String.at(current, at - 1) == " ", do: at, else: space
      wrap(world, current, width, at + 1, space, output)
    else
      output <> current
    end
  end

  defp break_line(world, current, width, at, space, output) do
    if Gml.gt?(Text.width(world.data, @font, String.slice(current, 0, at)), width) and space != -1 do
      {String.slice(current, space..-1//1), 1, -1, output <> String.slice(current, 0, space) <> @line_break}
    else
      {current, at, space, output}
    end
  end
end
