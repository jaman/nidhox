defmodule Nidhox.Screen.Credits do
  @moduledoc """
  The credits over `rCredits`, as the game's `Credits` shows them: the copy's own
  `credits.txt`, from beside its data file, every line of it followed by " #", in
  upper case `fMenu`, centred, 316 wide, its lines 20 apart. They start 64 above the
  view's bottom and rise 0.3 a step, in `make_color_hsv(hue, 180, 255)`, `hue` being
  `sin(frame / 60) × 10` taken round 255. They stay until `:attack` or `:start`.
  """

  alias Cauldron2D.GameMaker.Colour
  alias Nidhox.Screen.Art

  @width 316
  @separation 20
  @start 136
  @speed 0.3
  @centre 160
  @hue_period 60
  @hue_swing 10
  @hues 255
  @saturation 180
  @value 255

  @doc """
  The credits beside the data file at `path`, found whatever the case of its name,
  every line followed by `" #"`; empty when the copy has none.
  """
  @spec read(Path.t()) :: String.t()
  def read(path) do
    folder = Path.dirname(path)

    with {:ok, files} <- File.ls(folder),
         name when is_binary(name) <- Enum.find(files, &(String.downcase(&1) == "credits.txt")),
         {:ok, text} <- File.read(Path.join(folder, name)) do
      text |> String.split(~r/\r?\n/) |> Enum.map_join(&(&1 <> " #"))
    else
      _missing -> ""
    end
  end

  @doc "Whether a player pressed `:attack` or `:start`, which leaves the credits."
  @spec leave?(%{1 => map(), 2 => map()}) :: boolean()
  def leave?(players),
    do: Enum.any?(Map.values(players), &(:attack in &1.pressed or :start in &1.pressed))

  @doc "The credits' GUI items at step `timer` of the screen."
  @spec items(String.t(), non_neg_integer(), {number(), number()}) :: [map()]
  def items(text, timer, window) do
    hue =
      Float.round(:math.sin(timer / @hue_period) * @hue_swing) |> trunc() |> Integer.mod(@hues)

    Art.text("fMenu", String.upcase(text), {@centre, @start - timer * @speed}, window,
      halign: :center,
      wrap: @width,
      separation: @separation,
      colour: Colour.hsv(hue, @saturation, @value)
    )
  end
end
