defmodule Nidhox.Fencer do
  @moduledoc """
  One fencer: where it stands, how it moves, the height it holds its sword at, and what
  it is doing.

  `side` is `1` or `2`. `position` is the point it stands on, in room pixels; `facing`
  is `1` for right and `-1` for left. `stance` is `:high`, `:middle` or `:low`. `armed`
  is whether it holds its sword. `action` is what it is doing and `timer` how many steps
  it has been doing it:

    * `:ready` — standing, walking or running; armed and within `@on_guard` pixels of
      a living opponent, it faces the opponent and walks (`@walk` pixels a step) rather
      than runs (`@run`)
    * `:thrust` — a thrust at its stance's height; the blade reaches out during the
      steps `thrust_active/0` names
    * `:throw` — throwing its sword
    * `:punch` — a punch, with no sword in hand; it lands during `punch_active/0`
    * `:duck` — down low while `:down` is held: from the low stance, or unarmed; it
      crawls at `@crawl`, and `:attack` sweeps the leg
    * `:sweep` — sweeping the leg; it lands during `sweep_active/0`
    * `:divekick` — `:attack` in the air: a dive forward and down at `@divekick`
    * `:floored` — knocked down by a sweep or a divekick, for `@floored_steps` steps
    * `:heart` — `:attack` beside a floored opponent: tearing out its heart, which kills
      it at step `heart_kill/0`
    * `:punch2` — a second punch, `:attack` again late in a punch; `:uppercut` — an
      unarmed punch with `:up` held, rising as it lands
    * `:slide` — `:down` while running: sliding low, slowing by `@slide_drag` each step
    * `:roll` — landing with `:down` held while moving: rolling on at its speed
    * `:disarmed` — thrown back with its sword knocked away (`disarm/2`)
    * `:catch` — catching a falling sword (`catch_sword/1`)
    * `:hang`, `:climb`, `:wallrun` — on ledges and walls (`Nidhox.Climb`)
    * `:dead` — down, until the match brings it back

  `step/4` moves a fencer one step from its side's input — `%{held, pressed, released}`
  of `Nidhox.Controls` actions — given where the opponent stands.
  """

  alias Nidhox.{Climb, Terrain}

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
          action:
            :ready
            | :thrust
            | :throw
            | :punch
            | :punch2
            | :uppercut
            | :duck
            | :slide
            | :roll
            | :sweep
            | :divekick
            | :floored
            | :heart
            | :disarmed
            | :catch
            | :hang
            | :climb
            | :wallrun
            | :dead,
          timer: non_neg_integer(),
          grounded: boolean(),
          stance_changed: integer(),
          age: non_neg_integer()
        }

  @gravity 0.22
  @fall_limit 5.0
  @jump -5.5
  @walk 1.1
  @run 2.4
  @grip 0.45
  @on_guard 64
  @thrust_steps 16
  @thrust_active 3..8
  @throw_steps 12
  @punch_steps 14
  @punch_active 3..5
  @stances [:low, :middle, :high]
  @crawl 0.6
  @divekick {3.5, 3.5}
  @bounce {1.5, -3.0}
  @floored_steps 75
  @sweep_steps 20
  @sweep_active 6..12
  @heart_steps 32
  @heart_kill 16
  @heart_reach 18
  @slide_steps 24
  @slide_drag 0.94
  @roll_steps 16
  @disarmed_steps 16
  @catch_steps 18
  @uppercut {1.0, -3.5}
  @follow_window 6
  @running 1.5

  @doc "A fresh fencer of side `side` at `position`, facing `facing`, sword in hand."
  @spec new(1 | 2, {number(), number()}, 1 | -1) :: t()
  def new(side, position, facing), do: %__MODULE__{side: side, position: position, facing: facing}

  @doc "The total steps of a thrust."
  @spec thrust_steps() :: non_neg_integer()
  def thrust_steps, do: @thrust_steps

  @doc "The total steps of a punch."
  @spec punch_steps() :: non_neg_integer()
  def punch_steps, do: @punch_steps

  @doc "The total steps of a throw."
  @spec throw_steps() :: non_neg_integer()
  def throw_steps, do: @throw_steps

  @doc "The steps of a thrust during which the blade reaches out."
  @spec thrust_active() :: Range.t()
  def thrust_active, do: @thrust_active

  @doc "The steps of a punch during which it lands."
  @spec punch_active() :: Range.t()
  def punch_active, do: @punch_active

  @doc "Whether the fencer is punching and the punch is landing now."
  @spec punching?(t()) :: boolean()
  def punching?(%__MODULE__{action: action, timer: timer})
      when action in [:punch, :punch2, :uppercut],
      do: timer in @punch_active

  def punching?(%__MODULE__{}), do: false

  @doc "The steps of a sweep during which it lands."
  @spec sweep_active() :: Range.t()
  def sweep_active, do: @sweep_active

  @doc "The total steps a sweep takes."
  @spec sweep_steps() :: pos_integer()
  def sweep_steps, do: @sweep_steps

  @doc "The total steps a floored fencer stays down."
  @spec floored_steps() :: pos_integer()
  def floored_steps, do: @floored_steps

  @doc "The total steps of tearing out a heart."
  @spec heart_steps() :: pos_integer()
  def heart_steps, do: @heart_steps

  @doc "The step of tearing out a heart at which the floored fencer dies."
  @spec heart_kill() :: pos_integer()
  def heart_kill, do: @heart_kill

  @doc "How long a roll, being disarmed, and catching a sword take, in steps: `%{roll: _, disarmed: _, catch: _}`."
  @spec move_steps() :: %{roll: pos_integer(), disarmed: pos_integer(), catch: pos_integer()}
  def move_steps, do: %{roll: @roll_steps, disarmed: @disarmed_steps, catch: @catch_steps}

  @doc "Whether the fencer is sweeping and the sweep is landing now."
  @spec sweeping?(t()) :: boolean()
  def sweeping?(%__MODULE__{action: :sweep, timer: timer}), do: timer in @sweep_active
  def sweeping?(%__MODULE__{}), do: false

  @doc "The fencer knocked down where it is."
  @spec knock_down(t()) :: t()
  def knock_down(%__MODULE__{velocity: {_vx, vy}} = fencer),
    do: %{fencer | action: :floored, timer: 0, velocity: {0.0, max(vy, 0.0)}}

  @doc "A divekicking fencer thrown back off what it kicked."
  @spec bounce(t()) :: t()
  def bounce(%__MODULE__{facing: facing} = fencer) do
    {back, up} = @bounce
    %{fencer | action: :ready, timer: 0, velocity: {-facing * back, up}, grounded: false}
  end

  @doc "Whether the fencer's blade is out: a thrust in its active steps."
  @spec thrusting?(t()) :: boolean()
  def thrusting?(%__MODULE__{action: :thrust, timer: timer}), do: timer in @thrust_active
  def thrusting?(%__MODULE__{}), do: false

  @doc "The fencer one step on, from `input`, with the opponent at `opponent` (or `nil`)."
  @spec step(t(), map(), t() | nil, Terrain.t()) :: t()
  def step(%__MODULE__{action: :dead} = fencer, _input, _opponent, terrain),
    do: fencer |> tick() |> physics(0.0, terrain)

  def step(%__MODULE__{} = fencer, input, opponent, terrain) do
    fencer
    |> tick()
    |> face(input, opponent)
    |> change_stance(input)
    |> act(input, opponent)
    |> Climb.step(input, terrain)
    |> jump(input)
    |> physics(target_speed(fencer, input, opponent), terrain)
    |> landed(fencer, input)
  end

  @doc "The fencer with its sword knocked from its hand, thrown back `push` pixels a step."
  @spec disarm(t(), number()) :: t()
  def disarm(%__MODULE__{velocity: {_vx, vy}} = fencer, push),
    do: %{fencer | armed: false, action: :disarmed, timer: 0, velocity: {push, vy}}

  @doc "The fencer catching a falling sword."
  @spec catch_sword(t()) :: t()
  def catch_sword(%__MODULE__{} = fencer), do: %{fencer | armed: true, action: :catch, timer: 0}

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

  defp face(%__MODULE__{action: action} = fencer, input, _opponent)
       when action in [:ready, :duck] do
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

  defp act(%__MODULE__{action: :thrust, timer: timer} = fencer, _input, _opponent)
       when timer >= @thrust_steps,
       do: ready(fencer)

  defp act(%__MODULE__{action: :throw, timer: timer} = fencer, _input, _opponent)
       when timer >= @throw_steps,
       do: ready(fencer)

  defp act(%__MODULE__{action: :punch, timer: timer} = fencer, _input, _opponent)
       when timer >= @punch_steps,
       do: ready(fencer)

  defp act(%__MODULE__{action: :punch, timer: timer} = fencer, input, _opponent)
       when timer >= @follow_window and timer < @punch_steps do
    if :attack in input.pressed, do: %{fencer | action: :punch2, timer: 0}, else: fencer
  end

  defp act(%__MODULE__{action: action, timer: timer} = fencer, _input, _opponent)
       when action in [:punch2, :uppercut] and timer >= @punch_steps,
       do: ready(fencer)

  defp act(%__MODULE__{action: :roll, timer: timer} = fencer, _input, _opponent)
       when timer >= @roll_steps,
       do: ready(fencer)

  defp act(%__MODULE__{action: :disarmed, timer: timer} = fencer, _input, _opponent)
       when timer >= @disarmed_steps,
       do: ready(fencer)

  defp act(%__MODULE__{action: :catch, timer: timer} = fencer, _input, _opponent)
       when timer >= @catch_steps,
       do: ready(fencer)

  defp act(
         %__MODULE__{action: :slide, timer: timer, velocity: {vx, _vy}} = fencer,
         input,
         _opponent
       )
       when timer >= @slide_steps or abs(vx) < 0.3 do
    if :down in input.held, do: %{fencer | action: :duck, timer: 0}, else: ready(fencer)
  end

  defp act(%__MODULE__{action: :floored, timer: timer} = fencer, _input, _opponent)
       when timer >= @floored_steps,
       do: ready(fencer)

  defp act(%__MODULE__{action: :heart, timer: timer} = fencer, _input, _opponent)
       when timer >= @heart_steps,
       do: ready(fencer)

  defp act(%__MODULE__{action: :sweep, timer: timer} = fencer, input, _opponent)
       when timer >= @sweep_steps,
       do: if(:down in input.held, do: %{fencer | action: :duck, timer: 0}, else: ready(fencer))

  defp act(%__MODULE__{action: :duck} = fencer, input, _opponent) do
    cond do
      :down not in input.held -> ready(fencer)
      :attack in input.pressed -> %{fencer | action: :sweep, timer: 0}
      true -> fencer
    end
  end

  defp act(%__MODULE__{action: :divekick, grounded: true} = fencer, _input, _opponent),
    do: ready(fencer)

  defp act(
         %__MODULE__{action: :ready, grounded: false, facing: facing} = fencer,
         input,
         _opponent
       ) do
    {across, down} = @divekick

    if :attack in input.pressed,
      do: %{fencer | action: :divekick, timer: 0, velocity: {facing * across, down}},
      else: fencer
  end

  defp act(%__MODULE__{action: :ready} = fencer, input, opponent) do
    cond do
      :attack in input.pressed -> attack(fencer, input, opponent)
      :down in input.pressed and slides?(fencer) -> %{fencer | action: :slide, timer: 0}
      :down in input.pressed and ducks?(fencer) -> %{fencer | action: :duck, timer: 0}
      true -> fencer
    end
  end

  defp act(fencer, _input, _opponent), do: fencer

  defp attack(fencer, input, opponent) do
    cond do
      heart?(fencer, opponent) -> %{fencer | action: :heart, timer: 0}
      not fencer.armed and :up in input.held and fencer.grounded -> uppercut(fencer)
      not fencer.armed -> %{fencer | action: :punch, timer: 0}
      fencer.stance == :high and :up in input.held -> %{fencer | action: :throw, timer: 0}
      true -> %{fencer | action: :thrust, timer: 0}
    end
  end

  defp ready(fencer), do: %{fencer | action: :ready, timer: 0}

  defp slides?(%__MODULE__{grounded: true, velocity: {vx, _vy}}), do: abs(vx) > @running
  defp slides?(_fencer), do: false

  defp uppercut(%__MODULE__{facing: facing} = fencer) do
    {across, up} = @uppercut
    %{fencer | action: :uppercut, timer: 0, velocity: {facing * across, up}, grounded: false}
  end

  defp ducks?(%__MODULE__{armed: false}), do: true
  defp ducks?(%__MODULE__{stance: :low, stance_changed: changed, age: age}), do: changed != age
  defp ducks?(_fencer), do: false

  defp heart?(%__MODULE__{position: {x, _}}, %__MODULE__{action: :floored, position: {ox, _}}),
    do: abs(ox - x) <= @heart_reach

  defp heart?(_fencer, _opponent), do: false

  defp jump(%__MODULE__{action: :ready, grounded: true, velocity: {vx, _vy}} = fencer, input) do
    if :jump in input.pressed,
      do: %{fencer | velocity: {vx, @jump}, grounded: false},
      else: fencer
  end

  defp jump(fencer, _input), do: fencer

  defp target_speed(%__MODULE__{action: action}, _input, _opponent)
       when action in [
              :thrust,
              :throw,
              :punch,
              :punch2,
              :sweep,
              :floored,
              :heart,
              :disarmed,
              :catch,
              :wallrun
            ],
       do: 0.0

  defp target_speed(%__MODULE__{action: :slide, velocity: {vx, _vy}}, _input, _opponent),
    do: vx * @slide_drag

  defp target_speed(%__MODULE__{action: action, velocity: {vx, _vy}}, _input, _opponent)
       when action in [:roll, :uppercut],
       do: vx

  defp target_speed(%__MODULE__{action: :divekick, velocity: {vx, _vy}}, _input, _opponent),
    do: vx

  defp target_speed(%__MODULE__{action: :duck}, input, _opponent) do
    cond do
      :right in input.held and :left not in input.held -> @crawl
      :left in input.held and :right not in input.held -> -@crawl
      true -> 0.0
    end
  end

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

  defp physics(%__MODULE__{action: action} = fencer, _target, _terrain)
       when action in [:hang, :climb],
       do: fencer

  defp physics(%__MODULE__{velocity: {vx, vy}} = fencer, target, terrain) do
    vx =
      if fencer.grounded, do: approach(vx, target, @grip), else: approach(vx, target, @grip / 3)

    vy =
      case fencer.action do
        :divekick -> elem(@divekick, 1)
        :wallrun -> Climb.rise()
        _falling -> min(vy + @gravity * terrain.gravity, @fall_limit)
      end

    {position, velocity, grounded} = Terrain.move(terrain, fencer.position, {vx, vy})
    position = carried(terrain, position, grounded)
    %{fencer | position: position, velocity: velocity, grounded: grounded}
  end

  defp carried(_terrain, position, false), do: position

  defp carried(terrain, position, true) do
    case Terrain.belt(terrain, position) do
      0 -> position
      speed -> terrain |> Terrain.move(position, {speed, 0.0}) |> elem(0)
    end
  end

  defp landed(
         %__MODULE__{grounded: true, action: :ready, velocity: {vx, _vy}} = fencer,
         %__MODULE__{grounded: false},
         input
       ) do
    if :down in input.held and abs(vx) > 0.5,
      do: %{fencer | action: :roll, timer: 0},
      else: fencer
  end

  defp landed(fencer, _before, _input), do: fencer

  defp approach(value, target, rate) when value < target, do: min(value + rate, target)
  defp approach(value, target, rate), do: max(value - rate, target)
end
