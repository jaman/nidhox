defmodule Nidhox.Game do
  @moduledoc """
  NidhOX as a `Cauldron2D.Game`, stepped 60 times a second, the rooms running in
  `Cauldron2D.GameMaker`, the screens following `Nidhox.Flow` from the logos on.

      Cauldron2D.World.start_link(game: Nidhox.Game, game_opts: [area: "Wilds"], hz: 60)

  Options: `:area` (`"Cemetery"`, `"Castle"`, `"Mines"`, `"Sky"`, `"Wilds"`; default
  `"Cemetery"`), the area the level select starts on; `:port`, the port ONLINE VERSUS's
  host listens on for the joining machine (default any free port); `:seed`, the game's
  random number seed (default the clock). `Nidhox.Assets.load/1` must have run first.

  The first two players to join take sides `1` and `2`. A player joining as a client's
  local seat (join prop `:seat_of`) belongs to that client: what the game asks of a
  seat's player goes to the client it is a seat of. A player on a client of their own
  who joins with both sides taken takes a side from a seat of another client, the seat
  then watching; anyone else joining after the first two watches. A side left free goes
  to a watching seat. Where the computer plays side 2, the input of a player on side 2
  is not used. ONLINE VERSUS's hosting and joining are `Nidhox.Online`'s.

  The game's prefs that change what it does — `System.flashing` and
  `System.persistent_blood` — follow the options (`:flashing`, `:persistent_blood`,
  each `true` or `false`) sent with the input of the first player to join, and when
  that player leaves, of one of those still there.

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

  A world on another machine follows this one for ONLINE VERSUS (`Cauldron2D.World`'s
  `:follow`): `export/1` sends it the state without the data file's parts, the picture
  lookup, the surfaces' pixels or the frame's, `restore/1` fills them in from that
  machine's own copy and marks the state `following`, so `Nidhox.Online` carries out
  none of its effects there, and `checksum/1` covers what the steps decide: the world's
  instances and the rest of the game's state, not its surfaces, `online`, `following` or
  `frame`.
  """

  @behaviour Cauldron2D.Game

  alias Cauldron2D.Audio
  alias Cauldron2D.GameMaker.Data
  alias Cauldron2D.GameMaker.Draw
  alias Cauldron2D.GameMaker.Surfaces
  alias Cauldron2D.GameMaker.World
  alias Nidhox.{Assets, Flow, Online, Screen}
  alias Nidhox.Objects.System
  alias Nidhox.Screen.Pause

  @sides [1, 2]

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
    {:ok, %{state | prefs_from: state.prefs_from || id}}
  end

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

  defp preferred(%{prefs_from: id} = state, id, options) do
    prefs =
      for {option, variable} <- [flashing: :flashing, persistent_blood: :persistent_blood],
          is_boolean(Map.get(options, option)),
          into: %{},
          do: {variable, if(Map.fetch!(options, option), do: 1, else: 0)}

    %{state | world: System.put(state.world, prefs)}
  end

  defp preferred(state, _id, _options), do: state

  @impl true
  def step(state, _dt) do
    players = inputs(state)
    state = %{state | previous: state.held, steps: state.steps + 1, timer: state.timer + 1}

    state
    |> Online.pending()
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
  def view(state, id) do
    player = state.players[id]
    side = with %{side: side} <- player, do: side

    state.frame
    |> Map.put(:side, side)
    |> Map.put(:ask, ask(state, id))
    |> remote_pause(state, player)
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

  defp remote_pause(frame, %{screen: :paused} = state, %{} = player) do
    if Online.remote_player?(state, player),
      do: %{frame | overlay: Pause.items(state.menu, frame.window, :remote)},
      else: frame
  end

  defp remote_pause(frame, _state, _player), do: frame

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
          surfaces: Surfaces.rasters(world)
        }
    }
  end

  defp view_rectangle(%World{views: [%{view: rectangle} | _]}), do: rectangle

  defp view_rectangle(%World{} = world) do
    {width, height} = Enum.at(world.data.rooms, world.room).size
    {0, 0, width, height}
  end
end
