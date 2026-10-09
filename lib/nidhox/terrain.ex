defmodule Nidhox.Terrain do
  @moduledoc """
  What a fencer stands on and runs into in the current room: the shapes of every
  instance of `Block` and the objects descending from it (slopes, fallen and hanging
  blocks), and the one-way platforms of `PassThroughBlock`, which hold a body only while
  it falls onto them from above. A conveyor (`Nidhox.Objects.Mines`) carries a body
  standing on it (`belt/2`). `ledges` are the corners the room marks with `Ledge`, each
  `{x, y, open}`, `open` the side, `1` right or `-1` left, where nothing solid is.
  `gravity` is how much of their weight bodies fall with here, `1.0` unless the bout's
  rules say otherwise.

  A body is `body/1`'s rectangle: 8 pixels wide and 26 tall, standing on its position.
  `move/3` moves it by a velocity a pixel at a time, stopping each axis at the first
  pixel that would overlap something solid.
  """

  alias Cauldron2D.GameMaker.Collide
  alias Cauldron2D.GameMaker.World
  alias Cauldron2D.Overlap
  alias Cauldron2D.Shape
  alias Nidhox.Objects.Mines

  @enforce_keys [:solids, :platforms, :size]
  defstruct [:solids, :platforms, :size, belts: [], ledges: [], gravity: 1.0]

  @type t :: %__MODULE__{
          solids: [Shape.t()],
          platforms: [Shape.t()],
          size: {number(), number()},
          belts: [{Shape.t(), number()}],
          ledges: [{number(), number(), 1 | -1}],
          gravity: number()
        }

  @body_width 8
  @body_height 26

  @doc "The terrain of the room `world` is in."
  @spec new(World.t()) :: t()
  def new(%World{} = world) do
    terrain = %__MODULE__{
      solids: shapes(world, "Block"),
      platforms: shapes(world, "PassThroughBlock"),
      belts: belts(world),
      ledges: [],
      size: Enum.at(world.data.rooms, world.room).size
    }

    %{terrain | ledges: ledges(world, terrain)}
  end

  @doc "The body standing at `{x, y}`."
  @spec body({number(), number()}) :: Shape.t()
  def body({x, y}) do
    Shape.new({:rectangle, @body_width, @body_height}, {x, y},
      origin: {@body_width / 2, @body_height}
    )
  end

  @doc "Whether a body at `position` overlaps anything solid."
  @spec blocked?(t(), {number(), number()}) :: boolean()
  def blocked?(%__MODULE__{solids: solids}, position) do
    body = body(position)
    Enum.any?(solids, &Overlap.shapes?(body, &1))
  end

  @doc "Whether the pixel at `point` is inside something solid."
  @spec solid?(t(), {number(), number()}) :: boolean()
  def solid?(%__MODULE__{solids: solids}, point),
    do: Enum.any?(solids, &Overlap.point?(&1, point))

  @doc """
  How fast the conveyor a body at `position` stands on carries it along x, in pixels a
  step; `0` when it stands on none.
  """
  @spec belt(t(), {number(), number()}) :: number()
  def belt(%__MODULE__{belts: belts}, {x, y}) do
    Enum.find_value(belts, 0, fn {shape, speed} ->
      if Overlap.point?(shape, {x, y + 1}), do: speed
    end)
  end

  @doc "Whether a body at `position` stands on something: solid ground or a platform."
  @spec grounded?(t(), {number(), number()}) :: boolean()
  def grounded?(%__MODULE__{} = terrain, {x, y}) do
    blocked?(terrain, {x, y + 1}) or on_platform?(terrain, {x, y})
  end

  @doc """
  A body at `position` moved by `{vx, vy}`: across first, then down or up, a pixel at a
  time. Gives the new position, the velocity with any axis that hit something zeroed,
  and whether the body now stands on something.
  """
  @spec move(t(), {number(), number()}, {number(), number()}) ::
          {{number(), number()}, {number(), number()}, boolean()}
  def move(%__MODULE__{} = terrain, {x, y}, {vx, vy}) do
    {x, vx} = slide(terrain, {x, y}, vx, :x)
    {y, vy} = fall(terrain, {x, y}, vy)
    {{x, y}, {vx, vy}, grounded?(terrain, {x, y})}
  end

  @doc """
  The ground's height under `x`: the lowest position a body dropped from the top of the
  room at `x` comes to rest on, `nil` where it would fall out of the room.
  """
  @spec ground(t(), number()) :: number() | nil
  def ground(%__MODULE__{size: {_width, height}} = terrain, x) do
    Enum.find(@body_height..(height + @body_height), fn y ->
      not blocked?(terrain, {x, y}) and grounded?(terrain, {x, y})
    end)
  end

  defp slide(_terrain, {x, _y}, vx, :x) when vx == 0, do: {x, vx}

  defp slide(terrain, {x, y}, vx, :x) do
    steps = ceil(abs(vx))
    each = vx / steps

    Enum.reduce_while(1..steps, {x, vx}, fn _step, {at, velocity} ->
      next = at + each

      if blocked?(terrain, {next, y}),
        do: {:halt, {at, 0.0}},
        else: {:cont, {next, velocity}}
    end)
  end

  defp fall(_terrain, {_x, y}, vy) when vy == 0, do: {y, vy}

  defp fall(terrain, {x, y}, vy) do
    steps = ceil(abs(vy))
    each = vy / steps

    Enum.reduce_while(1..steps, {y, vy}, fn _step, {at, velocity} ->
      next = at + each

      cond do
        blocked?(terrain, {x, next}) -> {:halt, {at, 0.0}}
        each > 0 and lands_on_platform?(terrain, x, at, next) -> {:halt, {at, 0.0}}
        true -> {:cont, {next, velocity}}
      end
    end)
  end

  defp on_platform?(terrain, {x, y}), do: lands_on_platform?(terrain, x, y, y + 1)

  defp lands_on_platform?(%__MODULE__{platforms: platforms}, x, from, to) do
    Enum.any?(platforms, fn platform ->
      {left, top, right, _bottom} = Shape.bounds(platform)
      x >= left and x <= right and from <= top and to > top
    end)
  end

  defp ledges(world, terrain) do
    case World.object_index(world, "Ledge") do
      nil ->
        []

      ledge ->
        for id <- World.instances_of(world, ledge),
            %{x: x, y: y} = World.fetch(world, id),
            do: {x, y, if(solid?(terrain, {x - 2, y + 2}), do: 1, else: -1)}
    end
  end

  defp belts(world) do
    case World.object_index(world, "Conveyor") do
      nil ->
        []

      conveyor ->
        for id <- World.instances_of(world, conveyor),
            instance = World.fetch(world, id),
            way = Mines.belt_way(World.object(world, instance.object).name),
            way != 0,
            shape = Collide.shape(world, instance, {instance.x, instance.y}),
            shape != nil,
            do: {shape, way * Mines.belt_speed()}
    end
  end

  defp shapes(world, name) do
    case World.object_index(world, name) do
      nil ->
        []

      object ->
        for id <- World.instances_of(world, object),
            instance = World.fetch(world, id),
            shape = Collide.shape(world, instance, {instance.x, instance.y}),
            shape != nil,
            do: shape
    end
  end
end
