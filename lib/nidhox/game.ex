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

  A view is the frame — `items` (room pixels), `gui` (the room's own, window pixels),
  `overlay` (the screen's, window pixels, over `gui`), `surfaces` (the rasters
  `{:surface, id}` pictures name), `progress` (`Nidhox.Bout.progress/1`
  of the bout, `0.0` with none), `background`,
  `view`, `window`, `screen`, `area` — with the viewer's `side` and `ask`, what the game
  asks of the viewer's client (`Nidhox.Flow.ask/3`), or `nil`.

  A bout's sounds are sent as events from its objects. Each finished bout sends a
  `{:result, row}` event for every player who fought it, with the player's id and name,
  `won?`, the area and the mode.
  """

  @behaviour Cauldron2D.Game

  alias Cauldron2D.GameMaker.Data
  alias Cauldron2D.GameMaker.Draw
  alias Cauldron2D.GameMaker.World
  alias Nidhox.{Assets, Bout, Flow, Online, Screen}
  alias Nidhox.Objects.{Ambience, System}

  @sides [1, 2]
  @bouts [:bout, :paused, :replay]

  @impl true
  def init(opts) do
    %Assets{data: data} = Assets.get()

    %{
      world:
        World.new(data, Nidhox.Code,
          room: Data.index(data, :rooms, "rLogos"),
          pictures: &Map.get(Assets.get().pictures, &1),
          seed: Keyword.get_lazy(opts, :seed, fn -> :os.system_time(:millisecond) end)
        )
        |> System.create(),
      screen: nil,
      menu: nil,
      levels: nil,
      mode: nil,
      area: Keyword.get(opts, :area) || "Cemetery",
      arcade: 0,
      winner: nil,
      stats: nil,
      recording: nil,
      tutorial: nil,
      tournament: nil,
      online: Online.new(Keyword.get(opts, :port)),
      entry: nil,
      address: nil,
      effects: [],
      kept: nil,
      credits: "",
      timer: 0,
      steps: 0,
      players: %{},
      asks: %{},
      ask_number: 0,
      held: Map.new(@sides, &{&1, MapSet.new()}),
      previous: Map.new(@sides, &{&1, MapSet.new()}),
      events: [],
      frame: nil
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

    {:ok, Map.update!(state, :players, &Map.put_new(&1, id, %{side: nil, owner: owner}))}
  end

  @impl true
  def leave(state, id) do
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
  def handle_input(state, id, %{held: held}) do
    case Map.fetch(state.players, id) do
      {:ok, %{side: side}} when side != nil -> put_in(state.held[side], held)
      _watching -> state
    end
  end

  @impl true
  def step(state, _dt) do
    players = inputs(state)
    state = %{state | previous: state.held, steps: state.steps + 1, timer: state.timer + 1}

    state
    |> Online.pending()
    |> Flow.step(players)
    |> Online.perform()
    |> then(&%{&1 | world: Ambience.settle(&1.world)})
    |> present()
  end

  @impl true
  def view(state, id) do
    side = with %{side: side} <- state.players[id], do: side

    state.frame
    |> Map.put(:side, side)
    |> Map.put(:ask, ask(state, id))
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
          surfaces: world.surfaces,
          progress: if(state.screen in @bouts, do: Bout.progress(world), else: 0.0)
        }
    }
  end

  defp view_rectangle(%World{views: [%{view: rectangle} | _]}), do: rectangle

  defp view_rectangle(%World{} = world) do
    {width, height} = Enum.at(world.data.rooms, world.room).size
    {0, 0, width, height}
  end
end
