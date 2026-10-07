defmodule Nidhox.Terrain do
  @moduledoc """
  What a fencer stands on and runs into in the current room: the shapes of every
  instance of `Block` and the objects descending from it (slopes, fallen and hanging
  blocks), and the one-way platforms of `PassThroughBlock`, which hold a body only while
  it falls onto them from above.

  A body is `body/1`'s rectangle: 8 pixels wide and 26 tall, standing on its position.
  `move/3` moves it by a velocity a pixel at a time, stopping each axis at the first
  pixel that would overlap something solid.
  """

  alias Cauldron2D.GameMaker.Collide
  alias Cauldron2D.GameMaker.World
  alias Cauldron2D.Overlap
  alias Cauldron2D.Shape

  @enforce_keys [:solids, :platforms, :size]
  defstruct [:solids, :platforms, :size]

  @type t :: %__MODULE__{solids: [Shape.t()], platforms: [Shape.t()], size: {number(), number()}}

  @body_width 8
  @body_height 26

  @doc "The terrain of the room `world` is in."
  @spec new(World.t()) :: t()
  def new(%World{} = world) do
    %__MODULE__{
      solids: shapes(world, "Block"),
      platforms: shapes(world, "PassThroughBlock"),
      size: Enum.at(world.data.rooms, world.room).size
    }
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
