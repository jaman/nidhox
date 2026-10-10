defmodule Nidhox.Objects.DarkenClouds do
  @moduledoc """
  The clouds' `DarkenClouds`, as the game's code runs it: each step it tints the clouds
  and the cloud tiles towards the room's background colour, the tint drifting with the
  `System`'s frame.

    * create: the tile layer at depth 100 (`layer_get_id_at_depth(100)`), whose tiles it
      tints
    * step: with `amount` `0.4 + sin(frame / 60) × 0.25` and `cool`
      `make_color_hsv(200 + cos(frame / 80) × 20, 100, 255)`, every `CloudPoof`,
      `FakeCloudPoof`, `NewCloudBlock` and `DefensiveBlock` is blended with
      `merge_color(cool, background, amount)`, and the layer's tiles with
      `merge_color(cool, merge_color(background, warm, 0.5), amount)`, where `warm` is
      `make_color_hsv(40 + sin(frame / 70) × 20, 120, 255)` and `background` the room's
      background colour (`__background_get_colour`)
  """

  alias Cauldron2D.GameMaker.{Colour, World}
  alias Nidhox.{Backgrounds, Gml}
  alias Nidhox.Objects.System

  @tile_depth 100
  @tinted ["CloudPoof", "FakeCloudPoof", "NewCloudBlock", "DefensiveBlock"]

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_DarkenClouds_Create_0", &start/3},
      {"gml_Object_DarkenClouds_Step_0", &tint/3}
    ]
  end

  defp start(world, self, _other) do
    layer = Enum.find(World.layers(world), &(&1.depth == @tile_depth))
    Gml.put(world, self, %{layer: layer && layer.name})
  end

  defp tint(world, self, _other) do
    frame = System.get(world, :frame)
    amount = 0.4 + :math.sin(frame / 60) * 0.25
    cool = Colour.hsv(200 + :math.cos(frame / 80) * 20, 100, 255)
    background = Backgrounds.colour(world)
    warm = Colour.hsv(40 + :math.sin(frame / 70) * 20, 120, 255)
    clouds = Colour.merge(cool, background, amount)
    tiles = Colour.merge(cool, Colour.merge(background, warm, 0.5), amount)

    @tinted
    |> Enum.flat_map(&Gml.all(world, &1))
    |> Enum.reduce(world, fn cloud, world -> World.update(world, cloud, &%{&1 | image_blend: clouds}) end)
    |> blend_tiles(Gml.var(world, self, :layer, nil), tiles)
  end

  defp blend_tiles(world, nil, _colour), do: world
  defp blend_tiles(world, layer, colour), do: World.put_layer(world, layer, %{tile_blend: colour})
end
