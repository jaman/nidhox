defmodule Nidhox.Art do
  @moduledoc """
  Per-side color maps for fencer bodies and swords, extracted from the original game files.

  Body colors use three shades:
    * `B` — base (main body fill)
    * `D` — dark (shadows, boots, details)
    * `H` — highlight (head, raised details)

  Steel (swords) uses two shades:
    * `S` — bright steel
    * `G` — gold/bronze accents

  These maps are used to colourise extracted GameMaker rasters — white and near-white
  pixels become the appropriate side colour, other pixels are passed through.

      # Build the table: body_frames(pics, sprites)
      #                 |> Enum.map(&colorize(&1, Map.to_list(@colours[1])))

  ## Usage

      table = Nidhox.Sprites.table()
      raster = Map.fetch!(table, {:stand, 1, 0})  # yellow, stand, frame 0
  """

  @doc "Body colour maps for each side."
  @spec colours() :: %{
          1 => %{
            B: {integer(), integer(), integer()},
            D: {integer(), integer(), integer()},
            H: {integer(), integer(), integer()}
          },
          2 => %{
            B: {integer(), integer(), integer()},
            D: {integer(), integer(), integer()},
            H: {integer(), integer(), integer()}
          }
        }
  def colours do
    %{
      1 => %{B: {245, 205, 70}, D: {170, 130, 30}, H: {255, 236, 160}},
      2 => %{B: {240, 120, 45}, D: {160, 70, 20}, H: {255, 190, 140}}
    }
  end

  @doc "Steel colour map for swords (not tinted by side)."
  @spec steel() :: %{S: {integer(), integer(), integer()}, G: {integer(), integer(), integer()}}
  def steel do
    %{S: {214, 218, 228}, G: {130, 96, 46}}
  end

  @doc "All body colours (no mapping) as a keyword list."
  @spec body_colours() :: [{atom(), {integer(), integer(), integer()}}]
  def body_colours do
    Map.to_list(colours()[1]) ++ Map.to_list(colours()[2])
  end
end
