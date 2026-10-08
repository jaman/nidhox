defmodule Nidhox.Game do
  @moduledoc """
  NidhOX as a `Cauldron2D.Game`: the whole flow from the title to the end of a bout,
  stepped 60 times a second, the rooms running in `Cauldron2D.GameMaker`.

      Cauldron2D.World.start_link(game: Nidhox.Game, game_opts: [area: "Wilds"], hz: 60)

  Options: `:area` (`"Cemetery"`, `"Castle"`, `"Mines"`, `"Sky"`, `"Wilds"`; default
  `"Cemetery"`), the area shown behind the title and selected first for a bout.
  `Nidhox.Assets.load/1` must have run first.

  ## Screens

    * `:title` — the game's name over the area's centre room; any `:start`, `:attack` or
      `:jump` goes on to the main menu
    * `:main` — Arcade, Exhibition, Multiplayer, Credits
    * `:areas` — the area to fight in, for Exhibition and Multiplayer; the room behind
      the menu is the selected area's centre; `:jump` goes back
    * `:en_garde` — the fencers placed and still under "EN GARDE" for `@en_garde_steps`
      steps
    * `:bout` — the bout (`Nidhox.Match`) until it is finished
    * `:results` — the winner and the session's tally; going on returns to the main menu,
      or in Arcade after a win goes to the next area's bout
    * `:credits` — any choice returns to the main menu

  ## Modes

    * `:arcade` — side 2 is the computer (`Nidhox.AI`); the areas are fought in `@arcade`
      order, and a loss or the last win ends the run
    * `:exhibition` — side 2 is the computer, in the area chosen
    * `:multiplayer` — both sides are players, in the area chosen

  The first two players to join take sides `1` and `2`; anyone joining after them
  watches. Where the computer plays side 2, the input of a player on side 2 is not used.

  Each finished bout sends a `{:result, row}` event for every player who fought it, with
  the player's id and name, `won?`, the area and the mode.
  """

  @behaviour Cauldron2D.Game

  alias Cauldron2D.GameMaker.Data
  alias Cauldron2D.GameMaker.Draw
  alias Cauldron2D.GameMaker.Rooms
  alias Cauldron2D.GameMaker.Step
  alias Cauldron2D.GameMaker.World
  alias Nidhox.{AI, Assets, Look, Match}
  alias Nidhox.Screen.{Credits, Menu, Results, Text, Title}

  @sides [1, 2]
  @no_keys %{held: MapSet.new(), pressed: MapSet.new(), released: MapSet.new()}
  @areas ["Cemetery", "Castle", "Mines", "Sky", "Wilds"]
  @arcade @areas
  @en_garde_steps 90
  @gold {245, 205, 70}

  @impl true
  def init(opts) do
    %Assets{data: data} = Assets.get()
    area = Keyword.get(opts, :area) || "Cemetery"
    world = World.new(data, Nidhox.Code, room: centre(data, area))

    present(%{
      world: world,
      screen: :title,
      menu: nil,
      mode: nil,
      area: area,
      arcade: 0,
      match: nil,
      brain: nil,
      timer: 0,
      steps: 0,
      tally: %{1 => 0, 2 => 0},
      sides: %{},
      held: Map.new(@sides, &{&1, MapSet.new()}),
      previous: Map.new(@sides, &{&1, MapSet.new()}),
      events: [],
      frame: nil
    })
  end

  @impl true
  def join(state, id, _props) do
    taken = state.sides |> Map.values() |> MapSet.new()

    case Enum.find(@sides, &(&1 not in taken)) do
      nil -> {:ok, state}
      side -> {:ok, put_in(state.sides[id], side)}
    end
  end

  @impl true
  def leave(state, id) do
    case Map.pop(state.sides, id) do
      {nil, _sides} -> state
      {side, sides} -> %{state | sides: sides, held: Map.put(state.held, side, MapSet.new())}
    end
  end

  @impl true
  def handle_input(state, id, %{held: held}) do
    case Map.fetch(state.sides, id) do
      {:ok, side} -> put_in(state.held[side], held)
      :error -> state
    end
  end

  @impl true
  def step(state, _dt) do
    players = inputs(state)
    state = %{state | previous: state.held, steps: state.steps + 1, timer: state.timer + 1}

    state
    |> screen(players)
    |> present()
  end

  @impl true
  def view(state, id), do: Map.put(state.frame, :side, Map.get(state.sides, id))

  @impl true
  def drain_events(state) do
    {outbox, world} = World.take_outbox(state.world)
    bout = if state.match, do: state.match.events, else: []
    {outbox ++ bout ++ Enum.reverse(state.events), %{state | world: world, events: []}}
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

  defp screen(%{screen: :title} = state, players) do
    state = scenery(state, players)
    if Title.continue?(players), do: main_menu(state), else: state
  end

  defp screen(%{screen: :main} = state, players) do
    state = scenery(state, players)

    case Menu.input(state.menu, players) do
      {:choose, :arcade} -> en_garde(%{state | mode: :arcade, arcade: 0}, Enum.at(@arcade, 0))
      {:choose, :credits} -> %{state | screen: :credits, timer: 0}
      {:choose, mode} -> area_menu(%{state | mode: mode})
      :back -> %{state | screen: :title, timer: 0}
      {:stay, menu} -> %{state | menu: menu}
    end
  end

  defp screen(%{screen: :areas} = state, players) do
    state = scenery(state, players)

    case Menu.input(state.menu, players) do
      {:choose, area} -> en_garde(state, area)
      :back -> main_menu(state)
      {:stay, menu} -> preview(%{state | menu: menu}, Menu.selected(menu))
    end
  end

  defp screen(%{screen: :credits} = state, players) do
    state = scenery(state, players)
    if Title.continue?(players), do: main_menu(state), else: state
  end

  defp screen(%{screen: :en_garde} = state, players) do
    state = scenery(state, players)
    if state.timer >= @en_garde_steps, do: %{state | screen: :bout, timer: 0}, else: state
  end

  defp screen(%{screen: :bout} = state, players) do
    world = Step.run(state.world, Map.put(@no_keys, :players, players))
    {players, state} = computer(state, players)
    {match, world} = Match.step(state.match, world, players)
    state = %{state | world: world, match: match}
    if Match.finished?(match), do: results(state), else: state
  end

  defp screen(%{screen: :results} = state, players) do
    state = scenery(state, players)

    cond do
      not Title.continue?(players) ->
        state

      next_arcade?(state) ->
        en_garde(%{state | arcade: state.arcade + 1}, Enum.at(@arcade, state.arcade + 1))

      true ->
        main_menu(state)
    end
  end

  defp scenery(state, players),
    do: %{state | world: Step.run(state.world, Map.put(@no_keys, :players, players))}

  defp main_menu(state) do
    menu =
      Menu.new("NIDHOX", [
        {"ARCADE", :arcade},
        {"EXHIBITION", :exhibition},
        {"MULTIPLAYER", :multiplayer},
        {"CREDITS", :credits}
      ])

    %{state | screen: :main, menu: menu, match: nil, brain: nil, timer: 0}
  end

  defp area_menu(state) do
    selected = Enum.find_index(@areas, &(&1 == state.area)) || 0
    menu = Menu.new("CHOOSE AN AREA", Enum.map(@areas, &{String.upcase(&1), &1}), selected)
    %{state | screen: :areas, menu: menu, timer: 0}
  end

  defp preview(%{area: area} = state, area), do: state

  defp preview(state, area),
    do: %{state | area: area, world: Rooms.enter(state.world, centre(state.world.data, area))}

  defp en_garde(state, area) do
    {match, world} = Match.new(state.world, area)
    brain = if state.mode in [:arcade, :exhibition], do: AI.new(2, 1, AI.pick_personality())
    %{state | screen: :en_garde, area: area, world: world, match: match, brain: brain, timer: 0}
  end

  defp computer(%{brain: nil} = state, players), do: {players, state}

  defp computer(%{brain: brain, match: match} = state, players) do
    {brain, input} = AI.step(brain, match.fencers[2], match.fencers[1], players[2], match)
    {Map.put(players, 2, input), %{state | brain: brain}}
  end

  defp results(%{match: match} = state) do
    winner = match.winner
    tally = Map.update!(state.tally, winner, &(&1 + 1))

    %{
      state
      | screen: :results,
        tally: tally,
        timer: 0,
        events: result_events(state, winner) ++ state.events
    }
  end

  defp result_events(state, winner) do
    for {id, side} <- state.sides, side == 1 or state.brain == nil do
      {:result,
       %{id: id, name: to_string(id), won?: side == winner, area: state.area, mode: state.mode}}
    end
  end

  defp next_arcade?(%{mode: :arcade, match: %Match{winner: 1}, arcade: index}),
    do: index + 1 < length(@arcade)

  defp next_arcade?(_state), do: false

  defp present(state) do
    window = state.world.data.general.window
    {world, room} = Draw.run(state.world)
    {world, room_gui} = Draw.gui(world)
    state = %{state | world: world}
    {fencers, overlay} = layer(state, window)

    %{
      state
      | frame: %{
          items: room ++ fencers,
          gui: room_gui ++ overlay,
          background: Draw.background(world),
          view: view_rectangle(world),
          window: window,
          screen: state.screen
        }
    }
  end

  defp layer(%{screen: :title} = state, window), do: {[], Title.items(state.steps, window)}

  defp layer(%{screen: screen} = state, window) when screen in [:main, :areas],
    do: {[], Menu.items(state.menu, window)}

  defp layer(%{screen: :credits}, window), do: {[], Credits.items(window)}

  defp layer(%{screen: :en_garde} = state, window),
    do: {Look.items(state.match), [Text.centred("EN GARDE", @gold, 7, 200, window)]}

  defp layer(%{screen: :bout} = state, window),
    do: {Look.items(state.match), Look.banner(state.match, window)}

  defp layer(%{screen: :results} = state, window) do
    overlay = Results.items(state.match.winner, state.tally, results_note(state), window)
    {Look.items(state.match), overlay}
  end

  defp results_note(%{mode: :arcade, match: %Match{winner: 1}, arcade: index}) do
    case Enum.at(@arcade, index + 1) do
      nil -> "THE ARCADE IS WON"
      area -> "NEXT: #{String.upcase(area)}"
    end
  end

  defp results_note(%{mode: :arcade, arcade: index}),
    do: "THE RUN ENDS AT #{String.upcase(Enum.at(@arcade, index))}"

  defp results_note(_state), do: "BACK TO THE MENU"

  defp centre(%Data{} = data, area), do: Data.index(data, :rooms, "r#{area}Center")

  defp view_rectangle(%World{views: [%{view: rectangle} | _]}), do: rectangle

  defp view_rectangle(%World{} = world) do
    {width, height} = Enum.at(world.data.rooms, world.room).size
    {0, 0, width, height}
  end
end
