defmodule Nidhox.AI do
  @moduledoc """
  An AI brain for exhibition mode: a high-level state machine that
  decides what to do and a low-level action machine that executes it.

  The high-level state machine has these states:
  - `:idle` — observing, waiting for the opponent to move
  - `:approach` — moving toward the opponent
  - `:press` — holding pressure, looking for an opening
  - `:defend` — guarding against the opponent's attack
  - `:attack` — executing a lunge or counterattack
  - `:counter` — parrying then riposting
  - `:recover` — recovering from a completed action
  - `:release` — releasing guard, returning to neutral

  The low-level action machine has these actions:
  - `:stand` — idle stance
  - `:walk` — walking animation
  - `:run` — running (fast movement)
  - `:lunge` — attack lunge
  - `:jump` — airborne
  - `:defend` — defensive stance

  Personalities affect aggression, caution, and footwork preferences:
  - `:aggressive` — attacks frequently, takes risks
  - `:balanced` — mix of attack and defense
  - `:defensive` — plays cautiously, counters
  """

  alias Nidhox.{Fencer, Match}

  # High-level AI states.
  # @states [:idle, :approach, :press, :defend, :attack, :counter, :recover, :release]

  # Low-level fencing actions.

  # Personality weights.
  @personality %{
    aggressive: %{aggression: 0.8, caution: 0.2, footwork: 0.6},
    balanced: %{aggression: 0.5, caution: 0.5, footwork: 0.5},
    defensive: %{aggression: 0.2, caution: 0.8, footwork: 0.4}
  }

  @enforce_keys [:player_index, :opponent_side]
  defstruct [
    :player_index,
    :opponent_side,
    :personality,
    current_state: :idle,
    next_state: nil,
    needs_state_transition: false,
    current_action: :stand,
    # AI memory/context
    last_known_opponent_position: {0.0, 0.0},
    # Personality-specific weights
    aggression_level: 0.5,
    caution_level: 0.5,
    footwork_preference: 0.5,
    # Timing
    state_timer: 0,
    action_timer: 0
  ]

  @type personality :: :aggressive | :balanced | :defensive

  @type t :: %__MODULE__{
          player_index: 1 | 2,
          opponent_side: 1 | 2,
          personality: personality(),
          current_state: atom(),
          next_state: atom() | nil,
          needs_state_transition: boolean(),
          current_action: atom(),
          last_known_opponent_position: {number(), number()},
          aggression_level: number(),
          caution_level: number(),
          footwork_preference: number(),
          state_timer: non_neg_integer(),
          action_timer: non_neg_integer()
        }

  @doc "Create a new AI brain for `player_index` watching `opponent_side`."
  @spec new(1 | 2, 1 | 2, personality()) :: t()
  def new(player_index, opponent_side, personality \\ :balanced) do
    weights = Map.fetch!(@personality, personality)

    %__MODULE__{
      player_index: player_index,
      opponent_side: opponent_side,
      personality: personality,
      aggression_level: weights.aggression,
      caution_level: weights.caution,
      footwork_preference: weights.footwork
    }
  end

  @doc "One step of the AI, given the fencer, opponent, input, terrain, and match."
  @spec step(t(), Fencer.t(), Fencer.t(), map(), Match.t()) ::
          {t(), %{held: MapSet.t(), pressed: MapSet.t(), released: MapSet.t()}}
  def step(brain, fencer, opponent, _input, match) do
    brain = decide_next_state(brain, fencer, opponent, match)

    brain =
      if brain.needs_state_transition,
        do: transition_state(brain),
        else: brain

    {action, input} = execute_action(brain.current_action, brain, fencer, opponent, match)

    {%{brain | current_action: action, state_timer: brain.state_timer + 1}, input}
  end

  # ---- High-level decision making ----

  defp decide_next_state(brain, fencer, opponent, _match) do
    case brain.current_state do
      :idle ->
        case classify_opponent(opponent, fencer) do
          :attacking -> set_next(brain, :defend)
          :close -> set_next(brain, :press)
          :far -> set_next(brain, :approach)
        end

      :approach ->
        case distance_to(fencer, opponent) do
          d when d < 80 -> set_next(brain, :press)
          _ -> brain
        end

      :press ->
        case can_attack?(fencer, opponent) do
          true ->
            set_next(brain, :attack)

          false ->
            case is_opponent_closing?(fencer, opponent) do
              true -> set_next(brain, :defend)
              false -> brain
            end
        end

      :defend ->
        case is_opponent_attacking?(opponent) do
          true ->
            case can_counter?(fencer, opponent) do
              true -> set_next(brain, :counter)
              false -> brain
            end

          false ->
            set_next(brain, :release)
        end

      :attack ->
        case action_complete?(fencer, :thrust) do
          true -> set_next(brain, :recover)
          false -> brain
        end

      :counter ->
        case action_complete?(fencer, :throw) do
          true -> set_next(brain, :recover)
          false -> brain
        end

      :recover ->
        case recovery_complete?(brain) do
          true ->
            case should_chain?(brain) do
              true -> set_next(brain, :press)
              false -> set_next(brain, :idle)
            end

          false ->
            brain
        end

      :release ->
        case back_to_neutral?(fencer) do
          true -> set_next(brain, :idle)
          false -> brain
        end

      _ ->
        brain
    end
  end

  # Classify the opponent's current behavior.
  defp classify_opponent(opponent, fencer) do
    cond do
      is_opponent_attacking?(opponent) -> :attacking
      distance_to(fencer, opponent) < 80 -> :close
      true -> :far
    end
  end

  defp distance_to(fencer, opponent) do
    {x1, y1} = fencer.position
    {x2, y2} = opponent.position
    :math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2)
  end

  defp is_opponent_attacking?(%Fencer{action: action}) when action in [:thrust, :throw, :punch],
    do: true

  defp is_opponent_attacking?(_), do: false

  defp is_opponent_closing?(fencer, opponent) do
    {x1, _} = fencer.position
    {x2, _} = opponent.position

    case fencer.facing do
      1 -> x2 > x1 and opponent.facing == -1
      -1 -> x2 < x1 and opponent.facing == 1
    end
  end

  defp can_attack?(fencer, opponent) do
    {x1, _} = fencer.position
    {x2, _} = opponent.position
    dist = abs(x2 - x1)

    dist <= Fencer.reach() + 5 and
      fencer.action == :ready and
      fencer.armed and
      opposite_facing?(fencer, opponent)
  end

  defp can_counter?(fencer, opponent) do
    # Counter-attack opportunity: opponent is attacking but we're in a good
    # position to parry and riposte.
    is_opponent_attacking?(opponent) and
      fencer.action == :ready and
      fencer.armed and
      distance_to(fencer, opponent) <= Fencer.reach() + 12
  end

  defp opposite_facing?(fencer, opponent),
    do: fencer.facing == -opponent.facing

  defp action_complete?(fencer, :thrust),
    do: fencer.action == :thrust and fencer.timer >= Fencer.thrust_steps()

  defp action_complete?(fencer, :throw),
    do: fencer.action == :throw and fencer.timer >= Fencer.throw_steps()

  defp recovery_complete?(brain), do: brain.state_timer >= 30

  defp should_chain?(brain),
    do: brain.aggression_level > 0.5 and :rand.uniform() < brain.aggression_level

  defp back_to_neutral?(%Fencer{action: :ready}), do: true
  defp back_to_neutral?(_), do: false

  # ---- State transitions ----

  defp set_next(brain, new_state) do
    %{brain | next_state: new_state, needs_state_transition: true}
  end

  defp transition_state(brain) do
    %{
      brain
      | current_state: brain.next_state,
        next_state: nil,
        needs_state_transition: false,
        state_timer: 0
    }
  end

  # ---- Low-level action execution ----

  defp execute_action(:stand, _brain, _fencer, _opponent, _match), do: {:stand, input([], [])}

  defp execute_action(:walk, brain, fencer, opponent, match),
    do: {:walk, input([way(brain, fencer, opponent, match)], [])}

  defp execute_action(:run, brain, fencer, opponent, match),
    do: {:run, input([way(brain, fencer, opponent, match)], [])}

  defp execute_action(:lunge, brain, fencer, opponent, match),
    do: {:lunge, input([way(brain, fencer, opponent, match)], [:attack])}

  defp execute_action(:jump, brain, fencer, opponent, match),
    do: {:jump, input([way(brain, fencer, opponent, match)], [:jump])}

  defp execute_action(:defend, %{current_state: :defend}, fencer, opponent, _match),
    do: {:defend, input([], guard(fencer, opponent))}

  defp execute_action(:defend, _brain, _fencer, _opponent, _match), do: {:defend, input([], [])}

  defp input(held, pressed) do
    pressed = MapSet.new(pressed)
    %{held: MapSet.union(MapSet.new(held), pressed), pressed: pressed, released: MapSet.new()}
  end

  defp way(brain, %Fencer{position: {x, _}}, %Fencer{position: {ox, _}} = opponent, match) do
    direction =
      if opponent.action == :dead and match.advancing == brain.player_index,
        do: Match.goal(brain.player_index),
        else: if(ox >= x, do: 1, else: -1)

    if direction == 1, do: :right, else: :left
  end

  defp guard(%Fencer{stance: stance}, %Fencer{stance: stance}), do: []

  defp guard(%Fencer{stance: mine}, %Fencer{stance: theirs}) do
    if height_rank(theirs) > height_rank(mine), do: [:up], else: [:down]
  end

  defp height_rank(:low), do: 0
  defp height_rank(:middle), do: 1
  defp height_rank(:high), do: 2

  @doc "Get the personality name as a string."
  @spec personality_string(personality()) :: String.t()
  def personality_string(:aggressive), do: "Aggressive"
  def personality_string(:balanced), do: "Balanced"
  def personality_string(:defensive), do: "Defensive"

  @doc "Pick a random personality."
  @spec pick_personality() :: personality()
  def pick_personality, do: Enum.random(Map.keys(@personality))
end
