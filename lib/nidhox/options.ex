defmodule Nidhox.Options do
  @moduledoc """
  The game's options, a menu each client keeps for its own player
  (`Cauldron2D.Client.Game`'s `open_menu/1` and `menu_event/3`), opened by OPTIONS on
  the main menu or the client's menu key, and drawn as the game draws its menus
  (`Nidhox.Screen.MenuList`) over the game darkened to a quarter.

  Its first page, OPTIONS, is the game's options list: CONTROLS, "flashing" and
  "persistent blood", each ON or OFF, MUSIC and SFX, each with a slider (`drawSlider`).
  CONTROLS asks which player — PLAYER 1, the client's own keys, or PLAYER 2, the keys of
  the second seat at the same keyboard (the game option `:player_2`,
  `Nidhox.Controls.seat_keys/1`) — then lists, under that player, every action with its
  keys; choosing one waits for the next key and makes it that action's only key.

  `:up` and `:down` move round the list, `:enter` chooses, and `:escape` goes back a
  page and closes the menu from the first. Choosing "flashing" or "persistent blood"
  turns it on or off: the game options `:flashing` and `:persistent_blood`, which
  `Nidhox.Game` gives the game's `System`. `:left` and `:right` move MUSIC or SFX down
  or up by 0.1, within 0 to 1: the client's music and effects levels, the effects level
  scaling the music as well (`Nidhox.Client.audio/0`'s `master: :sfx`). Each change of
  SFX screams, one of `sfxScream1` to `sfxScream14` at random.

  Settings and options are kept by the client (`Cauldron2D.Drafter.Client.Settings`),
  under the player's configuration directory.
  """

  alias Cauldron2D.Input
  alias Nidhox.Controls
  alias Nidhox.Screen.{Art, MenuList}

  @enforce_keys [:page, :settings]
  defstruct [:page, :settings, selected: 0, rebinding: nil]

  @type page :: :options | :players | {:controls, 1 | 2}
  @type t :: %__MODULE__{
          page: page(),
          settings: map(),
          selected: non_neg_integer(),
          rebinding: atom() | nil
        }

  @step 0.1
  @screams 1..14
  @shade 0.75

  @doc "The menu as it opens, on its first page, showing `settings`."
  @spec open(map()) :: t()
  def open(settings), do: %__MODULE__{page: :options, settings: settings}

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

  def event(%__MODULE__{} = menu, {:key, key}, settings), do: key(menu, key, settings)
  def event(%__MODULE__{} = menu, _event, settings), do: reply(menu, settings)

  @doc "The menu's GUI items over a window `{width, height}`."
  @spec items(t(), {number(), number()}) :: [map()]
  def items(%__MODULE__{} = menu, window),
    do: [Art.shade(window, {0, 0, 0}, @shade) | MenuList.items(list(menu), window)]

  defp list(%__MODULE__{} = menu),
    do: %{MenuList.new(menu.page, title(menu.page), choices(menu)) | selected: menu.selected}

  defp key(menu, :up, settings), do: reply(turned(menu, -1), settings)
  defp key(menu, :down, settings), do: reply(turned(menu, 1), settings)
  defp key(menu, :escape, settings), do: back(menu, settings)
  defp key(menu, :enter, settings), do: choose(menu, chosen(menu), settings)
  defp key(menu, :left, settings), do: slide(menu, chosen(menu), -@step, settings)
  defp key(menu, :right, settings), do: slide(menu, chosen(menu), @step, settings)
  defp key(menu, _key, settings), do: reply(menu, settings)

  defp turned(%__MODULE__{selected: selected} = menu, step),
    do: %{menu | selected: Integer.mod(selected + step, length(choices(menu)))}

  defp slide(menu, :music, step, settings),
    do: reply(menu, %{settings | music: level(settings.music + step)})

  defp slide(menu, :sfx, step, settings) do
    menu
    |> reply(%{settings | sfx: level(settings.sfx + step)})
    |> Map.put(:sounds, [{:recording, "sfxScream#{Enum.random(@screams)}"}])
  end

  defp slide(menu, _row, _step, settings), do: reply(menu, settings)

  defp level(value), do: value |> max(0.0) |> min(1.0)

  defp choose(menu, option, settings) when option in [:flashing, :persistent_blood] do
    options = Map.update(settings.options, option, false, &(not &1))
    reply(menu, %{settings | options: options})
  end

  defp choose(menu, :controls, settings),
    do: reply(%{menu | page: :players, selected: 0}, settings)

  defp choose(menu, {:player, player}, settings),
    do: reply(%{menu | page: {:controls, player}, selected: 0}, settings)

  defp choose(menu, {:action, action}, settings), do: reply(%{menu | rebinding: action}, settings)
  defp choose(menu, _option, settings), do: reply(menu, settings)

  defp back(%__MODULE__{page: :options}, settings), do: %{menu: nil, settings: settings}

  defp back(%__MODULE__{page: :players} = menu, settings),
    do: reply(%{menu | page: :options, selected: 0}, settings)

  defp back(%__MODULE__{page: {:controls, player}} = menu, settings),
    do: reply(%{menu | page: :players, selected: player - 1}, settings)

  defp reply(menu, settings), do: %{menu: %{menu | settings: settings}, settings: settings}

  defp keymap(settings, 1), do: settings.bindings
  defp keymap(settings, 2), do: Controls.seat_keys(%{settings: settings})

  defp put_keys(settings, 1, action, keys),
    do: %{settings | bindings: Map.put(settings.bindings, action, keys)}

  defp put_keys(settings, 2, action, keys) do
    seat = settings |> keymap(2) |> Map.put(action, keys)
    %{settings | options: Map.put(settings.options, :player_2, seat)}
  end

  defp chosen(menu), do: menu |> choices() |> Enum.at(menu.selected) |> elem(1)

  defp title(:options), do: "OPTIONS"
  defp title(:players), do: "CONTROLS"
  defp title({:controls, player}), do: "PLAYER #{player}"

  defp choices(%__MODULE__{page: :options, settings: settings}) do
    [
      {"CONTROLS", :controls},
      {"flashing" <> switch(Map.get(settings.options, :flashing, true)), :flashing},
      {"persistent blood" <> switch(Map.get(settings.options, :persistent_blood, true)),
       :persistent_blood},
      {"MUSIC", :music, settings.music},
      {"SFX", :sfx, settings.sfx}
    ]
  end

  defp choices(%__MODULE__{page: :players}),
    do: [{"PLAYER 1", {:player, 1}}, {"PLAYER 2", {:player, 2}}]

  defp choices(%__MODULE__{page: {:controls, player}, settings: settings, rebinding: rebinding}) do
    keymap = keymap(settings, player)

    for action <- Controls.actions() do
      keys = if action == rebinding, do: "...", else: keys(Map.get(keymap, action, []))
      {"#{action}  #{keys}", {:action, action}}
    end
  end

  defp switch(true), do: " ON"
  defp switch(false), do: " OFF"

  defp keys([]), do: "NONE"
  defp keys(keys), do: Enum.map_join(keys, " ", &key_name/1)

  defp key_name({:mouse, button}), do: "MOUSE #{key_name(button)}"
  defp key_name({key, mods}), do: Enum.map_join(mods ++ [key], "+", &key_name/1)
  defp key_name(key), do: to_string(key)
end
