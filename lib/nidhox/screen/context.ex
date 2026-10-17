defmodule Nidhox.Screen.Context do
  @moduledoc """
  What the main menu (`Nidhox.Screen.MainMenu`) and its windows read from the game's
  state, as one map:

    * `language`, `hype` — from the prefs
    * `devices` — each side's device and key bindings, for the glyphs; a side whose
      client has sent none is a keyboard with that side's keys (`Nidhox.Controls.keys/1`)
    * `frame` — `System.frame`
    * `rules`, `time_limit`, `sudden_death?` — the variants
    * `entrants`, `area` — TOURNAMENT's PLAYERS and MAP
    * `world` — the running world
    * `colours` — each side's palette colour (`System.vsColor`, side `n` colour `n` when unset)
    * `remote?` — whether a player of the game is on another machine
    * `news`, `seen` — the copy's articles and the keys of those read
    * `prompt_side` — the menu's prompt side, else 1
    * `input_delay` — the online lobby's INPUT DELAY as shown (`Nidhox.OnlineFlow.delay_shown/1`)
    * `new?` — whether an item of the menu shows the "new" dot (`menuIsNew`): NEWS
      while an article is unread; TRAINING, ONLINE, CPU BATTLE and OPTIONS until seen;
      SINGLE PLAYER, MULTIPLAYER and EXTRAS while an item of their list is new
  """

  alias Nidhox.{Assets, Controls, News, Online, Rules}
  alias Nidhox.Objects.System
  alias Nidhox.Screen.MainMenu

  @parents [:single_player, :multiplayer, :extras]

  @doc "The context of `state`."
  @spec of(map()) :: map()
  def of(state) do
    news = Assets.get().news
    seen = state.prefs.news_seen
    unread = News.unread_count(news, seen)
    menu_seen = state.prefs.menu_seen

    %{
      language: state.prefs.language,
      hype: state.prefs.hype,
      devices: Map.new([1, 2], &{&1, device(state.devices[&1], &1)}),
      frame: System.get(state.world, :frame, 0),
      rules: state.rules,
      time_limit: state.rules.time_limit,
      sudden_death?: Rules.on?(state.rules, :suddenDeathOnly),
      entrants: state.entrants,
      area: state.area,
      world: state.world,
      colours: colours(state.world),
      remote?: Enum.any?(Map.values(state.players), &Online.remote_player?(state, &1)),
      news: news,
      seen: seen,
      prompt_side: prompt_side(state.menu),
      new?: &new?(&1, menu_seen, unread),
      input_delay: Nidhox.OnlineFlow.delay_shown(state)
    }
  end

  defp device(%{keys: keys} = device, _side) when map_size(keys) > 0, do: device
  defp device(%{device: {:pad, _name}} = device, _side), do: device
  defp device(_none, side), do: %{device: :keyboard, keys: Controls.keys(side)}

  defp colours(world) do
    chosen = System.get(world, :vsColor, nil)
    Map.new([1, 2], &{&1, colour(chosen, &1)})
  end

  defp colour(chosen, side) when is_map(chosen), do: Map.get(chosen, side, side)
  defp colour(chosen, side) when is_list(chosen), do: Enum.at(chosen, side) || side
  defp colour(_chosen, side), do: side

  defp prompt_side(%MainMenu{prompt_side: side}), do: side
  defp prompt_side(_menu), do: 1

  defp new?(:news, _menu_seen, unread), do: unread > 0

  defp new?(parent, menu_seen, unread) when parent in @parents,
    do: parent |> MainMenu.list() |> Enum.any?(&new?(&1, menu_seen, unread))

  defp new?(item, menu_seen, _unread) do
    case MainMenu.new_key(item) do
      nil -> false
      key -> key not in menu_seen
    end
  end
end
