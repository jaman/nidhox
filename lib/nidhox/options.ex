defmodule Nidhox.Options do
  @moduledoc """
  The game's options, a menu each client keeps for its own player
  (`Cauldron2D.Client.Game`'s `open_menu/1` and `menu_event/3`), opened by OPTIONS on
  the main menu or the client's menu key, and drawn in the copy's `fMenu` over the game.

  Its first page is the game's options list: CONTROLS, "flashing" and "persistent
  blood", each ON or OFF, MUSIC and SFX, each a slider, and BACK. CONTROLS asks
  which player — PLAYER 1, the client's own keys, or PLAYER 2, the keys of the second
  seat at the same keyboard (the game option `:player_2`, `Nidhox.Controls.seat_keys/1`)
  — then opens "REMAP INPUT FOR PLAYER": every action with its keys; choosing one waits
  for the next key and makes it that action's only key.

  `:up` and `:down` move, `:enter` chooses, and `:escape` goes back a page and closes
  the menu from the first. Choosing "flashing" or "persistent blood" turns it on or off:
  the game options `:flashing` and `:persistent_blood`, which `Nidhox.Game` gives the
  game's `System`. `:left` and `:right` move MUSIC or SFX down or up by 0.1, within
  0 to 1: the client's music and effects levels, the effects level scaling the music as
  well (`Nidhox.Client.audio/0`'s `master: :sfx`). Each change of SFX screams, one of
  `sfxScream1` to `sfxScream14` at random. A slider is drawn as `drawSlider` draws it:
  32 pixels wide and 4 high at x 164, outlined, filled for the level, its name beside
  it.

  Settings and options are kept by the client (`Cauldron2D.Drafter.Client.Settings`),
  under the player's configuration directory.
  """

  alias Cauldron2D.Input
  alias Nidhox.Controls
  alias Nidhox.Screen.Art

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
  @slider {164, 32, 4}
  @top 72
  @spacing 13
  @heading {160, 30}
  @chosen {255, 255, 255}
  @other {150, 150, 150}
  @controls_row 0

  @doc "The menu as it opens, on its first page, showing `settings`."
  @spec open(map()) :: t()
  def open(settings), do: %__MODULE__{page: :options, settings: settings}

  @doc """
  The menu after `event` (a client key event), with the settings it leaves:
  `%{menu: menu_or_nil, settings: settings}`.
  """
  @spec event(t(), term(), map()) :: %{menu: t() | nil, settings: map()}
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
  def items(%__MODULE__{} = menu, window) do
    lines =
      menu
      |> rows()
      |> Enum.with_index()
      |> Enum.flat_map(fn {{row, label}, index} ->
        colour = if index == menu.selected, do: @chosen, else: @other
        line(menu, row, label, @top + index * @spacing, colour, window)
      end)

    [Art.shade(window, {0, 0, 0}, 0.75) | heading(menu, window) ++ lines]
  end

  defp key(menu, :up, settings),
    do: reply(%{menu | selected: max(menu.selected - 1, 0)}, settings)

  defp key(menu, :down, settings),
    do: reply(%{menu | selected: min(menu.selected + 1, length(rows(menu)) - 1)}, settings)

  defp key(menu, :escape, settings), do: back(menu, settings)
  defp key(menu, :enter, settings), do: choose(menu, chosen(menu), settings)

  defp key(menu, :left, settings), do: slide(menu, chosen(menu), -@step, settings)
  defp key(menu, :right, settings), do: slide(menu, chosen(menu), @step, settings)
  defp key(menu, _key, settings), do: reply(menu, settings)

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
  defp choose(menu, :back, settings), do: back(menu, settings)

  defp back(%__MODULE__{page: :options}, settings), do: %{menu: nil, settings: settings}

  defp back(%__MODULE__{page: :players} = menu, settings),
    do: reply(%{menu | page: :options, selected: @controls_row}, settings)

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

  defp chosen(menu), do: menu |> rows() |> Enum.at(menu.selected) |> elem(0)

  defp rows(%__MODULE__{page: :options, settings: settings}) do
    [
      {:controls, "CONTROLS"},
      {:flashing, "flashing" <> switch(Map.get(settings.options, :flashing, true))},
      {:persistent_blood,
       "persistent blood" <> switch(Map.get(settings.options, :persistent_blood, true))},
      {:music, "MUSIC"},
      {:sfx, "SFX"},
      {:back, "BACK"}
    ]
  end

  defp rows(%__MODULE__{page: :players}),
    do: [{{:player, 1}, "PLAYER 1"}, {{:player, 2}, "PLAYER 2"}, {:back, "BACK"}]

  defp rows(%__MODULE__{page: {:controls, player}, settings: settings, rebinding: rebinding}) do
    keymap = keymap(settings, player)

    actions =
      for action <- Controls.actions() do
        keys = if action == rebinding, do: "...", else: keys(Map.get(keymap, action, []))
        {{:action, action}, "#{String.upcase(to_string(action))}  #{keys}"}
      end

    actions ++ [{:back, "BACK"}]
  end

  defp switch(true), do: " ON"
  defp switch(false), do: " OFF"

  defp line(menu, row, label, y, colour, window) when row in [:music, :sfx] do
    {x, _width, _height} = @slider

    Art.text("fMenu", label, {x - 6, y}, window, halign: :right, colour: colour) ++
      slider(Map.fetch!(menu.settings, row), y, colour, window)
  end

  defp line(_menu, _row, label, y, colour, window),
    do: Art.text("fMenu", label, {160, y}, window, halign: :center, colour: colour)

  defp slider(value, y, colour, window) do
    {x, width, height} = @slider
    top = y + 4

    Art.rectangle({x, top, x + width, top + height}, colour, window, true) ++
      Art.rectangle({x, top, x + width * value, top + height}, colour, window, false)
  end

  defp keys([]), do: "NONE"
  defp keys(keys), do: Enum.map_join(keys, " ", &key_name/1)

  defp key_name({:mouse, button}), do: "MOUSE #{key_name(button)}"
  defp key_name({key, mods}), do: Enum.map_join(mods ++ [key], "+", &key_name/1)
  defp key_name(key), do: key |> to_string() |> String.upcase()

  defp heading(%__MODULE__{page: :options}, window),
    do: Art.text("fMenu", "OPTIONS", @heading, window, halign: :center)

  defp heading(%__MODULE__{page: :players}, window),
    do: Art.text("fMenu", "CONTROLS", @heading, window, halign: :center)

  defp heading(%__MODULE__{page: {:controls, player}}, window),
    do: Art.text("fMenu", "REMAP INPUT#FOR PLAYER #{player}", @heading, window, halign: :center)
end
