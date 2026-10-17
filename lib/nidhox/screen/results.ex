defmodule Nidhox.Screen.Results do
  @moduledoc """
  The match's statistics after a bout, over `rMatchStats`, as the game's
  `ShowMatchStats` draws them in GUI units, every line in the language's font centred
  on its x from its top, lines 14 apart, labels from the `"match"` section:

    * "time" and the bout's time (`getTime`) at y 30
    * the copy's `sWinner` at (320, 144), twice its size, in the winner's colour
      (`getPlayerColor`)
    * for each side, in its colour, at y 260, around a point 128 to its side of the
      middle (yellow left, orange right): "kills" and its kills 64 left of the point,
      "suicides" and its suicides (falls out of the room) 64 right of it
    * the select glyph and "continue" at y 336, white, with the seconds left before
      CPU BATTLE goes on by itself in brackets (`countdownTag`), flashing red over the
      last 3

  Select, start or back goes on. NidhOX adds the replay to it: up or down turns the
  bottom line between "continue" and "watch replay", and the press that goes on does
  what it shows (`input/2`). The statistics are `Nidhox.Bout.stats/1`'s.
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.Bout.PlayerColour
  alias Nidhox.{Glyphs, Lang}
  alias Nidhox.Objects.Match
  alias Nidhox.Screen.{Gui, MainMenu}

  @type stats :: %{
          steps: non_neg_integer(),
          kills: %{1 => non_neg_integer(), 2 => non_neg_integer()},
          suicides: %{1 => non_neg_integer(), 2 => non_neg_integer()}
        }

  @centre 320
  @time_top 30
  @winner_at 144
  @rows_top 260
  @apart 128
  @half_apart 64
  @continue_top 336
  @separation 14
  @white {255, 255, 255}
  @flash_frames 12
  @last_seconds 3

  @type choice :: :continue | :replay

  @doc "What the players did on the results with `choice` shown: `{:go, choice}` or `{:stay, choice}`."
  @spec input(choice(), %{1 => map(), 2 => map()}) :: {:go, choice()} | {:stay, choice()}
  def input(choice, players) do
    cond do
      Enum.any?([8, 10, 9], &MainMenu.any_pressed?(players, &1)) -> {:go, choice}
      Enum.any?([2, 3], &MainMenu.any_pressed?(players, &1)) -> {:stay, other(choice)}
      true -> {:stay, choice}
    end
  end

  defp other(:continue), do: :replay
  defp other(:replay), do: :continue

  @doc """
  The GUI items for a bout won by side `winner` with `stats` and `choice` on the bottom
  line, coloured as `world` colours the sides; `context` gives `language`, `devices` and
  `frame`, and `seconds` the seconds left before the results go on by themselves, or `nil`.
  """
  @spec items(World.t(), 1 | 2, stats(), choice(), map(), number() | nil, Gui.window()) ::
          [map()]
  def items(%World{} = world, winner, stats, choice, context, seconds, window) do
    font = Lang.font(context.language)

    List.flatten([
      text(
        font,
        label(context, "time") <> "#" <> Match.time(stats.steps),
        {@centre, @time_top},
        @white,
        window
      ),
      Gui.sprite("sWinner", 0, {@centre, @winner_at}, window,
        scale: {2, 2},
        blend: colour(world, winner)
      ),
      Enum.map([1, 2], &side(world, &1, stats, context, font, window)),
      Gui.rich(font, bottom_line(choice, context, seconds), {@centre, @continue_top}, window,
        halign: :center
      )
    ])
  end

  defp bottom_line(:replay, _context, _seconds), do: "watch replay"

  defp bottom_line(:continue, context, seconds) do
    glyph = Gui.glyph(Glyphs.icon(context.devices[1], 8))
    countdown = if seconds, do: " " <> countdown(seconds, context.frame), else: ""
    glyph <> " " <> label(context, "continue") <> countdown
  end

  defp countdown(seconds, frame) do
    tag = "(#{seconds})"
    flash? = seconds <= @last_seconds and rem(div(trunc(frame), @flash_frames), 2) == 0
    if flash?, do: "[c_red]" <> tag <> "[/c]", else: tag
  end

  defp side(world, side, stats, context, font, window) do
    sign = if side == 1, do: -1, else: 1
    middle = @centre + sign * @apart
    colour = colour(world, side)

    [
      text(
        font,
        label(context, "kills") <> "##{stats.kills[side]}",
        {middle - @half_apart, @rows_top},
        colour,
        window
      ),
      text(
        font,
        label(context, "suicides") <> "##{stats.suicides[side]}",
        {middle + @half_apart, @rows_top},
        colour,
        window
      )
    ]
  end

  defp label(context, key), do: Lang.text(context.language, "match", key, key)

  defp text(font, words, at, colour, window),
    do:
      Gui.text(font, words, at, window, halign: :center, colour: colour, separation: @separation)

  defp colour(world, side) do
    {colour, _world} = PlayerColour.get(world, nil, side)
    colour
  end
end
