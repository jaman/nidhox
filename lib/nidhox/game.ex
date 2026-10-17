defmodule Nidhox.Game do
  @moduledoc """
  NidhOX as a `Cauldron2D.Game`, stepped 60 times a second, the rooms running in
  `Cauldron2D.GameMaker`, the screens following `Nidhox.Flow` from the logos on.

      Cauldron2D.World.start_link(game: Nidhox.Game, game_opts: [area: "Wilds"], hz: 60)

  Options: `:area` (`"Cemetery"`, `"Castle"`, `"Mines"`, `"Sky"`, `"Wilds"`; default
  `"Cemetery"`), the area the level select starts on; `:port`, the port ONLINE's
  host listens on for the joining machine (default any free port); `:seed`, the game's
  random number seed (default the clock). `Nidhox.Assets.load/1` must have run first.

  The first two players to join take sides `1` and `2`. A player joining as a client's
  local seat (join prop `:seat_of`) belongs to that client: what the game asks of a
  seat's player goes to the client it is a seat of. A player on a client of their own
  who joins with both sides taken takes a side from a seat of another client, the seat
  then watching; anyone else joining after the first two watches. A side left free goes
  to a watching seat. Where the computer plays side 2, the input of a player on side 2
  is not used. ONLINE's hosting and joining are `Nidhox.Online`'s.

  The game's prefs that change what it does — `System.flashing` and
  `System.persistent_blood` — and its language follow the options (`:flashing`,
  `:persistent_blood`, each `true` or `false`; `:language`) sent with the input of the
  first player to join, and when that player leaves, of one of those still there. That
  player's `:hype`, `:menu_seen`, `:news_seen`, `:colours` (CHANGE COLOR's choice
  for each side, put in `System.vsColor`), `:net_id` (the player's id online),
  `:recent` (their recent opponents) and `:search_global` are read from their first
  input with options; after that the game changes them itself and asks that player's
  client to keep them (`Nidhox.Flow`). A player with no `:net_id` is given one, made
  from their name and the step they joined at.

  Every player keeps their name (the join's `:username`), the round trip their machine
  measured to this one (the join's `:round_trip`, `Cauldron2D.World`), whether they
  joined through an invite (the join's `:invited`), and from their
  options their `net_id`, `colours` and `recent`, which ONLINE reads
  (`Nidhox.OnlineFlow`). A player who comes back from a lobby elsewhere joins with
  `online:` the outcome (`Nidhox.OnlineFlow.returned/2`), or `refused: true` when the
  lobby could not be joined.

  A view is the frame — `items` (room pixels), `gui` (the room's own, window pixels),
  `overlay` (the screen's, window pixels, over `gui`), `surfaces` (the rasters
  `{:surface, id}` pictures name), `background`,
  `view`, `window`, `screen`, `area` — with the viewer's `side` and `ask`, what the game
  asks of the viewer's client (`Nidhox.Flow.ask/3`), or `nil`.

  A bout's sounds are sent as events from its objects. Each finished bout sends a
  `{:result, row}` event for every player who fought it, with the player's id and name,
  `won?`, the area and the mode. While the game is paused, and not hosting ONLINE
  VERSUS, it is silent (`mute` and `unMute`): a `Cauldron2D.Audio.muted/1` event as the
  pause begins and another as it ends.

  A world on another machine follows this one for ONLINE (`Cauldron2D.World`'s
  `:follow`): `export/1` sends it the state without the data file's parts, the picture
  lookup, the surfaces' pixels or the frame's, `restore/1` fills them in from that
  machine's own copy and marks the state `following`, so `Nidhox.Online` carries out
  none of its effects there, and `checksum/1` covers what the steps decide: the world's
  instances and the rest of the game's state, not its surfaces, `online`, `following` or
  `frame`.
  """

  @behaviour Cauldron2D.Game

  import Bitwise

  alias Cauldron2D.Audio
  alias Cauldron2D.GameMaker.Data
  alias Cauldron2D.GameMaker.Draw
  alias Cauldron2D.GameMaker.Surfaces
  alias Cauldron2D.GameMaker.World
  alias Nidhox.{Assets, Flow, Online, Screen}
  alias Nidhox.Bout.Spiral
  alias Nidhox.Objects.System

  @sides [1, 2]
  @prefs %{
    language: "en",
    menu_seen: [],
    news_seen: [],
    hype: 0.75,
    colours: [1, 2],
    net_id: nil,
    recent: [],
    search_global: false
  }
  @kept_online [:net_id, :colours, :recent]

  @impl true
  def init(opts) do
    %Assets{data: data, object_depths: object_depths} = Assets.get()

    %{
      world:
        World.new(data, Nidhox.Code,
          room: Data.index(data, :rooms, "rLogos"),
          pictures: &Map.get(Assets.get().pictures, &1),
          object_depths: object_depths,
          seed: Keyword.get_lazy(opts, :seed, fn -> :os.system_time(:millisecond) end)
        )
        |> System.create(),
      screen: nil,
      menu: nil,
      levels: nil,
      mode: nil,
      area: Keyword.get(opts, :area) || "Cemetery",
      winner: nil,
      stats: nil,
      rules: %Nidhox.Rules{},
      recording: nil,
      kept: nil,
      entrants: 3,
      idle: 0,
      tutorial: nil,
      online:
        Online.new(Keyword.get(opts, :port), Keyword.get(opts, :ssh_port) || env_ssh_port()),
      entry: nil,
      typer: nil,
      typing_armed: false,
      requests: %{},
      address: nil,
      effects: [],
      credits: "",
      timer: 0,
      steps: 0,
      players: %{},
      asks: %{},
      ask_number: 0,
      held: Map.new(@sides, &{&1, MapSet.new()}),
      previous: Map.new(@sides, &{&1, MapSet.new()}),
      events: [],
      frame: nil,
      prefs_from: nil,
      prefs_loaded: nil,
      prefs: @prefs,
      devices: %{1 => nil, 2 => nil},
      net: Nidhox.OnlineFlow.new(),
      following: false
    }
    |> Flow.logos()
    |> present()
  end

  @impl true
  def join(state, id, props) do
    owner = Map.get(props, :seat_of, id)

    state =
      case {free_side(state), owner} do
        {nil, ^id} -> take_from_seat(state, id)
        {side, _owner} -> put_in(state.players[id], %{side: side, owner: owner})
      end

    state = Map.update!(state, :players, &Map.put_new(&1, id, %{side: nil, owner: owner}))

    state =
      Map.update!(
        state,
        :players,
        &Map.update!(&1, id, fn player -> Map.merge(player, identity(id, props)) end)
      )

    state = %{state | prefs_from: state.prefs_from || id}
    {:ok, returned(state, props)}
  end

  defp identity(id, props) do
    options = get_in(props, [:settings, :options]) || %{}

    %{
      name: to_string(Map.get(props, :username, id)),
      round_trip: Map.get(props, :round_trip),
      invited: Map.get(props, :invited) == true
    }
    |> Map.merge(Map.take(options, @kept_online))
  end

  defp returned(state, %{online: outcome}), do: Nidhox.OnlineFlow.returned(state, outcome)
  defp returned(state, %{refused: true}), do: Nidhox.OnlineFlow.returned(state, :refused)
  defp returned(state, _props), do: state

  @impl true
  def leave(state, id) do
    state
    |> without_player(id)
    |> prefs_passed_on(id)
  end

  defp prefs_passed_on(%{prefs_from: id} = state, id),
    do: %{state | prefs_from: state.players |> Map.keys() |> List.first()}

  defp prefs_passed_on(state, _id), do: state

  defp without_player(state, id) do
    case Map.pop(state.players, id) do
      {nil, _players} ->
        state

      {%{side: nil}, players} ->
        %{state | players: players}

      {%{side: side}, players} ->
        %{
          state
          | players: seat_side(players, side),
            held: Map.put(state.held, side, MapSet.new())
        }
    end
  end

  @impl true
  def handle_input(state, id, %{held: held} = input) do
    state
    |> held_by(id, held)
    |> device_of(id, input)
    |> identified(id, Map.get(input, :options, %{}))
    |> preferred(id, Map.get(input, :options, %{}))
    |> requested(id, Map.get(input, :request))
  end

  defp env_ssh_port do
    case Integer.parse(Elixir.System.get_env("NIDHOX_SSH_PORT", "")) do
      {port, ""} when port in 1..65_535 -> port
      _unset -> nil
    end
  end

  defp requested(state, _id, nil), do: state

  defp requested(state, id, {number, request}) do
    if Map.get(state.requests, id, 0) >= number,
      do: state,
      else: state |> put_in([:requests, id], number) |> act_on(id, request)
  end

  defp act_on(state, id, {:typed, kind, text}) do
    case state.players[id] do
      %{side: side} when side != nil -> Flow.typed(state, side, kind, text)
      _watching -> state
    end
  end

  defp act_on(state, _id, _request), do: state

  defp held_by(state, id, held) do
    case Map.fetch(state.players, id) do
      {:ok, %{side: side}} when side != nil -> put_in(state.held[side], held)
      _watching -> state
    end
  end

  defp device_of(state, id, %{device: device} = input) do
    case Map.fetch(state.players, id) do
      {:ok, %{side: side}} when side != nil ->
        put_in(state.devices[side], %{device: device, keys: Map.get(input, :keys, %{})})

      _watching ->
        state
    end
  end

  defp device_of(state, _id, _input), do: state

  defp identified(state, id, options) do
    case {Map.fetch(state.players, id), Map.take(options, @kept_online)} do
      {{:ok, _player}, online} when map_size(online) > 0 ->
        update_in(state.players[id], &Map.merge(&1, online))

      _none ->
        state
    end
  end

  defp preferred(%{prefs_from: id} = state, id, options) when map_size(options) > 0 do
    kept = kept_prefs(options)
    first? = state.prefs_loaded != id
    kept = if first?, do: kept, else: Map.take(kept, [:language])
    state = %{state | prefs: Map.merge(state.prefs, kept), prefs_loaded: id}
    state = if first? and state.prefs.net_id == nil, do: identity_made(state, id), else: state

    prefs =
      for {option, variable} <- [flashing: :flashing, persistent_blood: :persistent_blood],
          is_boolean(Map.get(options, option)),
          into: %{},
          do: {variable, if(Map.fetch!(options, option), do: 1, else: 0)}

    %{state | world: state.world |> System.put(prefs) |> coloured(kept)}
  end

  defp preferred(state, _id, _options), do: state

  defp identity_made(state, id) do
    name = state.players[id][:name] || to_string(id)
    high = :erlang.phash2({name, state.steps, :high}, 1 <<< 31)
    low = :erlang.phash2({name, state.steps, :low}, 1 <<< 31)
    Flow.preferred(state, %{net_id: (high <<< 31) + low + 1})
  end

  defp coloured(world, %{colours: [first, second]}),
    do: System.put(world, %{vsColor: %{1 => first, 2 => second}})

  defp coloured(world, _kept), do: world

  defp kept_prefs(options) do
    for {key, value} <- Map.take(options, Map.keys(@prefs)),
        kept?(key, value),
        into: %{},
        do: {key, value}
  end

  defp kept?(:language, code), do: code in Nidhox.Lang.codes()
  defp kept?(:hype, hype), do: is_number(hype) and hype >= 0 and hype <= 1

  defp kept?(:colours, [first, second]),
    do: first in 1..8 and second in 1..8 and first != second

  defp kept?(:colours, _colours), do: false
  defp kept?(:net_id, net_id), do: is_integer(net_id) and net_id > 0
  defp kept?(:search_global, global?), do: is_boolean(global?)

  defp kept?(:recent, recent),
    do:
      is_list(recent) and
        Enum.all?(
          recent,
          &match?(%{id: id, date: _date, name: name} when is_integer(id) and is_binary(name), &1)
        )

  defp kept?(_list, keys), do: is_list(keys) and Enum.all?(keys, &is_binary/1)

  @impl true
  def step(state, _dt) do
    players = inputs(state)
    state = %{state | previous: state.held, steps: state.steps + 1, timer: state.timer + 1}

    state
    |> Flow.opponent_gone()
    |> Flow.step(players)
    |> Online.perform()
    |> muted_since(paused?(state))
    |> present()
  end

  defp paused?(state), do: state.screen == :paused and not Online.hosting?(state)

  defp muted_since(state, was?) do
    case paused?(state) do
      ^was? -> state
      now? -> %{state | events: [Audio.muted(now?) | state.events]}
    end
  end

  @impl true
  def input_delay(state), do: Nidhox.OnlineFlow.input_delay(state)

  @impl true
  def view(state, id) do
    player = state.players[id]
    side = with %{side: side} <- player, do: side

    state.frame
    |> Map.put(:side, side)
    |> Map.put(:ask, ask(state, id))
    |> Map.update!(:overlay, &(&1 ++ Screen.for_side(state, side, state.frame.window)))
  end

  @impl true
  def export(state),
    do: %{state | world: World.detached(state.world), frame: Map.delete(state.frame, :surfaces)}

  @impl true
  def restore(exported) do
    %Assets{data: data} = Assets.get()
    world = World.attached(exported.world, data, &Map.get(Assets.get().pictures, &1))
    %{exported | world: world, following: true}
  end

  @impl true
  def checksum(state) do
    world =
      Map.drop(state.world, [
        :data,
        :objects,
        :sprites,
        :owners,
        :descendants,
        :pictures,
        :surfaces
      ])

    state
    |> Map.drop([:world, :online, :following, :frame])
    |> Map.put(:world, world)
    |> :erlang.phash2()
  end

  @impl true
  def drain_events(state) do
    {outbox, world} = World.take_outbox(state.world)
    {outbox ++ Enum.reverse(state.events), %{state | world: world, events: []}}
  end

  defp ask(state, id) do
    case Map.get(state.asks, id) do
      {number, ask, until} when until >= state.steps -> {number, ask}
      _none -> nil
    end
  end

  defp free_side(state) do
    taken = state.players |> Map.values() |> MapSet.new(& &1.side)
    Enum.find(@sides, &(&1 not in taken))
  end

  defp take_from_seat(state, id) do
    seat =
      Enum.find(state.players, fn {seat_id, player} ->
        player.side != nil and player.owner != seat_id
      end)

    case seat do
      nil ->
        state

      {seat_id, %{side: side} = player} ->
        players =
          state.players
          |> Map.put(seat_id, %{player | side: nil})
          |> Map.put(id, %{side: side, owner: id})

        %{state | players: players, held: Map.put(state.held, side, MapSet.new())}
    end
  end

  defp seat_side(players, side) do
    case Enum.find(players, fn {seat_id, player} ->
           player.side == nil and player.owner != seat_id
         end) do
      nil -> players
      {seat_id, player} -> Map.put(players, seat_id, %{player | side: side})
    end
  end

  defp inputs(state) do
    Map.new(@sides, fn side ->
      held = state.held[side]
      previous = state.previous[side]

      {side,
       %{
         held: held,
         pressed: MapSet.difference(held, previous),
         released: MapSet.difference(previous, held)
       }}
    end)
  end

  defp present(state) do
    window = state.world.data.general.window
    {world, room} = Draw.run(state.world)
    {world, room_gui} = Draw.gui(world)
    state = %{state | world: world}
    {fencers, overlay} = Screen.layer(state, window)

    %{
      state
      | frame: %{
          items: fencers ++ room,
          gui: room_gui,
          overlay: overlay,
          background: Draw.background(world),
          view: view_rectangle(world),
          window: window,
          screen: state.screen,
          area: state.area,
          surfaces: Surfaces.rasters(world),
          spiral: Spiral.amounts(world)
        }
    }
  end

  defp view_rectangle(%World{views: [%{view: rectangle} | _]}), do: rectangle

  defp view_rectangle(%World{} = world) do
    {width, height} = Enum.at(world.data.rooms, world.room).size
    {0, 0, width, height}
  end
end
