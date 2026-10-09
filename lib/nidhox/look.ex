defmodule Nidhox.Look do
  @moduledoc """
  A bout as draw items: the fencers and swords in room pixels (`items/1`), and the
  banner over the play in window pixels (`banner/2`), all from the copy's sprites.

  A fencer is its pose (`Nidhox.Pose`): the body's sprite tinted the side's colour
  (`{:body, side, sprite, frame}` in `Nidhox.Sprites.table/2`), and its sword — the
  sprite drawn with the body, or `sSword` held out from the hand — each placed by its
  own origin from the copy and turned the way the fencer faces. A sword in play is
  `Nidhox.Sprites`' `:sword` or `:flying_sword`.
  """

  alias Nidhox.{Assets, Ending, Fencer, Match, Pose}
  alias Nidhox.Screen.Art

  @fencer_depth -100
  @sword_depth -101
  @banner_at {160, 22}
  @go_blink 40
  @go_shown 28
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
  `sWinner` in its colour, or, for the side with the right of way, `sGO` pointing the
  way it runs in its colour, shown for `@go_shown` of every `@go_blink` steps.
  """
  @spec banner(Match.t(), {number(), number()}) :: [map()]
  def banner(%Match{winner: side}, window) when side != nil,
    do: [Art.centred("sWinner", 0, @banner_at, window, blend: @colours[side])]

  def banner(%Match{advancing: nil}, _window), do: []

  def banner(%Match{advancing: side, frame: frame}, window) do
    if rem(frame, @go_blink) < @go_shown,
      do: [
        Art.centred("sGO", go_frame(Match.goal(side)), @banner_at, window, blend: @colours[side])
      ],
      else: []
  end

  defp go_frame(1), do: 1
  defp go_frame(-1), do: 2

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
      depth: @sword_depth
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
