defmodule Nidhox.Screen.MultiMenu do
  @moduledoc """
  The online menu (`MultiMenu` in `rMultiMenu`): a panel of rows that is one of four
  menus, and the matchmaking search it runs.

    * `:main` — "Find a match", which starts the search; "Invite friend", which opens
      `Nidhox.Screen.Friends`; and NidhOX's "Host over ssh" and "Join by address". Back
      leaves for the main menu, at ONLINE
    * `:mtmk` — the search: "Searching for players", how many players are online, the
      search's reach ("my region" or "global", left and right), and the lines of
      `match.txt` one a second. Back cancels the search
    * `:wait` — "Waiting for opponent", with the opponent's name or "Invited {name}".
      Back asks LEAVE THE LOBBY?
    * `:error` — the error and "Return to menu"

  The menu shown is `:error` while there is an error, `:mtmk` while searching, `:wait`
  while a public or friends lobby is hosted, else `:main`.

  `step/3` takes both sides' input and the `context` (`Nidhox.Flow`'s): `now` (the
  milliseconds the game has run), `self` (this player's id), `lobbies` and `pings`
  (`Nidhox.Online`'s), `heard_at` (when the lobbies were last heard), `hosted` (the kind
  of lobby hosted, or `nil`), `remote` (`%{id, name}` of the opponent in the lobby, or
  `nil`), `invite` (the name of the friend invited, or `nil`), `invited?`, `global?`,
  `declined` (`Nidhox.Matchmaking`'s list), `pairing?` (whether the MATCH FOUND! box is
  up) and `rhymes`. It gives the menu and, in order:

    * `{:sound, :move | :choose}`
    * `{:host, kind}`, `:unhost` — host a lobby of `kind` (`:public`, `:standby`), stop
    * `{:join, lobby}` — join the lobby
    * `{:publish, fields}` — the search's beacon fields (`region`, `anyping`)
    * `{:declined, list}` — the declined list after the step
    * `{:global, global?}` — the search's reach changed
    * `:friends`, `:ssh`, `:address` — open the friends list, host over ssh, type an
      address to join
    * `:leave_prompt` — back on the wait menu
    * `:leave` — back on the main menu
    * `{:players_online, n}` — the players online, counted when a search's lobby list
      comes in

  Times follow the game: input waits 10 steps on opening and 2 after a window closes,
  the lobby list is asked for every 5 seconds while searching, a pick waits 3 seconds
  after a join, a join that goes nowhere is given up after 12 seconds, and a standby
  lobby is hosted at most every 3 seconds while the main menu shows.
  """

  alias Cauldron2D.GameMaker.Colour
  alias Nidhox.{Glyphs, Lang, Matchmaking}
  alias Nidhox.Screen.{Gui, MainMenu}

  @refresh_s 5
  @first_refresh_s 15
  @pick_gap_ms 3_000
  @join_timeout_ms 12_000
  @publish_every_ms 1_000
  @anyping_after_ms 10_000
  @cancel_ms 5_000
  @idle_host_ms 3_000
  @rhyme_us 1_000_000
  @frame_us 16_667
  @row 20
  @half_width 140
  @panel_width 320
  @most_height 320
  @connect_steps 10

  defstruct menu: :main,
            opts: %{},
            noinput: 10,
            prompt_side: 1,
            error: "",
            want: false,
            active: false,
            loading: false,
            requested_at: nil,
            resume: false,
            since: 0,
            join_at: 0,
            cancel_until: 0,
            last_owner: nil,
            partner: nil,
            anyping: false,
            region: "0",
            published_at: 0,
            hub_refresh: @first_refresh_s,
            idle_host_at: 0,
            rhyme_id: 0,
            rhyme_time: 0,
            rhyme: "",
            connect_time: 0

  @type t :: %__MODULE__{}

  @doc "The online menu as it opens, its input waiting 10 steps."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "The menu after `steps` steps without input (`menu_noinput`)."
  @spec hold(t(), non_neg_integer()) :: t()
  def hold(menu, steps), do: %{menu | noinput: max(menu.noinput, steps)}

  @doc "The menu searching again after a pairing that fell through (`mtmk_resume`)."
  @spec resumed(t()) :: t()
  def resumed(menu), do: %{menu | resume: true}

  @doc "The menu with the search given up and nothing more wanted of it."
  @spec stopped(t()) :: t()
  def stopped(menu), do: %{menu | want: false, active: false, resume: true}

  @doc "The menu with `error` shown (`menu_error`)."
  @spec failed(t(), String.t()) :: t()
  def failed(menu, error), do: %{menu | error: error}

  @doc "The menu once an opponent has arrived: no longer searching, the opponent kept as the partner."
  @spec arrived(t(), integer() | nil) :: t()
  def arrived(menu, partner),
    do: %{menu | active: false, partner: if(menu.want, do: partner, else: menu.partner)}

  @doc "The menu shown for `context`: `:error`, `:mtmk`, `:wait` or `:main`."
  @spec shown(t(), map()) :: :error | :mtmk | :wait | :main
  def shown(%{error: error}, _context) when error != "", do: :error
  def shown(%{active: true}, _context), do: :mtmk
  def shown(_menu, %{hosted: hosted}) when hosted in [:public, :friends], do: :wait
  def shown(menu, _context), do: menu.menu

  @doc "The menu after a step of `players`' input; see the module documentation."
  @spec step(t(), map(), map()) :: {t(), [term()]}
  def step(menu, players, context) do
    {menu, events} = menu |> rhymed_reset() |> resumed_search(context)

    menu =
      %{menu | prompt_side: MainMenu.prompt_side(players, menu.prompt_side)}
      |> partnered(context)

    {menu, events}
    |> chain(&join_timeout(&1, context))
    |> chain(&rhymed(&1, context))
    |> chain(&idle_host(&1, context))
    |> chain(&handled(&1, players, context))
    |> chain(&searched(&1, context))
  end

  defp chain({menu, events}, next) do
    {menu, more} = next.(menu)
    {menu, events ++ more}
  end

  defp rhymed_reset(%{active: false} = menu), do: %{menu | rhyme_id: 0, rhyme_time: 0, rhyme: ""}
  defp rhymed_reset(menu), do: menu

  defp resumed_search(%{resume: true} = menu, context),
    do: resume(%{menu | resume: false, join_at: 0}, context)

  defp resumed_search(menu, _context), do: {menu, []}

  defp resume(%{want: false} = menu, _context), do: {menu, [:unhost]}

  defp resume(menu, context) do
    hosting? = context.hosted == :public

    declined =
      cond do
        menu.partner != nil -> menu.partner
        not hosting? -> menu.last_owner
        true -> nil
      end

    list = Matchmaking.decline(context.declined, declined, context.now, context.invited?)

    menu = %{
      menu
      | partner: nil,
        last_owner: nil,
        active: true,
        loading: true,
        requested_at: context.now,
        hub_refresh: @refresh_s
    }

    menu = if hosting?, do: menu, else: %{menu | anyping: false}
    {menu, [{:declined, list}]}
  end

  defp partnered(%{want: true} = menu, %{remote: %{id: id}}) when id != nil,
    do: %{menu | partner: id}

  defp partnered(menu, _context), do: menu

  defp join_timeout(%{join_at: 0} = menu, _context), do: {menu, []}

  defp join_timeout(menu, context) do
    cond do
      not menu.want or context.pairing? or context.remote != nil ->
        {%{menu | join_at: 0}, []}

      context.now - menu.join_at >= @join_timeout_ms ->
        {%{menu | join_at: 0, resume: context.hosted != :public}, []}

      true ->
        {menu, []}
    end
  end

  defp rhymed(menu, context) do
    if shown(menu, context) == :mtmk and context.rhymes != [] do
      time = menu.rhyme_time + @frame_us

      if time >= @rhyme_us do
        id = rem(menu.rhyme_id + 1, length(context.rhymes))

        {%{menu | rhyme_time: time - @rhyme_us, rhyme_id: id, rhyme: Enum.at(context.rhymes, id)},
         []}
      else
        {%{menu | rhyme_time: time}, []}
      end
    else
      {menu, []}
    end
  end

  defp idle_host(menu, context) do
    if shown(menu, context) == :main and context.hosted == nil and context.now > menu.idle_host_at,
      do: {%{menu | idle_host_at: context.now + @idle_host_ms}, [{:host, :standby}]},
      else: {menu, []}
  end

  defp handled(menu, players, context) do
    shown = shown(menu, context)
    rows = rows(menu, shown, context)
    selected = selected(menu, shown, rows)
    connecting? = menu.connect_time >= @connect_steps
    can_input? = not context.window?

    cond do
      menu.noinput > 0 ->
        {%{menu | noinput: menu.noinput - 1}, []}

      MainMenu.any_pressed?(players, 9) and can_input? ->
        back(menu, shown, context)

      MainMenu.any_pressed?(players, 9) and connecting? ->
        {menu, [:unhost]}

      can_input? ->
        moved_or_pressed(menu, shown, rows, selected, players, context)

      true ->
        {menu, []}
    end
  end

  defp moved_or_pressed(menu, shown, rows, selected, players, context) do
    delta = pressed(players, 3) - pressed(players, 2)
    {moved, sounds} = moved(menu, shown, rows, selected, delta)

    if sounds != [] do
      {moved, sounds}
    else
      pressed_row(moved, shown, Enum.at(rows, selected(moved, shown, rows)), players, context)
    end
  end

  defp moved(menu, _shown, rows, _selected, _delta) when length(rows) <= 1, do: {menu, []}
  defp moved(menu, _shown, _rows, _selected, 0), do: {menu, []}

  defp moved(menu, shown, rows, selected, delta) do
    next = next_selectable(rows, selected, delta)

    if next == selected,
      do: {menu, []},
      else: {%{menu | opts: Map.put(menu.opts, shown, next)}, [{:sound, :move}]}
  end

  defp next_selectable(rows, selected, delta) do
    count = length(rows)

    Enum.reduce_while(1..count, selected, fn _try, at ->
      at = Integer.mod(at + delta, count)
      if row_type(Enum.at(rows, at)) == -2, do: {:cont, at}, else: {:halt, at}
    end)
  end

  defp pressed_row(menu, _shown, {_label, 0, action}, players, context) do
    if MainMenu.any_pressed?(players, 10) or MainMenu.any_pressed?(players, 4),
      do: press(menu, action, context),
      else: {menu, []}
  end

  defp pressed_row(menu, _shown, {_label, 1, :global}, players, context) do
    change =
      cond do
        MainMenu.any_pressed?(players, 0) -> -1
        Enum.any?([1, 4, 10], &MainMenu.any_pressed?(players, &1)) -> 1
        true -> 0
      end

    if change == 0,
      do: {menu, []},
      else: {%{menu | hub_refresh: 0}, [{:global, not context.global?}, {:sound, :move}]}
  end

  defp pressed_row(menu, _shown, _row, _players, _context), do: {menu, []}

  defp press(menu, :find, context) do
    {%{
       menu
       | want: true,
         active: true,
         loading: true,
         requested_at: context.now,
         since: context.now,
         anyping: false,
         join_at: 0,
         partner: nil,
         last_owner: nil,
         hub_refresh: @refresh_s
     }, [{:sound, :choose}, :unhost]}
  end

  defp press(menu, :friends, _context), do: {%{menu | noinput: 2}, [{:sound, :choose}, :friends]}
  defp press(menu, :ssh, _context), do: {menu, [{:sound, :choose}, :ssh]}
  defp press(menu, :address, _context), do: {menu, [{:sound, :choose}, :address]}
  defp press(menu, :return, _context), do: {%{menu | error: ""}, [{:sound, :choose}]}
  defp press(menu, _action, _context), do: {menu, []}

  defp back(menu, :main, _context), do: {menu, [:leave]}

  defp back(menu, :mtmk, context) do
    {%{
       menu
       | active: false,
         want: false,
         join_at: 0,
         cancel_until: context.now + @cancel_ms,
         idle_host_at: context.now + @idle_host_ms
     }, [{:declined, []}, :unhost]}
  end

  defp back(menu, :wait, _context), do: {menu, [:leave_prompt]}
  defp back(menu, :error, _context), do: {%{menu | error: ""}, []}

  defp searched(menu, context) do
    if shown(menu, context) == :mtmk and menu.active,
      do:
        menu
        |> refreshed(context)
        |> chain(&published(&1, context))
        |> chain(&counted(&1, context)),
      else: {menu, []}
  end

  defp refreshed(menu, context) do
    if menu.loading and context.heard_at != nil and context.heard_at > menu.requested_at,
      do: finished(%{menu | loading: false}, context),
      else: {menu, []}
  end

  defp finished(menu, context) do
    others = Enum.filter(context.lobbies, &(&1.kind == "public" and &1.owner != context.self))
    online = Enum.reduce(others, 1, &(&1.players + &2))

    candidates =
      for lobby <- others,
          lobby.open and lobby.players < lobby.slots,
          do: Map.put(lobby, :ping, Map.get(context.pings, {lobby.address, lobby.port}))

    if context.now - menu.join_at >= @pick_gap_ms,
      do: picked(menu, candidates, context, [{:players_online, online}]),
      else: {menu, [{:players_online, online}]}
  end

  defp picked(menu, candidates, context, events) do
    search = %{
      now: context.now,
      since: menu.since,
      declined: context.declined,
      global?: context.global?,
      hosting: if(context.hosted == :public, do: context.self)
    }

    {pick, declined} = Matchmaking.pick(candidates, search)
    events = events ++ [{:declined, declined}]

    case {pick, context.hosted} do
      {nil, :public} ->
        {menu, events}

      {nil, _hosted} ->
        declined =
          if menu.join_at > 0,
            do: Matchmaking.decline(declined, menu.last_owner, context.now, context.invited?),
            else: declined

        {%{menu | anyping: false, region: "0", join_at: 0},
         events ++ [{:declined, declined}, {:host, :public}]}

      {lobby, hosted} ->
        unhost = if hosted, do: [:unhost], else: []

        {%{menu | last_owner: lobby.owner, join_at: context.now},
         events ++ unhost ++ [{:join, lobby}]}
    end
  end

  defp published(menu, context) do
    if context.hosted == :public and context.now >= menu.published_at do
      anyping = menu.anyping or context.now - menu.since >= @anyping_after_ms
      region = if context.global?, do: "0", else: "1"

      {%{menu | published_at: context.now + @publish_every_ms, anyping: anyping, region: region},
       [{:publish, %{"anyping" => if(anyping, do: "1", else: "0"), "region" => region}}]}
    else
      {menu, []}
    end
  end

  defp counted(menu, context) do
    refresh = menu.hub_refresh - 1 / 60

    if refresh <= 0,
      do: {%{menu | hub_refresh: @refresh_s, loading: true, requested_at: context.now}, []},
      else: {%{menu | hub_refresh: refresh}, []}
  end

  defp pressed(players, button), do: if(MainMenu.any_pressed?(players, button), do: 1, else: 0)

  defp selected(menu, shown, rows) do
    index = Map.get(menu.opts, shown, 0)
    index = if index < length(rows), do: index, else: 0

    case Enum.at(rows, index) do
      nil -> 0
      row -> if row_type(row) == -2, do: next_selectable(rows, index, 1), else: index
    end
  end

  defp row_type({_label, type, _action}), do: type

  defp rows(_menu, :main, context) do
    [
      {text(context, "find_a_match", "Find a match"), 0, :find},
      {text(context, "invite_friend", "Invite friend"), 0, :friends},
      {"Host over ssh", 0, :ssh},
      {"Join by address", 0, :address}
    ]
  end

  defp rows(menu, :mtmk, context) do
    online =
      if context.players_online >= 0,
        do: "#{context.players_online} " <> text(context, "online", "online"),
        else: ""

    reach =
      if context.global?,
        do: text(context, "search_global", "global"),
        else: text(context, "search_region", "my region")

    [
      {text(context, "searching_for_players", "Searching for players"), -2, nil},
      {"", -2, nil},
      {online, -2, nil},
      {text(context, "search", "search:") <> " < " <> reach <> " >", 1, :global},
      {"", -2, nil},
      {menu.rhyme, -2, :rhyme}
    ]
  end

  defp rows(_menu, :wait, context) do
    second =
      cond do
        context.remote != nil and context.remote.name != "" ->
          [{context.remote.name, -2, nil}]

        context.remote == nil and context.invite not in [nil, ""] ->
          [
            {Lang.text(context.language, "online match", "invited", "Invited {0}", [
               context.invite
             ]), -2, nil}
          ]

        true ->
          []
      end

    [{text(context, "waiting_for_opponent", "Waiting for opponent"), -1, nil} | second]
  end

  defp rows(menu, :error, context),
    do: [{menu.error, -2, nil}, {text(context, "return_to_menu", "Return to menu"), 0, :return}]

  @doc "The menu's drawing as GUI items, for `context` as `step/3` takes it with `frame`, `devices` and `language`."
  @spec items(t(), map(), Gui.window()) :: [map()]
  def items(menu, context, window) do
    font = Lang.font(context.language)
    shown = shown(menu, context)
    rows = rows(menu, shown, context)
    height = min(length(rows) * @row, @most_height)
    left = 320 - @panel_width / 2
    top = 200 - height / 2 - 12 - 30
    right = left + @panel_width
    bottom = 200 + height / 2 + 12

    MainMenu.dim(0.8, window) ++
      Gui.box("sprtextBgBox", {left, top, @panel_width, bottom - top}, window) ++
      Gui.text(
        font,
        Lang.text(context.language, "main menu", "online_versus", "ONLINE"),
        {320, top + 15},
        window,
        halign: :center,
        valign: :middle,
        colour: {255, 255, 0}
      ) ++
      Gui.rectangle({left + 12, top + 27, right - 12, top + 27}, Gui.grey(50), window) ++
      list_items(menu, shown, rows, context, font, window) ++
      prompts(menu, shown, context, {right - 6, bottom}, font, window) ++
      status(context, font, bottom, window)
  end

  defp list_items(menu, shown, rows, context, font, window) do
    selected = selected(menu, shown, rows)
    line = Gui.line_height(font)
    total = @row * length(rows) - (@row - line)
    x0 = (640 - 2 * @half_width) / 2

    y0 =
      if total >= @most_height,
        do: (400 - line) / 2 - selected * @row,
        else: (400 - total) / 2

    rows
    |> Enum.with_index()
    |> Enum.flat_map(fn {{label, type, action}, index} ->
      y = y0 + index * @row
      chosen? = index == selected
      shown_label = connecting(label, menu, shown, index, selected, context)

      {box, alpha} =
        cond do
          shown == :mtmk ->
            {[], 1}

          not chosen? and type == -1 ->
            {[], 40 / 255}

          not chosen? ->
            {[], 80 / 255}

          type >= 0 ->
            {Gui.rectangle({x0, y - 4, x0 + 2 * @half_width, y + 14}, {255, 255, 255}, window,
               alpha: 30 / 255
             ), 1}

          true ->
            {Gui.rectangle({x0, y - 4, x0 + 2 * @half_width, y + 14}, {255, 255, 255}, window,
               alpha: 15 / 255
             ), 160 / 255}
        end

      colour = if action == :rhyme, do: rhyme_colour(context.frame), else: {255, 255, 255}

      box ++
        Gui.text(font, shown_label, {x0 + @half_width, y + 5}, window,
          halign: :center,
          valign: :middle,
          colour: colour,
          alpha: alpha
        )
    end)
  end

  defp connecting(label, menu, shown, index, selected, context) do
    target = if shown == :mtmk, do: 0, else: selected

    if index == target and menu.connect_time >= @connect_steps do
      dots = Enum.at(["   ", ".  ", ".. ", "..."], Integer.mod(div(menu.connect_time, 10) - 1, 4))
      text(context, "connecting", "Connecting") <> dots
    else
      label
    end
  end

  defp rhyme_colour(frame) do
    value = :math.sin(frame / 60)
    hue = cycle(value, 0, 255)
    Colour.hsv(hue, 180, 255)
  end

  defp cycle(value, low, high) do
    span = high - low
    result = low + (value - low - span * Float.floor((value - low) / span))
    if result < 0, do: result + span, else: result
  end

  defp prompts(menu, shown, context, at, font, window) do
    if context.window? do
      []
    else
      device = context.devices[menu.prompt_side]

      back =
        glyphs(device, [9]) <>
          " " <> Lang.text(context.language, "main menu", "prompt_back", "back")

      select =
        glyphs(device, [8]) <>
          " " <> Lang.text(context.language, "main menu", "prompt_select", "select")

      adjust =
        glyphs(device, [0, 1]) <>
          " " <> Lang.text(context.language, "main menu", "prompt_adjust", "adjust")

      list =
        case shown do
          :mtmk -> [adjust, back]
          :wait -> [back]
          _other -> [select, back]
        end

      Gui.prompts(list, at, font, window)
    end
  end

  defp status(%{address: nil}, _font, _bottom, _window), do: []

  defp status(%{address: address}, font, bottom, window),
    do:
      Gui.text(font, address, {320, bottom + 40}, window, halign: :center, colour: Gui.grey(150))

  defp glyphs(device, buttons), do: Enum.map_join(buttons, &Gui.glyph(Glyphs.icon(device, &1)))

  defp text(context, key, english), do: Lang.text(context.language, "online match", key, english)
end
