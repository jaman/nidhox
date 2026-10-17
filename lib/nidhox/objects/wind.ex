defmodule Nidhox.Objects.Wind do
  @moduledoc """
  The wind surface (`WindSurface`), as the game's code keeps it: a churning cloud texture
  in the cemetery's sky and across the title.

    * create: a canvas and a second canvas (`canvasB`), each `@width` × `@height`, the canvas tiled with
      `bWindSurface`
    * step: the canvas is copied, then `@passes` times (`@low_passes` at `System.detail`
      `@low_detail`) a patch of the second canvas is drawn back onto the canvas: its middle at
      `random(width)`, `random(height)`, nudged by `random_range(1, 3)` and
      `random_range(−2, 1)` when its `type` is `"right"`, else by `random_range(−3, 3)`
      and `random_range(−2, 2)`, each side `random_range(30, 60)`; the instance stands at
      `room_width / 2 − (room_width / 2 − cameraCenterX) × 0.8 − @width / 2`, at the
      camera's top
    * draw: the canvas added at the instance's place, blend and alpha
    * destroy, room end and game end: its user event 15, both canvases freed

  The title's menu (`MainMenu`, `Nidhox.Objects.MainMenu`) makes one as it starts, at
  alpha 0.1.

  The random draws come from the world's generator in that order.
  """

  alias Cauldron2D.GameMaker.{Draw, Instance, Surfaces, World}
  alias Nidhox.{Assets, Gml}
  alias Nidhox.Bout.Camera
  alias Nidhox.Objects.System

  @texture "bWindSurface"
  @width 640
  @height 200
  @passes 10
  @low_passes 5
  @low_detail 9001
  @follow 0.8

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_WindSurface_Create_0", &start/3},
      {"gml_Object_WindSurface_Step_0", &churn/3},
      {"gml_Object_WindSurface_Draw_0", &draw/3},
      {"gml_Object_WindSurface_Other_25", &free/3},
      {"gml_Object_WindSurface_Destroy_0",
       fn world, self, _other -> World.perform(world, self, :other, 25) end},
      {"gml_Object_WindSurface_Other_5",
       fn world, self, _other -> World.perform(world, self, :other, 25) end},
      {"gml_Object_WindSurface_Other_3",
       fn world, self, _other -> World.perform(world, self, :other, 25) end}
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
    {world, second} = Surfaces.create(world, @width, @height)
    {texture, %{size: {tile_width, tile_height}}} = Assets.sprite!(@texture)

    tiles =
      for x <- 0..(@width - 1)//tile_width,
          y <- 0..(@height - 1)//tile_height,
          do: %{picture: {:sprite, texture, 0}, position: {x, y}, origin: {0, 0}}

    world
    |> Surfaces.draw(canvas, tiles)
    |> World.update(
      self,
      &%{&1 | vars: Map.merge(&1.vars, %{canvas: canvas, canvasB: second, type: "right"})}
    )
  end

  defp churn(world, self, other) do
    %Instance{vars: vars} = World.fetch(world, self)

    if Surfaces.exists?(world, vars.canvas) and Surfaces.exists?(world, vars.canvasB),
      do: churned(world, self, vars),
      else: start(world, self, other)
  end

  defp churned(world, self, %{canvas: canvas, canvasB: second, type: type}) do
    world = Surfaces.draw(world, second, [Surfaces.item(world, canvas, {0, 0})])

    passes = if System.get(world, :detail) == @low_detail, do: @low_passes, else: @passes

    {patches, world} =
      Enum.map_reduce(1..passes, world, fn _pass, world -> patch(world, second, type) end)

    world = Surfaces.draw(world, canvas, Enum.reject(patches, &is_nil/1))
    room_middle = Enum.at(world.data.rooms, world.room).size |> elem(0) |> Kernel./(2)
    x = room_middle - (room_middle - Camera.center_x(world)) * @follow - @width / 2
    World.update(world, self, &%{&1 | x: x, y: camera_top(world)})
  end

  defp patch(world, second, type) do
    {centre_x, world} = Gml.random(world, @width)
    {centre_y, world} = Gml.random(world, @height)
    {{dx, dy}, world} = nudge(world, type)
    {width, world} = Gml.random_range(world, 30, 60)
    {height, world} = Gml.random_range(world, 30, 60)
    left = centre_x - width / 2
    top = centre_y - height / 2

    {Surfaces.part_item(world, second, {left, top, width, height}, {left + dx, top + dy}), world}
  end

  defp nudge(world, "right") do
    {dx, world} = Gml.random_range(world, 1, 3)
    {dy, world} = Gml.random_range(world, -2, 1)
    {{dx, dy}, world}
  end

  defp nudge(world, _type) do
    {dx, world} = Gml.random_range(world, -3, 3)
    {dy, world} = Gml.random_range(world, -2, 2)
    {{dx, dy}, world}
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

  defp free(world, self, _other) do
    vars = World.fetch(world, self).vars

    [Map.get(vars, :canvas), Map.get(vars, :canvasB)]
    |> Enum.reduce(world, fn surface, world ->
      if surface != nil and Surfaces.exists?(world, surface),
        do: Surfaces.free(world, surface),
        else: world
    end)
  end

  defp camera_top(%World{views: [%{view: {_x, y, _width, _height}} | _]}), do: y
  defp camera_top(%World{}), do: 0
end
