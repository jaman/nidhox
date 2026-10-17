defmodule Nidhox.Screen.NetNotice do
  @moduledoc """
  A notice over the screen when an online game ends unasked (`NetNotice`): CONNECTION
  LOST or OPPONENT DISCONNECTED!, in yellow in a box, with the select glyph and
  "continue" under it. From its 20th step select or start dismisses it: `step/3` gives
  `{:closed, [:dismissed]}`.
  """

  alias Nidhox.{Glyphs, Lang}
  alias Nidhox.Screen.{Gui, MainMenu}

  @width 440
  @height 120
  @ready_steps 20

  @enforce_keys [:text]
  defstruct [:text, age: 0]

  @type t :: %__MODULE__{text: String.t(), age: non_neg_integer()}

  @doc "A notice of `text`."
  @spec new(String.t()) :: t()
  def new(text), do: %__MODULE__{text: text}

  @doc "The notice after a step of `players`' input."
  @spec step(t(), map(), map()) :: {:open, t(), [term()]} | {:closed, [term()]}
  def step(notice, players, _context) do
    notice = %{notice | age: notice.age + 1}

    if notice.age >= @ready_steps and
         (MainMenu.any_pressed?(players, 8) or MainMenu.any_pressed?(players, 10)),
       do: {:closed, [:dismissed]},
       else: {:open, notice, []}
  end

  @doc "The notice as GUI items; `context` gives `language` and `devices`."
  @spec items(t(), map(), Gui.window()) :: [map()]
  def items(notice, context, window) do
    font = Lang.font(context.language)
    {x, y} = {320 - @width / 2, 200 - @height / 2}
    continue = Lang.text(context.language, "match", "continue", "continue")

    Gui.shade({60, 0, 0}, 0.8, window) ++
      Gui.box("sprtextBgBox", {x, y, @width, @height}, window) ++
      Gui.rich(font, notice.text, {320, y + @height / 2 - 8}, window,
        halign: :center,
        valign: :middle,
        colour: {255, 255, 0},
        wrap: @width - 32,
        line_height: 20
      ) ++
      Gui.prompts(
        [Gui.glyph(Glyphs.icon(context.devices[1], 8)) <> " " <> continue],
        {x + @width - 6, y + @height},
        font,
        window
      )
  end
end
