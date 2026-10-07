defmodule Nidhox.Fencer do
  @moduledoc """
  One fencer: where it stands, how it moves, the height it holds its sword at, and what
  it is doing.

  `side` is `1` or `2`. `position` is the point it stands on, in room pixels; `facing`
  is `1` for right and `-1` for left. `stance` is `:high`, `:middle` or `:low`. `armed`
  is whether it holds its sword. `action` is what it is doing and `timer` how many steps
  it has been doing it:

    * `:ready` — standing, walking or running
    * `:thrust` — a thrust at its stance's height; the blade reaches out during the
      steps `thrust_active/0` names
    * `:throw` — throwing its sword
    * `:punch` — a punch, with no sword in hand; it lands during `punch_active/0`
    * `:dead` — down, until the match brings it back

  `step/4` moves a fencer one step from its side's input — `%{held, pressed, released}`
  of `Nidhox.Controls` actions — given where the opponent stands.
  """

  alias Nidhox.Terrain

  @enforce_keys [:side, :position, :facing]
  defstruct [
    :side,
    :position,
    :facing,
    velocity: {0.0, 0.0},
    stance: :middle,
    armed: true,
    action: :ready,
    timer: 0,
    grounded: true,
    stance_changed: -100,
    age: 0
  ]

  @type stance :: :high | :middle | :low
  @type t :: %__MODULE__{
          side: 1 | 2,
          position: {number(), number()},
          facing: 1 | -1,
          velocity: {number(), number()},
          stance: stance(),
          armed: boolean(),
          action: :ready | :thrust | :throw | :punch | :dead,
          timer: non_neg_integer(),
          grounded: boolean(),
          stance_changed: integer(),
          age: non_neg_integer()
        }

  @gravity 0.22
  @fall_limit 5.0
  @jump -4.2
  @walk 1.1
  @run 2.4
  @grip 0.45
  @on_guard 110
  @thrust_steps 16
  @thrust_active 3..8
  @throw_steps 12
  @punch_steps 14
  @punch_active 3..5
  @reach 21
  @heights %{high: 21, middle: 15, low: 9}
  @stances [:low, :middle, :high]

  @doc "A fresh fencer of side `side` at `position`, facing `facing`, sword in hand."
  @spec new(1 | 2, {number(), number()}, 1 | -1) :: t()
  def new(side, position, facing), do: %__MODULE__{side: side, position: position, facing: facing}

  @doc "The steps of a thrust during which the blade reaches out."
  @spec thrust_active() :: Range.t()
  def thrust_active, do: @thrust_active

  @doc "The steps of a punch during which it lands."
  @spec punch_active() :: Range.t()
  def punch_active, do: @punch_active

  @doc "Whether the fencer is punching and the punch is landing now."
  @spec punching?(t()) :: boolean()
  def punching?(%__MODULE__{action: :punch, timer: timer}), do: timer in @punch_active
  def punching?(%__MODULE__{}), do: false

  @doc "How far in front of a fencer its blade's point reaches during a thrust."
  @spec reach() :: number()
  def reach, do: @reach

  @doc "The height above its feet a fencer holds its blade at in `stance`."
  @spec height(stance()) :: number()
  def height(stance), do: Map.fetch!(@heights, stance)

  @doc "Whether the fencer's blade is out, a thrust at its reach."
  @spec thrusting?(t()) :: boolean()
  def thrusting?(%__MODULE__{action: :thrust, timer: timer}), do: timer in @thrust_active
  def thrusting?(%__MODULE__{}), do: false

  @doc "The point of a fencer's blade: in front of it at its stance's height."
  @spec point(t(), number()) :: {number(), number()}
  def point(%__MODULE__{position: {x, y}, facing: facing, stance: stance}, reach),
    do: {x + facing * reach, y - height(stance)}

  @doc """
  Whether the blade of `attacker`, from its hand to its point at `reach`, crosses the
  fencer's body.
  """
  @spec cut?(t(), t(), number()) :: boolean()
  def cut?(%__MODULE__{action: :dead}, _attacker, _reach), do: false

  def cut?(%__MODULE__{position: {x, y}}, %__MODULE__{} = attacker, reach) do
    {ax, ay} = attacker.position
    blade_y = ay - height(attacker.stance)
    {near, far} = Enum.min_max([ax + attacker.facing * 4, ax + attacker.facing * reach])
    x >= near - 5 and x <= far + 5 and blade_y >= y - 26 and blade_y <= y
  end

  @doc "Whether `point` is inside the fencer's body."
  @spec struck?(t(), {number(), number()}) :: boolean()
  def struck?(%__MODULE__{action: :dead}, _point), do: false

  def struck?(%__MODULE__{position: {x, y}}, {px, py}),
    do: abs(px - x) <= 5 and py >= y - 26 and py <= y

  @doc "The fencer one step on, from `input`, with the opponent at `opponent` (or `nil`)."
  @spec step(t(), map(), t() | nil, Terrain.t()) :: t()
  def step(%__MODULE__{action: :dead} = fencer, _input, _opponent, terrain),
    do: fencer |> tick() |> physics(0.0, terrain)

  def step(%__MODULE__{} = fencer, input, opponent, terrain) do
    fencer
    |> tick()
    |> face(input, opponent)
    |> change_stance(input)
    |> act(input)
    |> jump(input)
    |> physics(target_speed(fencer, input, opponent), terrain)
  end

  @doc "The fencer down: dead, its sword gone from its hand."
  @spec kill(t()) :: t()
  def kill(%__MODULE__{} = fencer),
    do: %{fencer | action: :dead, timer: 0, armed: false, velocity: {0.0, 0.0}}

  @doc "The fencer pushed `push` pixels a step along x, its thrust stopped."
  @spec knock(t(), number()) :: t()
  def knock(%__MODULE__{velocity: {_vx, vy}} = fencer, push),
    do: %{fencer | velocity: {push, vy}, action: :ready, timer: 0}

  defp tick(%__MODULE__{} = fencer), do: %{fencer | timer: fencer.timer + 1, age: fencer.age + 1}

  defp face(%__MODULE__{action: :ready} = fencer, input, %__MODULE__{action: action} = opponent)
       when action != :dead do
    {x, _y} = fencer.position
    {ox, _oy} = opponent.position

    if fencer.armed and abs(ox - x) < @on_guard,
      do: %{fencer | facing: if(ox >= x, do: 1, else: -1)},
      else: face(fencer, input, nil)
  end

  defp face(%__MODULE__{action: :ready} = fencer, input, _opponent) do
    cond do
      :right in input.held and :left not in input.held -> %{fencer | facing: 1}
      :left in input.held and :right not in input.held -> %{fencer | facing: -1}
      true -> fencer
    end
  end

  defp face(fencer, _input, _opponent), do: fencer

  defp change_stance(%__MODULE__{action: :ready, armed: true} = fencer, input) do
    index = Enum.find_index(@stances, &(&1 == fencer.stance))

    cond do
      :up in input.pressed and :attack not in input.held -> stance(fencer, min(index + 1, 2))
      :down in input.pressed -> stance(fencer, max(index - 1, 0))
      true -> fencer
    end
  end

  defp change_stance(fencer, _input), do: fencer

  defp stance(fencer, index) do
    new = Enum.at(@stances, index)
    if new == fencer.stance, do: fencer, else: %{fencer | stance: new, stance_changed: fencer.age}
  end

  defp act(%__MODULE__{action: :thrust, timer: timer} = fencer, _input)
       when timer >= @thrust_steps,
       do: %{fencer | action: :ready, timer: 0}

  defp act(%__MODULE__{action: :throw, timer: timer} = fencer, _input) when timer >= @throw_steps,
    do: %{fencer | action: :ready, timer: 0}

  defp act(%__MODULE__{action: :punch, timer: timer} = fencer, _input) when timer >= @punch_steps,
    do: %{fencer | action: :ready, timer: 0}

  defp act(%__MODULE__{action: :ready, armed: false} = fencer, input) do
    if :attack in input.pressed, do: %{fencer | action: :punch, timer: 0}, else: fencer
  end

  defp act(%__MODULE__{action: :ready, armed: true} = fencer, input) do
    cond do
      :attack not in input.pressed -> fencer
      fencer.stance == :high and :up in input.held -> %{fencer | action: :throw, timer: 0}
      true -> %{fencer | action: :thrust, timer: 0}
    end
  end

  defp act(fencer, _input), do: fencer

  defp jump(%__MODULE__{action: :ready, grounded: true, velocity: {vx, _vy}} = fencer, input) do
    if :jump in input.pressed,
      do: %{fencer | velocity: {vx, @jump}, grounded: false},
      else: fencer
  end

  defp jump(fencer, _input), do: fencer

  defp target_speed(%__MODULE__{action: action}, _input, _opponent)
       when action in [:thrust, :throw, :punch],
       do: 0.0

  defp target_speed(%__MODULE__{} = fencer, input, opponent) do
    direction =
      cond do
        :right in input.held and :left not in input.held -> 1
        :left in input.held and :right not in input.held -> -1
        true -> 0
      end

    direction * speed(fencer, opponent)
  end

  defp speed(%__MODULE__{armed: true, position: {x, _}}, %__MODULE__{
         action: action,
         position: {ox, _}
       })
       when action != :dead and abs(ox - x) < @on_guard,
       do: @walk

  defp speed(_fencer, _opponent), do: @run

  defp physics(%__MODULE__{velocity: {vx, vy}} = fencer, target, terrain) do
    vx =
      if fencer.grounded, do: approach(vx, target, @grip), else: approach(vx, target, @grip / 3)

    vy = min(vy + @gravity, @fall_limit)
    {position, velocity, grounded} = Terrain.move(terrain, fencer.position, {vx, vy})
    %{fencer | position: position, velocity: velocity, grounded: grounded}
  end

  defp approach(value, target, rate) when value < target, do: min(value + rate, target)
  defp approach(value, target, rate), do: max(value - rate, target)
end
