defmodule Nidhox.Screen.Challenger do
  @moduledoc """
  MATCH FOUND! (`ChallengerPopup`), the box each player of a newly met pair answers: the
  opponent's name and ping, ACCEPT and DENY, and a 10-second count after which it
  denies by itself.

  Both sides answer the one box, each with their own buttons, and each sees it until
  they have answered. Input waits for the box's first 20 steps; select accepts, back
  denies. Over the last 5 seconds the count ticks (`sndPickup`) every second. `step/3`
  gives `{:open, box, events}` until both have accepted (`{:closed, [:accepted]}`) or
  one has denied (`{:closed, [{:denied, sides}]}`, the sides that denied or ran out of
  time). Events while open: `{:sound, :choose}` for an acceptance and `:tick`.
  """

  alias Nidhox.{Glyphs, Lang, Matchmaking}
  alias Nidhox.Screen.{Gui, MainMenu}

  @timer 600
  @ready_steps 20
  @ticking 300
  @x 160
  @y 125
  @width 320
  @height 150
  @pad 16

  defstruct timer: @timer, age: 0, accepted: %{1 => false, 2 => false}

  @type t :: %__MODULE__{
          timer: integer(),
          age: non_neg_integer(),
          accepted: %{1 => boolean(), 2 => boolean()}
        }

  @doc "A box just up, neither side having answered."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "The box with `side` already accepted: a player who joined through an invite (`netInvite`) accepts at once."
  @spec accept(t(), 1 | 2) :: t()
  def accept(box, side), do: %{box | accepted: Map.put(box.accepted, side, true)}

  @doc "The box after a step of `players`' input; see the module documentation."
  @spec step(t(), map(), map()) :: {:open, t(), [term()]} | {:closed, [term()]}
  def step(box, players, _context) do
    box = %{box | age: box.age + 1, timer: box.timer - 1}

    tick =
      if box.timer > 0 and box.timer <= @ticking and rem(box.timer, 60) == 0,
        do: [:tick],
        else: []

    {box, accepted} = accepted(box, players)
    denied = denied(box, players)

    cond do
      denied != [] -> {:closed, [{:denied, denied}]}
      box.accepted[1] and box.accepted[2] -> {:closed, [:accepted]}
      true -> {:open, box, tick ++ accepted}
    end
  end

  defp accepted(%{age: age} = box, _players) when age < @ready_steps, do: {box, []}

  defp accepted(box, players) do
    Enum.reduce([1, 2], {box, []}, fn side, {box, events} ->
      if not box.accepted[side] and MainMenu.pressed?(players, side, 8),
        do: {%{box | accepted: Map.put(box.accepted, side, true)}, events ++ [{:sound, :choose}]},
        else: {box, events}
    end)
  end

  defp denied(box, players) do
    Enum.filter([1, 2], fn side ->
      not box.accepted[side] and
        (box.timer <= 0 or (box.age >= @ready_steps and MainMenu.pressed?(players, side, 9)))
    end)
  end

  @doc """
  The box as side `side` sees it, as GUI items: nothing once that side has accepted.
  `context` gives `language`, `devices`, `frame`, and `opponent`, `%{name, ping}` of the
  other side.
  """
  @spec items(t(), 1 | 2, map(), Gui.window()) :: [map()]
  def items(%{accepted: accepted} = box, side, context, window) do
    if accepted[side], do: [], else: drawn(box, side, context, window)
  end

  defp drawn(box, side, context, window) do
    font = Lang.font(context.language)
    device = context.devices[side]
    ping = round(context.opponent.ping || 0)
    seconds = ceil(box.timer / 60)

    Gui.shade({60, 0, 0}, 0.75, window) ++
      Gui.box("sprtextBgBox", {@x, @y, @width, @height}, window) ++
      Gui.text(font, text(context, "match_found", "MATCH FOUND!"), {320, @y + 24}, window,
        halign: :center,
        valign: :middle,
        colour: {255, 255, 0}
      ) ++
      Gui.text(
        font,
        text(context, "player_name", "Player: {0}", [context.opponent.name]),
        {320, @y + 48},
        window,
        halign: :center,
        valign: :middle
      ) ++
      Gui.text(
        font,
        text(context, "ping", "Ping: {0} ms", [Integer.to_string(ping)]),
        {320, @y + 70},
        window,
        halign: :center,
        valign: :middle,
        colour: Matchmaking.ping_colour(ping)
      ) ++
      Gui.text(
        font,
        text(context, "auto_deny", "Denying in {0}...", [Integer.to_string(seconds)]),
        {@x + @pad, @y + @height - @pad},
        window,
        valign: :bottom,
        colour: countdown_colour(seconds, context.frame)
      ) ++
      Gui.rich(
        font,
        glyph(device, 9) <> " " <> text(context, "deny", "DENY"),
        {@x + @width - @pad, @y + @height - @pad - 20},
        window,
        halign: :right,
        valign: :bottom
      ) ++
      Gui.rich(
        font,
        glyph(device, 8) <> " " <> text(context, "accept_challenger", "ACCEPT"),
        {@x + @width - @pad, @y + @height - @pad},
        window,
        halign: :right,
        valign: :bottom
      )
  end

  @doc "The colour of a countdown at `seconds` (`countdownColor`): red on and off every 12 frames over the last 3 seconds, else grey 150."
  @spec countdown_colour(integer(), number()) :: Gui.rgb()
  def countdown_colour(seconds, frame) do
    if seconds <= 3 and rem(div(trunc(frame), 12), 2) == 0,
      do: {255, 0, 0},
      else: Gui.grey(150)
  end

  defp glyph(device, button), do: Gui.glyph(Glyphs.icon(device, button))

  defp text(context, key, english, args \\ []),
    do: Lang.text(context.language, "online match", key, english, args)
end
