defmodule Nidhox.Options do
  @moduledoc """
  The game's options, a menu each client keeps for its own player
  (`Cauldron2D.Client.Game`'s `open_menu/1` and `menu_event/3`), opened by OPTIONS on
  the main menu or the client's menu key, and drawn in the copy's `fMenu` over the game.

  Its first page has SFX and MUSIC, each ON or OFF, CONTROLS and BACK. CONTROLS asks
  which player — PLAYER 1, the client's own keys, or PLAYER 2, the keys of the second
  seat at the same keyboard (the game option `:player_2`, `Nidhox.Controls.seat_keys/1`)
  — then opens "REMAP INPUT FOR PLAYER": every action with its keys; choosing one waits
  for the next key and makes it that action's only key.

  `:up` and `:down` move, `:enter` chooses, `:left` and `:right` turn SFX and MUSIC on
  and off, and `:escape` goes back a page and closes the menu from the first. OFF sets
  the client's level to `0.0`; ON sets it to `@sfx_on` or `@music_on`.
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

  @sfx_on 0.85
  @music_on 0.35
  @top 72
  @spacing 13
  @heading {160, 30}
  @chosen {255, 255, 255}
  @other {150, 150, 150}
  @controls_row 2

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
      |> Enum.flat_map(fn {{_row, label}, index} ->
        colour = if index == menu.selected, do: @chosen, else: @other

        Art.text("fMenu", label, {160, @top + index * @spacing}, window,
          halign: :center,
          colour: colour
        )
      end)

    [Art.shade(window, {0, 0, 0}, 0.75) | heading(menu, window) ++ lines]
  end

  defp key(menu, :up, settings),
    do: reply(%{menu | selected: max(menu.selected - 1, 0)}, settings)

  defp key(menu, :down, settings),
    do: reply(%{menu | selected: min(menu.selected + 1, length(rows(menu)) - 1)}, settings)

  defp key(menu, :escape, settings), do: back(menu, settings)
  defp key(menu, :enter, settings), do: choose(menu, chosen(menu), settings)

  defp key(menu, side, settings) when side in [:left, :right] do
    case chosen(menu) do
      row when row in [:sfx, :music] -> choose(menu, row, settings)
      _row -> reply(menu, settings)
    end
  end

  defp key(menu, _key, settings), do: reply(menu, settings)

  defp choose(menu, :sfx, settings),
    do: reply(menu, %{settings | sfx: toggle(settings.sfx, @sfx_on)})

  defp choose(menu, :music, settings),
    do: reply(menu, %{settings | music: toggle(settings.music, @music_on)})

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

  defp toggle(level, _on) when level > 0, do: 0.0
  defp toggle(_level, on), do: on

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
      {:sfx, "SFX" <> switch(settings.sfx)},
      {:music, "MUSIC" <> switch(settings.music)},
      {:controls, "CONTROLS"},
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

  defp switch(level) when level > 0, do: " ON"
  defp switch(_level), do: " OFF"

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
