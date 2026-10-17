defmodule Nidhox.Screen.Invite do
  @moduledoc """
  INVITE! (`InvitePopup`), the box a player sees when a friend on the local network
  invites them: the friend's name, "join" and DENY, and a 30-second count after which it
  denies by itself. It shows on the main menu, the online menu and the attract mode.

  Input waits for the box's first 20 steps. Select takes the invite: `step/3` gives
  `{:closed, [{:sound, :choose}, {:take, lobby}]}`, the inviter's lobby. Back, or the
  count running out, gives `{:closed, [:denied]}`; nothing goes back to the inviter. The
  prompt side is the last side to press a menu button.
  """

  alias Nidhox.{Glyphs, Lang}
  alias Nidhox.Screen.{Challenger, Gui, MainMenu}

  @timer 1800
  @ready_steps 20
  @x 160
  @y 125
  @width 320
  @height 150
  @pad 16

  @enforce_keys [:lobby]
  defstruct [:lobby, timer: @timer, age: 0, prompt_side: 1]

  @type t :: %__MODULE__{
          lobby: map(),
          timer: integer(),
          age: non_neg_integer(),
          prompt_side: 1 | 2
        }

  @doc "The box offering `lobby` (`offer`), a `Nidhox.Online` lobby whose host invited this player."
  @spec new(map()) :: t()
  def new(lobby), do: %__MODULE__{lobby: lobby}

  @doc "The box after a step of `players`' input."
  @spec step(t(), map(), map()) :: {:open, t(), [term()]} | {:closed, [term()]}
  def step(box, players, _context) do
    box = %{
      box
      | age: box.age + 1,
        timer: box.timer - 1,
        prompt_side: MainMenu.prompt_side(players, box.prompt_side)
    }

    cond do
      box.age < @ready_steps and box.timer > 0 ->
        {:open, box, []}

      box.age >= @ready_steps and MainMenu.any_pressed?(players, 8) ->
        {:closed, [{:sound, :choose}, {:take, box.lobby}]}

      box.timer <= 0 or MainMenu.any_pressed?(players, 9) ->
        {:closed, [:denied]}

      true ->
        {:open, box, []}
    end
  end

  @doc "The box as GUI items; `context` gives `language`, `devices` and `frame`."
  @spec items(t(), map(), Gui.window()) :: [map()]
  def items(box, context, window) do
    font = Lang.font(context.language)
    device = context.devices[box.prompt_side]
    seconds = ceil(box.timer / 60)

    Gui.shade({60, 0, 0}, 0.75, window) ++
      Gui.box("sprtextBgBox", {@x, @y, @width, @height}, window) ++
      Gui.text(font, text(context, "invite_received", "INVITE!"), {320, @y + 24}, window,
        halign: :center,
        valign: :middle,
        colour: {255, 255, 0}
      ) ++
      Gui.text(
        font,
        text(context, "player_name", "Player: {0}", [box.lobby.name]),
        {320, @y + 48},
        window,
        halign: :center,
        valign: :middle
      ) ++
      Gui.text(
        font,
        text(context, "auto_deny", "Denying in {0}...", [Integer.to_string(seconds)]),
        {@x + @pad, @y + @height - @pad},
        window,
        valign: :bottom,
        colour: Challenger.countdown_colour(seconds, context.frame)
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
        glyph(device, 8) <> " " <> text(context, "prompt_join", "join"),
        {@x + @width - @pad, @y + @height - @pad},
        window,
        halign: :right,
        valign: :bottom
      )
  end

  defp glyph(device, button), do: Gui.glyph(Glyphs.icon(device, button))

  defp text(context, key, english, args \\ []),
    do: Lang.text(context.language, "online match", key, english, args)
end
