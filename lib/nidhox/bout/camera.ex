defmodule Nidhox.Bout.Camera do
  @moduledoc """
  Where the game's camera looks, as its code asks and moves it: the first view of the
  room less the margins of the wide view (`Nidhox.Bout.Spiral`) (`cameraLeft`,
  `cameraTop`, `cameraRight`, `cameraBottom`, `screenHeight`, `screenWidth`,
  `cameraCenterX`, `cameraCenterY`, `setCameraLeftX`, `setCameraRightX`,
  `setCameraCenterX`, `setCameraCenterY`, `setCameraTopY`). With no view, the centre is
  the middle of the room and the setters change nothing.

  `put_center_y/2` holds the centre at least half the camera's height inside the room's
  top and bottom edges; the other setters place the view where they are told.
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.Bout.Spiral

  @doc "The left edge of the camera (`cameraLeft`)."
  @spec left(World.t()) :: number()
  def left(%World{} = world), do: elem(view(world), 0) + Spiral.margin_left(world)

  @doc "The top edge of the camera (`cameraTop`)."
  @spec top(World.t()) :: number()
  def top(%World{} = world), do: elem(view(world), 1) + Spiral.margin_y(world)

  @doc "The right edge of the camera (`cameraRight`)."
  @spec right(World.t()) :: number()
  def right(%World{} = world) do
    {x, _y, width, _height} = view(world)
    x + width - Spiral.margin_right(world)
  end

  @doc "The bottom edge of the camera (`cameraBottom`)."
  @spec bottom(World.t()) :: number()
  def bottom(%World{} = world), do: top(world) + height(world)

  @doc "The camera's width (`screenWidth`)."
  @spec width(World.t()) :: number()
  def width(%World{} = world),
    do: elem(view(world), 2) - Spiral.margin_left(world) - Spiral.margin_right(world)

  @doc "The camera's height (`screenHeight`)."
  @spec height(World.t()) :: number()
  def height(%World{} = world), do: elem(view(world), 3) - 2 * Spiral.margin_y(world)

  @doc "The room's width (`room_width`)."
  @spec room_width(World.t()) :: number()
  def room_width(%World{} = world), do: world |> room_size() |> elem(0)

  @doc "The middle of the view across (`cameraCenterX`); the middle of the room without a view."
  @spec center_x(World.t()) :: number()
  def center_x(%World{views: [%{view: {x, _y, width, _height}} | _]}), do: x + width * 0.5
  def center_x(%World{} = world), do: room_width(world) / 2

  @doc "The middle of the camera down (`cameraCenterY`)."
  @spec center_y(World.t()) :: number()
  def center_y(%World{} = world), do: top(world) + height(world) * 0.5

  @doc "The world with the camera's left edge at `x` (`setCameraLeftX`)."
  @spec put_left(World.t(), number()) :: World.t()
  def put_left(%World{} = world, x) do
    margin = Spiral.margin_left(world)
    move(world, fn {_x, y, w, h} -> {x - margin, y, w, h} end)
  end

  @doc "The world with the camera's right edge at `x` (`setCameraRightX`)."
  @spec put_right(World.t(), number()) :: World.t()
  def put_right(%World{} = world, x) do
    margin = Spiral.margin_right(world)
    move(world, fn {_x, y, w, h} -> {x - w + margin, y, w, h} end)
  end

  @doc "The world with the view's middle across at `x` (`setCameraCenterX`)."
  @spec put_center_x(World.t(), number()) :: World.t()
  def put_center_x(%World{} = world, x),
    do: move(world, fn {_x, y, w, h} -> {x - w * 0.5, y, w, h} end)

  @doc "The world with the camera's top edge at `y` (`setCameraTopY`)."
  @spec put_top(World.t(), number()) :: World.t()
  def put_top(%World{} = world, y) do
    margin = Spiral.margin_y(world)
    move(world, fn {x, _y, w, h} -> {x, y - margin, w, h} end)
  end

  @doc "The world with the camera's middle down at `y`, kept inside the room (`setCameraCenterY`)."
  @spec put_center_y(World.t(), number()) :: World.t()
  def put_center_y(%World{} = world, y) do
    room_height = room_size(world) |> elem(1)
    camera_height = height(world)
    margin = Spiral.margin_y(world)

    centre =
      y
      |> max(camera_height / 2 + margin)
      |> min(room_height - camera_height / 2 - margin)

    move(world, fn {x, _y, w, h} -> {x, centre - camera_height * 0.5 - margin, w, h} end)
  end

  defp move(%World{views: [%{view: rectangle} | _]} = world, place),
    do: World.put_view(world, 0, place.(rectangle))

  defp move(%World{} = world, _place), do: world

  defp view(%World{views: [%{view: rectangle} | _]}), do: rectangle
  defp view(%World{} = world), do: {0, 0, room_width(world), 200}

  defp room_size(world), do: world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size)
end
