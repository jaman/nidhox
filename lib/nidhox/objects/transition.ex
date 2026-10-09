defmodule Nidhox.Objects.Transition do
  @moduledoc """
  The game's `FinalFantasyVIIITransition`, kept across rooms: the screen washing out to
  white and wiping back as a match moves between rooms.

    * create: a 320 × 200 `canvas` cleared to white and its copy (`canvasCopy`);
      `counter` 0, `WIPE_TIME` 80, `wipeTo` 2; the wipe heard at the `Ear` (119)
    * step: `counter` counts; past `WIPE_TIME` the transition is gone. Otherwise the
      canvas is copied, and 40 times a strip of the copy is slid along the canvas and
      the gap it leaves painted black, at a random column (0–320) and row (0–200):
        * `wipeTo` 0: the 6-pixel row slid 26 pixels left and up 1, the right 26
          pixels of it black
        * `wipeTo` 1: the row slid 26 pixels right and up 1, the left 26 pixels black
        * `wipeTo` 2: the 6-pixel column slid 26 pixels up and left 1, its bottom 26
          pixels black; and the canvas black from `200 − counter / WIPE_TIME × 200`
          down to at least 100 below it
    * draw: the canvas added onto the view at the camera's top left
    * destroy: both surfaces freed

  `start/2` makes one wiping towards `wipe_to`.
  """

  alias Cauldron2D.GameMaker.{Draw, Surfaces, World}
  alias Nidhox.Bout.{Camera, Sound}
  alias Nidhox.Gml
  alias Nidhox.Objects.Ear

  @object "FinalFantasyVIIITransition"
  @width 320
  @height 200
  @wipe_time 80
  @strips 40
  @strip 6
  @slide 26
  @sound 119
  @white {255, 255, 255}
  @black {0, 0, 0}

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_#{@object}_Create_0", &start/3},
      {"gml_Object_#{@object}_Step_0", &step/3},
      {"gml_Object_#{@object}_Draw_0", &draw/3},
      {"gml_Object_#{@object}_Destroy_0", &finish/3}
    ]
  end

  @doc "`{id, world}` with a transition made, wiping towards `wipe_to` (0, 1 or 2)."
  @spec start(World.t(), 0 | 1 | 2) :: {non_neg_integer(), World.t()}
  def start(%World{} = world, wipe_to) do
    {world, id} = World.create(world, World.object_index(world, @object), {0, 0})
    {id, Gml.put(world, id, %{wipeTo: wipe_to})}
  end

  defp start(world, self, _other) do
    {world, canvas} = Surfaces.create(world, @width, @height)
    {world, copy} = Surfaces.create(world, @width, @height)

    world
    |> Surfaces.clear(canvas, @white, 1)
    |> Gml.put(self, %{counter: 0, canvas: canvas, canvasCopy: copy, WIPE_TIME: @wipe_time, wipeTo: 2})
    |> Sound.play(@sound, Ear.position(world))
  end

  defp step(world, self, _other) do
    counter = Gml.var(world, self, :counter) + 1
    world = Gml.put(world, self, %{counter: counter})

    if counter > Gml.var(world, self, :WIPE_TIME),
      do: World.destroy(world, self),
      else: wipe(world, self, counter)
  end

  defp wipe(world, self, counter) do
    canvas = Gml.var(world, self, :canvas)
    copy = Gml.var(world, self, :canvasCopy)
    wipe_to = Gml.var(world, self, :wipeTo)

    if Surfaces.exists?(world, canvas) do
      world = Surfaces.clear(world, copy, @black, 0)
      world = Surfaces.draw(world, copy, [Surfaces.item(world, canvas, {0, 0})])
      {strips, world} = strips(world, copy, wipe_to)
      Surfaces.draw(world, canvas, strips ++ rising(wipe_to, counter, Gml.var(world, self, :WIPE_TIME)))
    else
      world
    end
  end

  defp strips(world, copy, wipe_to) do
    Enum.reduce(1..@strips, {[], world}, fn _strip, {items, world} ->
      {column, world} = Gml.irandom(world, @width)
      {row, world} = Gml.irandom(world, @height)
      {items ++ strip(world, copy, wipe_to, column, row), world}
    end)
  end

  defp strip(world, copy, 2, column, _row) do
    slid = Surfaces.part_item(world, copy, {column, 0, @strip, @height}, {column - 1, -@slide})
    Enum.reject([slid, rectangle({column, @height - @slide, column + @strip, @height})], &is_nil/1)
  end

  defp strip(world, copy, 0, _column, row) do
    slid = Surfaces.part_item(world, copy, {0, row, @width, @strip}, {-@slide, row - 1})
    Enum.reject([slid, rectangle({@width - @slide, row, @width, row + @strip})], &is_nil/1)
  end

  defp strip(world, copy, 1, _column, row) do
    slid = Surfaces.part_item(world, copy, {0, row, @width, @strip}, {@slide, row - 1})
    Enum.reject([slid, rectangle({0, row, @slide, row + @strip})], &is_nil/1)
  end

  defp strip(_world, _copy, _wipe_to, _column, _row), do: []

  defp rising(2, counter, wipe_time) do
    top = @height - counter / wipe_time * @height
    [rectangle({0, top, @width, max(top + 100, @height)})]
  end

  defp rising(_wipe_to, _counter, _wipe_time), do: []

  defp rectangle({left, top, right, bottom}),
    do: %{picture: :pixel, position: {left, top}, scale: {right - left + 1, bottom - top + 1}, blend: @black}

  defp draw(world, self, _other) do
    canvas = Gml.var(world, self, :canvas)

    if Surfaces.exists?(world, canvas),
      do: Draw.item(world, Surfaces.item(world, canvas, {Camera.left(world), Camera.top(world)}, mode: :add)),
      else: world
  end

  defp finish(world, self, _other) do
    Enum.reduce([:canvas, :canvasCopy], world, fn name, world ->
      surface = Gml.var(world, self, name, -1)
      if Surfaces.exists?(world, surface), do: Surfaces.free(world, surface), else: world
    end)
  end
end
