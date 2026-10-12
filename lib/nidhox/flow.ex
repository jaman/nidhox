defmodule Nidhox.Flow do
  @moduledoc """
  How NidhOX goes from screen to screen: one step of the game's state on its current
  screen, given both sides' input that step (`%{1 => input, 2 => input}`, each
  `%{held, pressed, released}`).

    * `:logos` — `Nidhox.Screen.Logos` over `rLogos`; when they end, or on any press,
      the title
    * `:title` — `rMainMenu` under the logo, the camera swaying across the room
      (`room_width / 2 + sin(frame / 500) × (room_width / 2 − 160)`); "press start"
      until a press, then the game's menus, each a `Nidhox.Screen.MenuList`, all in
      this room: the main menu — MULTIPLAYER, TOURNAMENT, OPTIONS, CREDITS, QUIT TO
      DESKTOP, HOW TO PLAY, SINGLE PLAYER and NidhOX's CHALLENGE, MULTIPLAYER selected
      at first; SINGLE PLAYER — BEGIN; MULTIPLAYER — OFFLINE VERSUS, ONLINE VERSUS,
      VARIANTS; ONLINE VERSUS — HOST, JOIN, SET IP; TOURNAMENT — PLAYERS (3 to 8, left
      and right), MAP (left and right), VARIANTS, START TOURNAMENT; VARIANTS — the game's
      variants (`Nidhox.Rules`), chosen one by one. A move plays `sfxChangeLevel1`, a
      choice `sndLevel`. `:jump` goes back to the menu before, selecting what opened
      it, and on the main menu selects QUIT TO DESKTOP. On the menus before ONLINE
      VERSUS's choices, the machine neither hosts nor looks for hosts
    * `:hosting` — hosting (`Nidhox.Online`), the address and join code shown, until a
      player on a client of their own takes a side, then the level select; `:jump` or
      `:pause` (`Esc`) goes back, hosting stopped
    * `:ssh_hosting` — HOST OVER SSH: the client of the player who chose it is asked for
      the port to serve on (`Nidhox.Typing`; empty, or not a port, for any free one,
      started with `ssh_port` when set), then the game served over ssh there
      (`Nidhox.Online`) and the command to connect with shown, until a player connecting that way takes a side,
      then the level select; `:jump` or `:pause` (`Esc`) goes back, serving stopped
    * `:join` — the hosts heard on the local network; choosing one asks for its code
    * `:address` — SET IP: the client of the player who chose it is asked to type the
      host's address (`Nidhox.Typing`, started with this machine's network part), then
      the code
    * `:code` — the client of the player joining is asked to type the host's join code;
      what they type (`typed/4`) joins, and that client is asked to enter the host's
      world. On both screens `:start` or `:attack` — pressed again once every player has
      let go of both since the typing closed — asks for the typing again and
      `:jump` or `:pause` (`Esc`) goes back
    * `:demo` — the title's attract mode (`MainMenu`'s `autoStartTimer`): after 1200
      steps on the title with no press, a match in one of the areas at random
      (`choose(20, 21, 22, 23, 25)`) played by the computer on both sides (`System.flow`
      1), with the logo and "press start" over it (`Nidhox.Objects.System`); any press,
      or the match ending, goes to the main menu
    * `:levels` — `Nidhox.Screen.Levels` over `rLevelSelect`: its chosen area begins a
      versus bout under the variants chosen; with no move for 720 steps, the main menu, except while
      this machine hosts ONLINE VERSUS
    * `:tournament` — the tournament's own rooms, run by the game's objects
      (`Nidhox.Objects.Tournament`, `Nidhox.Objects.CountDowns`): the ladder
      (`rShowLadder`), the warm-up before each match (`rPreMatch`, where `:start`
      pauses) and the champion (`rShowChampion`). Its match's start leads to `:bout`,
      and the main menu, once the champion's countdown goes there, to the main menu
    * `:tutorial` — HOW TO PLAY: `rTutorial` with the game's own `Tutorial` (`System.flow`
      656686433); it ends at the main menu once the tutorial is gone
    * `:challenge` — CHALLENGE: `rChallengeMode` with the game's own `ChallengeMode`
      (`Nidhox.Objects.Challenge`), until QUIT TO TITLE SCREEN from its pause
    * `:credits` — `Nidhox.Screen.Credits` over `rCredits`, until `:attack` or `:start`
    * `:bout` — the match (`Nidhox.Bout`), run by the game's own objects from its
      faceoff on under the rules chosen on the level select (`Nidhox.Rules`), until its
      `Match` is gone; `:start` or `:pause` (`Esc`) pauses it
    * `:paused` — `Nidhox.Screen.Pause`; UNPAUSE GAME goes back to the bout, CHANGE LEVEL
      ends the match (its music with it) for the level select, and QUIT TO TITLE SCREEN
      ends the match and any tournament for the title — except when chosen by the
      player from another machine while this machine hosts: then a bout in progress is
      the host's by forfeit, the match ends, that player's client is asked to quit
      (`ask/3`), and the hosting screen comes back, still hosting, saying "the other
      player quit"
    * `:results` — `Nidhox.Screen.Results` over `rMatchStats`: a press goes on to the
      level select, or with "watch replay" turned up, to the replay. In a single player
      run the run's own step moves on at a press
    * `:replay` — the bout just fought, run again from its start with every step's
      recorded input (the computer's as it chose them), then back to the results;
      `:start` (SKIP THIS) ends it early

  SINGLE PLAYER is the game's own run (`Nidhox.Objects.Arcade`) against the computer
  (the match's `Brain`) on side 2: `:arcade` is its progress screen in
  `rArcadeProgress`, from which the run starts each bout; after a bout a press on the
  results leads back to it — a loss to the same level, a win to the next — and after the
  last win to `:arcade_complete` (`rBeatGameStats`), from which a press goes to the main
  menu. The main menu ends any run and match (`kill(ArcadeMode)`, `kill(Match)`). OFFLINE VERSUS is the two sides against each other
  in the area chosen. ONLINE VERSUS is the same with side 2 a player joined from
  another machine: the host's world is the one both play in, and CONTINUE after a bout
  goes back to the level select. TOURNAMENT is the game's single elimination tournament
  (`Nidhox.Tournament`) of its menu's PLAYERS in its MAP (`Nidhox.Bout.start_tournament/4`),
  each match a bout under the variants chosen, the first of its two players on side 1;
  a finished match goes back to the ladder. OPTIONS and QUIT TO DESKTOP ask the client of
  the player who chose
  them to open the game's options or to quit (`ask/3`).

  QUIT TO TITLE SCREEN chosen by the host while it serves the game over ssh asks the client
  of each player connected that way to quit, as their own LEAVE GAME does, and shows the
  title; the ssh server stops once they have left, or after `@ask_steps` steps, so each
  of those players' sessions ends as their own quitting ends it.
  """

  alias Cauldron2D.Distribution
  alias Cauldron2D.GameMaker.Data
  alias Cauldron2D.GameMaker.Rooms
  alias Cauldron2D.GameMaker.Step
  alias Cauldron2D.GameMaker.World
  alias Nidhox.{Assets, Bout, Online}
  alias Nidhox.Bout.Sound
  alias Nidhox.Gml
  alias Nidhox.Objects.Grass
  alias Nidhox.Rules
  alias Nidhox.Screen.{Credits, Levels, Logos, MenuList, Pause, Results, Title}

  @no_keys %{held: MapSet.new(), pressed: MapSet.new(), released: MapSet.new()}
  @areas ["Cemetery", "Castle", "Mines", "Sky", "Wilds"]
  @tutorial_flow 656_686_433
  @ask_steps 30
  @sway_period 500
  @sway_margin 160
  @move_sound 65
  @attract_steps 1200
  @attract_levels [20, 21, 22, 23, 25]
  @choose_sound 22
  @fewest_entrants 3
  @played_online [:levels, :bout, :paused, :results, :replay]
  @most_entrants 8
  @rooms %{
    logos: "rLogos",
    title: "rMainMenu",
    levels: "rLevelSelect",
    credits: "rCredits",
    tutorial: "rTutorial",
    results: "rMatchStats",
    ladder: "rShowLadder",
    online: "rMainMenu"
  }

  @doc "The areas, in the order the level select goes through them."
  @spec areas() :: [String.t()]
  def areas, do: @areas

  @doc "The state after one step on its screen with `players`' input."
  @spec step(map(), %{1 => map(), 2 => map()}) :: map()
  def step(%{screen: :logos} = state, players) do
    state = scenery(state, players)
    if Title.continue?(players) or Logos.done?(state.timer), do: title(state), else: state
  end

  def step(%{screen: :title} = state, players) do
    state = state |> idled(players) |> titled(players)
    if state.screen == :title and state.idle > @attract_steps, do: demo(state), else: state
  end

  def step(%{screen: :demo} = state, players) do
    if any_press?(players) or not Bout.running?(state.world),
      do: state |> killed(["Match"]) |> main_menu(),
      else: advance(state, players)
  end

  def step(%{screen: :levels} = state, players) do
    state = scenery(state, players)

    case Levels.input(state.levels, players) do
      {:choose, area} -> chosen(state, area)
      :given_up -> given_up(state)
      {:moved, levels} -> %{state | levels: levels, world: Levels.pan(levels, state.world)}
      {:stay, levels} -> %{state | levels: levels, world: Levels.pan(levels, state.world)}
    end
  end

  def step(%{screen: :ssh_hosting} = state, players) do
    state = state |> scenery(players) |> armed(players)
    again = Enum.find([1, 2], &(:start in players[&1].pressed or :attack in players[&1].pressed))

    cond do
      ssh_joined?(state) ->
        met(state)

      backing_out?(players) ->
        online_menu(state)

      again != nil and state.typing_armed and state.online.ssh == nil ->
        typing(%{state | typer: again})

      true ->
        state
    end
  end

  def step(%{screen: :hosting} = state, players) do
    state = scenery(state, players)

    cond do
      joined?(state) -> met(state)
      backing_out?(players) -> online_menu(state)
      true -> state
    end
  end

  def step(%{screen: :join} = state, players) do
    state = scenery(state, players)

    case MenuList.input(found_menu(state), players) do
      {:choose, {:host, address}, side} -> code_entry(state, address, side)
      {:choose, :disabled, _side} -> state
      {:back, _side} -> online_menu(state)
      {:moved, menu} -> sound(%{state | menu: menu}, @move_sound)
      {:stay, menu} -> %{state | menu: menu}
      {:change, _option, _step, _side} -> state
    end
  end

  def step(%{screen: screen} = state, players) when screen in [:address, :code] do
    state = state |> scenery(players) |> armed(players)
    again = Enum.find([1, 2], &(:start in players[&1].pressed or :attack in players[&1].pressed))

    cond do
      backing_out?(players) -> online_menu(state)
      again != nil and state.typing_armed -> typing(%{state | typer: again})
      true -> state
    end
  end

  def step(%{screen: :tournament} = state, players) do
    if in_room?(state.world, "rPreMatch") and pausing?(players),
      do: %{state | screen: :paused, menu: Pause.menu(:tournament, false)},
      else: state |> scenery(players) |> followed()
  end

  def step(%{screen: :credits} = state, players) do
    state = scenery(state, players)

    if Credits.leave?(players), do: main_menu(state), else: state
  end

  def step(%{screen: :bout} = state, players) do
    if pausing?(players),
      do: %{state | screen: :paused, menu: Pause.menu(state.mode, Online.hosting?(state))},
      else: bout(state, players)
  end

  def step(%{screen: :challenge} = state, players) do
    if pausing?(players),
      do: %{state | screen: :paused, menu: Pause.menu(:challenge, false)},
      else: advance(state, players)
  end

  def step(%{screen: :tutorial} = state, players) do
    cond do
      pausing?(players) ->
        %{state | screen: :paused, menu: Pause.menu(:tutorial, false)}

      Gml.exists?(state.world, "Tutorial") ->
        advance(state, players)

      true ->
        main_menu(state)
    end
  end

  def step(%{screen: :paused} = state, players) do
    case Pause.input(state.menu, players) do
      {:choose, :unpause, _side} -> %{state | screen: resumed(state), menu: nil}
      {:choose, :change_level, _side} -> state |> killed(["Match"]) |> levels()
      {:choose, :title, side} -> quit_to_title(state, side)
      {:choose, :options, side} -> ask(state, side, :menu)
      {:stay, menu} -> %{state | menu: menu}
    end
  end

  def step(%{screen: :arcade} = state, players) do
    state = scenery(state, players)
    if Bout.running?(state.world), do: arcade_bout(state), else: state
  end

  def step(%{screen: :arcade_complete} = state, players) do
    state = scenery(state, players)
    if in_room?(state.world, "rMainMenu"), do: main_menu(state), else: state
  end

  def step(%{screen: :results, mode: :arcade} = state, players) do
    state = scenery(state, players)

    cond do
      in_room?(state.world, "rArcadeProgress") ->
        %{state | screen: :arcade, menu: nil, timer: 0}

      in_room?(state.world, "rBeatGameStats") ->
        %{state | screen: :arcade_complete, menu: nil, timer: 0}

      true ->
        state
    end
  end

  def step(%{screen: :results} = state, players) do
    state = scenery(state, players)

    case Results.input(state.menu || :continue, players) do
      {:go, :continue} -> levels(state)
      {:go, :replay} -> replay(state)
      {:stay, choice} -> %{state | menu: choice}
    end
  end

  def step(%{screen: :replay, recording: %{inputs: []}} = state, _players), do: replayed(state)

  def step(%{screen: :replay, recording: %{inputs: [next | rest]} = recording} = state, players) do
    if Enum.any?(Map.values(players), &(:start in &1.pressed)),
      do: replayed(state),
      else: advance(%{state | recording: %{recording | inputs: rest}}, next)
  end

  @doc """
  The state with `ask` (`:menu` or `:quit`) put to the client of the player on `side`,
  for the next `@ask_steps` steps, under a number no earlier ask had.
  """
  @spec ask(map(), 1 | 2, :menu | {:menu, term()} | :quit | {:enter, map()}) :: map()
  def ask(state, side, ask) do
    number = state.ask_number + 1

    asks =
      for {_id, %{side: ^side, owner: owner}} <- state.players,
          into: state.asks,
          do: {owner, {number, ask, state.steps + @ask_steps}}

    %{state | ask_number: number, asks: asks}
  end

  @doc """
  The state after the player on `side` typed `text` for an entry of `kind` (`:address`
  or `:code`), or went back from it (`text` `:back`); typing for a screen no longer
  shown changes nothing.
  """
  @spec typed(map(), 1 | 2, :address | :code, String.t() | :back) :: map()
  def typed(%{screen: kind} = state, _side, kind, :back) when kind in [:address, :code],
    do: online_menu(state)

  def typed(%{screen: :ssh_hosting} = state, _side, :ssh_port, :back), do: online_menu(state)

  def typed(%{screen: :ssh_hosting} = state, _side, :ssh_port, port),
    do: %{state | typing_armed: false, effects: [{:ssh_host, ssh_port(port)} | state.effects]}

  def typed(%{screen: :address} = state, side, :address, ""), do: typing(%{state | typer: side})

  def typed(%{screen: :address} = state, side, :address, address),
    do: code_entry(state, address, side)

  def typed(%{screen: :code, address: address} = state, side, :code, code),
    do: %{state | typing_armed: false, effects: [{:join, address, code, side} | state.effects]}

  def typed(state, _side, _kind, _text), do: state

  @doc """
  The state after the player from another machine left the ONLINE VERSUS game this
  machine hosts, while on the level select, in a bout, its pause, the results or the
  replay: a bout in progress won by forfeit by the hosting player (a `{:result, row}`
  event with `won?` `true`), the match ended, and the hosting screen it was hosted from
  (`:hosting` or `:ssh_hosting`) shown again with the status "the other player left",
  still hosting, so the next player connects as the first did. Any other state is
  returned unchanged.
  """
  @spec opponent_gone(map()) :: map()
  def opponent_gone(state), do: state |> departed() |> closed() |> forfeited()

  defp forfeited(%{screen: screen} = state) when screen in @played_online do
    if Online.hosting?(state) and not opponent?(state), do: forfeit(state), else: state
  end

  defp forfeited(state), do: state

  @doc "The state at the logos, the first screen."

  @spec logos(map()) :: map()
  def logos(state), do: enter(%{state | screen: :logos, menu: nil, timer: 0}, :logos)

  defp title(state),
    do:
      enter(
        offline(%{state | screen: :title, menu: nil, timer: 0}),
        :title
      )

  defp main_menu(state) do
    state = %{state | world: Enum.reduce(["ArcadeMode", "Match"], state.world, &kill_all(&2, &1))}

    menu(state, :main, nil)
  end

  defp titled(%{menu: nil} = state, players) do
    state = state |> scenery(players) |> sway()
    if Title.continue?(players), do: main_menu(state), else: state
  end

  defp titled(state, players) do
    state = state |> scenery(players) |> sway()

    case MenuList.input(state.menu, players) do
      {:moved, menu} ->
        sound(%{state | menu: menu}, @move_sound)

      {:stay, menu} ->
        %{state | menu: menu}

      {:choose, option, side} ->
        state |> sound(@choose_sound) |> chose(state.menu.key, option, side)

      {:change, option, step, _side} ->
        changed(state, state.menu.key, option, step)

      {:back, _side} ->
        back(state, state.menu.key)
    end
  end

  defp ssh_port(typed) do
    case Integer.parse(typed) do
      {port, ""} when port in 1..65_535 -> port
      _any -> 0
    end
  end

  defp backing_out?(players),
    do: Enum.any?(Map.values(players), &(:jump in &1.pressed or :pause in &1.pressed))

  defp pausing?(players),
    do: Enum.any?(Map.values(players), &(:start in &1.pressed or :pause in &1.pressed))

  defp idled(state, players),
    do: %{state | idle: if(any_press?(players), do: 0, else: state.idle + 1)}

  defp any_press?(players), do: Enum.any?(Map.values(players), &(MapSet.size(&1.pressed) > 0))

  defp demo(state) do
    {level, world} = Gml.choose(state.world, @attract_levels)
    area = Bout.area_of_level(level)
    world = Bout.start(world, area, %Rules{}, :demo)
    %{state | screen: :demo, mode: :demo, menu: nil, area: area, world: world, idle: 0, timer: 0}
  end

  defp menu(state, key, selected) do
    state = offline(%{state | screen: :title, menu: menu_list(state, key, selected), timer: 0})
    enter(state, :title)
  end

  defp menu_list(_state, :main, selected),
    do:
      MenuList.new(
        :main,
        nil,
        [
          {"MULTIPLAYER", :multi},
          {"TOURNAMENT", :tournament},
          {"OPTIONS", :options},
          {"CREDITS", :credits},
          {"QUIT TO DESKTOP", :quit},
          {"HOW TO PLAY", :tutorial},
          {"SINGLE PLAYER", :single},
          {"CHALLENGE", :challenge}
        ],
        selected
      )

  defp menu_list(_state, :single, selected),
    do: MenuList.new(:single, "SINGLE PLAYER", [{"BEGIN", :begin}], selected)

  defp menu_list(_state, :multi, selected),
    do:
      MenuList.new(
        :multi,
        "MULTIPLAYER",
        [{"OFFLINE VERSUS", :versus}, {"ONLINE VERSUS", :online}, {"VARIANTS", :variants}],
        selected
      )

  defp menu_list(_state, :online, selected),
    do:
      MenuList.new(
        :online,
        "ONLINE VERSUS",
        [{"HOST", :host}, {"HOST OVER SSH", :ssh}, {"JOIN", :join}, {"SET IP", :set_ip}],
        selected
      )

  defp menu_list(state, :tournament, selected),
    do:
      MenuList.new(
        :tournament,
        "TOURNAMENT",
        [
          {"PLAYERS #{state.entrants}", :players},
          {"MAP #{Levels.name(state.area)}", :map},
          {"VARIANTS", :variants},
          {"START TOURNAMENT", :start}
        ],
        selected
      )

  defp menu_list(state, {:variants, _from} = key, selected),
    do:
      MenuList.new(
        key,
        "VARIANTS",
        Enum.map(Rules.entries(), &{Rules.label(state.rules, &1), &1}),
        selected
      )

  defp chose(state, :main, :multi, _side), do: menu(state, :multi, nil)
  defp chose(state, :main, :tournament, _side), do: menu(state, :tournament, nil)
  defp chose(state, :main, :single, _side), do: menu(state, :single, nil)
  defp chose(state, :main, :options, side), do: ask(state, side, :menu)
  defp chose(state, :main, :credits, _side), do: credits(state)
  defp chose(state, :main, :quit, side), do: ask(state, side, :quit)
  defp chose(state, :main, :tutorial, _side), do: tutorial(state)
  defp chose(state, :main, :challenge, _side), do: challenge(state)
  defp chose(state, :single, :begin, _side), do: arcade(state)
  defp chose(state, :multi, :versus, _side), do: levels(%{state | mode: :versus})
  defp chose(state, :multi, :online, _side), do: online_menu(state)
  defp chose(state, :multi, :variants, _side), do: menu(state, {:variants, :multi}, nil)
  defp chose(state, :online, :host, side), do: hosting(state, side)
  defp chose(state, :online, :ssh, side), do: ssh_hosting(state, side)
  defp chose(state, :online, :join, _side), do: joining(state)
  defp chose(state, :online, :set_ip, side), do: address_entry(state, side)
  defp chose(state, :tournament, :variants, _side), do: menu(state, {:variants, :tournament}, nil)
  defp chose(state, :tournament, :start, _side), do: tournament(state)
  defp chose(state, :tournament, option, _side), do: changed(state, :tournament, option, 1)

  defp chose(state, {:variants, _from} = key, entry, _side) do
    state = %{state | rules: Rules.choose(state.rules, entry)}
    %{state | menu: MenuList.relabelled(state.menu, menu_list(state, key, entry).choices)}
  end

  defp changed(state, :tournament, :players, step) do
    entrants = state.entrants + step

    entrants =
      if entrants > @most_entrants,
        do: @fewest_entrants,
        else: if(entrants < @fewest_entrants, do: @most_entrants, else: entrants)

    relabelled(%{state | entrants: entrants}, :tournament)
  end

  defp changed(state, :tournament, :map, step),
    do: relabelled(%{state | area: Levels.next(state.area, step)}, :tournament)

  defp changed(state, _key, _option, _step), do: state

  defp relabelled(state, key),
    do: %{state | menu: MenuList.relabelled(state.menu, menu_list(state, key, nil).choices)}

  defp back(state, :main),
    do: %{state | menu: MenuList.new(:main, nil, state.menu.choices, :quit)}

  defp back(state, :online), do: menu(state, :multi, :online)
  defp back(state, {:variants, from}), do: menu(state, from, :variants)
  defp back(state, key), do: menu(state, :main, key)

  defp sound(state, sound) do
    case Gml.first(state.world, "Ear") do
      nil ->
        state

      ear ->
        %{
          state
          | world:
              Sound.play(
                state.world,
                sound,
                {World.fetch(state.world, ear).x, World.fetch(state.world, ear).y}
              )
        }
    end
  end

  defp given_up(state) do
    if Online.hosting?(state),
      do: %{state | levels: %{state.levels | idle: 0}},
      else: main_menu(state)
  end

  defp levels(state) do
    levels = Levels.new()
    enter(%{state | screen: :levels, menu: nil, levels: levels, timer: 0}, :levels)
  end

  defp online_menu(state) do
    state = offline(%{state | mode: :online, entry: nil, online: %{state.online | status: nil}})
    menu(state, :online, nil)
  end

  defp hosting(state, side) do
    owner =
      Enum.find_value(state.players, fn {_id, player} -> player.side == side && player.owner end)

    online = %{state.online | owner: owner, status: nil}
    %{state | screen: :hosting, menu: nil, online: online, effects: [:host | state.effects]}
  end

  defp joined?(%{online: %{host: host}} = state), do: host != nil and opponent?(state)

  defp ssh_joined?(%{online: %{ssh: ssh}} = state), do: ssh != nil and opponent?(state)

  defp opponent?(%{online: %{owner: owner, quitting: quitting}, players: players}),
    do:
      Enum.any?(players, fn {_id, player} ->
        player.side != nil and player.owner != owner and player.owner not in quitting
      end)

  defp quit_to_title(state, side) do
    case remote_owner(state, side) do
      nil ->
        state |> killed(["Match", "Tournament"]) |> left_for_title()

      owner ->
        state = state |> forfeit_result() |> killed(["Match"]) |> ask(side, :quit) |> waiting()
        online = state.online

        %{
          state
          | online: %{
              online
              | quitting: [owner | online.quitting],
                status: "the other player quit"
            }
        }
    end
  end

  defp left_for_title(%{online: %{ssh: ssh}} = state) when ssh != nil do
    case ssh_players(state) do
      [] -> title(state)
      players -> sent_away(state, players)
    end
  end

  defp left_for_title(state), do: title(state)

  defp ssh_players(state) do
    for {_id, %{side: side, owner: owner} = player} <- state.players,
        side != nil and Online.remote_player?(state, player),
        do: {side, owner}
  end

  defp sent_away(state, players) do
    state = Enum.reduce(players, state, fn {side, _owner}, state -> ask(state, side, :quit) end)
    owners = Enum.map(players, &elem(&1, 1))

    online = %{
      state.online
      | quitting: owners ++ state.online.quitting,
        closing: state.steps + @ask_steps
    }

    enter(%{state | screen: :title, menu: nil, timer: 0, online: online}, :title)
  end

  defp closed(%{online: %{closing: nil}} = state), do: state

  defp closed(%{online: %{closing: until, quitting: quitting} = online} = state)
       when quitting == [] or state.steps > until,
       do: offline(%{state | online: %{online | closing: nil, quitting: []}})

  defp closed(state), do: state

  defp remote_owner(state, side) do
    Enum.find_value(state.players, fn {_id, player} ->
      player.side == side and Online.remote_player?(state, player) and player.owner
    end)
  end

  defp departed(%{online: %{quitting: []}} = state), do: state

  defp departed(%{online: online, players: players} = state) do
    present = for {_id, %{owner: owner}} <- players, into: MapSet.new(), do: owner
    %{state | online: %{online | quitting: Enum.filter(online.quitting, &(&1 in present))}}
  end

  defp forfeit(state) do
    state = state |> forfeit_result() |> killed(["Match"]) |> waiting()
    %{state | online: %{state.online | status: "the other player left"}}
  end

  defp waiting(%{online: %{ssh: ssh}} = state) when ssh != nil,
    do: enter(%{state | screen: :ssh_hosting, menu: nil, entry: nil, timer: 0}, :online)

  defp waiting(state),
    do: enter(%{state | screen: :hosting, menu: nil, entry: nil, timer: 0}, :online)

  defp met(state), do: levels(%{state | online: %{state.online | status: nil}})

  defp forfeit_result(%{online: %{owner: owner}} = state) do
    if Bout.running?(state.world) and Map.has_key?(state.players, owner),
      do: %{state | events: [forfeit_event(state, owner) | state.events]},
      else: state
  end

  defp forfeit_event(state, owner),
    do:
      {:result,
       %{id: owner, name: to_string(owner), won?: true, area: state.area, mode: state.mode}}

  defp ssh_hosting(state, side) do
    owner =
      Enum.find_value(state.players, fn {_id, player} -> player.side == side && player.owner end)

    online = %{state.online | owner: owner, status: nil}
    offered = if state.online.ssh_port, do: Integer.to_string(state.online.ssh_port), else: ""

    typing(%{
      state
      | screen: :ssh_hosting,
        menu: nil,
        online: online,
        entry: {:ssh_port, "SSH PORT, EMPTY FOR ANY", ~c"0123456789", 5, offered},
        typer: side
    })
  end

  defp joining(state) do
    state = %{state | screen: :join, effects: [:listen | state.effects]}
    %{state | menu: found_menu(state)}
  end

  defp found_menu(%{online: %{found: found}, menu: menu}) do
    hosts = for %{host: host} <- found, do: {host, {:host, host}}
    choices = if hosts == [], do: [{"searching..", :disabled}], else: hosts

    case menu do
      %MenuList{key: :join, choices: ^choices} -> menu
      _other -> MenuList.new(:join, "JOIN", choices)
    end
  end

  defp address_entry(state, side),
    do: %{
      state
      | screen: :address,
        menu: nil,
        entry: {:address, "SET IP", ~c"0123456789.", 15, ""},
        typer: side,
        effects: [:prefill_address | state.effects]
    }

  defp code_entry(state, address, side) do
    typing(%{
      state
      | screen: :code,
        menu: nil,
        entry: {:code, "CODE", Distribution.alphabet(), Distribution.code_length(), ""},
        address: address,
        typer: side,
        online: %{state.online | status: nil},
        effects: [:unlisten | state.effects]
    })
  end

  defp typing(state),
    do: ask(%{state | typing_armed: false}, state.typer, {:menu, {:typing, state.entry}})

  defp armed(%{typing_armed: true} = state, _players), do: state

  defp armed(state, players) do
    held? = Enum.any?(Map.values(players), &(:start in &1.held or :attack in &1.held))
    %{state | typing_armed: not held?}
  end

  defp offline(state), do: %{state | effects: [:unhost, :ssh_unhost, :unlisten | state.effects]}

  defp tournament(state) do
    world = Bout.start_tournament(state.world, state.area, state.rules, state.entrants)
    %{state | screen: :tournament, mode: :tournament, menu: nil, world: world, timer: 0}
  end

  defp followed(%{world: world} = state) do
    cond do
      in_room?(world, "rMainMenu") -> main_menu(state)
      Bout.running?(world) and Bout.area(room_name(world)) != nil -> tournament_bout(state)
      true -> state
    end
  end

  defp tournament_bout(state),
    do: %{
      state
      | screen: :bout,
        menu: nil,
        area: Bout.area(room_name(state.world)),
        winner: nil,
        stats: nil,
        timer: 0,
        recording: %{world: state.world, inputs: [], kept: []}
    }

  defp room_name(%World{room: room} = world), do: Enum.at(world.data.rooms, room).name

  defp chosen(state, area), do: begin(state, area, state.rules)

  defp ladder(%{winner: winner} = state) do
    state = %{
      state
      | screen: :tournament,
        menu: nil,
        timer: 0,
        events: result_events(state, winner) ++ state.events
    }

    enter(state, :ladder)
  end

  defp credits(state) do
    text = Credits.read(Assets.get().path)
    enter(%{state | screen: :credits, menu: nil, credits: text, timer: 0}, :credits)
  end

  defp enter(state, screen) do
    room = Data.index(state.world.data, :rooms, Map.fetch!(@rooms, screen))
    if state.world.room == room, do: state, else: %{state | world: Rooms.enter(state.world, room)}
  end

  defp tutorial(state) do
    world =
      case Gml.first(state.world, "System") do
        nil -> state.world
        system -> Gml.put(state.world, system, %{flow: @tutorial_flow})
      end

    world = Rooms.enter(world, Data.index(world.data, :rooms, @rooms.tutorial))
    %{state | screen: :tutorial, menu: nil, mode: :tutorial, world: world, timer: 0}
  end

  defp challenge(state),
    do: %{
      state
      | screen: :challenge,
        menu: nil,
        mode: :challenge,
        world: Bout.start_challenge(state.world),
        timer: 0
    }

  defp arcade(state) do
    world = Bout.start_arcade(state.world)
    %{state | screen: :arcade, menu: nil, mode: :arcade, world: world, timer: 0}
  end

  defp arcade_bout(state) do
    area = Bout.area_of_level(Gml.var(state.world, Gml.first(state.world, "System"), :level))

    %{
      state
      | screen: :bout,
        menu: nil,
        area: area,
        winner: nil,
        stats: nil,
        timer: 0,
        recording: %{world: state.world, inputs: [], kept: []}
    }
  end

  defp in_room?(%World{room: room} = world, name),
    do: room == Data.index(world.data, :rooms, name)

  defp killed(state, names),
    do: %{state | world: Enum.reduce(names, state.world, &kill_all(&2, &1))}

  defp kill_all(world, name),
    do: world |> Gml.all(name) |> Enum.reduce(world, &World.destroy(&2, &1))

  defp resumed(%{mode: :tutorial}), do: :tutorial
  defp resumed(%{mode: :challenge}), do: :challenge

  defp resumed(%{mode: :tournament, world: world}) do
    if Bout.area(room_name(world)) != nil, do: :bout, else: :tournament
  end

  defp resumed(_state), do: :bout

  defp begin(state, area, rules) do
    world = Bout.start(state.world, area, rules, state.mode)

    %{
      state
      | screen: :bout,
        menu: nil,
        area: area,
        world: world,
        winner: nil,
        stats: nil,
        timer: 0,
        recording: %{world: world, inputs: [], kept: []}
    }
  end

  defp bout(state, players) do
    state = state |> record(players) |> advance(players)

    cond do
      Bout.running?(state.world) -> state
      state.mode == :tournament -> ladder(finished(state))
      true -> results(finished(state))
    end
  end

  defp finished(state),
    do: %{state | winner: Bout.winner(state.world), stats: Bout.stats(state.world)}

  defp advance(state, players),
    do: %{state | world: Step.run(state.world, Map.put(@no_keys, :players, players))}

  defp record(%{recording: %{inputs: inputs} = recording} = state, players),
    do: %{state | recording: %{recording | inputs: [players | inputs]}}

  defp replay(%{recording: recording} = state) do
    kept = Map.take(state, [:world, :winner, :stats, :menu])

    %{
      state
      | screen: :replay,
        kept: kept,
        world: recording.world,
        recording: %{recording | inputs: Enum.reverse(recording.inputs), kept: recording.inputs},
        timer: 0
    }
  end

  defp replayed(%{kept: kept, recording: recording} = state) do
    state
    |> Map.merge(kept)
    |> Map.merge(%{
      screen: :results,
      kept: nil,
      timer: 0,
      recording: %{recording | inputs: recording.kept}
    })
  end

  defp results(%{winner: winner} = state) do
    state = %{
      state
      | screen: :results,
        menu: nil,
        timer: 0,
        events: result_events(state, winner) ++ state.events
    }

    enter(state, :results)
  end

  defp result_events(state, winner) do
    for {id, %{side: side}} <- state.players,
        side == 1 or (side == 2 and state.mode != :arcade) do
      {:result,
       %{id: id, name: to_string(id), won?: side == winner, area: state.area, mode: state.mode}}
    end
  end

  defp sway(%{world: %World{views: [%{view: {_x, y, width, height}} | _]} = world} = state) do
    room_width = world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size) |> elem(0)

    centre =
      room_width / 2 + :math.sin(state.steps / @sway_period) * (room_width / 2 - @sway_margin)

    %{state | world: World.put_view(world, 0, {centre - width / 2, y, width, height})}
  end

  defp sway(state), do: state

  defp scenery(state, players) do
    world = state.world |> Step.run(Map.put(@no_keys, :players, players)) |> Grass.update_all()
    %{state | world: world}
  end
end
