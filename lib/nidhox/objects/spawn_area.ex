defmodule Nidhox.Objects.SpawnArea do
  @moduledoc """
  The game's `SpawnArea`: a stretch of ground where fencers come back. Made, it lays a
  `RespawnPoint` every 16 pixels along its width, starting at its left, on its bottom
  edge (`instance_create(x + i × 16, y + sprite_height, RespawnPoint)` for `i` below
  `sprite_width / 16`).
  """

  alias Cauldron2D.GameMaker.{Instance, World}

  @spacing 16

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers, do: [{"gml_Object_SpawnArea_Create_0", &start/3}]

  defp start(world, self, _other) do
    %Instance{x: x, y: y, sprite_index: sprite, image_xscale: xscale, image_yscale: yscale} =
      World.fetch(world, self)

    {width, height} = size(world, sprite)
    point = World.object_index(world, "RespawnPoint")

    0
    |> Stream.iterate(&(&1 + 1))
    |> Enum.take_while(&(&1 < width * xscale / @spacing))
    |> Enum.reduce(world, fn i, world ->
      world |> World.create(point, {x + i * @spacing, y + height * yscale}) |> elem(0)
    end)
  end

  defp size(world, sprite) do
    case World.sprite(world, sprite) do
      nil -> {0, 0}
      definition -> definition.size
    end
  end
end
