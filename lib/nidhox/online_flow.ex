defmodule Nidhox.OnlineFlow do
  @moduledoc """
  ONLINE as `Nidhox.Flow` runs it: the online menu (`Nidhox.Screen.MultiMenu`) and its
  windows, the pairing of two players, and the rounds they play, all in the state of
  the machine that hosts the lobby, which the other machine follows with rollback.

  Screens:

    * `:multi` — `rMultiMenu` with the online menu. Over it: INVITE FRIEND
      (`Nidhox.Screen.Friends`), LEAVE THE LOBBY? (`Nidhox.Screen.Confirm`), INVITE!
      (`Nidhox.Screen.Invite`) and MATCH FOUND! (`Nidhox.Screen.Challenger`)
    * `:notice` — `Nidhox.Screen.NetNotice`, then the online menu afresh
    * `:bout`, `:levels`, `:results`, `:paused` in mode `:online` — the rounds

  A player arriving in a lobby this machine hosts is the opponent (`net.peer`). Through
  an invite both sides accept at once; else each answers MATCH FOUND!. A denial sends the
  other machine's player home (`{:return, %{online: outcome}}`): the side that denies
  stops searching, the other searches again with the denier declined. Once both
  accept, the lobby round begins: each side's colour (`netColor`, the second the other
  colour when they are the same), the recent opponents kept on both machines, and a
  match in `rOnlineLobby` with `System.flow` 4890734 (`netFlowKind` 1). When both stand
  in their ready zones for 60 steps (`Nidhox.Objects.Lobby`) the round ends for the
  level select, where the loser of the last match picks (`netLevelPicker`); the area
  chosen starts a match with `System.flow` 4 (`netFlowKind` 2), its sides swapped at
  random (`netSwap`); its results wait for both sides to go on, or 600 steps; and the
  lobby round starts again.

  In the lobby's pause, INPUT DELAY steps the input delay wanted from 1 to 10 frames
  (`netAdjustDelay`), shown in milliseconds, green when it covers half the round trip
  and 8 milliseconds, orange one frame short, red further short (`netDelayRating`);
  closing the pause with a new delay restarts the ready-up round with it, and both
  worlds stamp their input that far ahead (`input_delay/1`).

  In the lobby and on the level select, EXIT (LEAVE LOBBY) and back on the level select
  end the session for both: the leaver goes back to the online menu and the other sees
  OPPONENT DISCONNECTED!. In a match, FORFEIT gives it to the other side. An opponent
  gone unasked shows OPPONENT DISCONNECTED! once the lobby round has begun, and before
  that sends this side back to searching.
  """

  alias Cauldron2D.GameMaker.{Data, Rooms}
  alias Cauldron2D.World.Rollback
  alias Nidhox.{Bout, Flow, Gml, Lang, Online, Rules}
  alias Nidhox.Bout.Outcome
  alias Nidhox.Objects.{Match, System}
  alias Nidhox.Screen.{Challenger, Confirm, Context, Friends, Invite, Levels, MainMenu}
  alias Nidhox.Screen.{MultiMenu, NetNotice, Pause}

  @lobby_flow 4_890_734
  @stats_steps 600
  @lobby_room "rOnlineLobby"
  @multi_room "rMultiMenu"
  @online_key "online_2026_10"
  @recent_most 10
  @tick_sound "sndPickup"
  @scream_sounds 1..14
  @most_delay 10
  @frame_ms 1000 / 60
  @delay_margin_ms 8

  @doc "The online part of a game's state as it starts."
  @spec new() :: map()
  def new,
    do: %{
      flow_kind: 0,
      pairing: nil,
      peer: nil,
      denied?: false,
      window: nil,
      invite?: false,
      invite_name: "",
      invite_to: nil,
      declined: [],
      players_online: -1,
      history: [],
      stats_ok: %{1 => false, 2 => false},
      stats_timer: @stats_steps,
      swap: false,
      offers_denied: [],
      picker: 1,
      direct?: false,
      delay: nil,
      delay_pending: nil
    }

  @doc "The state with the online menu opened by the player on `side`."
  @spec open(map(), 1 | 2) :: map()
  def open(state, side) do
    owner = owner_of(state, side)
    online = %{state.online | owner: owner, status: nil}

    state = %{
      state
      | screen: :multi,
        mode: :online,
        menu: MultiMenu.new(),
        online: online,
        net: %{new() | declined: state.net.declined, history: []},
        effects: [:listen | state.effects],
        timer: 0
    }

    state |> Flow.remembered(:menu_seen, @online_key) |> room(@multi_room)
  end

  @doc "The state after a step of the online menu or the notice."
  @spec step(map(), map()) :: map()
  def step(%{screen: :notice} = state, players) do
    state = Flow.scenery(state, players)

    case NetNotice.step(state.menu, players, %{}) do
      {:open, notice, _events} -> %{state | menu: notice}
      {:closed, _events} -> state |> left() |> open(1)
    end
  end

  def step(%{screen: :multi, players: players_map} = state, _players)
      when map_size(players_map) == 0,
      do: state

  def step(%{screen: :multi} = state, players) do
    state = state |> Flow.scenery(players) |> arrivals() |> departures()

    state =
      cond do
        state.net.pairing != nil -> paired(state, players)
        state.net.window != nil -> windowed(state, players)
        true -> invited(state)
      end

    if state.screen == :multi, do: menu_step(state, players), else: state
  end

  @doc "The state after a step of a round in mode `:online`: the lobby, the level select, a match, its results, or a pause over them."
  @spec round(map(), map()) :: map()
  def round(state, players) do
    state = departures(state)

    if state.screen in [:bout, :levels, :results, :paused],
      do: rounded(state, players),
      else: state
  end

  defp rounded(%{screen: :bout} = state, players) do
    if pausing_side(players) != nil,
      do: paused(state, pausing_side(players)),
      else: played(state, players)
  end

  defp rounded(%{screen: :paused} = state, players) do
    side = state.menu.prompt_side
    state = played(state, quiet(players, side))

    case Pause.step(state.menu, only(players, side), Context.of(state)) do
      {:open, pause, events} ->
        Enum.reduce(events, %{state | menu: pause}, &on_pause(&2, &1, side))

      {:closed, events} ->
        Enum.reduce(events, state, &on_pause(&2, &1, side))
    end
  end

  defp rounded(%{screen: :levels, menu: %Confirm{} = box} = state, players) do
    state = Flow.scenery(state, players)

    case Confirm.step(box, players, %{}) do
      {:open, box, _events} -> %{state | menu: box}
      {:closed, [{:yes, side}]} -> leave_session(state, side)
      {:closed, _no} -> %{state | menu: nil}
    end
  end

  defp rounded(%{screen: :levels} = state, players) do
    state = Flow.scenery(state, players)
    picker = state.net.picker

    case Levels.input(state.levels, only(players, picker)) do
      {:choose, area} ->
        match(state, area)

      :back ->
        %{
          state
          | menu: Confirm.new({"leave_prompt", "BACK TO MAIN MENU?"}, picker, prompt_side: picker)
        }

      {:moved, levels} ->
        Flow.sound(
          %{state | levels: levels, world: Levels.pan(levels, state.world)},
          "sfxChangeLevel1"
        )

      {:stay, levels} ->
        %{state | levels: levels, world: Levels.pan(levels, state.world)}
    end
  end

  defp rounded(%{screen: :results} = state, players) do
    state = Flow.scenery(state, players)
    net = state.net

    ok =
      Enum.reduce([1, 2], net.stats_ok, fn side, ok ->
        if Enum.any?([8, 10, 9], &MainMenu.pressed?(players, side, &1)),
          do: Map.put(ok, side, true),
          else: ok
      end)

    net = %{net | stats_ok: ok, stats_timer: net.stats_timer - 1}
    state = %{state | net: net}

    if (ok[1] and ok[2]) or net.stats_timer <= 0,
      do: lobby(%{state | net: %{net | history: net.history ++ winner_list(state)}}),
      else: state
  end

  defp played(state, players) do
    state = Flow.advance(state, swapped(players, state.net.swap))

    cond do
      Gml.truthy?(System.get(state.world, :netFlowClose, 0)) -> flow_end(state)
      state.net.flow_kind == 2 and not Bout.running?(state.world) -> results(state)
      true -> state
    end
  end

  defp flow_end(state) do
    world = System.put(state.world, %{netFlowClose: 0})
    state = Flow.killed(%{state | world: world}, ["Match", "Tournament"])

    case state.net.flow_kind do
      1 -> level_select(state)
      _match -> lobby(state)
    end
  end

  defp level_select(state) do
    picker = picker(state.net.history)
    world = System.put(state.world, %{netFlowKind: 0})
    levels = Levels.new(state.area)

    %{
      state
      | screen: :levels,
        menu: nil,
        levels: levels,
        world: world,
        net: %{state.net | flow_kind: 0, picker: picker},
        timer: 0
    }
    |> Flow.room(:levels)
  end

  @doc "The side that picks the level (`netLevelPicker`): the loser of the last match, side 1 before any."
  @spec picker([1 | 2]) :: 1 | 2
  def picker([]), do: 1
  def picker(history), do: if(List.last(history) == 1, do: 2, else: 1)

  defp match(state, area) do
    {swap, world} = Gml.irandom(state.world, 1)
    world = System.put(world, %{netFlowKind: 2})
    world = Bout.start(world, area, state.rules, :online)

    net = %{
      state.net
      | flow_kind: 2,
        swap: swap == 1,
        stats_ok: %{1 => false, 2 => false},
        stats_timer: @stats_steps
    }

    %{
      state
      | screen: :bout,
        menu: nil,
        area: area,
        world: world,
        winner: nil,
        stats: nil,
        net: net,
        timer: 0,
        recording: %{world: world, inputs: [], kept: []}
    }
  end

  defp results(state) do
    winner = swapped_side(Bout.winner(state.world), state.net.swap)

    state = %{
      state
      | winner: winner,
        stats: Bout.stats(state.world),
        screen: :results,
        menu: nil,
        timer: 0
    }

    Flow.room(state, :results)
  end

  defp winner_list(%{winner: winner}) when winner in [1, 2], do: [winner]
  defp winner_list(_state), do: []

  defp lobby(state) do
    world = state.world |> System.put(%{flow: @lobby_flow, netFlowKind: 1, netFlowClose: 0})
    world = Match.start_match(world, Data.index(world.data, :rooms, @lobby_room))
    world = Rooms.enter(world, world.pending_room)
    net = %{state.net | flow_kind: 1, swap: false}
    %{state | screen: :bout, menu: nil, world: world, net: net, timer: 0}
  end

  defp paused(state, side) do
    pause =
      Pause.new(
        flow: System.get(state.world, :flow),
        remote?: true,
        lobby?: state.net.flow_kind == 1,
        variants?: false,
        side: side
      )

    %{state | screen: :paused, menu: pause}
  end

  defp on_pause(state, :unpause, _side) do
    net = state.net
    state = %{state | screen: :bout, menu: nil, net: %{net | delay_pending: nil}}

    if net.delay_pending != nil and net.delay_pending != current_delay(state),
      do: lobby(%{state | net: %{state.net | delay: net.delay_pending}}),
      else: state
  end

  defp on_pause(state, {:input_delay, step}, _side) do
    wanted = (wanted_delay(state) + step) |> max(1) |> min(@most_delay)
    state = Flow.sound(state, "sfxChangeLevel1")
    %{state | net: %{state.net | delay_pending: wanted}}
  end

  defp on_pause(state, {:exit, _chooser}, side) when state.net.flow_kind == 2,
    do: forfeit(state, side)

  defp on_pause(state, {:exit, _chooser}, side), do: leave_session(state, side)
  defp on_pause(state, {:options, _chooser}, side), do: Flow.ask(state, side, :menu)
  defp on_pause(state, {:sound, :move}, _side), do: Flow.sound(state, "sfxChangeLevel1")
  defp on_pause(state, {:sound, :choose}, _side), do: Flow.sound(state, "sndLevel")

  defp on_pause(state, {:rules, rules}, _side),
    do: %{state | rules: rules, world: System.put(state.world, Rules.system(rules))}

  defp on_pause(state, {:colour, side, colour}, _side), do: coloured(state, side, colour)
  defp on_pause(state, _event, _side), do: state

  defp forfeit(state, side) do
    winner = swapped_side(3 - side, state.net.swap)
    %{state | screen: :bout, menu: nil, world: Outcome.winner(state.world, winner)}
  end

  defp coloured(state, side, colour) do
    colours = Context.of(state).colours |> Map.put(side, colour)
    %{state | world: System.put(state.world, %{vsColor: colours})}
  end

  defp leave_session(state, side) do
    case state.net.peer do
      nil ->
        state |> left() |> open(1)

      peer ->
        if side == peer.side do
          state = Flow.asked(state, [peer.owner], {:return, %{online: :menu}})
          %{state | net: %{state.net | peer: %{peer | leaving?: true}}}
        else
          state
          |> Flow.asked([peer.owner], {:return, %{online: {:notice, "opponent_disconnected"}}})
          |> left()
          |> open(side)
        end
    end
  end

  defp left(state) do
    state = Flow.killed(state, ["Match", "Tournament"])

    %{
      state
      | effects: [:unhost | state.effects],
        world: System.put(state.world, %{netFlowKind: 0, flow: 1})
    }
  end

  defp menu_step(state, players) do
    context = context(state)
    {menu, events} = MultiMenu.step(state.menu, players, context)
    Enum.reduce(events, %{state | menu: menu}, &on_menu(&2, &1))
  end

  defp on_menu(state, {:sound, :move}), do: Flow.sound(state, "sfxChangeLevel1")
  defp on_menu(state, {:sound, :choose}), do: Flow.sound(state, "sndLevel")
  defp on_menu(state, {:host, kind}), do: host(state, kind)
  defp on_menu(state, :unhost), do: %{state | effects: [:unhost | state.effects]}
  defp on_menu(state, {:join, lobby}), do: join(state, lobby)

  defp on_menu(state, {:publish, fields}),
    do: %{state | effects: [{:publish, fields} | state.effects]}

  defp on_menu(state, {:declined, list}), do: %{state | net: %{state.net | declined: list}}
  defp on_menu(state, {:global, global?}), do: Flow.preferred(state, %{search_global: global?})

  defp on_menu(state, {:players_online, count}),
    do: %{state | net: %{state.net | players_online: count}}

  defp on_menu(state, :friends), do: %{state | net: %{state.net | window: Friends.new()}}
  defp on_menu(state, :ssh), do: Flow.ssh_hosting(state, state.menu.prompt_side)
  defp on_menu(state, :address), do: Flow.address_entry(state, state.menu.prompt_side)

  defp on_menu(state, :leave_prompt),
    do: %{
      state
      | net: %{
          state.net
          | window:
              Confirm.new({"leave_lobby_prompt", "LEAVE THE LOBBY?"}, :leave_lobby,
                prompt_side: state.menu.prompt_side
              )
        }
    }

  defp on_menu(state, :leave) do
    state = %{state | effects: [:unhost, :unlisten | state.effects]}
    Flow.main_menu(state, :online)
  end

  defp host(state, kind) do
    me = me(state)
    fields = Online.lobby_fields(me.id, me.name, kind)

    fields =
      if kind == :friends and state.net.invite_to,
        do: Map.put(fields, "invite", Integer.to_string(state.net.invite_to)),
        else: fields

    %{state | effects: [{:host, kind, fields} | state.effects]}
  end

  defp join(state, lobby),
    do: %{
      state
      | effects: [{:join, lobby, state.menu.prompt_side, state.net.invite?} | state.effects]
    }

  defp windowed(state, players) do
    %module{} = window = state.net.window

    case module.step(window, players, window_context(state)) do
      {:open, window, events} ->
        Enum.reduce(events, put_window(state, window), &on_window(&2, &1))

      {:closed, events} ->
        Enum.reduce(events, put_window(state, nil) |> held(2), &on_window(&2, &1))
    end
  end

  defp put_window(state, window), do: %{state | net: %{state.net | window: window}}
  defp held(state, steps), do: %{state | menu: MultiMenu.hold(state.menu, steps)}

  defp on_window(state, {:sound, :move}), do: Flow.sound(state, "sfxChangeLevel1")
  defp on_window(state, {:sound, :choose}), do: Flow.sound(state, "sndLevel")
  defp on_window(state, {:join, lobby}), do: invite_join(state, lobby)
  defp on_window(state, {:take, lobby}), do: invite_join(state, lobby)

  defp on_window(state, {:invite, id, name}) do
    net = %{state.net | invite?: true, invite_name: name, invite_to: id}
    menu = %{state.menu | want: false, active: false}
    host(%{state | net: net, menu: menu}, :friends)
  end

  defp on_window(state, {:yes, :leave_lobby}) do
    state = Flow.killed(state, ["Match"])
    net = %{state.net | invite?: false, invite_name: "", invite_to: nil}
    menu = if state.menu.want, do: %{state.menu | want: false}, else: state.menu
    declined = if state.menu.want, do: [], else: net.declined
    %{state | net: %{net | declined: declined}, menu: menu, effects: [:unhost | state.effects]}
  end

  defp on_window(state, :denied) do
    case state.net.window do
      %Invite{lobby: lobby} ->
        %{
          state
          | net: %{
              state.net
              | offers_denied: [{lobby.owner, lobby.port} | state.net.offers_denied]
            }
        }

      _other ->
        state
    end
  end

  defp on_window(state, _event), do: state

  defp invite_join(state, lobby) do
    net = %{state.net | invite?: true, invite_name: "", window: nil}
    menu = %{state.menu | want: false, active: false, resume: false, join_at: 0, error: ""}
    join(%{state | net: net, menu: menu, screen: :multi}, lobby)
  end

  defp invited(state) do
    me = me(state)

    case Enum.find(state.online.lobbies, &invites?(&1, me.id, state.net.offers_denied)) do
      nil -> state
      lobby -> %{state | net: %{state.net | window: Invite.new(lobby)}} |> Flow.sound(@tick_sound)
    end
  end

  defp invites?(lobby, id, denied),
    do: lobby.invite == id and lobby.kind == "friends" and {lobby.owner, lobby.port} not in denied

  @doc "The state of the menus outside ONLINE after a step, with an invite from a friend offered when one is heard."
  @spec menus(map()) :: map()
  def menus(%{screen: :title, menu: %MainMenu{window: nil} = menu} = state) do
    me = me(state)

    case Enum.find(state.online.lobbies, &invites?(&1, me.id, state.net.offers_denied)) do
      nil -> state
      lobby -> %{state | menu: %{menu | window: Invite.new(lobby)}} |> Flow.sound(@tick_sound)
    end
  end

  def menus(state), do: state

  @doc "The state after the main menu's INVITE! box closed with `event`."
  @spec invite_answered(map(), term()) :: map()
  def invite_answered(state, {:take, lobby}),
    do: state |> open(state.menu.prompt_side) |> invite_join(lobby)

  def invite_answered(state, :denied), do: state
  def invite_answered(state, _event), do: state

  defp arrivals(%{net: %{peer: nil}} = state) do
    case remote(state) do
      nil -> state
      {id, player} -> arrived(state, id, player)
    end
  end

  defp arrivals(state), do: state

  defp arrived(state, id, player) do
    peer = %{
      id: id,
      owner: player.owner,
      side: player.side,
      net_id: Map.get(player, :net_id),
      name: Map.get(player, :name, ""),
      round_trip: Map.get(player, :round_trip),
      invited?: Map.get(player, :invited) == true,
      leaving?: false
    }

    state = %{
      state
      | net: %{state.net | peer: peer, denied?: false},
        menu: MultiMenu.arrived(state.menu, peer.net_id)
    }

    state = Flow.sound(state, "sfxScream#{Enum.random(@scream_sounds)}")
    me = me(state)
    state = Flow.asked(state, [peer.owner], {:on_return, %{online: {:resume, me.id}}})

    cond do
      state.net.invite? ->
        accepted(state)

      peer.invited? ->
        %{state | net: %{state.net | pairing: Challenger.accept(Challenger.new(), peer.side)}}

      true ->
        %{state | net: %{state.net | pairing: Challenger.new()}}
    end
  end

  defp departures(%{net: %{peer: nil}} = state), do: state

  defp departures(%{net: %{peer: peer}} = state) do
    if Map.has_key?(state.players, peer.id), do: state, else: departed(state, peer)
  end

  defp departed(state, peer) do
    state = %{state | net: %{state.net | peer: nil, pairing: nil}}

    cond do
      peer.leaving? ->
        state |> left() |> open(1) |> notice("opponent_disconnected")

      state.net.flow_kind != 0 or state.screen != :multi ->
        state |> left() |> notice("opponent_disconnected")

      state.net.denied? ->
        %{state | net: %{state.net | denied?: false}}

      true ->
        %{state | menu: %{MultiMenu.resumed(state.menu) | partner: peer.net_id}}
    end
  end

  defp notice(state, key) do
    text = Lang.text(state.prefs.language, "online match", key, notice_english(key))

    %{
      state
      | screen: :notice,
        menu: NetNotice.new(text),
        mode: :online,
        net: %{state.net | flow_kind: 0}
    }
  end

  defp notice_english("opponent_disconnected"), do: "OPPONENT DISCONNECTED!"
  defp notice_english(_key), do: "CONNECTION LOST"

  defp paired(state, players) do
    case Challenger.step(state.net.pairing, players, %{}) do
      {:open, box, events} ->
        Enum.reduce(events, %{state | net: %{state.net | pairing: box}}, &on_pairing(&2, &1))

      {:closed, [:accepted]} ->
        accepted(state)

      {:closed, [{:denied, sides}]} ->
        denied(%{state | net: %{state.net | pairing: nil}}, sides)
    end
  end

  defp on_pairing(state, :tick), do: Flow.sound(state, @tick_sound)
  defp on_pairing(state, {:sound, :choose}), do: Flow.sound(state, "sndLevel")

  defp denied(state, sides) do
    peer = state.net.peer
    me = me(state)
    host_side = 3 - peer.side

    {state, outcome} =
      if host_side in sides,
        do:
          {%{state | menu: MultiMenu.stopped(state.menu), net: %{state.net | denied?: true}},
           if(peer.side in sides, do: :menu, else: {:resume, me.id})},
        else:
          {%{
             state
             | net: %{state.net | denied?: true},
               menu: %{MultiMenu.resumed(state.menu) | partner: peer.net_id}
           }, :menu}

    state = Flow.asked(state, [peer.owner], {:return, %{online: outcome}})
    held(state, 2)
  end

  defp accepted(state) do
    peer = state.net.peer
    me = me(state)
    host_side = 3 - peer.side
    own = Enum.at(state.prefs.colours, 0, 1)
    theirs = peer_colour(state, peer)
    theirs = if theirs == own, do: rem(own, 8) + 1, else: theirs
    colours = %{host_side => own, peer.side => theirs}

    world = System.put(state.world, %{vsColor: colours, training: 0})

    state = %{
      state
      | world: world,
        net: %{
          state.net
          | pairing: nil,
            history: [],
            invite?: false,
            invite_name: "",
            invite_to: nil
        }
    }

    state
    |> recent(me, peer)
    |> Flow.asked([peer.owner], {:on_return, %{online: {:notice, "opponent_disconnected"}}})
    |> then(
      &%{
        &1
        | effects: [{:publish, %{"open" => "0", "players" => "2", "avail" => "0"}} | &1.effects]
      }
    )
    |> lobby()
  end

  defp peer_colour(state, peer) do
    case state.players[peer.id] do
      %{colours: [_first, second]} -> second
      _none -> 2
    end
  end

  defp recent(state, me, peer) do
    today = today()

    mine =
      recorded(state.prefs[:recent] || [], %{id: peer.net_id || 0, date: today, name: peer.name})

    theirs =
      recorded(Map.get(state.players[peer.id] || %{}, :recent, []), %{
        id: me.id,
        date: today,
        name: me.name
      })

    state
    |> Flow.preferred(%{recent: mine})
    |> Flow.asked([peer.owner], {:options, %{recent: theirs}})
  end

  defp recorded(list, entry) do
    [entry | Enum.reject(list, &(&1.id == entry.id))] |> Enum.take(@recent_most)
  end

  defp today do
    {{year, month, day}, _time} = :calendar.local_time()
    year * 10_000 + month * 100 + day
  end

  @doc """
  The state after this machine's own player came back to it from a lobby elsewhere,
  joined with `outcome` (`{:resume, declined}`, `:menu`, `{:notice, key}`, or
  `:refused` when the lobby could not be joined).
  """
  @spec returned(map(), term()) :: map()
  def returned(%{screen: :multi} = state, {:resume, declined}),
    do: %{state | menu: %{MultiMenu.resumed(state.menu) | partner: declined}}

  def returned(%{screen: :multi} = state, :menu),
    do: %{state | menu: MultiMenu.stopped(state.menu)}

  def returned(%{screen: :multi, net: %{direct?: true}} = state, :refused) do
    text = Lang.text(state.prefs.language, "online match", "connection_lost", "CONNECTION LOST")
    %{state | menu: MultiMenu.failed(state.menu, text), net: %{state.net | direct?: false}}
  end

  def returned(%{screen: :multi} = state, :refused),
    do: %{state | menu: MultiMenu.resumed(state.menu)}

  def returned(%{screen: :multi} = state, {:notice, key}),
    do: notice(%{state | menu: MultiMenu.stopped(state.menu)}, key)

  def returned(state, _outcome), do: state

  defp menu_context(state), do: Map.merge(Context.of(state), context(state))

  @doc "The online menu's context (`Nidhox.Screen.MultiMenu`) for `state`."
  @spec context(map()) :: map()
  def context(state) do
    me = me(state)
    peer = state.net.peer

    Map.merge(Context.of(state), %{
      now: round(state.steps * 1000 / 60),
      self: me.id,
      lobbies: state.online.lobbies,
      pings: state.online.pings,
      heard_at: if(state.online.lobbies_at, do: round(state.online.lobbies_at * 1000 / 60)),
      hosted: state.online.hosted,
      remote: if(peer, do: %{id: peer.net_id, name: peer.name}),
      invite: if(state.net.invite?, do: state.net.invite_name),
      invited?: state.net.invite?,
      global?: Map.get(state.prefs, :search_global, false),
      declined: state.net.declined,
      pairing?: state.net.pairing != nil,
      window?: state.net.pairing != nil or state.net.window != nil,
      players_online: state.net.players_online,
      rhymes: rhymes(),
      address: address(state.online),
      recent: Map.get(state.prefs, :recent, [])
    })
  end

  defp window_context(state),
    do: Map.put(menu_context(state), :prompt_side, state.menu.prompt_side)

  defp address(%{hosted: nil}), do: nil

  defp address(%{port: port}) do
    case Cauldron2D.Distribution.address() do
      {:ok, address} -> "#{address} : #{port}"
      {:error, _reason} -> nil
    end
  end

  defp rhymes do
    case :persistent_term.get({__MODULE__, :rhymes}, nil) do
      nil ->
        lines = read_rhymes()
        :persistent_term.put({__MODULE__, :rhymes}, lines)
        lines

      lines ->
        lines
    end
  end

  defp read_rhymes do
    path = Path.join(Path.dirname(Nidhox.Assets.get().path), "match.txt")

    case File.read(path) do
      {:ok, text} ->
        lines = String.split(text, ["\r\n", "\n"])
        if List.last(lines) == "", do: Enum.drop(lines, -1), else: lines

      {:error, _reason} ->
        []
    end
  end

  @doc "This machine's player online: `%{id, name}`, the prefs player's id (`net_id`) and name."
  @spec me(map()) :: %{id: integer(), name: String.t()}
  def me(state) do
    player = state.players[state.prefs_from] || %{}
    %{id: Map.get(state.prefs, :net_id) || 0, name: Map.get(player, :name, "")}
  end

  defp remote(state) do
    Enum.find(state.players, fn {_id, player} ->
      player.side != nil and Online.remote_player?(state, player) and state.online.ssh == nil
    end)
  end

  defp owner_of(state, side),
    do:
      Enum.find_value(state.players, fn {_id, player} -> player.side == side && player.owner end)

  defp pausing_side(players),
    do: Enum.find([1, 2], &(:start in players[&1].pressed or :pause in players[&1].pressed))

  defp only(players, side) do
    empty = %{held: MapSet.new(), pressed: MapSet.new(), released: MapSet.new()}
    Map.new([1, 2], &{&1, if(&1 == side, do: players[&1], else: empty)})
  end

  defp quiet(players, side), do: only(players, 3 - side)

  defp swapped(players, false), do: players
  defp swapped(players, true), do: %{1 => players[2], 2 => players[1]}

  defp swapped_side(nil, _swap), do: nil
  defp swapped_side(side, false), do: side
  defp swapped_side(side, true), do: 3 - side

  defp room(state, name) do
    room = Data.index(state.world.data, :rooms, name)
    if state.world.room == room, do: state, else: %{state | world: Rooms.enter(state.world, room)}
  end

  @doc "The input delay both worlds stamp their input ahead with, in frames, `nil` for the one they started with (`Cauldron2D.Game`'s `input_delay/1`)."
  @spec input_delay(map()) :: pos_integer() | nil
  def input_delay(%{net: %{delay: delay}}), do: delay
  def input_delay(_state), do: nil

  @doc "The input delay INPUT DELAY shows: `%{ms, colour}` of the delay wanted (`netWantedDelay`), coloured by `netDelayRating`."
  @spec delay_shown(map()) :: %{ms: integer(), colour: {byte(), byte(), byte()}}
  def delay_shown(state) do
    wanted = wanted_delay(state)
    needed = needed_delay(state)

    colour =
      cond do
        needed == nil or needed - wanted <= 0 -> {128, 255, 64}
        needed - wanted == 1 -> {255, 208, 64}
        true -> {255, 64, 64}
      end

    %{ms: round(wanted * @frame_ms), colour: colour}
  end

  defp wanted_delay(state), do: state.net.delay_pending || current_delay(state)
  defp current_delay(state), do: state.net.delay || auto_delay(state)

  defp auto_delay(state) do
    case state.net.peer do
      %{round_trip: round_trip} when is_number(round_trip) ->
        Rollback.delay(round_trip, 60)

      _unknown ->
        2
    end
  end

  defp needed_delay(state) do
    case state.net.peer do
      %{round_trip: round_trip} when is_number(round_trip) ->
        ceil((round_trip / 2 + @delay_margin_ms) / @frame_ms)

      _unknown ->
        nil
    end
  end

  @doc "The opponent's ping in milliseconds, half the round trip their machine measured to this one, `nil` while unknown."
  @spec ping_of(map()) :: number() | nil
  def ping_of(%{net: %{peer: %{round_trip: round_trip}}}) when is_number(round_trip),
    do: round_trip / 2

  def ping_of(_state), do: nil

  @doc "The side each slot of the round plays: `side` itself, or the other with the sides swapped (`slotPlayer`)."
  @spec slot_side(map(), 1 | 2) :: 1 | 2
  def slot_side(state, side), do: swapped_side(side, state.net.swap)

  @doc "The matches each side has won since the lobby began (`getPlayerWins`)."
  @spec wins(map(), 1 | 2) :: non_neg_integer()
  def wins(state, side), do: Enum.count(state.net.history, &(&1 == side))

  @doc "The results' line for side `side` when it has gone on and the other has not: \"Waiting for opponent\" and the seconds left."
  @spec waiting(map(), 1 | 2) :: String.t() | nil
  def waiting(%{screen: :results, mode: :online, net: net} = state, side) do
    if net.stats_ok[side] and not net.stats_ok[3 - side],
      do:
        Lang.text(
          state.prefs.language,
          "online match",
          "waiting_for_opponent",
          "Waiting for opponent"
        ) <> " (#{max(ceil(net.stats_timer / 60), 0)})",
      else: nil
  end

  def waiting(_state, _side), do: nil
end
