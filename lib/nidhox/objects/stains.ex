defmodule Nidhox.Objects.Stains do
  @moduledoc """
  Blood that stays where it lands (`BloodSurface`). Each `BloodSurface` instance covers
  a stretch of ground — its `sBloodSurface` sprite, 32 pixels square, scaled over it —
  and keeps the stains made there in its `:stains`, each `{x, y, colour}`, the newest
  first, at most `@most`. It draws its stains as squares `@size` pixels a side in their
  colours, never its own sprite.

  `soak/1` takes every blood drop (`Nidhox.Blood`'s particles of kind `:blood_drop`)
  that has reached a stretch out of the air and stains the stretch where it is.
  """

  alias Cauldron2D.GameMaker.{Draw, Particles, World}

  @object "BloodSurface"
  @side 32
  @most 600
  @size 2

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers, do: [{"gml_Object_BloodSurface_Draw_0", &draw/3}]

  @doc "`world` with the blood drops inside a stretch of ground turned into its stains."
  @spec soak(World.t()) :: World.t()
  def soak(%World{} = world) do
    case surfaces(world) do
      [] ->
        world

      surfaces ->
        {drops, world} =
          Particles.take(
            world,
            &(Map.get(&1, :kind) == :blood_drop and covering(surfaces, &1) != nil)
          )

        Enum.reduce(drops, world, &stain(&2, covering(surfaces, &1), &1))
    end
  end

  defp surfaces(world) do
    case World.object_index(world, @object) do
      nil ->
        []

      object ->
        for id <- World.instances_of(world, object), do: {id, area(World.fetch(world, id))}
    end
  end

  defp area(surface),
    do:
      {surface.x, surface.y, surface.x + @side * surface.image_xscale,
       surface.y + @side * surface.image_yscale}

  defp covering(surfaces, %{position: {x, y}}) do
    Enum.find_value(surfaces, fn {id, {left, top, right, bottom}} ->
      if x >= left and x < right and y >= top and y < bottom, do: id
    end)
  end

  defp stain(world, id, %{position: {x, y}} = drop) do
    stain = {round(x), round(y), Map.get(drop, :blend, {255, 255, 255})}

    World.update(world, id, fn surface ->
      stains = [stain | Map.get(surface.vars, :stains, [])] |> Enum.take(@most)
      %{surface | vars: Map.put(surface.vars, :stains, stains)}
    end)
  end

  defp draw(world, self, _other) do
    world
    |> World.fetch(self)
    |> Map.fetch!(:vars)
    |> Map.get(:stains, [])
    |> Enum.reduce(world, fn {x, y, colour}, world ->
      Draw.item(world, %{
        picture: :pixel,
        position: {x - div(@size, 2), y - div(@size, 2)},
        scale: {@size, @size},
        blend: colour
      })
    end)
  end
end
