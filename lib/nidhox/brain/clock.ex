defmodule Nidhox.Brain.Clock do
  @moduledoc """
  The computer player's timing: a `Brain` acts on its `beat`, a count of frames it
  picks now and then, and on multiples of it.

    * `period/3`: `round(beat × times)`
    * `on?/2`: whether `count mod period` is 0, as the game compares it
    * `between?/2`: whether `count mod period` is past 0.5, as `if (count mod period)`
      reads it
    * `every?/4`: `on?/2` for one of the `Brain`'s own counters (`stateCounter`,
      `actionCounter`) against `period/3`
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.Gml

  @doc "`round(beat × times)` for `Brain` `self`."
  @spec period(World.t(), non_neg_integer(), number()) :: integer()
  def period(%World{} = world, self, times), do: Gml.round(Gml.var(world, self, :beat) * times)

  @doc "Whether `count mod period` is 0."
  @spec on?(number(), number()) :: boolean()
  def on?(count, period), do: Gml.eq?(:math.fmod(count, period), 0)

  @doc "Whether `count mod period` counts as true."
  @spec between?(number(), number()) :: boolean()
  def between?(count, period), do: Gml.truthy?(:math.fmod(count, period))

  @doc "Whether `Brain` `self`'s `counter` is on a multiple of `round(beat × times)`."
  @spec every?(World.t(), non_neg_integer(), atom(), number()) :: boolean()
  def every?(%World{} = world, self, counter, times),
    do: on?(Gml.var(world, self, counter), period(world, self, times))
end
