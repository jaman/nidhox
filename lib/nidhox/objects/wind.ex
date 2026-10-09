defmodule Nidhox.Objects.Wind do
  @moduledoc """
  The wind surface (`WindSurface`), as the game's code keeps it: a churning cloud texture
  in the cemetery's sky and across the title.

    * create: a canvas and a copy, each `@width` × `@height`, the canvas tiled with
      `bWindSurface`
    * step: the canvas is copied, then `@passes` times a random patch of the copy, each
      side `random_range(30, 60)`, is drawn back onto the canvas nudged by
      `random_range(1, 3)` and `random_range(−2, 1)` when its `type` is `"right"`, else by
      `random_range(−3, 3)` and `random_range(−2, 2)`; the instance stands at
      `room_width / 2 − (room_width / 2 − cameraCenterX) × 0.8 − @width / 2`, at the
      camera's top
    * draw: the canvas added at the instance's place, blend and alpha

  The title's menu (`MainMenu`) makes one as it starts, at alpha `@title_alpha`.

  The random draws come from the step, the instance and the pass, not GameMaker's
  generator.

  The castle's fire clouds (`oFireClouds`) are drawn as `bWindSurface` tiled across the
  view, added in `@fire` at `@fire_alpha`, carried leftward at `@fire_drift` pixels a
  step.
  """

  alias Cauldron2D.GameMaker.{Draw, Instance, Surfaces, World}
  alias Nidhox.{Assets, Parallax}

  @texture "bWindSurface"
  @width 640
  @height 200
  @passes 5
  @follow 0.8
  @fire {255, 120, 50}
  @fire_alpha 0.12
  @fire_drift 0.25
  @title_alpha 0.1

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_WindSurface_Create_0", &start/3},
      {"gml_Object_WindSurface_Step_0", &churn/3},
      {"gml_Object_WindSurface_Draw_0", &draw/3},
      {"gml_Object_oFireClouds_Draw_0", &fire/3},
      {"gml_Object_MainMenu_Create_0", fn world, _self, _other -> create(world, @title_alpha) end}
    ]
  end

  @doc "`world` with a wind surface made at `{0, 0}` whose alpha is `alpha`, as the title's menu makes one."
  @spec create(World.t(), number()) :: World.t()
  def create(%World{} = world, alpha) do
    case World.object_index(world, "WindSurface") do
      nil ->
        world

      object ->
        {world, id} = World.create(world, object, {0, 0})
        World.update(world, id, &%{&1 | image_alpha: alpha})
    end
  end

  defp start(world, self, _other) do
    {world, canvas} = Surfaces.create(world, @width, @height)
    {world, copy} = Surfaces.create(world, @width, @height)
    {texture, %{size: {tile_width, tile_height}}} = Assets.sprite!(@texture)

    tiles =
      for x <- 0..(@width - 1)//tile_width,
          y <- 0..(@height - 1)//tile_height,
          do: %{picture: {:sprite, texture, 0}, position: {x, y}, origin: {0, 0}}

    world
    |> Surfaces.draw(canvas, tiles)
    |> World.update(
      self,
      &%{&1 | vars: Map.merge(&1.vars, %{canvas: canvas, copy: copy, type: "right"})}
    )
  end

  defp churn(world, self, other) do
    %Instance{vars: vars} = World.fetch(world, self)

    if Surfaces.exists?(world, vars.canvas) and Surfaces.exists?(world, vars.copy),
      do: churned(world, self, vars),
      else: start(world, self, other)
  end

  defp churned(world, self, %{canvas: canvas, copy: copy, type: type}) do
    world = Surfaces.draw(world, copy, [Surfaces.item(world, canvas, {0, 0})])

    patches =
      for pass <- 1..@passes,
          patch = patch(world, self, copy, type, pass),
          patch != nil,
          do: patch

    world = Surfaces.draw(world, canvas, patches)
    room_middle = Enum.at(world.data.rooms, world.room).size |> elem(0) |> Kernel./(2)
    x = room_middle - (room_middle - Parallax.camera_center_x(world)) * @follow - @width / 2
    World.update(world, self, &%{&1 | x: x, y: camera_top(world)})
  end

  defp patch(world, self, copy, type, pass) do
    random = fn key, low, high ->
      low + :erlang.phash2({world.steps, self, pass, key}, 1_000_000) / 1_000_000 * (high - low)
    end

    {dx, dy} =
      if type == "right",
        do: {random.(:dx, 1, 3), random.(:dy, -2, 1)},
        else: {random.(:dx, -3, 3), random.(:dy, -2, 2)}

    centre_x = random.(:x, 0, @width)
    centre_y = random.(:y, 0, @height)
    width = random.(:width, 30, 60)
    height = random.(:height, 30, 60)
    left = centre_x - width / 2
    top = centre_y - height / 2

    Surfaces.part_item(world, copy, {left, top, width, height}, {left + dx, top + dy})
  end

  defp draw(world, self, _other) do
    %Instance{x: x, image_alpha: alpha, image_blend: blend, vars: vars, depth: depth} =
      World.fetch(world, self)

    if Surfaces.exists?(world, Map.get(vars, :canvas)),
      do:
        Draw.item(
          world,
          Surfaces.item(world, vars.canvas, {x, camera_top(world)},
            mode: :add,
            alpha: alpha,
            blend: blend,
            depth: depth
          )
        ),
      else: world
  end

  defp fire(world, self, _other) do
    {view_x, view_y, view_width, view_height} = view(world)
    {texture, %{size: {width, height}}} = Assets.sprite!(@texture)
    depth = World.fetch(world, self).depth
    shift = world.steps * @fire_drift

    for column <- spans(view_x + shift, view_width, width),
        row <- spans(view_y, view_height, height),
        reduce: world do
      world ->
        Draw.item(world, %{
          picture: {:sprite, texture, 0},
          position: {column - shift, row},
          alpha: @fire_alpha,
          mode: :add,
          blend: @fire,
          depth: depth
        })
    end
  end

  defp spans(from, length, size) do
    first = floor(from / size) * size
    Enum.take_while(Stream.iterate(first, &(&1 + size)), &(&1 < from + length))
  end

  defp camera_top(%World{views: [%{view: {_x, y, _width, _height}} | _]}), do: y
  defp camera_top(%World{}), do: 0

  defp view(%World{views: [%{view: rectangle} | _]}), do: rectangle
  defp view(%World{}), do: {0, 0, 320, 200}
end
