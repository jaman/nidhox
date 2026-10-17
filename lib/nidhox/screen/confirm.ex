defmodule Nidhox.Screen.Confirm do
  @moduledoc """
  A yes-or-no box over the screen (`ConfirmQuit`, `ConfirmPopup`, `drawConfirmBox`):
  QUIT TO DESKTOP?, BACK TO MAIN MENU? and the like.

  Select answers yes, back answers no, after the box's first 10 steps. `step/3` gives
  `{:closed, [{:yes, answer}]}` or `{:closed, [:no]}`, `answer` what the box was made
  with, so the caller knows what was asked. The prompt side follows the last side to
  press a menu button.
  """

  alias Nidhox.{Glyphs, Lang}
  alias Nidhox.Screen.{Gui, MainMenu}

  @ready_steps 10

  @enforce_keys [:text, :answer]
  defstruct [:text, :answer, yes: {"yes", "YES"}, no: {"no", "NO"}, age: 0, prompt_side: 1]

  @type t :: %__MODULE__{
          text: {String.t(), String.t()},
          answer: term(),
          yes: {String.t(), String.t()},
          no: {String.t(), String.t()},
          age: non_neg_integer(),
          prompt_side: 1 | 2
        }

  @doc "A box asking `{key, english}` (section `\"main menu\"`), answering `answer` on yes; `:yes` and `:no` relabel its buttons."
  @spec new({String.t(), String.t()}, term(), keyword()) :: t()
  def new(text, answer, opts \\ []) do
    %__MODULE__{
      text: text,
      answer: answer,
      yes: Keyword.get(opts, :yes, {"yes", "YES"}),
      no: Keyword.get(opts, :no, {"no", "NO"}),
      prompt_side: Keyword.get(opts, :prompt_side, 1)
    }
  end

  @doc "The box after `players`' input; see the module documentation."
  @spec step(t(), map(), map()) :: {:open, t(), [term()]} | {:closed, [term()]}
  def step(box, players, _context) do
    box = %{box | age: box.age + 1, prompt_side: MainMenu.prompt_side(players, box.prompt_side)}

    cond do
      box.age < @ready_steps -> {:open, box, []}
      MainMenu.any_pressed?(players, 9) -> {:closed, [:no]}
      MainMenu.any_pressed?(players, 8) -> {:closed, [{:yes, box.answer}]}
      true -> {:open, box, []}
    end
  end

  @doc "The box's drawing as GUI items; `context` gives `language` and `devices`."
  @spec items(t(), map(), Gui.window()) :: [map()]
  def items(box, context, size) do
    device = context.devices[box.prompt_side]

    Gui.confirm(
      Lang.font(context.language),
      text(context, box.text),
      Gui.glyph(Glyphs.icon(device, 9)) <> " " <> text(context, box.no),
      Gui.glyph(Glyphs.icon(device, 8)) <> " " <> text(context, box.yes),
      size
    )
  end

  defp text(context, {key, english}), do: Lang.text(context.language, "main menu", key, english)
end
