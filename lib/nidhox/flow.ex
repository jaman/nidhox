defmodule Nidhox.Flow do
  @moduledoc """
  How NidhOX goes from screen to screen: one step of the game's state on its current
  screen, given both sides' input that step (`%{1 => input, 2 => input}`, each
  `%{held, pressed, released}`).

    * `:logos` — `Nidhox.Screen.Logos` over `rLogos`; when they end, or on any press,
      the title
    * `:title` — `rMainMenu` with the game's main menu (`Nidhox.Screen.MainMenu`), the
      camera swaying across the room (`room_width / 2 + sin(frame / 500) ×
      (room_width / 2 − 160)`). Its windows — TRAINING, TOURNAMENT (with VARIANTS),
      NEWS and QUIT TO DESKTOP? — open over it and take the input while open. Coming to
      the main menu ends any match, run and tournament and sets what the game's
      `MainMenu` sets as it starts: 3 tournament players, the Castle, the variants as
      they start, training off and `System.flow` 1. OPTIONS asks the client of the
      player who chose it to open its options, and QUIT TO DESKTOP?'s yes asks it to
      quit (`ask/3`); a NEWS article's link is asked onto that player's clipboard
      (`{:clipboard, url}`). HYPE, the "new" markers seen and the articles read change
      the prefs and are asked onto the prefs player's client (`{:options, prefs}`). A
      move plays `sfxChangeLevel1`, a choice `sndLevel`. The machine neither hosts nor
      looks for hosts here
    * `:multi`, `:notice` and the rounds of mode `:online` — ONLINE (`Nidhox.OnlineFlow`)
    * `:ssh_hosting` — HOST OVER SSH, from the online menu: the client of the player who
      chose it is asked for the port to serve on (`Nidhox.Typing`; empty, or not a
      port, for any free one, started with `ssh_port` when set), then the game served
      over ssh there (`Nidhox.Online`) and the command to connect with shown, until a
      player connecting that way takes a side, then the level select; `:jump` or
      `:pause` (`Esc`) goes back to the online menu, serving stopped
    * `:address` — JOIN BY ADDRESS, from the online menu: the client of the player who
      chose it is asked to type the host's address and the port its lobby shows,
      `address:port` (`Nidhox.Typing`, started with this machine's network part), and
      that client is then asked to enter the lobby's world. `:start` or `:attack` —
      pressed again once every player has let go of both since the typing closed — asks
      for the typing again and `:jump` or `:pause` (`Esc`) goes back
    * `:demo` — the title's attract mode (`MainMenu`'s `autoStartTimer`): 1200 steps
      after the main menu began, with no move on its lists since, a match in one of the
      released levels at random played by the computer on both sides (`System.flow`
      1), with the logo and "press start" over it (`Nidhox.Objects.System`); any press,
      or the match ending, goes to the main menu
    * `:levels` — `Nidhox.Screen.Levels` over `rLevelSelect`: its chosen area begins a
      bout under the variants chosen; back asks BACK TO MAIN MENU?
      (`Nidhox.Screen.Confirm`), the level select still while it is open
    * `:tournament` — the tournament's own rooms, run by the game's objects
      (`Nidhox.Objects.Tournament`, `Nidhox.Objects.CountDowns`): the ladder
      (`rShowLadder`), the warm-up before each match (`rPreMatch`, where `:start`
      pauses) and the champion (`rShowChampion`). Its match's start leads to `:bout`,
      and the main menu, once the champion's countdown goes there, to the main menu
    * `:tutorial` — HOW TO PLAY: `rTutorial` with the game's own `Tutorial` (`System.flow`
      9836834); it ends at the main menu, at HOW TO PLAY, once the tutorial is gone
    * `:challenge` — CHALLENGE: `rChallengeMode` with the game's own `ChallengeMode`
      (`Nidhox.Objects.Challenge`), until QUIT TO TITLE SCREEN from its pause
    * `:credits` — `Nidhox.Screen.Credits` over `rCredits`, until `:attack` or `:start`,
      then the main menu at CREDITS
    * `:bout` — the match (`Nidhox.Bout`), run by the game's own objects from its
      faceoff on under the rules chosen on the level select (`Nidhox.Rules`), until its
      `Match` is gone; `:start` or `:pause` (`Esc`) pauses it
    * `:paused` — `Nidhox.Screen.Pause`; UNPAUSE GAME goes back to the bout, CHANGE LEVEL
      ends the match (its music with it) for the level select, VARIANTS changes the
      variants of the match being played — restarting it when asked — CHANGE COLOR
      changes `System.vsColor` and keeps it in the prefs (`colours`), OPTIONS asks the
      chooser's client to open its options, and EXIT ends the match and any tournament
      for the main menu — except when chosen by the player from another machine while
      this machine hosts: then a bout in progress is the host's by forfeit, the match
      ends, that player's client is asked to quit (`ask/3`), and the hosting screen
      comes back, still hosting, saying "the other player quit"
    * `:results` — `Nidhox.Screen.Results` over `rMatchStats`: a press goes on to the
      level select, or with "watch replay" turned up, to the replay. In a single player
      run the run's own step moves on at a press
    * `:replay` — the bout just fought, run again from its start with every step's
      recorded input (the computer's as it chose them), then back to the results;
      `:start` (SKIP THIS) ends it early

  TRAINING is a versus bout against the computer on side 2 (`System.training`), its
  personality and difficulty chosen in the TRAINING window; the level select and results
  follow as for LOCAL. CPU BATTLE is the computer against itself (`System.flow`
  62831853) under the HYPE (`System.cpuBattleHype`), TIME LIMIT and SUDDEN DEATH ONLY
  chosen: a level select on a released level at random that chooses by itself after
  2700 steps, the bout, and results that go on to the next level select by themselves
  after 900 steps, round until a player leaves from the pause or the level select.

  ARCADE is the game's own run (`Nidhox.Objects.Arcade`) against the computer
  (the match's `Brain`) on side 2: `:arcade` is its progress screen in
  `rArcadeProgress`, from which the run starts each bout; after a bout a press on the
  results leads back to it — a loss to the same level, a win to the next — and after the
  last win to `:arcade_complete` (`rBeatGameStats`), from which a press goes to the main
  menu. The main menu ends any run and match (`kill(ArcadeMode)`, `kill(Match)`). LOCAL is the two sides against each other
  in the area chosen. ONLINE is `Nidhox.OnlineFlow`'s. TOURNAMENT is the game's single elimination tournament
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

  alias Cauldron2D.GameMaker.Data
  alias Cauldron2D.GameMaker.Rooms
  alias Cauldron2D.GameMaker.Step
  alias Cauldron2D.GameMaker.World
  alias Nidhox.{Assets, Bout, Online, OnlineFlow}
  alias Nidhox.Bout.{Sound, Variants}
  alias Nidhox.Brain.Personality
  alias Nidhox.Gml
  alias Nidhox.Objects.{Grass, System, Tournament}
  alias Nidhox.Rules
  alias Nidhox.Screen.{Confirm, Context, Credits, Levels, Logos, MainMenu, News}
  alias Nidhox.Screen.{Pause, Results, Title, TournamentMenu, Training}

  @no_keys %{held: MapSet.new(), pressed: MapSet.new(), released: MapSet.new()}
  @areas ["Cemetery", "Castle", "Mines", "Sky", "Wilds"]
  @tutorial_flow 9_836_834
  @ask_steps 30
  @sway_period 500
  @sway_margin 160
  @move_sound "sfxChangeLevel1"
  @attract_steps 1200
  @choose_sound "sndLevel"
  @menu_entrants 3
  @menu_area "Castle"
  @menu_level 20
  @cpu_battle_start 2700
  @cpu_battle_results 900
  @kept_prefs [:hype, :menu_seen, :news_seen, :colours, :net_id, :recent, :search_global]
  @played_online [:levels, :bout, :paused, :results, :replay]
  @rooms %{
    logos: "rLogos",
    title: "rMainMenu",
    multi: "rMultiMenu",
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
  def step(%{screen: screen} = state, players) when screen in [:multi, :notice],
    do: OnlineFlow.step(state, players)

  def step(%{mode: :online, screen: screen} = state, players)
      when screen in [:bout, :levels, :results, :paused],
      do: OnlineFlow.round(state, players)

  def step(%{screen: :logos} = state, players) do
    state = scenery(state, players)
    if Title.continue?(players) or Logos.done?(state.timer), do: title(state), else: state
  end

  def step(%{screen: :title} = state, players) do
    state = state |> scenery(players) |> sway()
    context = Context.of(state)
    {menu, events} = MainMenu.step(state.menu, players, context)
    {menu, window_events} = windowed(menu, players, context)
    state = %{state | menu: menu, idle: state.idle + 1}
    state = Enum.reduce(events ++ window_events, state, &on_menu(&2, &1)) |> OnlineFlow.menus()
    if state.screen == :title and state.idle > @attract_steps, do: demo(state), else: state
  end

  def step(%{screen: :demo} = state, players) do
    if any_press?(players) or not Bout.running?(state.world),
      do: state |> killed(["Match"]) |> main_menu(),
      else: advance(state, players)
  end

  def step(%{screen: :levels, menu: %Confirm{} = box} = state, players) do
    state = scenery(state, players)

    case Confirm.step(box, players, %{}) do
      {:open, box, _events} -> %{state | menu: box}
      {:closed, [{:yes, :leave}]} -> main_menu(state)
      {:closed, _no} -> %{state | menu: nil}
    end
  end

  def step(%{screen: :levels} = state, players) do
    state = scenery(state, players)

    case Levels.input(state.levels, players) do
      {:choose, area} -> chosen(state, area)
      :back -> %{state | menu: leave_box(players)}
      {:moved, levels} -> moved_levels(state, levels)
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
        online_menu(state, state.typer || 1)

      again != nil and state.typing_armed and state.online.ssh == nil ->
        typing(%{state | typer: again})

      true ->
        state
    end
  end

  def step(%{screen: :address} = state, players) do
    state = state |> scenery(players) |> armed(players)
    again = Enum.find([1, 2], &(:start in players[&1].pressed or :attack in players[&1].pressed))

    cond do
      backing_out?(players) -> online_menu(state, state.typer || 1)
      again != nil and state.typing_armed -> typing(%{state | typer: again})
      true -> state
    end
  end

  def step(%{screen: :tournament} = state, players) do
    if in_room?(state.world, "rPreMatch") and pausing?(players),
      do: paused(state, players),
      else: state |> scenery(players) |> followed()
  end

  def step(%{screen: :credits} = state, players) do
    state = scenery(state, players)

    if Credits.leave?(players), do: main_menu(state, :credits), else: state
  end

  def step(%{screen: :bout} = state, players) do
    if pausing?(players),
      do: paused(state, players),
      else: bout(state, players)
  end

  def step(%{screen: :challenge} = state, players) do
    if pausing?(players),
      do: paused(state, players),
      else: advance(state, players)
  end

  def step(%{screen: :tutorial} = state, players) do
    cond do
      pausing?(players) ->
        paused(state, players)

      Gml.exists?(state.world, "Tutorial") ->
        advance(state, players)

      true ->
        main_menu(state, :how_to_play)
    end
  end

  def step(%{screen: :paused} = state, players) do
    case Pause.step(state.menu, players, Context.of(state)) do
      {:open, pause, events} -> Enum.reduce(events, %{state | menu: pause}, &on_pause(&2, &1))
      {:closed, events} -> Enum.reduce(events, state, &on_pause(&2, &1))
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

  def step(%{screen: :results, mode: :cpu_battle, timer: timer} = state, _players)
      when timer >= @cpu_battle_results,
      do: levels(state)

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
  The state with `ask` (`:menu`, `:quit`, `{:clipboard, text}` and the like) put to the
  client of the player on `side`, for the next `@ask_steps` steps, under a number no
  earlier ask had.
  """
  @spec ask(map(), 1 | 2, term()) :: map()
  def ask(state, side, ask) do
    owners = for {_id, %{side: ^side, owner: owner}} <- state.players, do: owner
    asked(state, owners, ask)
  end

  @doc "The state with `ask` put to the clients `owners`, as `ask/3` puts it."
  @spec asked(map(), [term()], term()) :: map()
  def asked(state, owners, ask) do
    number = state.ask_number + 1
    asks = Map.new(owners, &{&1, {number, ask, state.steps + @ask_steps}})
    %{state | ask_number: number, asks: Map.merge(state.asks, asks)}
  end

  @doc """
  The state after the player on `side` typed `text` for an entry of `kind` (`:address`
  or `:ssh_port`), or went back from it (`text` `:back`); typing for a screen no longer
  shown changes nothing.
  """
  @spec typed(map(), 1 | 2, :address | :ssh_port, String.t() | :back) :: map()
  def typed(%{screen: :address} = state, side, :address, :back), do: online_menu(state, side)

  def typed(%{screen: :ssh_hosting} = state, side, :ssh_port, :back),
    do: online_menu(state, side)

  def typed(%{screen: :ssh_hosting} = state, _side, :ssh_port, port),
    do: %{state | typing_armed: false, effects: [{:ssh_host, ssh_port(port)} | state.effects]}

  def typed(%{screen: :address} = state, side, :address, ""), do: typing(%{state | typer: side})

  def typed(%{screen: :address} = state, side, :address, typed) do
    with [address, port_text] <- String.split(typed, ":", parts: 2),
         {port, ""} when port in 1..65_535 <- Integer.parse(port_text) do
      state = online_menu(state, side)

      %{
        state
        | net: %{state.net | direct?: true},
          effects: [{:join_address, address, port, side} | state.effects]
      }
    else
      _bad -> typing(%{state | typer: side})
    end
  end

  def typed(state, _side, _kind, _text), do: state

  @doc """
  The state after the player connected over ssh left the game this machine serves
  (HOST OVER SSH), while on the level select, in a bout, its pause, the results or the
  replay: a bout in progress won by forfeit by the hosting player (a `{:result, row}`
  event with `won?` `true`), the match ended, and the serving screen (`:ssh_hosting`)
  shown again with the status "the other player left", still serving, so the next
  player connects as the first did. Any other state is returned unchanged.
  """
  @spec opponent_gone(map()) :: map()
  def opponent_gone(state), do: state |> departed() |> closed() |> forfeited()

  defp forfeited(%{screen: screen} = state) when screen in @played_online do
    if state.online.ssh != nil and not opponent?(state), do: forfeit(state), else: state
  end

  defp forfeited(state), do: state

  @doc "The state at the logos, the first screen."

  @spec logos(map()) :: map()
  def logos(state), do: enter(%{state | screen: :logos, menu: nil, timer: 0}, :logos)

  defp title(state), do: main_menu(state)

  @doc "The state at the main menu, opened at `resume` (`Nidhox.Screen.MainMenu.new/1`), every match, run and tournament ended."
  @spec main_menu(map(), atom() | nil) :: map()
  def main_menu(state, resume \\ nil) do
    world =
      ["ArcadeMode", "Match", "Tournament"]
      |> Enum.reduce(state.world, &kill_all(&2, &1))
      |> System.put(%{training: 0, flow: 1, level: @menu_level})
      |> World.put_global(:players, @menu_entrants)

    state = %{
      state
      | screen: :title,
        menu: MainMenu.new(resume),
        world: world,
        mode: nil,
        entrants: @menu_entrants,
        area: @menu_area,
        rules: %Rules{},
        idle: 0,
        timer: 0
    }

    enter(offline(state), :title)
  end

  defp windowed(%MainMenu{window: nil} = menu, _players, _context), do: {menu, []}

  defp windowed(%MainMenu{window: %module{} = window} = menu, players, context) do
    case module.step(window, players, context) do
      {:open, window, events} -> {%{menu | window: window}, events}
      {:closed, events} -> {%{menu | window: nil}, events}
    end
  end

  defp on_menu(state, {:sound, :move}), do: sound(state, @move_sound)
  defp on_menu(state, {:sound, :choose}), do: sound(state, @choose_sound)
  defp on_menu(state, :idle_reset), do: %{state | idle: 0}
  defp on_menu(state, {:go, :options, side}), do: ask(state, side, :menu)

  defp on_menu(state, {:go, :quit, side}),
    do:
      opened(
        state,
        Confirm.new({"quit_prompt", "QUIT TO DESKTOP?"}, {:quit, side},
          prompt_side: state.menu.prompt_side
        )
      )

  defp on_menu(state, {:yes, {:quit, side}}), do: ask(state, side, :quit)
  defp on_menu(state, :no), do: state
  defp on_menu(state, {:go, :news, _side}), do: opened(state, News.new())
  defp on_menu(state, {:read, key}), do: remembered(state, :news_seen, key)
  defp on_menu(state, {:link, url}), do: ask(state, state.menu.prompt_side, {:clipboard, url})
  defp on_menu(state, {:go, :how_to_play, _side}), do: tutorial(state)
  defp on_menu(state, {:go, :credits, _side}), do: credits(state)
  defp on_menu(state, {:go, :arcade, _side}), do: arcade(state)
  defp on_menu(state, {:go, :training, _side}), do: opened(state, training_window(state))

  defp on_menu(state, {:begin, personality, difficulty}),
    do: training(state, personality, difficulty)

  defp on_menu(state, {:go, :local, _side}), do: levels(%{state | mode: :versus})
  defp on_menu(state, {:go, :online, side}), do: OnlineFlow.open(state, side)
  defp on_menu(state, {:take, _lobby} = taken), do: OnlineFlow.invite_answered(state, taken)
  defp on_menu(state, :denied), do: OnlineFlow.invite_answered(state, :denied)

  defp on_menu(state, {:go, :tournament, _side}),
    do: state |> opened(TournamentMenu.new()) |> in_world(&Tournament.remade(&1, state.entrants))

  defp on_menu(state, {:go, :begin_cpu, _side}), do: cpu_battle(state)
  defp on_menu(state, {:go, :challenge, _side}), do: challenge(state)
  defp on_menu(state, {:hype, hype}), do: preferred(state, %{hype: hype})

  defp on_menu(state, {:time_limit, step}),
    do: %{
      state
      | rules: %{state.rules | time_limit: Rules.step_time_limit(state.rules.time_limit, step)}
    }

  defp on_menu(state, :sudden_death),
    do: %{state | rules: Rules.choose(state.rules, :suddenDeathOnly)}

  defp on_menu(state, {:seen, key}), do: remembered(state, :menu_seen, key)
  defp on_menu(state, :reset_variants), do: %{state | rules: %Rules{}}
  defp on_menu(state, {:rules, rules}), do: %{state | rules: rules}
  defp on_menu(state, {:lobby, _message}), do: state
  defp on_menu(state, :tournament_held), do: in_world(state, &Tournament.held/1)

  defp on_menu(state, {:entrants, entrants}),
    do: in_world(%{state | entrants: entrants}, &Tournament.remade(&1, entrants))

  defp on_menu(state, {:area, area}), do: %{state | area: area}
  defp on_menu(state, :tournament_closed), do: in_world(state, &Tournament.remade(&1, 0))
  defp on_menu(state, :start_tournament), do: tournament(state)

  defp paused(state, players) do
    side = Enum.find([1, 2], 1, &(:start in players[&1].pressed or :pause in players[&1].pressed))

    pause =
      Pause.new(
        flow: System.get(state.world, :flow),
        remote?: Context.of(state).remote?,
        variants?: Variants.active?(state.world),
        side: side
      )

    %{state | screen: :paused, menu: pause}
  end

  defp on_pause(state, :unpause), do: %{state | screen: resumed(state), menu: nil}
  defp on_pause(state, :change_level), do: state |> killed(["Match"]) |> levels()
  defp on_pause(state, {:exit, side}), do: quit_to_title(state, side)
  defp on_pause(state, {:options, side}), do: ask(state, side, :menu)
  defp on_pause(state, {:sound, :move}), do: sound(state, @move_sound)
  defp on_pause(state, {:sound, :choose}), do: sound(state, @choose_sound)
  defp on_pause(state, {:lobby, _message}), do: state

  defp on_pause(state, {:rules, rules}),
    do: %{state | rules: rules, world: System.put(state.world, Rules.system(rules))}

  defp on_pause(state, :restart_match),
    do: state |> killed(["Match"]) |> begin(state.area, state.rules)

  defp on_pause(state, {:colour, side, colour}) do
    colours = Map.put(Context.of(state).colours, side, colour)
    %{state | world: System.put(state.world, %{vsColor: colours})}
  end

  defp on_pause(state, :colours_kept) do
    colours = Context.of(state).colours
    preferred(state, %{colours: [colours[1], colours[2]]})
  end

  defp opened(%{menu: %MainMenu{} = menu} = state, window),
    do: %{state | menu: %{menu | window: window}}

  defp in_world(state, change), do: %{state | world: change.(state.world)}

  @doc "The state with `value` added to the prefs' list `key` and kept on the prefs player's client."
  @spec remembered(map(), atom(), term()) :: map()
  def remembered(state, key, value) do
    list = Map.fetch!(state.prefs, key)
    if value in list, do: state, else: preferred(state, %{key => list ++ [value]})
  end

  @doc "The state with `changes` merged into the prefs and kept on the prefs player's client."
  @spec preferred(map(), map()) :: map()
  def preferred(state, changes) do
    state = %{state | prefs: Map.merge(state.prefs, changes)}

    case state.players[state.prefs_from] do
      %{owner: owner} -> asked(state, [owner], {:options, Map.take(state.prefs, @kept_prefs)})
      nil -> state
    end
  end

  defp training_window(state) do
    chosen = System.get(state.world, :trainingPersonality, 5)

    personality =
      Enum.find_value(Personality.training(), :no_divekicks, fn {name, id} ->
        if id == chosen, do: name
      end)

    Training.new(personality, System.get(state.world, :trainingDifficulty, 0.5))
  end

  defp training(state, personality, difficulty) do
    {:ok, id} = Personality.training_id(personality)

    world =
      System.put(state.world, %{
        training: 1,
        trainingPersonality: id,
        trainingDifficulty: difficulty
      })

    levels(%{state | world: world, mode: :training})
  end

  defp cpu_battle(state) do
    world = System.put(state.world, %{cpuBattleHype: state.prefs.hype})
    levels(%{state | world: world, mode: :cpu_battle})
  end

  defp leave_box(players) do
    side = if MainMenu.pressed?(players, 2, 9), do: 2, else: 1
    Confirm.new({"leave_prompt", "BACK TO MAIN MENU?"}, :leave, prompt_side: side)
  end

  defp moved_levels(state, levels),
    do: sound(%{state | levels: levels, world: Levels.pan(levels, state.world)}, @move_sound)

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

  defp any_press?(players), do: Enum.any?(Map.values(players), &(MapSet.size(&1.pressed) > 0))

  defp demo(state) do
    released = Levels.released()
    {index, world} = Gml.irandom(state.world, length(released) - 1)
    area = Enum.at(released, index)
    world = Bout.start(world, area, %Rules{}, :demo)
    %{state | screen: :demo, mode: :demo, menu: nil, area: area, world: world, idle: 0, timer: 0}
  end

  @doc "The state with sound `sound` played at the `Ear`."
  @spec sound(map(), String.t()) :: map()
  def sound(state, sound) do
    case Gml.first(state.world, "Ear") do
      nil ->
        state

      ear ->
        %{
          state
          | world:
              Sound.play(
                state.world,
                Data.index(state.world.data, :sounds, sound),
                {World.fetch(state.world, ear).x, World.fetch(state.world, ear).y}
              )
        }
    end
  end

  defp levels(%{mode: :cpu_battle} = state) do
    released = Levels.released()
    {index, world} = Gml.irandom(state.world, length(released) - 1)
    levels = Levels.new(Enum.at(released, index), @cpu_battle_start)
    enter(%{state | screen: :levels, menu: nil, levels: levels, world: world, timer: 0}, :levels)
  end

  defp levels(%{mode: :online} = state),
    do:
      enter(
        %{state | screen: :levels, menu: nil, levels: Levels.new(state.area), timer: 0},
        :levels
      )

  defp levels(state),
    do: enter(%{state | screen: :levels, menu: nil, levels: Levels.new(), timer: 0}, :levels)

  defp online_menu(state, side) do
    state = %{state | entry: nil, effects: [:ssh_unhost | state.effects]}
    OnlineFlow.open(state, side)
  end

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

  defp waiting(state), do: main_menu(state)

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

  @doc "The state at HOST OVER SSH, the client of the player on `side` asked for the port."
  @spec ssh_hosting(map(), 1 | 2) :: map()
  def ssh_hosting(state, side) do
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

  @doc "The state at JOIN BY ADDRESS, the client of the player on `side` asked to type `address:port`."
  @spec address_entry(map(), 1 | 2) :: map()
  def address_entry(state, side),
    do: %{
      state
      | screen: :address,
        menu: nil,
        entry: {:address, "ADDRESS:PORT", ~c"0123456789.:", 21, ""},
        typer: side,
        effects: [:prefill_address | state.effects]
    }

  defp typing(state),
    do: ask(%{state | typing_armed: false}, state.typer, {:menu, {:typing, state.entry}})

  defp armed(%{typing_armed: true} = state, _players), do: state

  defp armed(state, players) do
    held? = Enum.any?(Map.values(players), &(:start in &1.held or :attack in &1.held))
    %{state | typing_armed: not held?}
  end

  defp offline(state), do: %{state | effects: [:listen, :unhost, :ssh_unhost | state.effects]}

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

  @doc "The state in the room of screen `screen` (`:logos`, `:title`, `:levels`, `:results`, `:multi` and the like)."
  @spec room(map(), atom()) :: map()
  def room(state, screen), do: enter(state, screen)

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

  @doc "The state with every instance of each object in `names` gone."
  @spec killed(map(), [String.t()]) :: map()
  def killed(state, names),
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

  @doc "The state after a step of its world under `players`' input."
  @spec advance(map(), map()) :: map()
  def advance(state, players),
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
        state.mode != :cpu_battle,
        side == 1 or (side == 2 and state.mode not in [:arcade, :training]) do
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

  @doc "The state after a step of its world under `players`' input, the grass tended."
  @spec scenery(map(), map()) :: map()
  def scenery(state, players) do
    world = state.world |> Step.run(Map.put(@no_keys, :players, players)) |> Grass.update_all()
    %{state | world: world}
  end
end
