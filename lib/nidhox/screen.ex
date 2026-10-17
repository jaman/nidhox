defmodule Nidhox.Screen do
  @moduledoc """
  What each screen of `Nidhox.Flow` draws over its room, as GUI items for a window
  `{width, height}`: the screen's own pictures and text. A bout draws itself through
  its objects; over it only the pause menu and the replay's skip line are added, over
  the attract mode "press start" (`pressStart`, outlined, its bottom middle at
  (320, 368), shown the first 60 of every 120 frames), and over HOW TO PLAY the current
  lesson's instruction (white, centred from (320, 24), wrapped at 576), each with the
  glyphs of side 1's device. Over the online lobby round it adds the lobby's own GUI
  (`OnlineLobby` and `ReadyZone`): each side's name in its colour mixed a third toward
  black, centred at (144, 22) and (496, 22), "wins:" at (64, 46) and (384, 46) with a
  tally (`sTally`, twice its size) for each match won 8 apart, the opponent's ping at
  the top (`drawPing`), START's glyph and "settings" in the bottom right, and "READY"
  over each ready zone, white while its owner stands in it.

  `for_side/3` gives what only the player on one side sees: the online menu and its
  windows, MATCH FOUND!, the pause of an online round to the side that paused, and the
  online results' "Waiting for opponent".
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.Bout.PlayerColour
  alias Nidhox.{Glyphs, Lang, Matchmaking, OnlineFlow}
  alias Nidhox.Gml
  alias Nidhox.Objects.{System, Tutorial}
  alias Nidhox.Screen.{Art, Confirm, Context, Credits, Levels, Logos, MainMenu, Online}
  alias Nidhox.Screen.{Challenger, Gui, MultiMenu, NetNotice, Pause, Results}
  alias Nidhox.Tutorial.Lessons

  @skip {160, 186}
  @press_start_at {320, 368}
  @blink_period 120
  @blink_shown 60
  @lesson_at {320, 24}
  @lesson_wrap 576
  @cpu_battle_results 900

  @doc "The room items and the GUI items of `state`'s screen."
  @spec layer(map(), {number(), number()}) :: {[map()], [map()]}
  def layer(%{screen: :logos} = state, window),
    do: {[], Logos.items(state.timer, System.get(state.world, :frame), window)}

  def layer(%{screen: :title, menu: %MainMenu{} = menu} = state, window) do
    context = Context.of(state)
    {[], MainMenu.items(menu, context, window) ++ window_items(menu.window, context, window)}
  end

  def layer(%{screen: :levels, menu: %Confirm{} = box} = state, window),
    do: {Levels.items(state.levels, state.world), Confirm.items(box, Context.of(state), window)}

  def layer(%{screen: :levels} = state, _window),
    do: {Levels.items(state.levels, state.world), []}

  def layer(%{screen: :credits} = state, window),
    do: {[], Credits.items(state.credits, state.timer, window)}

  def layer(%{screen: :ssh_hosting} = state, window),
    do: {[], Online.ssh_hosting(state.online, window)}

  def layer(%{screen: :address} = state, window),
    do: {[], Online.entry(state.entry, state.online.status, window)}

  def layer(%{screen: :multi}, _window), do: {[], []}

  def layer(%{screen: :notice} = state, window),
    do: {[], NetNotice.items(state.menu, Context.of(state), window)}

  def layer(%{screen: :bout, mode: :online, net: %{flow_kind: 1}} = state, window),
    do: {[], lobby(state, window)}

  def layer(%{screen: screen, mode: :online}, _window) when screen in [:bout, :paused],
    do: {[], []}

  def layer(%{screen: :results, mode: :online} = state, window),
    do:
      {[],
       Results.items(
         state.world,
         state.winner,
         state.stats,
         :continue,
         Context.of(state),
         nil,
         window
       )}

  def layer(%{screen: :demo} = state, window), do: {[], press_start(state, window)}
  def layer(%{screen: :tutorial} = state, window), do: {[], lesson(state, window)}

  def layer(%{screen: screen}, _window)
      when screen in [:bout, :challenge, :arcade, :arcade_complete, :tournament],
      do: {[], []}

  def layer(%{screen: :paused} = state, window),
    do: {[], lesson(state, window) ++ Pause.items(state.menu, Context.of(state), window)}

  def layer(%{screen: :replay}, window),
    do: {[], Art.text("fMenu", "SKIP THIS", @skip, window, halign: :center)}

  def layer(%{screen: :results} = state, window),
    do:
      {[],
       Results.items(
         state.world,
         state.winner,
         state.stats,
         state.menu || :continue,
         Context.of(state),
         seconds_left(state),
         window
       )}

  @doc "What only the player on `side` sees over the screen, as GUI items; `[]` for a viewer without a side."
  @spec for_side(map(), 1 | 2 | nil, {number(), number()}) :: [map()]
  def for_side(_state, nil, _window), do: []

  def for_side(%{screen: :multi} = state, side, window) do
    context = viewer_context(state, side)

    MultiMenu.items(state.menu, context, window) ++
      opened_window(state.net.window, context, window) ++
      pairing(state, side, context, window)
  end

  def for_side(
        %{screen: :paused, mode: :online, menu: %Pause{prompt_side: side} = pause} = state,
        side,
        window
      ),
      do: Pause.items(pause, Context.of(state), window)

  def for_side(%{screen: :results, mode: :online} = state, side, window) do
    case OnlineFlow.waiting(state, side) do
      nil -> []
      line -> Gui.text(Lang.font(state.prefs.language), line, {320, 360}, window, halign: :center)
    end
  end

  def for_side(_state, _side, _window), do: []

  defp viewer_context(state, side) do
    context = OnlineFlow.context(state)
    peer = state.net.peer

    remote =
      cond do
        peer == nil -> context.remote
        peer.side == side -> %{id: OnlineFlow.me(state).id, name: OnlineFlow.me(state).name}
        true -> context.remote
      end

    %{context | remote: remote}
  end

  defp opened_window(nil, _context, _window), do: []
  defp opened_window(%module{} = open, context, window), do: module.items(open, context, window)

  defp pairing(%{net: %{pairing: nil}}, _side, _context, _window), do: []

  defp pairing(state, side, context, window) do
    opponent = %{
      name: (context.remote && context.remote.name) || "",
      ping: OnlineFlow.ping_of(state)
    }

    Challenger.items(state.net.pairing, side, Map.put(context, :opponent, opponent), window)
  end

  defp lobby(state, window) do
    context = Context.of(state)
    font = Lang.font(context.language)

    sides =
      for side <- [1, 2], name = side_name(state, side), name != nil do
        colour = mixed(PlayerColour.fixed(state.world, OnlineFlow.slot_side(state, side)))
        label = String.downcase(Lang.text(context.language, "online match", "wins", "Wins:"))
        wins_x = (side - 1) * 320 + 64
        tally_x = wins_x + Gui.text_width(font, label) + 8

        Gui.text(font, name, {if(side == 1, do: 144, else: 496), 22}, window,
          halign: :center,
          valign: :middle,
          colour: colour
        ) ++
          Gui.text(font, label, {wins_x, 46}, window, valign: :middle, colour: colour) ++
          Enum.flat_map(0..(OnlineFlow.wins(state, side) - 1)//1, fn won ->
            Gui.sprite("sTally", 0, {tally_x + won * 8, 46}, window, scale: {2, 2}, blend: colour)
          end)
      end

    settings =
      Gui.glyph(Glyphs.icon(context.devices[1], 10)) <>
        " " <> Lang.text(context.language, "online match", "prompt_settings", "settings")

    {_width, text_height} = Gui.rich_size(font, settings)
    prompt_height = max(24, text_height + 4)

    List.flatten(sides) ++
      ping(state, context, font, window) ++
      ready_labels(state, context, font, window) ++
      Gui.prompts([settings], {634, 394 - prompt_height + 1}, font, window)
  end

  defp side_name(state, side) do
    Enum.find_value(state.players, fn {_id, player} ->
      player.side == side && Map.get(player, :name)
    end)
  end

  defp mixed({red, green, blue}), do: {round(red * 0.65), round(green * 0.65), round(blue * 0.65)}

  defp ping(state, context, font, window) do
    case OnlineFlow.ping_of(state) do
      nil ->
        []

      ping ->
        shown = min(round(ping), 999)

        text =
          Lang.text(context.language, "online match", "ping", "Ping: {0} ms", [
            Integer.to_string(shown)
          ])

        width = Gui.text_width(font, text) + 12
        height = Gui.line_height(font) + 4

        Gui.rectangle({320 - width / 2, 2, 320 + width / 2, 2 + height}, {0, 0, 0}, window) ++
          Gui.text(font, text, {320, 2 + height / 2}, window,
            halign: :center,
            valign: :middle,
            colour: Matchmaking.ping_colour(shown)
          )
    end
  end

  defp ready_labels(state, context, font, window) do
    ready = String.upcase(Lang.text(context.language, "online match", "ready", "Ready"))

    for zone <- Gml.all(state.world, "ReadyZone"),
        instance = World.fetch(state.world, zone),
        item <- ready_label(state.world, zone, instance, ready, font, window),
        do: item
  end

  defp ready_label(world, zone, instance, ready, font, window) do
    {left, bottom} = {instance.x, instance.y + 64 * instance.image_yscale}
    player = Gml.var(world, zone, :playerIndex, 1)
    text_x = if player == 1, do: left + 14, else: left + 3
    occupied? = Gml.truthy?(Gml.var(world, zone, :occupied, 0))

    Gui.text(font, ready, {2 * text_x, 2 * (bottom - 46)}, window,
      valign: :middle,
      colour: if(occupied?, do: {255, 255, 255}, else: Gui.grey(150))
    )
  end

  defp seconds_left(%{mode: :cpu_battle, timer: timer}),
    do: max(ceil((@cpu_battle_results - timer) / 60), 0)

  defp seconds_left(_state), do: nil

  defp press_start(state, window) do
    context = Context.of(state)

    if rem(trunc(context.frame), @blink_period) < @blink_shown,
      do:
        Gui.outlined(
          Lang.font(context.language),
          MainMenu.press_start_text(context, 1),
          @press_start_at,
          window,
          halign: :center,
          valign: :bottom
        ),
      else: []
  end

  defp lesson(state, window) do
    case Tutorial.current_move(state.world) do
      nil ->
        []

      move ->
        context = Context.of(state)
        {key, english, buttons} = Lessons.line(move)
        glyphs = Enum.map(buttons, &Gui.glyph(Glyphs.icon(context.devices[1], &1)))
        words = Lang.text(context.language, "tutorial", key, english, glyphs)

        Gui.rich(Lang.font(context.language), words, @lesson_at, window,
          halign: :center,
          wrap: @lesson_wrap
        )
    end
  end

  defp window_items(nil, _context, _window), do: []
  defp window_items(%module{} = open, context, window), do: module.items(open, context, window)
end
