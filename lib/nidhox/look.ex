defmodule Nidhox.Look do
  @moduledoc """
  A bout as draw items: the fencers and swords in room pixels (`items/1`), and the
  banner over the play in window pixels (`banner/2`).

  Pictures are named as `Nidhox.Sprites.table/0` keys them, and text as `{:text, string,
  colour, scale}`, which `Nidhox.Client` renders.

  Each animation cycle uses its own frame count — a 2-frame animation is 2 frames, a
  15-frame animation is 15 frames. They are not collapsed into a shared bucket.

  The colour maps for each side are defined in `Nidhox.Art` and baked into the
  sprite table at load time. Each draw item carries the picture key (matched to
  the table) so the correct side colour is rendered.
  """

  alias Nidhox.{Fencer, Match, Terrain}

  @fencer_depth -100
  @sword_depth -101
  @bg_sky_depth -200
  @bg_cloud_depth -150
  @bg_foreground_depth -90
  @names %{1 => "YELLOW", 2 => "ORANGE"}
  @colours %{1 => {245, 205, 70}, 2 => {240, 120, 45}}

  # Thrust/punch/throw timing — must match Fencer constants.
  @thrust_steps 16
  @punch_steps 14
  @throw_steps 12

  @doc """
  The background layers for a match: moon, clouds, grass tufts, and foreground
  silhouettes that appear behind and in front of the fencers.
  """
  @spec background(Match.t()) :: [map()]
  def background(%Match{} = match) do
    frame = match.frame
    Enum.concat([moon(frame), clouds(frame), foreground(match)])
  end

  @doc "The fencers and the swords in play."
  @spec items(Match.t()) :: [map()]
  def items(%Match{} = match) do
    Enum.concat([
      background(match),
      Enum.flat_map(Map.values(match.fencers), &fencer/1),
      Enum.map(match.swords, &sword/1)
    ])
  end

  @doc """
  All items including banner (used for full scene rendering).
  """
  @spec all_items(Match.t()) :: [map()]
  def all_items(%Match{} = match) do
    items(match) ++ banner(match)
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

  # sManStandResting origin x
  defp body_origin_x(1), do: 13
  # sSwordStandResting origin x
  defp body_origin_x(2), do: 18
  # sManStandResting origin y
  defp body_origin_y(1), do: 30
  # sSwordStandResting origin y
  defp body_origin_y(2), do: 34

  # ---- Drawing ----

  @spec fencer(Fencer.t()) :: [map()]
  defp fencer(%Fencer{action: :dead} = fencer) do
    %{
      picture: {:down, fencer.side, dead_frame(fencer)},
      position: fencer.position,
      origin: dead_origin(),
      scale: {fencer.facing, 1},
      depth: @fencer_depth
    }
  end

  defp fencer(%Fencer{} = fencer), do: [body(fencer) | arm(fencer)]

  @spec body(Fencer.t()) :: map()
  defp body(%Fencer{} = fencer) do
    %{
      picture: body_key(fencer),
      position: fencer.position,
      origin: {body_origin_x(fencer.side), body_origin_y(fencer.side)},
      scale: {fencer.facing, 1},
      depth: @fencer_depth
    }
  end

  defp body_key(%Fencer{side: side, action: :thrust, age: age}),
    do: {:lunge, side, lunge_frame({side, age})}

  defp body_key(%Fencer{side: side, action: :punch, age: age}),
    do: {:lunge, side, lunge_frame({side, age})}

  # Throw — grounded (standing throw animation, 13 frames).
  defp body_key(%Fencer{side: side, action: :throw, grounded: true, age: age}),
    do: {:throw, side, throw_frame({side, age})}

  # Throw — in air (air throw animation, 7 frames).
  defp body_key(%Fencer{side: side, action: :throw, grounded: false, age: age}),
    do: {:throw_air, side, throw_air_frame({side, age})}

  # In air (not throwing — regular jump).
  defp body_key(%Fencer{side: side, grounded: false, age: age}),
    do: {:air, side, air_frame({side, age})}

  # Running / walking.
  defp body_key(%Fencer{side: side, velocity: {vx, _}, action: :ready, age: age})
       when abs(vx) > 1.5,
       do: {:run, side, run_frame({side, age})}

  defp body_key(%Fencer{side: side, velocity: {vx, _}, action: :ready, age: age})
       when abs(vx) > 0.2,
       do: {:walk, side, walk_frame({side, age})}

  # Standing idle — cycle through walk frames (slow advance).
  # In the real game, fencers slowly walk back and forth when idle,
  # not standing still holding their swords.
  defp body_key(%Fencer{side: side, action: :ready, age: age}),
    do: {:walk, side, idle_frame({side, age})}

  # Frame counters and frame selectors.
  defp idle_frame({side, age}),
    do: rem(div(age, 12), idle_frame_count(side))

  # sManRun — slow cycle through 24 walk frames
  defp idle_frame_count(_side), do: 24

  defp lunge_frame({side, age}),
    do: rem(div(age, 4), lunge_frame_count(side))

  # sManSwordAttackMed
  defp lunge_frame_count(1), do: 15
  # sManSwordAttackMed (shared)
  defp lunge_frame_count(2), do: 15

  defp air_frame({side, age}),
    do: rem(div(age, 4), air_frame_count(side))

  # sManJump (shared)
  defp air_frame_count(_side), do: 3

  defp run_frame({side, age}),
    do: rem(div(age, 4), run_frame_count(side))

  # sManRun (shared)
  defp run_frame_count(_side), do: 24

  defp walk_frame({side, age}),
    do: rem(div(age, 8), walk_frame_count(side))

  # sManRun (walk uses same sprite)
  defp walk_frame_count(_side), do: 24

  defp dead_frame(%Fencer{side: side, age: age}),
    do: rem(div(age, 2), dead_frame_count(side))

  # sManLieOnBack (shared)
  defp dead_frame_count(_side), do: 7

  # lying flat — shoulder near feet
  defp dead_origin, do: {13, 5}

  defp throw_frame({side, age}),
    do: rem(div(age, 4), throw_frame_count(side))

  # sManThrowStanding (shared)
  defp throw_frame_count(_side), do: 13

  defp throw_air_frame({side, age}),
    do: rem(div(age, 4), throw_air_frame_count(side))

  # sManThrowMidAir (shared)
  defp throw_air_frame_count(_side), do: 7

  # ---- Arm / sword hand position ----

  @spec arm(Fencer.t()) :: [map()]
  defp arm(%Fencer{position: {_x, _y}, facing: facing, side: _side} = fencer) do
    hand = hand(fencer)

    if fencer.armed,
      do: [
        %{
          picture: :sword,
          position: hand,
          origin: {0, 1},
          scale: {facing, 1},
          depth: @sword_depth
        }
      ],
      else: []
  end

  # Thrusting (standing lunge) — sword extends forward.
  defp hand(%Fencer{
         position: {x, y},
         facing: facing,
         stance: stance,
         action: :thrust,
         timer: timer
       }) do
    progress = (@thrust_steps - 1 - timer) / @thrust_steps
    forward = min(progress * 20, 20)
    # body leans forward, hand drops slightly
    y_off = progress * 8
    {x + facing * (8 + round(forward)), y - Fencer.height(stance) + round(y_off)}
  end

  # Punching — hand extends and lowers.
  defp hand(%Fencer{
         position: {x, y},
         facing: facing,
         stance: stance,
         action: :punch,
         timer: timer
       }) do
    progress = (@punch_steps - 1 - timer) / @punch_steps
    forward = min(progress * 10, 10)
    y_off = progress * 5
    {x + facing * (8 + round(forward)), y - Fencer.height(stance) + round(y_off)}
  end

  # Throwing — hand rises high as the sword is released.
  defp hand(%Fencer{
         position: {x, y},
         facing: facing,
         stance: stance,
         action: :throw,
         timer: timer
       }) do
    progress = (@throw_steps - 1 - timer) / @throw_steps
    # hand rises up to 25px above stance height
    height_off = 25 * progress
    {x + facing * 8, y - Fencer.height(stance) + round(height_off)}
  end

  # Standing (grounded, no action) — hand at natural height.
  defp hand(%Fencer{position: {x, y}, facing: facing, stance: stance, grounded: true}),
    do: {x + facing * 8, y - Fencer.height(stance)}

  # In air — hand slightly higher (no sword support).
  defp hand(%Fencer{position: {x, y}, facing: facing, stance: stance, grounded: false}),
    do: {x + facing * 8, y - Fencer.height(stance) - 3}

  # ---- Sword objects ----

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

  # ---- Text / GUI ----

  @spec text(String.t(), {integer(), integer(), integer()}, {number(), number()}) :: map()
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

  # ---- Helpers ----

  @spec sign(number()) :: -1 | 1
  defp sign(value) when value < 0, do: -1
  defp sign(_), do: 1

  # ---- Background elements ----

  # Moon — 2 frames, slowly pulsing.
  defp moon(frame) do
    pulse = 0.95 + 0.05 * :math.sin(2 * :math.pi() * frame / 180)

    [
      %{
        picture: {:effect, :moon},
        position: {480, 120},
        origin: {160, 0},
        scale: {pulse, pulse},
        depth: @bg_sky_depth
      }
    ]
  end

  # Clouds — animated, slowly drifting across the sky.
  defp clouds(frame) do
    drift = 2 * :math.sin(2 * :math.pi() * frame / 900)

    [
      %{
        picture: {:effect, :cloud},
        position: {480 + round(drift), 200},
        origin: {35, 13},
        scale: {1, 1},
        depth: @bg_cloud_depth
      },
      %{
        picture: {:effect, :cloud},
        position: {200 + round(drift * 0.7), 280},
        origin: {35, 13},
        scale: {0.8, 0.8},
        depth: @bg_cloud_depth
      },
      %{
        picture: {:effect, :cloud},
        position: {750 + round(drift * 0.5), 250},
        origin: {35, 13},
        scale: {0.9, 0.9},
        depth: @bg_cloud_depth
      }
    ]
  end

  # Grass tufts and foreground silhouettes at the bottom of the screen.
  defp foreground(%Match{terrain: terrain}) do
    # Find a ground point near the center of the room for grass placement.
    {center_x, _} = {elem(terrain.size, 0) / 2, 0}
    ground_y = Terrain.ground(terrain, center_x) || elem(terrain.size, 1)

    grass_tufts =
      Enum.map(0..23, fn i ->
        x = 40.0 * i - 480
        # Offset grass by a few pixels to alternate positions
        y_off =
          case rem(i, 3) do
            0 -> 0
            1 -> 3
            2 -> -2
          end

        %{
          picture: {:effect, :grass},
          position: {x, round(ground_y) + y_off},
          origin: {8, 28},
          scale: {1, 1},
          depth: @bg_foreground_depth
        }
      end)

    # Foreground silhouettes (bushes/trees) at screen edges.
    foreground_sil = %{
      picture: {:effect, :foreground},
      position: {0, elem(terrain.size, 1)},
      origin: {0, 0},
      scale: {1, 1},
      depth: @bg_foreground_depth + 1
    }

    grass_tufts ++ [foreground_sil]
  end

  @doc "Banner with no window (returns empty)."
  @spec banner(Match.t()) :: [map()]
  def banner(%Match{}), do: []
end
