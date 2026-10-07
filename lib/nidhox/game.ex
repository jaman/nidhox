defmodule Nidhox.Game do
  @moduledoc """
  NidhOX as a `Cauldron2D.Game`: a bout (`Nidhox.Match`) fought across one area's rooms,
  the rooms themselves running in `Cauldron2D.GameMaker`, stepped 60 times a second.

      Cauldron2D.World.start_link(game: Nidhox.Game, game_opts: [area: "Wilds"], hz: 60)

  Options: `:area` (`"Cemetery"`, `"Castle"`, `"Mines"`, `"Sky"`, `"Wilds"`; default
  `"Cemetery"`), or `:room`, any of an area's rooms, to fight in that room's area.
  `Nidhox.Assets.load/1` must have run first.

  The first two players to join take sides `1` and `2`; anyone joining after them
  watches. Each step the rooms are stepped, then the bout with each side's held,
  pressed and released `Nidhox.Controls` actions, and every viewer is sent that step's
  frame.
  """

  @behaviour Cauldron2D.Game

  alias Cauldron2D.GameMaker.Data
  alias Cauldron2D.GameMaker.Draw
  alias Cauldron2D.GameMaker.Step
  alias Cauldron2D.GameMaker.World
  alias Nidhox.{Assets, Look, Match}

  @sides [1, 2]
  @no_keys %{held: MapSet.new(), pressed: MapSet.new(), released: MapSet.new()}

  @impl true
  def init(opts) do
    %Assets{data: data} = Assets.get()
    area = area(opts)
    centre = Data.index(data, :rooms, "r#{area}Center")
    {match, world} = Match.new(World.new(data, Nidhox.Code, room: centre), area)

    draw(%{
      world: world,
      match: match,
      sides: %{},
      held: Map.new(@sides, &{&1, MapSet.new()}),
      previous: Map.new(@sides, &{&1, MapSet.new()}),
      frame: nil
    })
  end

  @impl true
  def join(state, id, _props) do
    taken = state.sides |> Map.values() |> MapSet.new()
    side = Enum.find(@sides, &(&1 not in taken))
    {:ok, if(side, do: put_in(state.sides[id], side), else: state)}
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
    players =
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

    world = Step.run(state.world, Map.put(@no_keys, :players, players))
    {match, world} = Match.step(state.match, world, players)
    draw(%{state | world: world, match: match, previous: state.held})
  end

  @impl true
  def view(state, id), do: Map.put(state.frame, :side, Map.get(state.sides, id))

  @impl true
  def drain_events(state) do
    {events, world} = World.take_outbox(state.world)
    {events ++ state.match.events, %{state | world: world}}
  end

  defp area(opts) do
    case Keyword.get(opts, :room) do
      nil -> Keyword.get(opts, :area) || "Cemetery"
      room -> Match.area(room) || raise ArgumentError, "#{inspect(room)} is not an arena room"
    end
  end

  defp draw(state) do
    {world, items} = Draw.run(state.world)
    {world, gui} = Draw.gui(world)
    window = world.data.general.window

    %{
      state
      | world: world,
        frame: %{
          items: items ++ Look.items(state.match),
          gui: gui ++ Look.banner(state.match, window),
          background: Draw.background(world),
          view: view_rectangle(world),
          window: window
        }
    }
  end

  defp view_rectangle(%World{views: [%{view: rectangle} | _]}), do: rectangle

  defp view_rectangle(%World{} = world) do
    {width, height} = Enum.at(world.data.rooms, world.room).size
    {0, 0, width, height}
  end
end
