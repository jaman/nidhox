defmodule Nidhox.Screen.Entry do
  @moduledoc """
  Text typed with the game's own keys, in the copy's `fMenu` font: an address to join
  or a join code.

  The text is a row of characters with one under the cursor. Either side changes the
  character under the cursor through the entry's `alphabet` with `:up` and `:down`,
  moves the cursor with `:left` and `:right` — `:right` past the end adds the
  alphabet's first character, up to `longest` — finishes with `:start` or `:attack`,
  and goes back with `:jump`. `input/2` says which happened; `items/3` draws the entry
  under its label, the character under the cursor brighter than the rest.

      entry = Entry.new("SET IP", ~c"0123456789.", 15, "192.168.1.")
  """

  alias Nidhox.Screen.Art

  @enforce_keys [:label, :alphabet, :longest]
  defstruct [:label, :alphabet, :longest, text: [], cursor: 0]

  @type t :: %__MODULE__{
          label: String.t(),
          alphabet: charlist(),
          longest: pos_integer(),
          text: charlist(),
          cursor: non_neg_integer()
        }

  @chosen {255, 255, 255}
  @other {150, 150, 150}
  @label_gap 20

  @doc """
  An entry under `label`, typed from `alphabet`, at most `longest` characters, starting
  as `text` (only its characters in `alphabet`) with the cursor on its last character,
  or as the alphabet's first character when `text` has none.
  """
  @spec new(String.t(), charlist(), pos_integer(), String.t()) :: t()
  def new(label, [first | _] = alphabet, longest, text \\ "") do
    typed = text |> String.to_charlist() |> Enum.filter(&(&1 in alphabet)) |> Enum.take(longest)
    typed = if typed == [], do: [first], else: typed

    %__MODULE__{
      label: label,
      alphabet: alphabet,
      longest: longest,
      text: typed,
      cursor: length(typed) - 1
    }
  end

  @doc "The text typed."
  @spec text(t()) :: String.t()
  def text(%__MODULE__{text: text}), do: List.to_string(text)

  @doc """
  What the players did to the entry this step: `{:done, text, side}`, `{:back, side}`,
  or `{:stay, entry}` changed as they changed it.
  """
  @spec input(t(), %{1 => map(), 2 => map()}) ::
          {:done, String.t(), 1 | 2} | {:back, 1 | 2} | {:stay, t()}
  def input(%__MODULE__{} = entry, players) do
    case Enum.find_value([1, 2], &pressed(entry, &1, players[&1].pressed)) do
      nil -> {:stay, entry}
      outcome -> outcome
    end
  end

  @doc "The entry's GUI items: its label centred on `x` at `top`, and its text under it."
  @spec items(t(), {number(), number()}, {number(), number()}) :: [map()]
  def items(%__MODULE__{} = entry, {x, top}, window) do
    width = Art.text_width("fMenu", text(entry))
    left = x - width / 2

    characters =
      entry.text
      |> Enum.with_index()
      |> Enum.flat_map(fn {character, index} ->
        before = Art.text_width("fMenu", entry.text |> Enum.take(index) |> List.to_string())
        colour = if index == entry.cursor, do: @chosen, else: @other

        Art.text("fMenu", <<character>>, {left + before, top + @label_gap}, window,
          colour: colour
        )
      end)

    Art.text("fMenu", entry.label, {x, top}, window, halign: :center) ++ characters
  end

  defp pressed(entry, side, pressed) do
    cond do
      :start in pressed or :attack in pressed ->
        {:done, String.replace(text(entry), " ", ""), side}

      :jump in pressed ->
        {:back, side}

      :up in pressed ->
        {:stay, turn(entry, 1)}

      :down in pressed ->
        {:stay, turn(entry, -1)}

      :left in pressed ->
        {:stay, %{entry | cursor: max(entry.cursor - 1, 0)}}

      :right in pressed ->
        {:stay, forward(entry)}

      true ->
        nil
    end
  end

  defp turn(%__MODULE__{alphabet: alphabet, text: text, cursor: cursor} = entry, step) do
    index = Enum.find_index(alphabet, &(&1 == Enum.at(text, cursor))) || 0
    character = Enum.at(alphabet, Integer.mod(index + step, length(alphabet)))
    %{entry | text: List.replace_at(text, cursor, character)}
  end

  defp forward(%__MODULE__{text: text, cursor: cursor} = entry)
       when cursor + 1 < length(text),
       do: %{entry | cursor: cursor + 1}

  defp forward(%__MODULE__{text: text, longest: longest, alphabet: [first | _]} = entry)
       when length(text) < longest,
       do: %{entry | text: text ++ [first], cursor: length(text)}

  defp forward(entry), do: entry
end
