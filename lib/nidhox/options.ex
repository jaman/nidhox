defmodule Nidhox.Options do
  @moduledoc """
  The game's OPTIONS (`OptionsMenu`), a menu each client keeps for its own player
  (`Cauldron2D.Client.Game`'s `open_menu/1` and `menu_event/3`), opened by OPTIONS on
  the main menu or in the pause, or by the client's menu key, and drawn as the game
  draws it: a `Nidhox.Screen.PopupList` over the game, in the client's language.

  Its first page lists LANGUAGE (the language's own name), CONTROLS, "flashing" and
  "persistent blood" (each a toggle), MUSIC and SFX (each a slider). CONTROLS asks which
  player — PLAYER 1, the client's own keys, or PLAYER 2, the keys of the second seat at
  the same keyboard (the game option `:player_2`, `Nidhox.Controls.seat_keys/1`) — then
  lists, under that player, every action with its keys; choosing one waits for the next
  key and makes it that action's only key. CONTROLS also has CONTROLLERS: every
  connected controller with the player it plays (the client's `controllers`), choosing
  one or left and right moving it between PLAYER 1, PLAYER 2 and NONE (saved as the
  client's `pads`).

  Either player's keys work it, as the menu buttons do (`Nidhox.Glyphs`): up and down
  move round the list, jump or start chooses, pause goes back a page (closing the menu
  from the first), left and right change a value; the raw keys `:up`, `:down`, `:left`,
  `:right`, `:enter` and `:escape` (a controller's d-pad, `A`, `B` and `Start`) do the
  same. LANGUAGE steps through the game's languages (`Nidhox.Lang`), choosing it as
  right does: the game option `:language`. Choosing "flashing" or "persistent blood"
  turns it on or off: the game options `:flashing` and `:persistent_blood`, which
  `Nidhox.Game` gives the game's `System`. Left and right move MUSIC or SFX down or up
  by 0.1, within 0 to 1: the client's music and effects levels, the effects level
  scaling the music as well (`Nidhox.Client.audio/0`'s `master: :sfx`). Each change of
  SFX screams, one of `sfxScream1` to `sfxScream14` at random.

  Settings and options are kept by the client (`Cauldron2D.Drafter.Client.Settings`),
  under the player's configuration directory.
  """

  alias Cauldron2D.Input
  alias Nidhox.{Controls, Glyphs, Lang}
  alias Nidhox.Screen.{Gui, PopupList}

  @enforce_keys [:page, :settings, :popup]
  defstruct [:page, :settings, :popup, rebinding: nil]

  @type page :: :options | :players | {:controls, 1 | 2} | :controllers
  @type t :: %__MODULE__{
          page: page(),
          settings: map(),
          popup: PopupList.t(),
          rebinding: atom() | nil
        }

  @width 300
  @step 0.1
  @screams 1..14
  @pad_choices [1, 2, :none]
  @adjusted [:language, :music, :sfx]
  @menu_keys %{
    up: :up,
    down: :down,
    left: :left,
    right: :right,
    jump: :enter,
    start: :enter,
    pause: :escape
  }

  @doc "The menu as it opens, on its first page, showing `settings`."
  @spec open(map()) :: t()
  def open(settings), do: paged(settings, :options, 0)

  @doc """
  The menu after `event` (a client key event), with the settings it leaves:
  `%{menu: menu_or_nil, settings: settings}`, with `:sounds` when it makes one.
  """
  @spec event(t(), term(), map()) :: map()
  def event(%__MODULE__{rebinding: action, page: {:controls, player}} = menu, event, settings)
      when action != nil do
    case Input.spec_of(event) do
      nil -> reply(menu, settings)
      :escape -> reply(%{menu | rebinding: nil}, settings)
      key -> reply(%{menu | rebinding: nil}, put_keys(settings, player, action, [key]))
    end
  end

  def event(%__MODULE__{} = menu, {:key, _key} = event, settings),
    do: key(menu, menu_key(settings, event), settings)

  def event(%__MODULE__{} = menu, _event, settings), do: reply(menu, settings)

  @doc "The menu's GUI items over a window `{width, height}`."
  @spec items(t(), {number(), number()}) :: [map()]
  def items(%__MODULE__{} = menu, window) do
    language = language(menu.settings)
    font = Lang.font(language)
    popup = menu.popup

    PopupList.draw_window(popup, title(menu.page, language), font, window) ++
      Enum.flat_map(Enum.with_index(rows(menu)), &row(menu, &1, language, font, window)) ++
      PopupList.draw_scrollbar(popup, window) ++
      Gui.prompts(prompts(menu, language), PopupList.prompt_at(popup), font, window)
  end

  defp paged(settings, page, selected) do
    count = length(rows(%__MODULE__{page: page, settings: settings, popup: nil}))
    popup = PopupList.move_to(PopupList.new(@width, count), min(selected, max(count - 1, 0)))
    %__MODULE__{page: page, settings: settings, popup: popup}
  end

  defp menu_key(settings, {:key, key} = event) do
    spec = Input.spec_of(event)

    Enum.find_value([1, 2], key, fn player ->
      settings
      |> keymap(player)
      |> Enum.find_value(fn {action, keys} -> spec in keys and Map.get(@menu_keys, action) end)
    end)
  end

  defp key(menu, :up, settings), do: reply(turned(menu, -1), settings)
  defp key(menu, :down, settings), do: reply(turned(menu, 1), settings)
  defp key(menu, :escape, settings), do: back(menu, settings)
  defp key(menu, :enter, settings), do: choose(menu, chosen(menu), settings)
  defp key(menu, :left, settings), do: slide(menu, chosen(menu), -1, settings)
  defp key(menu, :right, settings), do: slide(menu, chosen(menu), 1, settings)
  defp key(menu, _key, settings), do: reply(menu, settings)

  defp turned(menu, step) do
    count = max(menu.popup.count, 1)

    %{
      menu
      | popup: PopupList.move_to(menu.popup, Integer.mod(menu.popup.selection + step, count))
    }
  end

  defp slide(menu, :language, direction, settings) do
    options = Map.put(settings.options, :language, Lang.step(language(settings), direction))
    reply(menu, %{settings | options: options})
  end

  defp slide(menu, :music, direction, settings),
    do: reply(menu, %{settings | music: level(settings.music + direction * @step)})

  defp slide(menu, :sfx, direction, settings) do
    menu
    |> reply(%{settings | sfx: level(settings.sfx + direction * @step)})
    |> Map.put(:sounds, [{:recording, "sfxScream#{Enum.random(@screams)}"}])
  end

  defp slide(menu, {:pad, name}, direction, settings),
    do: reply(menu, put_pad(settings, name, direction))

  defp slide(menu, _row, _direction, settings), do: reply(menu, settings)

  defp level(value), do: (value * 10) |> round() |> max(0) |> min(10) |> Kernel./(10)

  defp choose(menu, :language, settings), do: slide(menu, :language, 1, settings)

  defp choose(menu, option, settings) when option in [:flashing, :persistent_blood] do
    options = Map.update(settings.options, option, false, &(not &1))
    reply(menu, %{settings | options: options})
  end

  defp choose(_menu, :controls, settings), do: reply(paged(settings, :players, 0), settings)

  defp choose(_menu, {:player, player}, settings),
    do: reply(paged(settings, {:controls, player}, 0), settings)

  defp choose(menu, {:action, action}, settings), do: reply(%{menu | rebinding: action}, settings)

  defp choose(_menu, :controllers, settings),
    do: reply(paged(settings, :controllers, 0), settings)

  defp choose(menu, {:pad, name}, settings), do: reply(menu, put_pad(settings, name, 1))
  defp choose(menu, _option, settings), do: reply(menu, settings)

  defp back(%__MODULE__{page: :options}, settings), do: %{menu: nil, settings: settings}

  defp back(%__MODULE__{page: :players}, settings),
    do: reply(paged(settings, :options, 1), settings)

  defp back(%__MODULE__{page: {:controls, player}}, settings),
    do: reply(paged(settings, :players, player - 1), settings)

  defp back(%__MODULE__{page: :controllers}, settings),
    do: reply(paged(settings, :players, 2), settings)

  defp reply(menu, settings), do: %{menu: %{menu | settings: settings}, settings: settings}

  defp keymap(settings, 1), do: settings.bindings
  defp keymap(settings, 2), do: Controls.seat_keys(%{settings: settings})

  defp put_keys(settings, 1, action, keys),
    do: %{settings | bindings: Map.put(settings.bindings, action, keys)}

  defp put_keys(settings, 2, action, keys) do
    seat = settings |> keymap(2) |> Map.put(action, keys)
    %{settings | options: Map.put(settings.options, :player_2, seat)}
  end

  defp chosen(menu), do: menu |> rows() |> Enum.at(menu.popup.selection) |> row_name()

  defp row_name({name, _label}), do: name

  defp language(settings), do: Map.get(settings.options, :language, "en")

  defp title(:options, language), do: Lang.text(language, "main menu", "options", "OPTIONS")
  defp title(:players, language), do: Lang.text(language, "main menu", "controls", "CONTROLS")
  defp title({:controls, player}, _language), do: "PLAYER #{player}"
  defp title(:controllers, _language), do: "CONTROLLERS"

  defp rows(%__MODULE__{page: :options}) do
    [
      {:language, {"language", "language"}},
      {:controls, {"controls", "CONTROLS"}},
      {:flashing, {"flashing", "flashing"}},
      {:persistent_blood, {"persistent_blood", "persistent blood"}},
      {:music, {"music", "MUSIC"}},
      {:sfx, {"sfx", "SFX"}}
    ]
  end

  defp rows(%__MODULE__{page: :players}),
    do: [
      {{:player, 1}, "PLAYER 1"},
      {{:player, 2}, "PLAYER 2"},
      {:controllers, "CONTROLLERS"}
    ]

  defp rows(%__MODULE__{page: :controllers, settings: %{controllers: [_ | _] = controllers}}),
    do: for(%{name: name} <- controllers, do: {{:pad, name}, name})

  defp rows(%__MODULE__{page: :controllers}), do: [{:none, "NO CONTROLLERS"}]

  defp rows(%__MODULE__{page: {:controls, _player}}),
    do: Enum.map(Controls.actions(), &{{:action, &1}, Atom.to_string(&1)})

  defp row(menu, {{name, label}, index}, language, font, window) do
    PopupList.draw_row(menu.popup, index, label_text(label, language), font, window) ++
      value(menu, name, index, language, font, window)
  end

  defp label_text({key, english}, language), do: Lang.text(language, "main menu", key, english)
  defp label_text(label, _language), do: label

  defp value(menu, :language, index, language, font, window),
    do: PopupList.draw_value(menu.popup, index, Lang.name(language), font, window)

  defp value(menu, option, index, _language, font, window)
       when option in [:flashing, :persistent_blood],
       do:
         PopupList.draw_tick(
           menu.popup,
           index,
           Map.get(menu.settings.options, option, true),
           font,
           window
         )

  defp value(menu, level, index, _language, font, window) when level in [:music, :sfx],
    do: PopupList.draw_bar(menu.popup, index, Map.fetch!(menu.settings, level), font, window)

  defp value(menu, {:action, action}, index, _language, font, window) do
    {:controls, player} = menu.page

    shown =
      if action == menu.rebinding,
        do: "...",
        else: keys(Map.get(keymap(menu.settings, player), action, []))

    PopupList.draw_value(menu.popup, index, shown, font, window)
  end

  defp value(menu, {:pad, name}, index, _language, font, window) do
    player = Enum.find_value(menu.settings.controllers, &(&1.name == name and &1.player))
    PopupList.draw_value(menu.popup, index, pad_player(player), font, window)
  end

  defp value(_menu, _name, _index, _language, _font, _window), do: []

  defp prompts(menu, language) do
    device = %{device: :keyboard, keys: menu.settings.bindings}
    adjust? = adjusted?(chosen(menu))

    first =
      if adjust?,
        do:
          glyphs(device, [0, 1]) <>
            " " <> Lang.text(language, "main menu", "prompt_adjust", "adjust"),
        else:
          glyphs(device, [8]) <>
            " " <> Lang.text(language, "main menu", "prompt_select", "select")

    [first, glyphs(device, [9]) <> " " <> Lang.text(language, "main menu", "prompt_back", "back")]
  end

  defp adjusted?({:pad, _name}), do: true
  defp adjusted?(name), do: name in @adjusted

  defp glyphs(device, buttons), do: Enum.map_join(buttons, &Gui.glyph(Glyphs.icon(device, &1)))

  defp pad_player(nil), do: "NONE"
  defp pad_player(false), do: "NONE"
  defp pad_player(player), do: "PLAYER #{player}"

  defp put_pad(settings, name, step) do
    current =
      Enum.find_value(settings.controllers, :none, &(&1.name == name and (&1.player || :none)))

    index = Enum.find_index(@pad_choices, &(&1 == current)) || 0

    pads =
      Map.put(
        settings.pads,
        name,
        Enum.at(@pad_choices, Integer.mod(index + step, length(@pad_choices)))
      )

    %{settings | pads: pads}
  end

  defp keys([]), do: "NONE"
  defp keys(keys), do: Enum.map_join(keys, " ", &key_name/1)

  defp key_name({:mouse, button}), do: "MOUSE #{key_name(button)}"
  defp key_name({key, mods}), do: Enum.map_join(mods ++ [key], "+", &key_name/1)
  defp key_name(key), do: to_string(key)
end
