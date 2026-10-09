defmodule Nidhox.Ending do
  @moduledoc """
  The end of a bout: the Nidhogg comes for the winner and eats them.

  It starts where the room places its `Nidhogg` (off the screen) — or, in a room that
  places none, `@above` pixels above the winner — and its head
  steers for the winner — turning `@turn` of the way to a heading straight at them
  each step, at `@speed` pixels a step. Its body follows the head's own path: a segment
  every `@spacing` steps of it, `@segments` of them, shrinking towards the tail through
  the copy's `sDragonSegment` frames. Within `@bite` pixels of the winner it bites: the
  winner is gone from the ground and held in its jaw (`sManInJaw`, in the winner's
  colour), and it flies on, climbing by `@climb` a step and speeding up by `@hurry`,
  until `@exit` steps after the bite, when `done?/1`.

  Its sounds are events in `events` for the step they happen: `{:nidhogg, :roar}` as it
  comes, `{:nidhogg, :bite}` at the bite and `{:nidhogg, :slurp}` `@slurp_after` steps
  later, each with where it happened.
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.Assets

  @enforce_keys [:head, :velocity, :trail, :winner]
  defstruct [:head, :velocity, :trail, :winner, bitten: nil, age: 0, events: []]

  @type t :: %__MODULE__{
          head: {number(), number()},
          velocity: {number(), number()},
          trail: [{number(), number()}],
          winner: 1 | 2,
          bitten: non_neg_integer() | nil,
          age: non_neg_integer(),
          events: list()
        }

  @speed 4.5
  @turn 0.12
  @bite 14
  @segments 26
  @spacing 3
  @climb 0.12
  @hurry 0.05
  @exit 120
  @slurp_after 25
  @mouth 14
  @depth -150
  @above 260

  @doc "The Nidhogg coming for side `winner`, from where `world`'s room places it."
  @spec new(World.t(), 1 | 2, {number(), number()}) :: t()
  def new(%World{} = world, winner, {wx, wy}) do
    head = start(world, {wx, wy})

    %__MODULE__{
      head: head,
      velocity: {0.0, 0.0},
      trail: [head],
      winner: winner,
      events: [{{:nidhogg, :roar}, head}]
    }
  end

  @doc "The Nidhogg one step on, the winner standing at `target` until it is eaten."
  @spec step(t(), {number(), number()}) :: t()
  def step(%__MODULE__{} = ending, {tx, ty}) do
    ending = %{ending | age: ending.age + 1, events: []}
    ending = if ending.bitten, do: fly_off(ending), else: hunt(ending, {tx, ty - @mouth})
    {x, y} = ending.head
    {vx, vy} = ending.velocity
    head = {x + vx, y + vy}
    %{ending | head: head, trail: Enum.take([head | ending.trail], @segments * @spacing)}
  end

  @doc "Whether the winner has been eaten."
  @spec eaten?(t() | nil) :: boolean()
  def eaten?(%__MODULE__{bitten: bitten}), do: bitten != nil
  def eaten?(nil), do: false

  @doc "Whether the Nidhogg has flown off with the winner."
  @spec done?(t()) :: boolean()
  def done?(%__MODULE__{bitten: nil}), do: false
  def done?(%__MODULE__{bitten: bitten, age: age}), do: age - bitten >= @exit

  @doc "The Nidhogg as room draw items, the winner in its jaw in `colour` once eaten."
  @spec items(t(), {byte(), byte(), byte()}) :: [map()]
  def items(%__MODULE__{} = ending, colour) do
    {segment, %{frames: frames}} = Assets.sprite!("sDragonSegment")
    {head, _sprite} = Assets.sprite!("sNidhoggHeadFull")
    facing = if elem(ending.velocity, 0) < 0, do: -1, else: 1

    body =
      ending.trail
      |> Enum.take_every(@spacing)
      |> Enum.drop(1)
      |> Enum.with_index()
      |> Enum.map(fn {position, index} ->
        frame = min(div(index * length(frames), @segments), length(frames) - 1)

        %{
          picture: {:sprite, segment, frame},
          position: position,
          origin: origin("sDragonSegment"),
          scale: {facing, 1},
          depth: @depth + 1 + index
        }
      end)

    jaw =
      if ending.bitten do
        {man, _sprite} = Assets.sprite!("sManInJaw")

        [
          %{
            picture: {:sprite, man, 0},
            position: ending.head,
            origin: origin("sManInJaw"),
            scale: {facing, 1},
            blend: colour,
            depth: @depth - 1
          }
        ]
      else
        []
      end

    [
      %{
        picture: {:sprite, head, 0},
        position: ending.head,
        origin: origin("sNidhoggHeadFull"),
        scale: {facing, 1},
        depth: @depth
      }
      | jaw
    ] ++
      body
  end

  defp hunt(%__MODULE__{head: {x, y}, velocity: {vx, vy}} = ending, {tx, ty}) do
    distance = :math.sqrt((tx - x) * (tx - x) + (ty - y) * (ty - y))

    if distance <= @bite do
      %{ending | bitten: ending.age, events: [{{:nidhogg, :bite}, ending.head}]}
    else
      {wx, wy} = {(tx - x) / distance * @speed, (ty - y) / distance * @speed}
      %{ending | velocity: {vx + (wx - vx) * @turn, vy + (wy - vy) * @turn}}
    end
  end

  defp fly_off(%__MODULE__{velocity: {vx, vy}} = ending) do
    events =
      if ending.age - ending.bitten == @slurp_after,
        do: [{{:nidhogg, :slurp}, ending.head}],
        else: []

    %{ending | velocity: {vx * (1 + @hurry), vy - @climb}, events: events}
  end

  defp start(world, {wx, wy}) do
    fallback = {wx, wy - @above}

    case World.object_index(world, "Nidhogg") do
      nil ->
        fallback

      object ->
        case World.instances_of(world, object) do
          [id | _] -> world |> World.fetch(id) |> then(&{&1.x, &1.y})
          [] -> fallback
        end
    end
  end

  defp origin(name), do: name |> Assets.sprite!() |> elem(1) |> Map.fetch!(:origin)
end
