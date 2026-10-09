defmodule Nidhox.Gml do
  @moduledoc """
  The pieces of GameMaker's language the ported game code leans on: an instance's own
  variables, the built-in maths as the game's runtime computes it, and random numbers
  from the world's generator (`Cauldron2D.GameMaker.Random`), each draw giving the
  world back with the generator moved on.

      {roll, world} = Gml.random(world, 10)
      world = Gml.put(world, self, %{hspd: Gml.approach(hspd, 0, 0.2)})

  `round/1` rounds halves to the even neighbour, as the runtime's `round` does.
  """

  alias Cauldron2D.GameMaker.{Instance, Random, World}

  @epsilon 1.0e-5

  @doc "Instance `id`'s variable `name`, `default` when it has none."
  @spec var(World.t(), non_neg_integer(), atom(), term()) :: term()
  def var(%World{} = world, id, name, default \\ 0) do
    case World.fetch(world, id) do
      %Instance{vars: vars} -> Map.get(vars, name, default)
      nil -> default
    end
  end

  @doc "The world with instance `id`'s variables in `values` set."
  @spec put(World.t(), non_neg_integer(), map()) :: World.t()
  def put(%World{} = world, id, values),
    do: World.update(world, id, &%{&1 | vars: Map.merge(&1.vars, values)})

  @doc "`value` moved towards `target` by `amount`, never past it (the game's `approach`)."
  @spec approach(number(), number(), number()) :: number()
  def approach(value, target, amount) when value < target, do: min(value + amount, target)
  def approach(value, target, amount), do: max(value - amount, target)

  @doc "Whether `a` equals `b` as the runtime compares numbers: within 0.00001."
  @spec eq?(number(), number()) :: boolean()
  def eq?(a, b), do: abs(a - b) <= @epsilon

  @doc "Whether `a` is less than `b` by more than the runtime's 0.00001."
  @spec lt?(number(), number()) :: boolean()
  def lt?(a, b), do: a - b < -@epsilon

  @doc "Whether `a` is greater than `b` by more than the runtime's 0.00001."
  @spec gt?(number(), number()) :: boolean()
  def gt?(a, b), do: a - b > @epsilon

  @doc "The across part of `length` pointing `direction` degrees (`lengthdir_x`)."
  @spec lengthdir_x(number(), number()) :: float()
  def lengthdir_x(length, direction), do: length * :math.cos(direction * :math.pi() / 180)

  @doc "The down part of `length` pointing `direction` degrees, up being 90 (`lengthdir_y`)."
  @spec lengthdir_y(number(), number()) :: float()
  def lengthdir_y(length, direction), do: -length * :math.sin(direction * :math.pi() / 180)

  @doc "The direction from `{x1, y1}` to `{x2, y2}` in degrees, 0–360, up being 90 (`point_direction`)."
  @spec point_direction({number(), number()}, {number(), number()}) :: float()
  def point_direction({x1, y1}, {x2, y2}) do
    degrees = :math.atan2(-(y2 - y1), x2 - x1) * 180 / :math.pi()
    if degrees < 0, do: degrees + 360, else: degrees
  end

  @doc "`-1`, `0` or `1` by the sign of `value` (`sign`)."
  @spec sign(number()) :: -1 | 0 | 1
  def sign(value) when value > 0, do: 1
  def sign(value) when value < 0, do: -1
  def sign(_value), do: 0

  @doc "`value` rounded to the nearest whole number, halves to the even one (`round`)."
  @spec round(number()) :: integer()
  def round(value) do
    floor = Float.floor(value * 1.0)
    rest = value - floor

    cond do
      rest > 0.5 -> trunc(floor) + 1
      rest < 0.5 -> trunc(floor)
      rem(trunc(floor), 2) == 0 -> trunc(floor)
      true -> trunc(floor) + 1
    end
  end

  @doc "The instance of object `name` nearest `{x, y}` (`instance_nearest`), `nil` for none."
  @spec nearest(World.t(), {number(), number()}, String.t()) :: non_neg_integer() | nil
  def nearest(%World{} = world, {x, y}, name) do
    with object when is_integer(object) <- World.object_index(world, name),
         [_ | _] = ids <- World.instances_of(world, object) do
      Enum.min_by(ids, fn id ->
        %Instance{x: ix, y: iy} = World.fetch(world, id)
        (ix - x) * (ix - x) + (iy - y) * (iy - y)
      end)
    else
      _none -> nil
    end
  end

  @doc "Every instance of object `name` or of an object descending from it, in creation order."
  @spec all(World.t(), String.t()) :: [non_neg_integer()]
  def all(%World{} = world, name) do
    case World.object_index(world, name) do
      nil -> []
      object -> World.instances_of(world, object)
    end
  end

  @doc "The first instance of object `name` (`name.<variable>` reads this one), `nil` for none."
  @spec first(World.t(), String.t()) :: non_neg_integer() | nil
  def first(%World{} = world, name), do: world |> all(name) |> List.first()

  @doc "Whether an instance of object `name` exists (`instance_exists`)."
  @spec exists?(World.t(), String.t()) :: boolean()
  def exists?(%World{} = world, name), do: first(world, name) != nil

  @doc "Whether `value` counts as true: a number above 0.5, or `true`."
  @spec truthy?(term()) :: boolean()
  def truthy?(value) when is_number(value), do: value > 0.5
  def truthy?(value), do: value == true

  @doc "`value` held between `low` and `high` (`clamp`)."
  @spec clamp(number(), number(), number()) :: number()
  def clamp(value, low, high), do: value |> max(low) |> min(high)

  @doc "A real from 0 up to `n` (`random`), and the world after the draw."
  @spec random(World.t(), number()) :: {float(), World.t()}
  def random(%World{random: random} = world, n) do
    {value, random} = Random.random(random, n)
    {value, %{world | random: random}}
  end

  @doc "A real from `low` up to `high` (`random_range`), and the world after the draw."
  @spec random_range(World.t(), number(), number()) :: {float(), World.t()}
  def random_range(%World{random: random} = world, low, high) do
    {value, random} = Random.random_range(random, low, high)
    {value, %{world | random: random}}
  end

  @doc "A whole number from 0 to `n` (`irandom`), and the world after the draw."
  @spec irandom(World.t(), number()) :: {integer(), World.t()}
  def irandom(%World{random: random} = world, n) do
    {value, random} = Random.irandom(random, n)
    {value, %{world | random: random}}
  end

  @doc "One of `values` (`choose`), and the world after the draw."
  @spec choose(World.t(), [term(), ...]) :: {term(), World.t()}
  def choose(%World{random: random} = world, values) do
    {value, random} = Random.choose(random, values)
    {value, %{world | random: random}}
  end

  @doc "Whether a `percent` in 100 chance comes up: `random(100) < percent` (the game's `prob`)."
  @spec prob(World.t(), number()) :: {boolean(), World.t()}
  def prob(%World{} = world, percent) do
    {roll, world} = random(world, 100)
    {roll < percent, world}
  end
end
