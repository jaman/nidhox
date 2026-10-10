defmodule Nidhox.Bout.Camera do
  @moduledoc """
  Where the game's camera looks, as its code asks and moves it: the first view of the
  room (`cameraLeft`, `cameraTop`, `cameraRight`, `cameraBottom`, `screenHeight`,
  `screenWidth`, `cameraCenterX`, `cameraCenterY`,
  `setCameraLeftX`, `setCameraRightX`, `setCameraCenterX`, `setCameraCenterY`). With
  no view, the centre is the middle of the room and the setters change nothing.

  `put_center_y/2` holds the centre at least half the view's height inside the room's
  top and bottom edges; the other setters place the view where they are told.
  """

  alias Cauldron2D.GameMaker.World

  @doc "The left edge of the view (`cameraLeft`)."
  @spec left(World.t()) :: number()
  def left(%World{} = world), do: elem(view(world), 0)

  @doc "The top edge of the view (`cameraTop`)."
  @spec top(World.t()) :: number()
  def top(%World{} = world), do: elem(view(world), 1)

  @doc "The right edge of the view (`cameraRight`)."
  @spec right(World.t()) :: number()
  def right(%World{} = world) do
    {x, _y, width, _height} = view(world)
    x + width
  end

  @doc "The bottom edge of the view (`cameraBottom`)."
  @spec bottom(World.t()) :: number()
  def bottom(%World{} = world) do
    {_x, y, _width, height} = view(world)
    y + height
  end

  @doc "The view's width (`screenWidth`)."
  @spec width(World.t()) :: number()
  def width(%World{} = world), do: elem(view(world), 2)

  @doc "The view's height (`screenHeight`)."
  @spec height(World.t()) :: number()
  def height(%World{} = world), do: elem(view(world), 3)

  @doc "The room's width (`room_width`)."
  @spec room_width(World.t()) :: number()
  def room_width(%World{} = world), do: world |> room_size() |> elem(0)

  @doc "The middle of the view across (`cameraCenterX`); the middle of the room without a view."
  @spec center_x(World.t()) :: number()
  def center_x(%World{views: [%{view: {x, _y, width, _height}} | _]}), do: x + width * 0.5
  def center_x(%World{} = world), do: room_width(world) / 2

  @doc "The middle of the view down (`cameraCenterY`)."
  @spec center_y(World.t()) :: number()
  def center_y(%World{} = world) do
    {_x, y, _width, height} = view(world)
    y + height * 0.5
  end

  @doc "The world with the view's left edge at `x` (`setCameraLeftX`)."
  @spec put_left(World.t(), number()) :: World.t()
  def put_left(%World{} = world, x), do: move(world, fn {_x, y, w, h} -> {x, y, w, h} end)

  @doc "The world with the view's right edge at `x` (`setCameraRightX`)."
  @spec put_right(World.t(), number()) :: World.t()
  def put_right(%World{} = world, x), do: move(world, fn {_x, y, w, h} -> {x - w, y, w, h} end)

  @doc "The world with the view's middle across at `x` (`setCameraCenterX`)."
  @spec put_center_x(World.t(), number()) :: World.t()
  def put_center_x(%World{} = world, x),
    do: move(world, fn {_x, y, w, h} -> {x - w * 0.5, y, w, h} end)

  @doc "The world with the view's middle down at `y`, kept inside the room (`setCameraCenterY`)."
  @spec put_center_y(World.t(), number()) :: World.t()
  def put_center_y(%World{} = world, y) do
    room_height = room_size(world) |> elem(1)

    move(world, fn {x, _y, w, h} ->
      centre = y |> max(h / 2) |> min(room_height - h / 2)
      {x, centre - h * 0.5, w, h}
    end)
  end

  defp move(%World{views: [%{view: rectangle} | _]} = world, place),
    do: World.put_view(world, 0, place.(rectangle))

  defp move(%World{} = world, _place), do: world

  defp view(%World{views: [%{view: rectangle} | _]}), do: rectangle
  defp view(%World{} = world), do: {0, 0, room_width(world), 200}

  defp room_size(world), do: world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size)
end
