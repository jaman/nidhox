defmodule Nidhox.Look do
  @moduledoc """
  A bout as draw items: the fencers and swords in room pixels (`items/1`), and the
  banner over the play in window pixels (`banner/2`), all from the copy's sprites.

  A fencer is its pose (`Nidhox.Pose`): the body's sprite tinted the side's colour
  (`{:body, side, sprite, frame}` in `Nidhox.Sprites.table/2`), and its sword — the
  sprite drawn with the body, or `sSword` held out from the hand — each placed by its
  own origin from the copy and turned the way the fencer faces. A sword in play is
  `Nidhox.Sprites`' `:sword` or `:flying_sword`.

  Depths are the game's own: the fencer `@fencer_depth`, its held sword `@held_depth`,
  swords in play `@sword_depth`. The room's own instances at an equal depth, its grass
  among them, are drawn over these items.
  """

  alias Cauldron2D.GameMaker.Colour
  alias Nidhox.{Assets, Ending, Fencer, Match, Pose}
  alias Nidhox.Screen.Art

  @fencer_depth 0
  @held_depth 1
  @sword_depth 0
  @banner_at {160, 22}
  @arrow_reach 124
  @arrow_top 12
  @arrow_band 5
  @screen_middle 160
  @colours %{1 => {245, 205, 70}, 2 => {240, 120, 45}}

  @doc "Side `side`'s colour."
  @spec colour(1 | 2) :: {byte(), byte(), byte()}
  def colour(side), do: Map.fetch!(@colours, side)

  @doc "The fencers, the swords in play, and the Nidhogg once it comes (the winner gone from the ground once eaten)."
  @spec items(Match.t()) :: [map()]
  def items(%Match{} = match) do
    fencers =
      for {side, fencer} <- match.fencers,
          not (side == match.winner and Ending.eaten?(match.ending)),
          item <- fencer(fencer),
          do: item

    nidhogg = if match.ending, do: Ending.items(match.ending, @colours[match.winner]), else: []
    Enum.concat([fencers, Enum.map(match.swords, &sword/1), nidhogg])
  end

  @doc """
  The banner for `window` `{width, height}`, from the copy's sprites: the winner's
  `sWinner` in its colour, or the right of way's arrow (`Arrow`), as the game draws it
  on its GUI:

    * `sGO`, frame 1 for side 1 and 2 for side 2, its left edge at
      `@screen_middle ± @arrow_reach − width / 2` on that side of the screen, and its top
      at `@arrow_top + (@screen_middle − |left − @screen_middle|) × 0.1`
    * first its shadow in black at `(left − 1 + ±sin(frame / 30), top − 1 + cos(frame /
      50) / 2)`
    * then the arrow in bands `@arrow_band` pixels tall, band `i` (from its top) in the
      side's colour merged towards that colour 5% darkened by `0.5 + sin(i² / 10 + frame
      / 4) × 0.5`
  """
  @spec banner(Match.t(), {number(), number()}) :: [map()]
  def banner(%Match{winner: side}, window) when side != nil,
    do: [Art.centred("sWinner", 0, @banner_at, window, blend: @colours[side])]

  def banner(%Match{advancing: nil}, _window), do: []

  def banner(%Match{advancing: side, frame: frame}, window) do
    {width, height} = Art.size("sGO")
    toward = if side == 1, do: 1, else: -1
    left = @screen_middle + toward * @arrow_reach - width / 2
    top = @arrow_top + (@screen_middle - abs(left - @screen_middle)) * 0.1

    shadow =
      Art.part(
        "sGO",
        side,
        {0, 0, width, height},
        {left - 1 + toward * :math.sin(frame / 30), top - 1 + :math.cos(frame / 50) / 2},
        window,
        blend: {0, 0, 0}
      )

    [shadow | arrow_bands(side, frame, {left, top}, {width, height}, window)]
  end

  defp arrow_bands(side, frame, {left, top}, {width, height}, window) do
    colour = @colours[side]
    darker = Colour.merge(colour, {0, 0, 0}, 0.05)

    for band <- 0..(height - 1)//@arrow_band do
      shade = 0.5 + :math.sin(band * band / 10 + frame / 4) * 0.5

      Art.part(
        "sGO",
        side,
        {0, band, width, min(@arrow_band, height - band)},
        {left, top + band},
        window,
        blend: Colour.merge(colour, darker, shade)
      )
    end
  end

  defp fencer(%Fencer{} = fencer) do
    %{body: {name, frame}, sword: held} = Pose.of(fencer)
    {_index, %{origin: origin}} = Assets.sprite!(name)

    body = %{
      picture: {:body, fencer.side, name, frame},
      position: fencer.position,
      origin: origin,
      scale: {fencer.facing, 1},
      depth: @fencer_depth
    }

    [body | held(fencer, held)]
  end

  defp held(_fencer, nil), do: []

  defp held(%Fencer{} = fencer, {:paired, {name, frame}}),
    do: [sprite(name, frame, fencer.position, fencer.facing)]

  defp held(%Fencer{position: {x, y}} = fencer, {:hand, {dx, dy}}),
    do: [sprite("sSword", 0, {x + fencer.facing * dx, y + dy}, fencer.facing)]

  defp sprite(name, frame, position, facing) do
    {index, %{origin: origin}} = Assets.sprite!(name)

    %{
      picture: {:sprite, index, frame},
      position: position,
      origin: origin,
      scale: {facing, 1},
      depth: @held_depth
    }
  end

  @spec sword(Nidhox.Match.sword()) :: map()
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

  defp sign(value) when value < 0, do: -1
  defp sign(_), do: 1
end
