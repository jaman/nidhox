defmodule Nidhox.Objects.Torches do
  @moduledoc """
  The candles and torches (`Torch`, `TorchDark`, `WallTorch`): each step a flame burns
  on every tip of the candle's sprite, as particles of the copy's `sTorch` — a flame
  rises from a tip every `@flame_every` steps, playing its frames once as it goes — and
  now and then an ember (`sEmber`) drifts up and away.

  A tip is a column of the candle's first frame whose topmost pixel stands higher than
  or as high as every column within `@apart` pixels of it, the leftmost of a flat top,
  found once per sprite and kept. Which tip
  burns and how each flame and ember wanders is drawn from the instance id and the
  step, so every machine sees the same fire.
  """

  alias Cauldron2D.GameMaker.Instance
  alias Cauldron2D.GameMaker.Particles
  alias Cauldron2D.GameMaker.World
  alias Nidhox.Assets

  @flame_every 3
  @flame_rise -0.35
  @flame_sway 0.15
  @ember_one_in 24
  @ember_rise -0.6
  @ember_life 45
  @apart 2

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Torch_Step_0", &burn/3},
      {"gml_Object_WallTorch_Step_0", &burn/3}
    ]
  end

  @doc "The tips of frame 0 of sprite `name`, `{dx, dy}` from its origin, left to right."
  @spec tips(String.t()) :: [{integer(), integer()}]
  def tips(name) do
    key = {__MODULE__, :tips, name}

    case :persistent_term.get(key, nil) do
      nil ->
        tips = find_tips(name)
        :persistent_term.put(key, tips)
        tips

      tips ->
        tips
    end
  end

  defp burn(world, self, _other) do
    %Instance{x: x, y: y, sprite_index: sprite, depth: depth} = World.fetch(world, self)
    name = Enum.at(world.data.sprites, sprite).name
    world |> flames(self, {x, y}, tips(name), depth) |> ember(self, {x, y}, tips(name), depth)
  end

  defp flames(world, self, {x, y}, tips, depth) do
    if rem(world.steps + self, @flame_every) == 0 do
      Enum.reduce(tips, world, fn {dx, dy}, world ->
        {flame, sprite} = Assets.sprite!("sTorch")
        frames = length(sprite.frames)
        sway = (:erlang.phash2({self, dx, world.steps}, 21) - 10) / 10 * @flame_sway

        Particles.create(world, %{
          sprite: flame,
          position: {x + dx, y + dy},
          velocity: {sway, @flame_rise},
          life: frames * 2,
          frame_speed: 0.5,
          depth: depth - 1
        })
      end)
    else
      world
    end
  end

  defp ember(world, _self, _at, [], _depth), do: world

  defp ember(world, self, {x, y}, tips, depth) do
    if :erlang.phash2({self, world.steps, :ember}, @ember_one_in) == 0 do
      {dx, dy} = Enum.at(tips, :erlang.phash2({self, world.steps}, length(tips)))
      {spark, sprite} = Assets.sprite!("sEmber")
      sway = (:erlang.phash2({self, world.steps, :sway}, 21) - 10) / 20

      Particles.create(world, %{
        sprite: spark,
        position: {x + dx, y + dy},
        velocity: {sway, @ember_rise},
        life: @ember_life,
        frame_speed: length(sprite.frames) / @ember_life,
        alpha: {1.0, 0.0},
        depth: depth - 1
      })
    else
      world
    end
  end

  defp find_tips(name) do
    {index, %{origin: {origin_x, origin_y}}} = Assets.sprite!(name)
    raster = Map.fetch!(Assets.get().pictures, {:sprite, index, 0})
    {width, _height} = FrenchCurve.Raster.dimensions(raster)
    tops = tops(raster, width)

    for {column, top} <- Enum.with_index(tops) |> Enum.map(fn {top, column} -> {column, top} end),
        top != nil,
        higher?(tops, column, top),
        do: {column - origin_x, top - origin_y}
  end

  defp tops(raster, width) do
    raster
    |> FrenchCurve.Raster.to_rgba_binary()
    |> then(&for(<<_r, _g, _b, a <- &1>>, do: a > 0))
    |> Enum.chunk_every(width)
    |> Enum.zip_with(& &1)
    |> Enum.map(&Enum.find_index(&1, fn opaque -> opaque end))
  end

  defp higher?(tops, column, top) do
    neighbours =
      for near <- (column - @apart)..(column + @apart),
          near != column,
          near >= 0,
          do: Enum.at(tops, near)

    left = if column > 0, do: Enum.at(tops, column - 1)
    Enum.all?(neighbours, &(&1 == nil or &1 >= top)) and (left == nil or left > top)
  end
end
