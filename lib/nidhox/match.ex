defmodule Nidhox.Match do
  @moduledoc """
  A bout across one area's rooms: who has the right of way, where the fencers are, the
  swords in play, the camera, and who has won.

  An area's rooms run from its left end, through its left rooms, its centre and its
  right rooms, to its right end (`rooms/2`). A bout starts in the centre with both
  fencers at their entry points and nobody with the right of way. Side `1` runs right,
  towards the right end; side `2` runs left.

    * A kill gives the killer the right of way, and a fencer falling out of the room
      gives it to the other fencer if that one is up. The fencer killed comes back after
      `@respawn_steps` steps on the ground ahead of the killer, sword in hand.
    * The camera follows the fencer with the right of way, keeping more of the room ahead
      of it in view; with nobody holding it, it centres between the two.
    * Only the fencer with the right of way may leave the camera's view, and only
      towards its goal: past the room's edge it takes the bout into the next room, where
      it enters at its own entry point and the other fencer comes back ahead of it.
    * Two fencers who are both up never stand closer than `@personal_space` pixels at
      the same height: they are pushed apart about their midpoint.
    * In the end room, the fencer with the right of way reaching the goal zone wins.
      The bout starts again in the centre `@win_steps` steps later.
  """

  alias Cauldron2D.GameMaker.Collide
  alias Cauldron2D.GameMaker.Data
  alias Cauldron2D.GameMaker.Rooms
  alias Cauldron2D.GameMaker.World
  alias Cauldron2D.Shape
  alias Nidhox.{Duel, Fencer, Terrain}

  @enforce_keys [:area, :rooms, :index, :fencers, :terrain]
  defstruct [
    :area,
    :rooms,
    :index,
    :fencers,
    :terrain,
    advancing: nil,
    swords: [],
    winner: nil,
    winner_timer: 0,
    events: []
  ]

  @type t :: %__MODULE__{}

  @respawn_steps 90
  @win_steps 240
  @view_width 320
  @lead 0.35
  @edge_margin 4
  @personal_space 10
  @order ~w(LeftEnd LeftC LeftB LeftA Center RightA RightB RightC RightEnd)

  @doc """
  The rooms of area `area` (`"Cemetery"`, `"Castle"`, `"Mines"`, `"Sky"`, `"Wilds"`) in
  order from left end to right end, as indices into `data.rooms`.
  """
  @spec rooms(Data.t(), String.t()) :: [non_neg_integer()]
  def rooms(%Data{} = data, area) do
    for part <- @order,
        index = Data.index(data, :rooms, "r#{area}#{part}"),
        index != nil,
        do: index
  end

  @doc "The area a room named `name` belongs to, `nil` for a room that is no area's."
  @spec area(String.t()) :: String.t() | nil
  def area(name) do
    case Regex.run(
           ~r/^r([A-Z][a-z]+)(LeftEnd|LeftC|LeftB|LeftA|Center|RightA|RightB|RightC|RightEnd)$/,
           name
         ) do
      [_, area, _part] -> area
      nil -> nil
    end
  end

  @doc "A bout in area `area`, starting in its centre room; gives the world in that room too."
  @spec new(World.t(), String.t()) :: {t(), World.t()}
  def new(%World{} = world, area) do
    rooms = rooms(world.data, area)
    index = Enum.find_index(rooms, &(Enum.at(world.data.rooms, &1).name == "r#{area}Center"))
    centre = Enum.at(rooms, index)
    world = if world.room == centre, do: world, else: Rooms.enter(world, centre)
    terrain = Terrain.new(world)

    fencers = %{
      1 => Fencer.new(1, entry(world, terrain, "YellowPlayerMatchEntryPoint", 0.3), 1),
      2 => Fencer.new(2, entry(world, terrain, "OrangePlayerMatchEntryPoint", 0.7), -1)
    }

    match = %__MODULE__{
      area: area,
      rooms: rooms,
      index: index,
      fencers: fencers,
      terrain: terrain
    }

    {match, camera(match, world)}
  end

  @doc "The bout one step on, with each side's input; gives the world as the bout leaves it."
  @spec step(t(), World.t(), %{1 => map(), 2 => map()}) :: {t(), World.t()}
  def step(%__MODULE__{winner: winner} = match, world, _inputs) when winner != nil do
    if match.winner_timer >= @win_steps,
      do: new(world, match.area),
      else: {%{match | winner_timer: match.winner_timer + 1, events: []}, world}
  end

  def step(%__MODULE__{} = match, world, inputs) do
    fencers =
      Map.new([1, 2], fn side ->
        {side,
         Fencer.step(match.fencers[side], inputs[side], match.fencers[other(side)], match.terrain)}
      end)

    {fencers, swords, events} = Duel.step(fencers, match.swords, match.terrain)

    %{match | fencers: separate(fencers), swords: swords, events: events}
    |> right_of_way(events)
    |> fall_out()
    |> respawn()
    |> keep_in_view(world)
    |> advance(world)
  end

  @doc "Side `side`'s goal direction: `1` to the right, `-1` to the left."
  @spec goal(1 | 2) :: 1 | -1
  def goal(1), do: 1
  def goal(2), do: -1

  defp separate(%{1 => one, 2 => two} = fencers) do
    {x1, y1} = one.position
    {x2, y2} = two.position
    gap = abs(x2 - x1)

    if one.action != :dead and two.action != :dead and gap < @personal_space and abs(y2 - y1) < 20 do
      middle = (x1 + x2) / 2
      side = if x1 <= x2, do: -1, else: 1
      half = @personal_space / 2

      %{
        fencers
        | 1 => %{one | position: {middle + side * half, y1}},
          2 => %{two | position: {middle - side * half, y2}}
      }
    else
      fencers
    end
  end

  defp right_of_way(match, events) do
    Enum.reduce(events, match, fn
      {:killed, killer, _victim}, match -> %{match | advancing: killer}
      _event, match -> match
    end)
  end

  defp fall_out(%__MODULE__{terrain: %Terrain{size: {_width, height}}} = match) do
    Enum.reduce([1, 2], match, fn side, match ->
      fencer = match.fencers[side]
      {_x, y} = fencer.position

      if fencer.action != :dead and y > height + 30,
        do: fallen(match, side, fencer),
        else: match
    end)
  end

  defp fallen(match, side, fencer) do
    rival = match.fencers[other(side)]
    advancing = if rival.action == :dead, do: match.advancing, else: other(side)
    %{match | fencers: Map.put(match.fencers, side, Fencer.kill(fencer)), advancing: advancing}
  end

  defp respawn(match) do
    Enum.reduce([1, 2], match, fn side, match ->
      fencer = match.fencers[side]

      if fencer.action == :dead and fencer.timer >= @respawn_steps,
        do: %{match | fencers: Map.put(match.fencers, side, back(match, side))},
        else: match
    end)
  end

  defp back(match, side) do
    rival = match.fencers[other(side)]
    {rx, ry} = rival.position
    {width, _height} = match.terrain.size
    ahead = goal(other(side))
    preferred = clamp(rx + ahead * 130, 12, width - 12)
    step = if rx >= preferred, do: 8, else: -8

    x =
      preferred
      |> Stream.iterate(&(&1 + step))
      |> Stream.take_while(&(step * (rx - &1) >= 0))
      |> Enum.find(rx, &(Terrain.ground(match.terrain, &1) != nil))

    Fencer.new(side, {x, Terrain.ground(match.terrain, x) || ry}, -ahead)
  end

  defp keep_in_view(match, world) do
    {view_x, _y, view_width, _h} = view(world)
    {room_width, _} = match.terrain.size

    fencers =
      Map.new(match.fencers, fn {side, fencer} ->
        {x, y} = fencer.position
        free = leaving?(match, side, x, view_x, view_width, room_width)
        low = if free and goal(side) == -1, do: x, else: view_x + @edge_margin
        high = if free and goal(side) == 1, do: x, else: view_x + view_width - @edge_margin
        {side, %{fencer | position: {clamp(x, low, high), y}}}
      end)

    %{match | fencers: fencers}
  end

  defp leaving?(%__MODULE__{advancing: side}, side, _x, view_x, view_width, room_width) do
    case goal(side) do
      1 -> view_x + view_width >= room_width
      -1 -> view_x <= 0
    end
  end

  defp leaving?(_match, _side, _x, _view_x, _view_width, _room_width), do: false

  defp advance(%__MODULE__{advancing: nil} = match, world), do: {match, camera(match, world)}

  defp advance(%__MODULE__{advancing: side} = match, world) do
    fencer = match.fencers[side]

    cond do
      fencer.action != :dead and in_goal?(match, world, fencer) ->
        {%{match | winner: side, winner_timer: 0}, camera(match, world)}

      past_edge?(match, fencer) ->
        next_room(match, world, side)

      true ->
        {match, camera(match, world)}
    end
  end

  defp past_edge?(match, %Fencer{side: side, position: {x, _y}}) do
    {room_width, _} = match.terrain.size
    (goal(side) == 1 and x > room_width) or (goal(side) == -1 and x < 0)
  end

  defp next_room(match, world, side) do
    next = match.index + goal(side)

    if next >= 0 and next < length(match.rooms),
      do: enter(match, world, next, side),
      else: {match, camera(match, world)}
  end

  defp in_goal?(match, world, %Fencer{position: {x, _y}}) do
    end_room? = match.index in [0, length(match.rooms) - 1]

    end_room? and
      Enum.any?(zones(world), fn {left, _top, right, _bottom} -> x >= left and x <= right end)
  end

  defp zones(world) do
    case World.object_index(world, "NidhoggZone") do
      nil ->
        []

      object ->
        for id <- World.instances_of(world, object),
            instance = World.fetch(world, id),
            shape = Collide.shape(world, instance, {instance.x, instance.y}),
            shape != nil,
            do: Shape.bounds(shape)
    end
  end

  defp enter(match, world, next, side) do
    world = Rooms.enter(world, Enum.at(match.rooms, next))
    terrain = Terrain.new(world)
    point = if side == 1, do: "YellowPlayerRoomEntryPoint", else: "OrangePlayerRoomEntryPoint"
    fraction = if goal(side) == 1, do: 0.02, else: 0.98
    runner = %{match.fencers[side] | position: entry(world, terrain, point, fraction)}
    waiting = %{Fencer.kill(match.fencers[other(side)]) | timer: @respawn_steps - 30}

    match = %{
      match
      | index: next,
        terrain: terrain,
        swords: [],
        fencers: %{side => runner, other(side) => waiting}
    }

    {match, camera(match, world)}
  end

  defp entry(world, terrain, name, fraction) do
    with object when is_integer(object) <- World.object_index(world, name),
         [id | _] <- World.instances_of(world, object) do
      instance = World.fetch(world, id)
      {instance.x, Terrain.ground(terrain, instance.x) || instance.y}
    else
      _ ->
        {width, _} = terrain.size
        x = width * fraction
        {x, Terrain.ground(terrain, x) || 0}
    end
  end

  defp camera(match, world) do
    {_x, view_y, width, height} = view(world)
    {room_width, _} = match.terrain.size

    focus =
      case match.advancing do
        nil ->
          positions =
            for {_side, %Fencer{action: action, position: {x, _}}} <- match.fencers,
                action != :dead,
                do: x

          if positions == [], do: room_width / 2, else: Enum.sum(positions) / length(positions)

        side ->
          {x, _} = match.fencers[side].position
          x + goal(side) * width * @lead
      end

    left = clamp(round(focus - width / 2), 0, max(room_width - width, 0))
    World.put_view(world, 0, {left, view_y, width, height})
  end

  defp view(%World{views: [%{view: rectangle} | _]}), do: rectangle
  defp view(%World{}), do: {0, 0, @view_width, 200}

  defp clamp(value, low, high), do: value |> max(low) |> min(high)

  defp other(1), do: 2
  defp other(2), do: 1
end
