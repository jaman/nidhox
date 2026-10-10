defmodule Nidhox.Flow do
  @moduledoc """
  How NidhOX goes from screen to screen: one step of the game's state on its current
  screen, given both sides' input that step (`%{1 => input, 2 => input}`, each
  `%{held, pressed, released}`).

    * `:logos` — `Nidhox.Screen.Logos` over `rLogos`; when they end, or on any press,
      the title
    * `:title` — `rMainMenu` under the logo, the camera swaying across the room
      (`room_width / 2 + sin(frame / 500) × (room_width / 2 − 160)`); "press start" until a press, then the main
      menu: SINGLE PLAYER, MULTIPLAYER, OPTIONS, HOW TO PLAY, CREDITS, QUIT TO DESKTOP. `:jump` goes
      back to "press start"
    * `:multi` — `rMultiMenu`: OFFLINE VERSUS, TOURNAMENT, ONLINE VERSUS, BACK
    * `:online` — `rMultiMenu`: HOST, JOIN, SET IP, BACK; on this menu and every one
      before it, the machine neither hosts nor looks for hosts
    * `:hosting` — hosting (`Nidhox.Online`), the address and join code shown, until a
      player on a client of their own takes a side, then the level select; `:jump`
      goes back
    * `:join` — the hosts heard on the local network; choosing one asks for its code
    * `:address` — SET IP: the host's address typed (`Nidhox.Screen.Entry`), then its
      code
    * `:code` — the host's join code typed; finishing it joins, and the client of the
      player who finished is asked to enter the host's world
    * `:levels` — `Nidhox.Screen.Levels` over `rLevelSelect`, for a versus bout or a
      tournament
    * `:tournament_intro` — the tournament's players (`Nidhox.Screen.Ladder`) over
      `rTournamentIntro`, for `@intro_steps` steps or until a press
    * `:ladder` — the tournament so far and its next match over `rShowLadder`; a press
      starts the match
    * `:champion` — the tournament's champion over `rShowChampion` (its number the
      world's global `:champion`, for the pyre's colour), for
      `@champion_steps` steps or until a press, then the main menu
    * `:tutorial` — HOW TO PLAY: `rTutorial` with the game's own `Tutorial` (`System.flow`
      656686433); it ends at the main menu once the tutorial is gone
    * `:challenge` — CHALLENGE: `rChallengeMode` with the game's own `ChallengeMode`
      (`Nidhox.Objects.Challenge`), until QUIT TO TITLE SCREEN from its pause
    * `:credits` — `Nidhox.Screen.Credits` over `rCredits`, until they have risen away or
      a press
    * `:bout` — the match (`Nidhox.Bout`), run by the game's own objects from its
      faceoff on under the rules chosen on the level select (`Nidhox.Rules`), until its
      `Match` is gone; `:start` pauses it
    * `:paused` — `Nidhox.Screen.Pause`; UNPAUSE GAME goes back to the bout
    * `:results` — `Nidhox.Screen.Results` over `rMatchStats`: CONTINUE goes to the main
      menu; WATCH REPLAY; BACK TO MAIN MENU. In a single player run only CONTINUE, and
      the run's own step moves on at a press
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
  goes back to the level select. TOURNAMENT is a double elimination tournament (`Nidhox.Tournament`)
  in the area chosen, each match a bout under the rules chosen, its first player on
  side 1 and its second on side 2; a finished match goes to the ladder, or to the
  champion after the last. OPTIONS and QUIT TO DESKTOP ask the client of the player who chose
  them to open the game's options or to quit (`ask/3`).
  """

  alias Cauldron2D.Distribution
  alias Cauldron2D.GameMaker.Data
  alias Cauldron2D.GameMaker.Rooms
  alias Cauldron2D.GameMaker.Step
  alias Cauldron2D.GameMaker.World
  alias Nidhox.{Assets, Bout, Online, Tournament}
  alias Nidhox.Gml
  alias Nidhox.Objects.Grass
  alias Nidhox.Screen.{Credits, Entry, Levels, Logos, Menu, Pause, Results, Title}

  @no_keys %{held: MapSet.new(), pressed: MapSet.new(), released: MapSet.new()}
  @areas ["Cemetery", "Castle", "Mines", "Sky", "Wilds"]
  @tutorial_flow 656_686_433
  @ask_steps 30
  @sway_period 500
  @sway_margin 160
  @intro_steps 180
  @champion_steps 600
  @rooms %{
    logos: "rLogos",
    title: "rMainMenu",
    multi: "rMultiMenu",
    levels: "rLevelSelect",
    credits: "rCredits",
    tutorial: "rTutorial",
    results: "rMatchStats",
    tournament_intro: "rTournamentIntro",
    ladder: "rShowLadder",
    champion: "rShowChampion",
    online: "rMultiMenu"
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

  def step(%{screen: :title, menu: nil} = state, players) do
    state = state |> scenery(players) |> sway()
    if Title.continue?(players), do: main_menu(state), else: state
  end

  def step(%{screen: :title} = state, players) do
    state = state |> scenery(players) |> sway()

    case Menu.input(state.menu, players) do
      {:choose, :single, _side} -> arcade(state)
      {:choose, :multi, _side} -> multi_menu(state)
      {:choose, :options, side} -> ask(state, side, :menu)
      {:choose, :tutorial, _side} -> tutorial(state)
      {:choose, :challenge, _side} -> challenge(state)
      {:choose, :credits, _side} -> credits(state)
      {:choose, :quit, side} -> ask(state, side, :quit)
      {:back, _side} -> %{state | menu: nil, timer: 0}
      {:stay, menu} -> %{state | menu: menu}
    end
  end

  def step(%{screen: :multi} = state, players) do
    state = scenery(state, players)

    case Menu.input(state.menu, players) do
      {:choose, :versus, _side} -> levels(%{state | mode: :versus})
      {:choose, :tournament, _side} -> levels(%{state | mode: :tournament})
      {:choose, :online, _side} -> online_menu(state)
      {:choose, :back, _side} -> main_menu(state)
      {:back, _side} -> main_menu(state)
      {:stay, menu} -> %{state | menu: menu}
    end
  end

  def step(%{screen: :levels} = state, players) do
    state = scenery(state, players)

    case Levels.input(state.levels, players) do
      {:choose, area, _side} -> chosen(state, area)
      {:back, _side} -> levels_back(state)
      {:stay, levels} -> %{state | levels: levels, world: Levels.pan(levels, state.world, :ease)}
    end
  end

  def step(%{screen: :online} = state, players) do
    state = scenery(state, players)

    case Menu.input(state.menu, players) do
      {:choose, :host, side} -> hosting(state, side)
      {:choose, :join, _side} -> joining(state)
      {:choose, :set_ip, _side} -> address_entry(state)
      {:choose, :back, _side} -> multi_menu(state)
      {:back, _side} -> multi_menu(state)
      {:stay, menu} -> %{state | menu: menu}
    end
  end

  def step(%{screen: :hosting} = state, players) do
    state = scenery(state, players)

    cond do
      joined?(state) -> levels(state)
      Enum.any?(Map.values(players), &(:jump in &1.pressed)) -> online_menu(state)
      true -> state
    end
  end

  def step(%{screen: :join} = state, players) do
    state = scenery(state, players)

    case Menu.input(found_menu(state), players) do
      {:choose, {:host, address}, _side} -> code_entry(state, address)
      {:choose, :back, _side} -> online_menu(state)
      {:back, _side} -> online_menu(state)
      {:choose, :disabled, _side} -> state
      {:stay, menu} -> %{state | menu: menu}
    end
  end

  def step(%{screen: :address} = state, players) do
    state = scenery(state, players)

    case Entry.input(state.entry, players) do
      {:done, "", _side} -> state
      {:done, address, _side} -> code_entry(state, address)
      {:back, _side} -> online_menu(state)
      {:stay, entry} -> %{state | entry: entry}
    end
  end

  def step(%{screen: :code, address: address} = state, players) do
    state = scenery(state, players)

    case Entry.input(state.entry, players) do
      {:done, code, side} -> %{state | effects: [{:join, address, code, side} | state.effects]}
      {:back, _side} -> online_menu(state)
      {:stay, entry} -> %{state | entry: entry}
    end
  end

  def step(%{screen: :tournament_intro} = state, players) do
    state = scenery(state, players)
    if Title.continue?(players) or state.timer >= @intro_steps, do: ladder(state), else: state
  end

  def step(%{screen: :ladder} = state, players) do
    state = scenery(state, players)

    if Title.continue?(players),
      do: begin(state, state.area, state.tournament.rules),
      else: state
  end

  def step(%{screen: :champion} = state, players) do
    state = scenery(state, players)

    if Title.continue?(players) or state.timer >= @champion_steps,
      do: main_menu(%{state | tournament: nil}),
      else: state
  end

  def step(%{screen: :credits} = state, players) do
    state = scenery(state, players)

    if Title.continue?(players) or Credits.done?(state.credits, state.timer),
      do: main_menu(state),
      else: state
  end

  def step(%{screen: :bout} = state, players) do
    if Enum.any?(Map.values(players), &(:start in &1.pressed)),
      do: %{state | screen: :paused, menu: Pause.menu(state.mode, Online.hosting?(state))},
      else: bout(state, players)
  end

  def step(%{screen: :challenge} = state, players) do
    if Enum.any?(Map.values(players), &(:start in &1.pressed)),
      do: %{state | screen: :paused, menu: Pause.menu(:challenge, false)},
      else: advance(state, players)
  end

  def step(%{screen: :tutorial} = state, players) do
    cond do
      Enum.any?(Map.values(players), &(:start in &1.pressed)) ->
        %{state | screen: :paused, menu: Pause.menu(:tutorial, false)}

      Gml.exists?(state.world, "Tutorial") ->
        advance(state, players)

      true ->
        main_menu(state)
    end
  end

  def step(%{screen: :paused} = state, players) do
    case Pause.input(state.menu, players) do
      {:choose, :unpause} -> %{state | screen: resumed(state), menu: nil}
      {:choose, :change_level} -> levels(state)
      {:choose, :title} -> title(state)
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

    case Menu.input(state.menu, players) do
      {:choose, :continue, _side} -> continue(state)
      {:choose, :replay, _side} -> replay(state)
      {:choose, :main, _side} -> main_menu(state)
      {:back, _side} -> main_menu(state)
      {:stay, menu} -> %{state | menu: menu}
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
  @spec ask(map(), 1 | 2, :menu | :quit | {:enter, map()}) :: map()
  def ask(state, side, ask) do
    number = state.ask_number + 1

    asks =
      for {_id, %{side: ^side, owner: owner}} <- state.players,
          into: state.asks,
          do: {owner, {number, ask, state.steps + @ask_steps}}

    %{state | ask_number: number, asks: asks}
  end

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

    menu =
      Menu.new([
        {"SINGLE PLAYER", :single},
        {"CHALLENGE", :challenge},
        {"MULTIPLAYER", :multi},
        {"OPTIONS", :options},
        {"HOW TO PLAY", :tutorial},
        {"CREDITS", :credits},
        {"QUIT TO DESKTOP", :quit}
      ])

    enter(
      offline(%{state | screen: :title, menu: menu, timer: 0}),
      :title
    )
  end

  defp multi_menu(state) do
    menu =
      Menu.new([
        {"OFFLINE VERSUS", :versus},
        {"TOURNAMENT", :tournament},
        {"ONLINE VERSUS", :online},
        {"BACK", :back}
      ])

    enter(
      offline(%{state | screen: :multi, menu: menu, timer: 0}),
      :multi
    )
  end

  defp levels(state) do
    levels = Levels.new(@areas, state.area, levels_mode(state.mode))

    state =
      enter(
        %{state | screen: :levels, menu: nil, levels: levels, timer: 0},
        :levels
      )

    %{state | world: Levels.pan(levels, state.world, :snap)}
  end

  defp online_menu(state) do
    menu =
      Menu.new([{"HOST", :host}, {"JOIN", :join}, {"SET IP", :set_ip}, {"BACK", :back}])

    state = offline(%{state | screen: :online, menu: menu, mode: :online, entry: nil, timer: 0})
    enter(%{state | online: %{state.online | status: nil}}, :online)
  end

  defp hosting(state, side) do
    owner =
      Enum.find_value(state.players, fn {_id, player} -> player.side == side && player.owner end)

    online = %{state.online | owner: owner, status: nil}
    %{state | screen: :hosting, menu: nil, online: online, effects: [:host | state.effects]}
  end

  defp joined?(%{online: %{host: host, owner: owner}, players: players}) when host != nil,
    do: Enum.any?(players, fn {_id, player} -> player.side != nil and player.owner != owner end)

  defp joined?(_state), do: false

  defp joining(state) do
    state = %{state | screen: :join, effects: [:listen | state.effects]}
    %{state | menu: found_menu(state)}
  end

  defp found_menu(%{online: %{found: found}, menu: menu}) do
    hosts = for %{host: host} <- found, do: {host, {:host, host}}
    choices = if hosts == [], do: [{"searching..", :disabled}], else: hosts
    fresh = Menu.new(choices ++ [{"BACK", :back}])
    if menu && menu.choices == fresh.choices, do: menu, else: fresh
  end

  defp address_entry(state) do
    entry = Entry.new("SET IP", ~c"0123456789. ", 15)

    %{
      state
      | screen: :address,
        menu: nil,
        entry: entry,
        effects: [:prefill_address | state.effects]
    }
  end

  defp code_entry(state, address) do
    entry = Entry.new("CODE", Distribution.alphabet(), Distribution.code_length())

    %{
      state
      | screen: :code,
        menu: nil,
        entry: entry,
        address: address,
        online: %{state.online | status: nil},
        effects: [:unlisten | state.effects]
    }
  end

  defp offline(state), do: %{state | effects: [:unhost, :unlisten | state.effects]}

  defp levels_back(%{mode: :online} = state), do: online_menu(state)
  defp levels_back(state), do: multi_menu(state)

  defp levels_mode(:tournament), do: :tournament
  defp levels_mode(_mode), do: :versus

  defp chosen(%{mode: :tournament, levels: levels} = state, area) do
    tournament = %{
      bracket: Tournament.new(Levels.players(levels)),
      rules: Levels.rules(levels)
    }

    enter(
      %{state | screen: :tournament_intro, area: area, tournament: tournament, timer: 0},
      :tournament_intro
    )
  end

  defp chosen(%{levels: levels} = state, area), do: begin(state, area, Levels.rules(levels))

  defp ladder(state),
    do:
      enter(
        %{state | screen: :ladder, menu: nil, timer: 0},
        :ladder
      )

  defp decided(%{tournament: %{bracket: bracket} = tournament, winner: winner} = state) do
    bracket = Tournament.won(bracket, elem(Tournament.next(bracket), winner - 1))

    state = %{
      state
      | tournament: %{tournament | bracket: bracket},
        events: result_events(state, winner) ++ state.events
    }

    if bracket.champion,
      do:
        enter(
          %{
            state
            | screen: :champion,
              timer: 0,
              world: World.put_global(state.world, :champion, bracket.champion)
          },
          :champion
        ),
      else: ladder(state)
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

  defp kill_all(world, name),
    do: world |> Gml.all(name) |> Enum.reduce(world, &World.destroy(&2, &1))

  defp resumed(%{mode: :tutorial}), do: :tutorial
  defp resumed(%{mode: :challenge}), do: :challenge
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
      state.mode == :tournament -> decided(finished(state))
      true -> results(finished(state))
    end
  end

  defp finished(state),
    do: %{state | winner: Bout.winner(state.world), stats: Bout.stats(state.world)}

  defp advance(state, players),
    do: %{state | world: Step.run(state.world, Map.put(@no_keys, :players, players))}

  defp record(%{recording: %{inputs: inputs} = recording} = state, players),
    do: %{state | recording: %{recording | inputs: [players | inputs]}}

  defp continue(state) do
    if state.mode == :online, do: levels(state), else: continue_offline(state)
  end

  defp continue_offline(state), do: main_menu(state)

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
        menu: results_menu(state.mode),
        timer: 0,
        events: result_events(state, winner) ++ state.events
    }

    enter(state, :results)
  end

  defp results_menu(:arcade), do: Menu.new([{"CONTINUE", :continue}])
  defp results_menu(_mode), do: Results.menu()

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
