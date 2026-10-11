defmodule Nidhox.Tournament.Drawing do
  @moduledoc """
  The tournament's pictures, as the game's `Tournament` draws them from its draw event,
  in room pixels.

  `brackets/5` is `drawBracketsListXYWH(bracketHistory, x, y, width, height)`: every
  round a row, the first at the bottom and the last at the top, each `height / rounds`
  tall, a slot's middle `(slot + 0.5) × width / round width` across it.

    * from every slot of every round but the last, a line up to its slot in the next
      round: up 0.66 of the way between the rows, across, then up — open while that slot
      is undecided, in the slot's player's colour (`getPlayerColor(player + 1)`) when
      it won it, and lost otherwise
    * the lines drawn three times over, each `|sin(frame / 30)| × 1.5 + 5` wide: all in
      black; then the open ones in `make_color_hsv(|sin(frame × 75)| × 10 + 30, 50,
      255)` and the won ones in their colour; then 2 thinner (at least 1) — the open
      ones in `make_color_hsv(|sin(frame × 50)| × 10, 200, 150)`, the won ones again
      in their colour. A level line has a filled circle half the width across at each
      end, a pixel right of and below it
    * every slot's player icon over its middle (`icon/6`), flashing for the two in the
      match being played while it is undecided and its round has more than one slot

  `icon/6` is `drawPlayerIconAtFlash(player, x, y, flash)`: `sPlayerIconBack` at frame
  `frame × 0.6`, twice in white each up to a pixel off at random, then over them in the
  player's colour, `1 + sin(frame / 5) × 0.01` wide and `1 + cos(frame / 7) × 0.01`
  tall; over it the player's number `player + 1`, white in `fMenu`, centred, wrapped
  at 96. An undecided slot (−1) is `make_color_hsv(80, 20, 50)` with "?" for 55 steps
  of every 80; a bye is black with "X". A flashing icon is 1.25 times the size, white
  on the second of every six steps and black on the first; nothing flashes while the
  tournament is busy (`busyTimer` above 0).

  `champion/3` is the champion's room: the champion's icon, flashing, 20 above the
  view's bottom middle, and `sWinner` in the champion's colour 24 below the view's
  middle.
  """

  alias Cauldron2D.GameMaker.{Colour, Data, Draw, World}
  alias Nidhox.Bout.{Camera, PlayerColour}
  alias Nidhox.Gml
  alias Nidhox.Objects.System
  alias Nidhox.Tournament

  @undecided -1
  @rise 0.66
  @passes [2, 1, 0]
  @black {0, 0, 0}
  @white {255, 255, 255}
  @font "fMenu"
  @icon "sPlayerIconBack"
  @winner "sWinner"
  @frame_rate 0.6
  @wrap 96
  @flash_scale 1.25
  @flash_period 6
  @unknown_period 80
  @unknown_shown 55
  @champion_rise 20
  @winner_drop 24

  @doc """
  The world with `tournament`'s bracket drawn in the box `{x, y, width, height}` by
  instance `self`, `busy?` while nothing may flash.
  """
  @spec brackets(
          World.t(),
          non_neg_integer(),
          Tournament.t(),
          {number(), number(), number(), number()},
          boolean()
        ) ::
          World.t()
  def brackets(%World{} = world, self, %Tournament{} = tournament, box, busy?) do
    slots = slots(tournament, box)
    lines = Enum.flat_map(slots, &lines(tournament, &1, box))
    frame = System.get(world, :frame)
    width = abs(:math.sin(frame / 30)) * 1.5 + 5

    world =
      Enum.reduce(@passes, world, fn pass, world ->
        Enum.reduce(lines, world, &line(&2, self, &1, pass, width, frame))
      end)

    Enum.reduce(slots, world, fn slot, world ->
      icon(
        world,
        self,
        tournament,
        slot.player,
        {slot.x, slot.y},
        flashing?(tournament, slot) and not busy?
      )
    end)
  end

  @doc """
  The world with `player`'s icon drawn at `{x, y}` by instance `self`, flashing when
  `flash?`.
  """
  @spec icon(
          World.t(),
          non_neg_integer(),
          Tournament.t(),
          Tournament.slot() | nil,
          {number(), number()},
          boolean()
        ) ::
          World.t()
  def icon(%World{} = world, self, %Tournament{} = tournament, player, {x, y}, flash?) do
    frame = System.get(world, :frame)
    scale = if flash?, do: @flash_scale, else: 1
    {colour, world} = PlayerColour.get(world, self, (player || 0) + 1)
    colour = flashed(colour, frame, flash?)
    {colour, label} = shown(tournament, player, colour, frame)
    icon = Data.index(world.data, :sprites, @icon)
    image = frame * @frame_rate

    world =
      Enum.reduce(1..2, world, fn _copy, world ->
        {down, world} = Gml.random_range(world, -1, 1)
        {across, world} = Gml.random_range(world, -1, 1)

        Draw.sprite(world, icon, image, {x + across, y + down},
          scale: {scale, scale},
          blend: @white
        )
      end)

    world
    |> Draw.sprite(icon, image, {x, y},
      scale:
        {(1 + :math.sin(frame / 5) * 0.01) * scale, (1 + :math.cos(frame / 7) * 0.01) * scale},
      blend: colour
    )
    |> Draw.text(@font, label, {x, y},
      halign: :center,
      valign: :middle,
      wrap: @wrap,
      scale: {scale, scale}
    )
  end

  @doc "The world with `tournament`'s champion drawn by instance `self` in the champion's room."
  @spec champion(World.t(), non_neg_integer(), Tournament.t()) :: World.t()
  def champion(%World{} = world, self, %Tournament{} = tournament) do
    champion = Tournament.champion(tournament)
    centre = Camera.center_x(world)

    world =
      icon(
        world,
        self,
        tournament,
        champion,
        {centre, Camera.bottom(world) - @champion_rise},
        true
      )

    {colour, world} = PlayerColour.get(world, self, champion + 1)

    Draw.sprite(
      world,
      Data.index(world.data, :sprites, @winner),
      0,
      {centre, Camera.center_y(world) + @winner_drop},
      blend: colour
    )
  end

  defp slots(tournament, {x, y, width, height}) do
    count = length(tournament.rounds)

    for {round, row} <- Enum.with_index(tournament.rounds),
        {player, place} <- Enum.with_index(round) do
      %{
        player: player,
        row: row,
        place: place,
        x: x + width * place / length(round) + width * 0.5 / length(round),
        y: row_y(y, height, row, count)
      }
    end
  end

  defp row_y(y, height, row, count), do: y + height - height * row / count - height * 0.5 / count

  defp lines(tournament, slot, {x, y, width, height}) do
    case Tournament.next_round(tournament, slot.row) do
      0 ->
        []

      next_row ->
        next = Enum.at(tournament.rounds, next_row)
        half = div(slot.place, 2)
        across = x + width * half / length(next) + width * 0.5 / length(next)
        above = row_y(y, height, next_row, length(tournament.rounds))
        bend = slot.y - abs(above - slot.y) * @rise
        kind = kind(Enum.at(next, half), slot.player)

        [
          {{slot.x, slot.y}, {slot.x, bend}, kind},
          {{slot.x, bend}, {across, bend}, kind},
          {{across, bend}, {across, above}, kind}
        ]
    end
  end

  defp kind(@undecided, _player), do: :open
  defp kind(player, player), do: {:won, player}
  defp kind(_winner, _player), do: :lost

  defp flashing?(tournament, slot) do
    {first, second} = tournament.playing

    slot.row == tournament.round and length(Enum.at(tournament.rounds, slot.row)) > 1 and
      Tournament.champion(tournament) == nil and slot.player in [first, second]
  end

  defp line(world, _self, {_from, _to, :lost}, pass, _width, _frame) when pass != 2, do: world

  defp line(world, self, {from, to, kind}, pass, width, frame) do
    {colour, world} = colour(world, self, kind, pass, frame)
    width = if pass == 0, do: max(1, width - 2), else: width
    world |> ends(from, to, width, colour) |> Draw.line(from, to, width, colour)
  end

  defp colour(world, _self, _kind, 2, _frame), do: {@black, world}

  defp colour(world, _self, :open, 1, frame),
    do: {Colour.hsv(abs(:math.sin(frame * 75)) * 10 + 30, 50, 255), world}

  defp colour(world, _self, :open, 0, frame),
    do: {Colour.hsv(abs(:math.sin(frame * 50)) * 10, 200, 150), world}

  defp colour(world, self, {:won, player}, _pass, _frame),
    do: PlayerColour.get(world, self, player + 1)

  defp ends(world, {x1, y}, {x2, y}, width, colour),
    do:
      world
      |> circle({x1 + 1, y + 1}, width / 2, colour)
      |> circle({x2 + 1, y + 1}, width / 2, colour)

  defp ends(world, _from, _to, _width, _colour), do: world

  defp circle(world, {x, y}, radius, colour),
    do:
      Draw.item(world, %{
        picture: {:ellipse, {radius * 2, radius * 2}, :filled},
        position: {x - radius, y - radius},
        blend: colour
      })

  defp flashed(colour, frame, true) do
    cond do
      fmod(frame, @flash_period) < 1 -> @black
      fmod(frame, @flash_period) < 2 -> @white
      true -> colour
    end
  end

  defp flashed(colour, _frame, false), do: colour

  defp shown(_tournament, @undecided, _colour, frame),
    do:
      {Colour.hsv(80, 20, 50),
       if(fmod(frame, @unknown_period) < @unknown_shown, do: "?", else: "")}

  defp shown(tournament, player, colour, _frame) do
    if Tournament.bye?(tournament, player),
      do: {@black, "X"},
      else: {colour, "#{(player || 0) + 1}"}
  end

  defp fmod(value, divisor), do: value - divisor * trunc(value / divisor)
end
