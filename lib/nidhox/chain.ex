defmodule Nidhox.Chain do
  @moduledoc """
  The game's `drawChainXYXY(x1, y1, x2, y2, small)`: a chain drawn from draw code, links
  of `sChainLink` (`sMiniChain` when `small`) from `{x1, y1}` towards `{x2, y2}`, one
  every sprite height along the line while short of its length, each at frame 0.

      world = Nidhox.Chain.draw(world, {x, y}, {x, -5}, false)
  """

  alias Cauldron2D.GameMaker.{Data, Draw, World}
  alias Nidhox.Gml

  @doc "The world with a chain drawn from `from` towards `to`, of small links when `small`."
  @spec draw(World.t(), {number(), number()}, {number(), number()}, boolean()) :: World.t()
  def draw(%World{} = world, {x1, y1} = from, {x2, y2} = to, small) do
    link = Data.index(world.data, :sprites, if(small, do: "sMiniChain", else: "sChainLink"))
    {_width, height} = World.sprite(world, link).size
    length = :math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))
    direction = Gml.point_direction(from, to)

    0
    |> Stream.iterate(&(&1 + height))
    |> Enum.take_while(&(&1 < length))
    |> Enum.reduce(world, fn along, world ->
      Draw.sprite(world, link, 0, {x1 + Gml.lengthdir_x(along, direction), y1 + Gml.lengthdir_y(along, direction)})
    end)
  end
end
