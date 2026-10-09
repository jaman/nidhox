defmodule Nidhox.Climb do
  @moduledoc """
  Ledges and walls (`Nidhox.Terrain`'s `ledges`), for `Nidhox.Fencer`:

    * a fencer in the air facing a ledge's wall, with its feet within `@reach` pixels
      of the ledge's hanging point (`@out` pixels out from the corner, `@drop` below its
      top) catches it and hangs there (`:hang`), still
    * hanging, `:jump` or `:up` climbs (`:climb`, `@climb_steps` steps, ending stood on
      the ledge `@inward` pixels in from the corner); `:down` lets go
    * a fencer on the ground, its way blocked by a wall, that presses `:jump` runs up the
      wall (`:wallrun`), rising `@rise` pixels a step for `@run_steps` steps — catching
      a ledge it reaches — then falls
  """

  alias Nidhox.{Fencer, Terrain}

  @reach 8
  @out 4
  @drop 24
  @inward 6
  @climb_steps 14
  @rise -3.0
  @run_steps 14

  @doc "How long a climb takes, in steps."
  @spec climb_steps() :: pos_integer()
  def climb_steps, do: @climb_steps

  @doc "How long a run up a wall lasts, in steps."
  @spec run_steps() :: pos_integer()
  def run_steps, do: @run_steps

  @doc "How fast a fencer rises running up a wall, in pixels a step (negative is up)."
  @spec rise() :: float()
  def rise, do: @rise

  @doc "`fencer` after this step's ledges and walls, given `input` and `terrain`."
  @spec step(Fencer.t(), map(), Terrain.t()) :: Fencer.t()
  def step(%Fencer{action: :hang} = fencer, input, _terrain) do
    cond do
      :jump in input.pressed or :up in input.pressed -> %{fencer | action: :climb, timer: 0}
      :down in input.pressed -> %{fencer | action: :ready, timer: 0, velocity: {0.0, 1.0}}
      true -> fencer
    end
  end

  def step(
        %Fencer{action: :climb, timer: timer, position: {x, y}, facing: facing} = fencer,
        _input,
        _terrain
      )
      when timer >= @climb_steps,
      do: %{
        fencer
        | action: :ready,
          timer: 0,
          position: {x + facing * (@out + @inward), y - @drop},
          grounded: true,
          velocity: {0.0, 0.0}
      }

  def step(%Fencer{action: :wallrun, timer: timer} = fencer, _input, terrain) do
    case ledge(fencer, terrain) do
      nil when timer >= @run_steps -> %{fencer | action: :ready, timer: 0, velocity: {0.0, 0.0}}
      nil -> fencer
      hold -> hang(fencer, hold)
    end
  end

  def step(%Fencer{action: :ready, grounded: false} = fencer, _input, terrain) do
    case ledge(fencer, terrain) do
      nil -> fencer
      hold -> hang(fencer, hold)
    end
  end

  def step(
        %Fencer{action: :ready, grounded: true, position: {x, y}, facing: facing} = fencer,
        input,
        terrain
      ) do
    if :jump in input.pressed and Terrain.blocked?(terrain, {x + facing * 2, y - 1}),
      do: %{fencer | action: :wallrun, timer: 0, velocity: {0.0, @rise}, grounded: false},
      else: fencer
  end

  def step(fencer, _input, _terrain), do: fencer

  defp ledge(%Fencer{position: {x, y}, facing: facing}, %Terrain{ledges: ledges}) do
    Enum.find_value(ledges, fn {lx, ly, open} ->
      {hx, hy} = {lx + open * @out, ly + @drop}
      if facing == -open and abs(x - hx) <= @reach and abs(y - hy) <= @reach, do: {hx, hy}
    end)
  end

  defp hang(fencer, point),
    do: %{
      fencer
      | action: :hang,
        timer: 0,
        position: point,
        velocity: {0.0, 0.0},
        grounded: false
    }
end
