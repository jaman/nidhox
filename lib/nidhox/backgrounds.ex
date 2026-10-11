defmodule Nidhox.Backgrounds do
  @moduledoc """
  The game's compatibility scripts for a room's backgrounds, on the room's layers.

  Background `n` is the layer named `Compatibility_Background_<n>_…` or
  `Compatibility_Foreground_<n>_…`. `set/4` (`__background_set(property, n, value)`) and
  `get/3` (`__background_get(property, n)`) change and read one of its properties, by
  the game's numbers: 0 visible, 2 sprite, 3 x, 4 y, 7 tiled across, 8 tiled down, 9
  x scale, 10 y scale, 11 speed across, 12 speed down, 13 blend, 14 alpha. A room
  without that layer is left as it is, and reads give 0. `colour/1` is
  `__background_get_colour`, the colour of the layer named `Compatibility_Colour`.
  """

  alias Cauldron2D.GameMaker.Room.Layer
  alias Cauldron2D.GameMaker.World

  @colour_layer "Compatibility_Colour"

  @doc "The room's background colour (`__background_get_colour`), black without a colour layer."
  @spec colour(World.t()) :: {byte(), byte(), byte()}
  def colour(%World{} = world) do
    case Enum.find(World.layers(world), &(&1.name == @colour_layer)) do
      %Layer{content: {:background, %{colour: {red, green, blue, _alpha}}}} -> {red, green, blue}
      _none -> {0, 0, 0}
    end
  end

  @doc "The world with property `property` of background `index` set to `value` (`__background_set`)."
  @spec set(World.t(), non_neg_integer(), non_neg_integer(), term()) :: World.t()
  def set(%World{} = world, property, index, value) do
    case layer(world, index) do
      nil -> world
      %Layer{} = layer -> World.put_layer(world, layer.name, change(layer, property, value))
    end
  end

  @doc "Property `property` of background `index` (`__background_get`), 0 without the layer."
  @spec get(World.t(), non_neg_integer(), non_neg_integer()) :: term()
  def get(%World{} = world, property, index) do
    case layer(world, index) do
      nil -> 0
      %Layer{} = layer -> read(layer, property)
    end
  end

  defp layer(world, index) do
    Enum.find(World.layers(world), fn %Layer{name: name, content: content} ->
      match?({:background, _}, content) and
        Regex.match?(~r/^Compatibility_(Background|Foreground)_#{index}(_|$)/, name)
    end)
  end

  defp change(_layer, 0, value),
    do: %{visible: truthy?(value), background: %{visible: truthy?(value)}}

  defp change(_layer, 2, value), do: %{background: %{sprite: round(value)}}
  defp change(%Layer{offset: {_x, y}}, 3, value), do: %{offset: {value, y}}
  defp change(%Layer{offset: {x, _y}}, 4, value), do: %{offset: {x, value}}

  defp change(%Layer{content: {:background, %{tiled: {_across, down}}}}, 7, value),
    do: %{background: %{tiled: {truthy?(value), down}}}

  defp change(%Layer{content: {:background, %{tiled: {across, _down}}}}, 8, value),
    do: %{background: %{tiled: {across, truthy?(value)}}}

  defp change(_layer, 9, value), do: %{background: %{xscale: value}}
  defp change(_layer, 10, value), do: %{background: %{yscale: value}}
  defp change(%Layer{speed: {_across, down}}, 11, value), do: %{speed: {value, down}}
  defp change(%Layer{speed: {across, _down}}, 12, value), do: %{speed: {across, value}}

  defp change(
         %Layer{content: {:background, %{colour: {_r, _g, _b, alpha}}}},
         13,
         {red, green, blue}
       ),
       do: %{background: %{colour: {red, green, blue, alpha}}}

  defp change(%Layer{content: {:background, %{colour: {red, green, blue, _alpha}}}}, 14, value),
    do: %{background: %{colour: {red, green, blue, round(value * 255)}}}

  defp change(_layer, _property, _value), do: %{}

  defp read(%Layer{visible: visible}, 0), do: if(visible, do: 1, else: 0)
  defp read(%Layer{content: {:background, %{sprite: sprite}}}, 2), do: sprite
  defp read(%Layer{offset: {x, _y}}, 3), do: x
  defp read(%Layer{offset: {_x, y}}, 4), do: y

  defp read(%Layer{content: {:background, %{tiled: {across, _down}}}}, 7),
    do: if(across, do: 1, else: 0)

  defp read(%Layer{content: {:background, %{tiled: {_across, down}}}}, 8),
    do: if(down, do: 1, else: 0)

  defp read(%Layer{content: {:background, background}}, 9), do: Map.get(background, :xscale, 1)
  defp read(%Layer{content: {:background, background}}, 10), do: Map.get(background, :yscale, 1)
  defp read(%Layer{speed: {across, _down}}, 11), do: across
  defp read(%Layer{speed: {_across, down}}, 12), do: down

  defp read(%Layer{content: {:background, %{colour: {red, green, blue, _alpha}}}}, 13),
    do: {red, green, blue}

  defp read(%Layer{content: {:background, %{colour: {_red, _green, _blue, alpha}}}}, 14),
    do: alpha / 255

  defp read(_layer, _property), do: 0

  defp truthy?(value), do: value > 0.5
end
