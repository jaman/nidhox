defmodule Nidhox.Sprites do
  @moduledoc """
  The fencers' pictures, cut from the player's copy and tinted, for `Nidhox.Look`:

    * `{:body, side, sprite, frame}` — every frame of every body sprite a pose uses
      (`Nidhox.Pose.bodies/0`), its white painted in side `1`'s yellow or side `2`'s
      orange
    * `:sword` and `:flying_sword` — `sSword` and `sFlyingSword` in steel, for swords
      in play
    * `{:shadow, sprite}` — the first frame of each of `@shadows` as cover: white, each
      pixel as opaque as it is bright, the brightest pixel fully opaque

  `Nidhox.Assets.load/1` merges `table/2` into the pictures it installs.
  """

  alias Cauldron2D.GameMaker.Data
  alias Cauldron2D.GameMaker.Pictures
  alias FrenchCurve.Raster

  @white {255, 255, 255}
  @sides %{1 => {245, 205, 70}, 2 => {240, 120, 45}}
  @steel {214, 218, 228}
  @shadows ["bWindSurface"]

  @doc "Every fencer and sword picture of the copy's `data`, cut from its decoded `pages`."
  @spec table(Pictures.t(), Data.t()) :: %{term() => Raster.t()}
  def table(%Pictures{} = pages, %Data{} = data) do
    bodies =
      for name <- Nidhox.Pose.bodies(),
          {frame, index} <- Enum.with_index(frames(pages, data, name)),
          {side, colour} <- @sides,
          do: {{:body, side, name, index}, tint(frame, colour)}

    swords = [
      {:sword, pages |> frames(data, "sSword") |> hd() |> tint(@steel)},
      {:flying_sword, pages |> frames(data, "sFlyingSword") |> hd() |> tint(@steel)}
    ]

    shadows =
      for name <- @shadows, do: {{:shadow, name}, pages |> frames(data, name) |> hd() |> shadow()}

    Map.new(bodies ++ swords ++ shadows)
  end

  defp frames(pages, data, name) do
    case Data.index(data, :sprites, name) do
      nil -> raise ArgumentError, "the copy has no sprite named #{inspect(name)}"
      index -> Pictures.sprite(pages, Enum.at(data.sprites, index))
    end
  end

  defp shadow(raster) do
    {width, height} = Raster.dimensions(raster)
    rgba = Raster.to_rgba_binary(raster)

    brightest =
      for(<<r, g, b, _a <- rgba>>, reduce: 1, do: (most -> max(most, max(r, max(g, b)))))

    cover =
      for <<r, g, b, a <- rgba>>,
        into: <<>>,
        do: <<255, 255, 255, div(max(r, max(g, b)) * a, brightest)>>

    Raster.from_rgba(width, height, cover)
  end

  defp tint(raster, {red, green, blue}) do
    {width, height} = Raster.dimensions(raster)
    {white_r, white_g, white_b} = @white

    rgba =
      for <<r, g, b, a <- Raster.to_rgba_binary(raster)>>, into: <<>> do
        if {r, g, b} == {white_r, white_g, white_b},
          do: <<red, green, blue, a>>,
          else: <<r, g, b, a>>
      end

    Raster.from_rgba(width, height, rgba)
  end
end
