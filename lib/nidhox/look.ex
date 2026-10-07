defmodule Nidhox.Look do
  @moduledoc """
  A bout as draw items: the fencers and swords in room pixels (`items/1`), and the
  banner over the play in window pixels (`banner/2`).

  Pictures are named as `Nidhox.Art.table/0` keys them, and text as `{:text, string,
  colour, scale}`, which `Nidhox.Client` renders.
  """

  alias Nidhox.{Art, Fencer, Match}

  @fencer_depth -100
  @sword_depth -101
  @body_origin {5, 23}
  @down_origin {13, 5}
  @arm_rows %{high: 3, middle: 0, low: 0, extended: 0}
  @arm_widths %{high: 6, middle: 6, low: 6, extended: 8}
  @hand_rise %{high: 2, middle: -2, low: -7}
  @names %{1 => "YELLOW", 2 => "ORANGE"}
  @colours %{1 => {245, 205, 70}, 2 => {240, 120, 45}}

  @doc "The fencers and the swords in play."
  @spec items(Match.t()) :: [map()]
  def items(%Match{} = match) do
    fencers = Enum.flat_map(Map.values(match.fencers), &fencer/1)
    swords = Enum.map(match.swords, &sword/1)
    fencers ++ swords
  end

  @doc """
  The banner for `window` `{width, height}`: the side with the right of way and the way
  it runs, or the winner.
  """
  @spec banner(Match.t(), {number(), number()}) :: [map()]
  def banner(%Match{winner: side}, window) when side != nil,
    do: [text("#{@names[side]} WINS", @colours[side], window)]

  def banner(%Match{advancing: nil}, _window), do: []

  def banner(%Match{advancing: side}, window) do
    words = if Match.goal(side) == 1, do: "#{@names[side]} GO ->", else: "<- #{@names[side]} GO"
    [text(words, @colours[side], window)]
  end

  defp fencer(%Fencer{action: :dead} = fencer) do
    [
      %{
        picture: {:fencer, fencer.side, :down},
        position: fencer.position,
        origin: @down_origin,
        scale: {fencer.facing, 1},
        depth: @fencer_depth
      }
    ]
  end

  defp fencer(%Fencer{} = fencer) do
    [body(fencer) | arm(fencer)]
  end

  defp body(%Fencer{} = fencer) do
    %{
      picture: {:fencer, fencer.side, frame(fencer)},
      position: fencer.position,
      origin: @body_origin,
      scale: {fencer.facing, 1},
      depth: @fencer_depth
    }
  end

  defp frame(%Fencer{action: action}) when action in [:thrust, :punch], do: :lunge
  defp frame(%Fencer{grounded: false}), do: :air

  defp frame(%Fencer{velocity: {vx, _}, age: age}) do
    cond do
      abs(vx) > 1.5 -> {:run, rem(div(age, 4), 4)}
      abs(vx) > 0.2 -> {:walk, rem(div(age, 8), 2)}
      true -> :stand
    end
  end

  defp arm(%Fencer{position: {x, y}, facing: facing} = fencer) do
    pose = pose(fencer)
    shoulder = {x + facing * 2, y - Art.shoulder()}
    hand = hand(fencer, pose, shoulder)

    arm = %{
      picture: {:arm, fencer.side, pose},
      position: shoulder,
      origin: {0, @arm_rows[pose]},
      scale: {facing, 1},
      depth: @fencer_depth - 0.5
    }

    if fencer.armed,
      do: [
        arm,
        %{
          picture: :sword,
          position: hand,
          origin: {0, 1},
          scale: {facing, 1},
          depth: @sword_depth
        }
      ],
      else: [arm]
  end

  defp pose(fencer) do
    cond do
      Fencer.thrusting?(fencer) or fencer.action == :punch -> :extended
      fencer.armed -> fencer.stance
      true -> :middle
    end
  end

  defp hand(%Fencer{position: {_x, y}, facing: facing, stance: stance}, :extended, {sx, _sy}),
    do: {sx + facing * @arm_widths.extended, y - Fencer.height(stance)}

  defp hand(%Fencer{facing: facing}, pose, {sx, sy}),
    do: {sx + facing * @arm_widths[pose], sy - @hand_rise[pose]}

  defp sword(%{flying: true, position: position, velocity: {vx, _}}),
    do: %{
      picture: :flying_sword,
      position: position,
      origin: {7, 1},
      scale: {sign(vx), 1},
      depth: @sword_depth
    }

  defp sword(%{position: position}),
    do: %{picture: :sword, position: position, origin: {7, 1}, depth: @sword_depth}

  defp text(words, colour, {width, _height}) do
    scale = 3
    raster = Linocut.Font.render(words, colour, scale: scale)
    {text_width, _} = FrenchCurve.Raster.dimensions(raster)

    %{
      picture: {:text, words, colour, scale},
      position: {(width - text_width) / 2, 24},
      depth: 0
    }
  end

  defp sign(value) when value < 0, do: -1
  defp sign(_value), do: 1
end
