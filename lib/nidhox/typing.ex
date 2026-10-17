defmodule Nidhox.Typing do
  @moduledoc """
  Text typed on the keyboard — a host's address or its join code — as the client's own
  menu (`Cauldron2D.Client.Game`'s `open_menu/2` and `menu_event/3`), opened when the
  world asks for it (`Nidhox.Flow`), and drawn over the game darkened to a quarter in
  `fMenu`: its label, the text with the caret, and how to finish.

  A key whose character is in the entry's `alphabet` — as typed, or in upper case — is
  put in at the caret, up to `longest` characters; `:backspace` takes out the character
  before the caret and `:delete` the one after it; `:left`, `:right`, `:home` and `:end`
  move the caret; `:up` and `:down` turn the character before the caret through the
  alphabet (a controller's d-pad), putting in the alphabet's first when there is none.
  `:enter` finishes, sending the world `{:typed, kind, text}`, and `:escape` goes back,
  sending `{:typed, kind, :back}`; either closes the menu.

      typing = Typing.open({:code, "CODE", ~c"ABC23", 8, ""})
  """

  alias Nidhox.Screen.Art

  @enforce_keys [:kind, :label, :alphabet, :longest]
  defstruct [:kind, :label, :alphabet, :longest, text: [], caret: 0]

  @type kind :: :address | :code
  @type t :: %__MODULE__{
          kind: kind(),
          label: String.t(),
          alphabet: charlist(),
          longest: pos_integer(),
          text: charlist(),
          caret: non_neg_integer()
        }

  @shade 0.75
  @label_y 80
  @text_y 100
  @hint_y 130
  @centre 160
  @typed {255, 255, 255}
  @caret {255, 255, 0}
  @hint {150, 150, 150}

  @doc """
  The entry `{kind, label, alphabet, longest, text}` opened, starting as the characters
  of `text` in `alphabet`, the caret at its end.
  """
  @spec open({kind(), String.t(), charlist(), pos_integer(), String.t()}) :: t()
  def open({kind, label, alphabet, longest, text}) do
    typed = text |> String.to_charlist() |> Enum.filter(&(&1 in alphabet)) |> Enum.take(longest)

    %__MODULE__{
      kind: kind,
      label: label,
      alphabet: alphabet,
      longest: longest,
      text: typed,
      caret: length(typed)
    }
  end

  @doc """
  The entry after a client key event, as `menu_event/3` answers: `%{menu: entry_or_nil,
  settings: settings}`, with `:request` when it finishes or goes back.
  """
  @spec event(t(), term(), map()) :: map()
  def event(%__MODULE__{} = typing, {:key, key}, settings), do: key(typing, key, settings)
  def event(%__MODULE__{} = typing, {:key, key, _mods}, settings), do: key(typing, key, settings)
  def event(%__MODULE__{} = typing, _event, settings), do: %{menu: typing, settings: settings}

  @doc "The entry's GUI items over a window `{width, height}`."
  @spec items(t(), {number(), number()}) :: [map()]
  def items(%__MODULE__{} = typing, window) do
    {before, after_caret} = Enum.split(typing.text, typing.caret)
    shown = List.to_string(before) <> "_" <> List.to_string(after_caret)
    left = @centre - Art.text_width("fMenu", shown) / 2
    caret_x = left + Art.text_width("fMenu", List.to_string(before))

    [Art.shade(window, {0, 0, 0}, @shade)] ++
      Art.text("fMenu", typing.label, {@centre, @label_y}, window, halign: :center) ++
      Art.text("fMenu", List.to_string(before), {left, @text_y}, window, colour: @typed) ++
      Art.text("fMenu", "_", {caret_x, @text_y}, window, colour: @caret) ++
      Art.text(
        "fMenu",
        List.to_string(after_caret),
        {caret_x + Art.text_width("fMenu", "_"), @text_y},
        window,
        colour: @typed
      ) ++
      Art.text("fMenu", "enter to finish, esc to go back", {@centre, @hint_y}, window,
        halign: :center,
        colour: @hint
      )
  end

  defp key(typing, :enter, settings), do: finished(typing, List.to_string(typing.text), settings)
  defp key(typing, :escape, settings), do: finished(typing, :back, settings)
  defp key(typing, :backspace, settings), do: reply(erased(typing, typing.caret - 1), settings)
  defp key(typing, :delete, settings), do: reply(erased(typing, typing.caret), settings)

  defp key(typing, :left, settings),
    do: reply(%{typing | caret: max(typing.caret - 1, 0)}, settings)

  defp key(typing, :right, settings),
    do: reply(%{typing | caret: min(typing.caret + 1, length(typing.text))}, settings)

  defp key(typing, :home, settings), do: reply(%{typing | caret: 0}, settings)
  defp key(typing, :end, settings), do: reply(%{typing | caret: length(typing.text)}, settings)
  defp key(typing, :up, settings), do: reply(turned(typing, 1), settings)
  defp key(typing, :down, settings), do: reply(turned(typing, -1), settings)
  defp key(typing, key, settings), do: reply(typed(typing, character(typing, key)), settings)

  defp character(typing, key) when is_atom(key) do
    case Atom.to_charlist(key) do
      [single] -> Enum.find([single, upper(single)], &(&1 in typing.alphabet))
      _name -> nil
    end
  end

  defp upper(character) when character in ?a..?z, do: character - 32
  defp upper(character), do: character

  defp typed(typing, nil), do: typing

  defp typed(%__MODULE__{text: text, longest: longest} = typing, _character)
       when length(text) >= longest, do: typing

  defp typed(%__MODULE__{text: text, caret: caret} = typing, character),
    do: %{typing | text: List.insert_at(text, caret, character), caret: caret + 1}

  defp erased(typing, at) when at < 0 or at >= length(typing.text), do: typing

  defp erased(%__MODULE__{text: text, caret: caret} = typing, at),
    do: %{
      typing
      | text: List.delete_at(text, at),
        caret: if(at < caret, do: caret - 1, else: caret)
    }

  defp turned(%__MODULE__{caret: 0, alphabet: [first | _]} = typing, _step),
    do: typed(typing, first)

  defp turned(%__MODULE__{text: text, caret: caret, alphabet: alphabet} = typing, step) do
    index = Enum.find_index(alphabet, &(&1 == Enum.at(text, caret - 1))) || 0

    %{
      typing
      | text:
          List.replace_at(
            text,
            caret - 1,
            Enum.at(alphabet, Integer.mod(index + step, length(alphabet)))
          )
    }
  end

  defp reply(typing, settings), do: %{menu: typing, settings: settings}

  defp finished(typing, text, settings),
    do: %{menu: nil, settings: settings, request: {:typed, typing.kind, text}}
end
