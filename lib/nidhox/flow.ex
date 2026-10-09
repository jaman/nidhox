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
    * `:champion` — the tournament's champion over `rShowChampion`, for
      `@champion_steps` steps or until a press, then the main menu
    * `:tutorial` — HOW TO PLAY (`Nidhox.Tutorial`) in `rTutorial`, the orange fencer a
      dummy; it ends at the main menu once every lesson is passed
    * `:credits` — `Nidhox.Screen.Credits` over `rCredits`, until they have risen away or
      a press
    * `:en_garde` — the fencers placed and still for `@en_garde_steps` steps; the start
      sound as it ends
    * `:bout` — the bout (`Nidhox.Match`) until it is finished, under the rules chosen on
      the level select (`Nidhox.Rules`): as many bout steps a game step as its variant
      says, and into sudden death when its time runs out; `:start` pauses it
    * `:paused` — `Nidhox.Screen.Pause`; `:jump` or UNPAUSE GAME goes back to the bout
    * `:results` — `Nidhox.Screen.Results` over `rMatchStats`: CONTINUE goes on to the
      next area of a single player run after a win, else to the main menu; WATCH REPLAY;
      BACK TO MAIN MENU
    * `:replay` — the bout just fought, run again from its start with every step's
      recorded input (the computer's as it chose them), then back to the results;
      `:start` (SKIP THIS) ends it early

  SINGLE PLAYER is a run through `@arcade` against the computer (`Nidhox.AI`) on side
  2, ended by a loss or the last win. OFFLINE VERSUS is the two sides against each other
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
  alias Nidhox.{AI, Assets, Blood, Match, Noises, Parallax, Rules, Sounds, Tournament, Tutorial}
  alias Nidhox.Objects.{Animals, Doors, Grass, Stains}
  alias Nidhox.Screen.{Credits, Entry, Levels, Logos, Menu, Pause, Results, Title}

  @no_keys %{held: MapSet.new(), pressed: MapSet.new(), released: MapSet.new()}
  @areas ["Cemetery", "Castle", "Mines", "Sky", "Wilds"]
  @arcade @areas
  @en_garde_steps 90
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

  @doc "The areas, in the order the level select and a single player run go through them."
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
      {:choose, :single, _side} -> en_garde(%{state | mode: :arcade, arcade: 0}, hd(@arcade))
      {:choose, :multi, _side} -> multi_menu(state)
      {:choose, :options, side} -> ask(state, side, :menu)
      {:choose, :tutorial, _side} -> tutorial(state)
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
      do: en_garde(state, state.area, state.tournament.rules),
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

  def step(%{screen: :en_garde} = state, players) do
    state = scenery(state, players)

    if state.timer >= @en_garde_steps,
      do: %{
        state
        | screen: :bout,
          timer: 0,
          recording: %{world: state.world, match: state.match, inputs: [], kept: []},
          events: [Sounds.event(:start, state.steps) | state.events]
      },
      else: state
  end

  def step(%{screen: :bout} = state, players) do
    if Enum.any?(Map.values(players), &(:start in &1.pressed)),
      do: %{state | screen: :paused, menu: Pause.menu(state.mode)},
      else: bout(state, players)
  end

  def step(%{screen: :tutorial} = state, players) do
    if Enum.any?(Map.values(players), &(:start in &1.pressed)) do
      %{state | screen: :paused, menu: Pause.menu(:tutorial)}
    else
      {tutorial, match} = Tutorial.opening(state.tutorial, state.match)
      players = Map.put(players, 2, Tutorial.opponent(tutorial))
      state = advance(%{state | match: match}, players)
      tutorial = Tutorial.step(tutorial, match, state.match)
      if Tutorial.done?(tutorial), do: main_menu(state), else: %{state | tutorial: tutorial}
    end
  end

  def step(%{screen: :paused} = state, players) do
    case Menu.input(state.menu, players) do
      {:choose, :unpause, _side} -> %{state | screen: resumed(state), menu: nil}
      {:choose, :change_level, _side} -> levels(state)
      {:choose, :title, _side} -> title(state)
      {:back, _side} -> %{state | screen: resumed(state), menu: nil}
      {:stay, menu} -> %{state | menu: menu}
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
        offline(%{state | screen: :title, menu: nil, match: nil, brain: nil, timer: 0}),
        :title
      )

  defp main_menu(state) do
    menu =
      Menu.new([
        {"SINGLE PLAYER", :single},
        {"MULTIPLAYER", :multi},
        {"OPTIONS", :options},
        {"HOW TO PLAY", :tutorial},
        {"CREDITS", :credits},
        {"QUIT TO DESKTOP", :quit}
      ])

    enter(
      offline(%{state | screen: :title, menu: menu, match: nil, brain: nil, timer: 0}),
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
      offline(%{state | screen: :multi, menu: menu, match: nil, brain: nil, timer: 0}),
      :multi
    )
  end

  defp levels(state) do
    levels = Levels.new(@areas, state.area, levels_mode(state.mode))

    state =
      enter(
        %{state | screen: :levels, menu: nil, levels: levels, match: nil, brain: nil, timer: 0},
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

  defp chosen(%{levels: levels} = state, area), do: en_garde(state, area, Levels.rules(levels))

  defp ladder(state),
    do:
      enter(
        %{state | screen: :ladder, menu: nil, match: nil, brain: nil, timer: 0},
        :ladder
      )

  defp decided(%{tournament: %{bracket: bracket} = tournament, match: match} = state) do
    bracket = Tournament.won(bracket, elem(Tournament.next(bracket), match.winner - 1))

    state = %{
      state
      | tournament: %{tournament | bracket: bracket},
        events: result_events(state, match.winner) ++ state.events
    }

    if bracket.champion,
      do: enter(%{state | screen: :champion, match: nil, timer: 0}, :champion),
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
    state =
      enter(
        %{state | screen: :tutorial, menu: nil, mode: :tutorial, brain: nil, timer: 0},
        :tutorial
      )

    room = state.world.room
    {match, world} = Match.in_room(state.world, "Tutorial", room)

    %{
      state
      | match: match,
        world: world,
        stats: Results.new(),
        tutorial: Tutorial.new(finish_line(world))
    }
  end

  defp finish_line(world) do
    with object when object != nil <- World.object_index(world, "TutorialFinishLine"),
         [id | _] <- World.instances_of(world, object) do
      World.fetch(world, id).x
    else
      _none -> world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size) |> elem(0)
    end
  end

  defp resumed(%{mode: :tutorial}), do: :tutorial
  defp resumed(_state), do: :bout

  defp en_garde(state, area, rules \\ %Rules{}) do
    {match, world} = Match.new(state.world, area, rules)
    brain = if state.mode == :arcade, do: AI.new(2, 1, AI.pick_personality())

    %{
      state
      | screen: :en_garde,
        menu: nil,
        area: area,
        world: world,
        match: match,
        brain: brain,
        stats: Results.new(),
        timer: 0
    }
  end

  defp bout(state, players) do
    {players, state} = computer(state, players)
    times = Rules.steps(state.match.rules, state.steps)
    state = Enum.reduce(List.duplicate(players, times), state, &(&2 |> record(&1) |> advance(&1)))

    cond do
      Match.finished?(state.match) and state.mode == :tournament -> decided(state)
      Match.finished?(state.match) -> results(state)
      Match.overtime?(state.match) -> overtime(state)
      true -> state
    end
  end

  defp overtime(state) do
    {match, world} = Match.sudden_death(state.match, state.world)

    %{
      state
      | match: match,
        world: world,
        events: [Sounds.event(:start, state.steps) | state.events]
    }
  end

  defp advance(state, players) do
    world =
      state.world
      |> Animals.watch(Match.positions(state.match))
      |> Step.run(Map.put(@no_keys, :players, players))
      |> Doors.swing(Match.bodies(state.match))
      |> Grass.update(Map.values(state.match.fencers), state.match.swords)

    {match, world} = Match.step(state.match, world, players)
    world = world |> Blood.spill(match) |> Stains.soak()
    noises = Noises.step(state.match, match)

    %{
      state
      | world: Parallax.apply(world),
        match: match,
        stats: Results.count(state.stats, match.events),
        events: Enum.reverse(noises) ++ state.events
    }
  end

  defp record(%{recording: %{inputs: inputs} = recording} = state, players),
    do: %{state | recording: %{recording | inputs: [players | inputs]}}

  defp continue(state) do
    if state.mode == :online, do: levels(state), else: continue_offline(state)
  end

  defp continue_offline(state) do
    if next_arcade?(state),
      do: en_garde(%{state | arcade: state.arcade + 1}, Enum.at(@arcade, state.arcade + 1)),
      else: main_menu(state)
  end

  defp replay(%{recording: recording} = state) do
    kept = Map.take(state, [:world, :match, :stats, :menu])

    %{
      state
      | screen: :replay,
        kept: kept,
        world: recording.world,
        match: recording.match,
        stats: Results.new(),
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

  defp computer(%{brain: nil} = state, players), do: {players, state}

  defp computer(%{brain: brain, match: match} = state, players) do
    {brain, input} = AI.step(brain, match.fencers[2], match.fencers[1], players[2], match)
    {Map.put(players, 2, input), %{state | brain: brain}}
  end

  defp results(%{match: match} = state) do
    state = %{
      state
      | screen: :results,
        menu: Results.menu(),
        timer: 0,
        events: result_events(state, match.winner) ++ state.events
    }

    enter(state, :results)
  end

  defp result_events(state, winner) do
    for {id, %{side: side}} <- state.players, side == 1 or (side == 2 and state.brain == nil) do
      {:result,
       %{id: id, name: to_string(id), won?: side == winner, area: state.area, mode: state.mode}}
    end
  end

  defp next_arcade?(%{mode: :arcade, match: %Match{winner: 1}, arcade: index}),
    do: index + 1 < length(@arcade)

  defp next_arcade?(_state), do: false

  defp sway(%{world: %World{views: [%{view: {_x, y, width, height}} | _]} = world} = state) do
    room_width = world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size) |> elem(0)

    centre =
      room_width / 2 + :math.sin(state.steps / @sway_period) * (room_width / 2 - @sway_margin)

    %{state | world: World.put_view(world, 0, {centre - width / 2, y, width, height})}
  end

  defp sway(state), do: state

  defp scenery(state, players) do
    world = state.world |> Step.run(Map.put(@no_keys, :players, players)) |> Grass.update([], [])
    %{state | world: world}
  end
end
