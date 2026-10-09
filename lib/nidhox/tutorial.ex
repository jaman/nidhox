defmodule Nidhox.Tutorial do
  @moduledoc """
  HOW TO PLAY: the copy's tutorial lines, taught one at a time in `rTutorial` with the
  orange fencer standing in as a dummy.

  Each lesson shows its line — the executable's own words, each `|` where the game
  shows a button given as the action's name in brackets — and is passed when side 1
  does what it says, judged from the bout one step to the next (`step/3`). The next
  line shows `@pause` steps later. Some lessons set the bout up as they open
  (`opening/2`): the pick-up and punch lessons knock side 1's sword away, and the
  blocking lesson arms the dummy, who throws its sword (`opponent/1`). The last
  lesson is passed by running past the room's `TutorialFinishLine`; `done?/1` then.
  """

  alias Nidhox.{Duel, Fencer, Match}

  @enforce_keys [:finish]
  defstruct [:finish, lesson: 0, count: 0, passed: nil, opened: false, thrown: false]

  @type t :: %__MODULE__{
          finish: number(),
          lesson: non_neg_integer(),
          count: non_neg_integer(),
          passed: non_neg_integer() | nil,
          opened: boolean(),
          thrown: boolean()
        }

  @pause 60

  @lessons [
    {"TAP [LEFT] OR [RIGHT] TO FENCE", :fence},
    {"HOLD [RIGHT] TO RUN", :run},
    {"PRESS [UP] AND [DOWN] TO CHANGE YOUR SWORD HEIGHT", :heights},
    {"[DOWN] TO DUCK", :duck},
    {"[JUMP] TO JUMP", :jump},
    {"[ATTACK] WITH A SWORD TO LUNGE", :lunge},
    {"IN CLOSE QUARTERS MOVING UP OR DOWN INTO A SWORD WILL DISARM", :disarm},
    {"[DOWN] TO PICK UP SWORDS", :pick_up},
    {"PRESS UP AND [ATTACK] TO THROW YOUR SWORD", :throw},
    {"BLOCK THROWN SWORDS WITH YOUR SWORD, DUCK UNDER THEM, OR JUMP OVER THEM", :block},
    {"[ATTACK] IN THE AIR TO DIVEKICK", :divekick},
    {"[ATTACK] NEAR A KNOCKED DOWN OPPONENT TO REMOVE HEART", :heart},
    {"[ATTACK] WHILE DUCKING TO SWEEP THE LEG", :sweep},
    {"[ATTACK] WHILE UNARMED TO PUNCH", :punch},
    {"THE ARROW SHOWS THE RIGHT OF WAY. TO GET IT, KILL YOUR OPPONENT. IF YOU HAVE IT, RUN!",
     :right_of_way},
    {"THAT'S IT! follow that arrow!", :finish}
  ]

  @doc "The tutorial at its first lesson, finished by running past `finish` along x."
  @spec new(number()) :: t()
  def new(finish), do: %__MODULE__{finish: finish}

  @doc "The line of the lesson being taught, or `nil` between lessons."
  @spec line(t()) :: String.t() | nil
  def line(%__MODULE__{passed: nil, lesson: lesson}), do: @lessons |> Enum.at(lesson) |> elem(0)
  def line(%__MODULE__{}), do: nil

  @doc "Whether every lesson has been passed."
  @spec done?(t()) :: boolean()
  def done?(%__MODULE__{lesson: lesson}), do: lesson >= length(@lessons)

  @doc "The bout set up for the lesson about to be taught, once, as it opens."
  @spec opening(t(), Match.t()) :: {t(), Match.t()}
  def opening(%__MODULE__{opened: true} = tutorial, match), do: {tutorial, match}

  def opening(%__MODULE__{passed: passed} = tutorial, match) when passed != nil,
    do: {tutorial, match}

  def opening(%__MODULE__{} = tutorial, %Match{} = match) do
    {%{tutorial | opened: true}, open(kind(tutorial), match)}
  end

  @doc "The dummy's input this step: still, but for throwing its sword in the blocking lesson."
  @spec opponent(t()) :: map()
  def opponent(%__MODULE__{passed: nil, thrown: false} = tutorial) do
    if kind(tutorial) == :block,
      do: input([:up], [:attack]),
      else: input([], [])
  end

  def opponent(_tutorial), do: input([], [])

  @doc "The tutorial after a step of the bout from `before` to `later`, side 1 the learner."
  @spec step(t(), Match.t(), Match.t()) :: t()
  def step(%__MODULE__{passed: passed} = tutorial, _before, _later) when passed != nil do
    if passed >= @pause,
      do: %{
        tutorial
        | lesson: tutorial.lesson + 1,
          passed: nil,
          count: 0,
          opened: false,
          thrown: false
      },
      else: %{tutorial | passed: passed + 1}
  end

  def step(%__MODULE__{} = tutorial, %Match{} = before, %Match{} = later) do
    tutorial =
      if later.fencers[2].action == :throw, do: %{tutorial | thrown: true}, else: tutorial

    {tutorial, passed?} = check(kind(tutorial), tutorial, before, later)
    if passed?, do: %{tutorial | passed: 0}, else: tutorial
  end

  defp kind(%__MODULE__{lesson: lesson}),
    do: @lessons |> Enum.at(lesson, {nil, :finish}) |> elem(1)

  defp open(kind, %Match{fencers: fencers, swords: swords} = match)
       when kind in [:pick_up, :punch] do
    learner = fencers[1]

    if learner.armed,
      do: %{
        match
        | fencers: %{fencers | 1 => %{learner | armed: false}},
          swords: [Duel.dropped(learner) | swords]
      },
      else: match
  end

  defp open(:block, %Match{fencers: fencers} = match),
    do: %{
      match
      | fencers: %{
          fencers
          | 2 => %{fencers[2] | armed: true, stance: :high, action: :ready, timer: 0}
        }
    }

  defp open(_kind, match), do: match

  defp check(:fence, tutorial, _before, later), do: {tutorial, moving?(later.fencers[1], 0.2)}
  defp check(:run, tutorial, _before, later), do: {tutorial, moving?(later.fencers[1], 1.5)}

  defp check(:heights, tutorial, before, later) do
    count =
      if later.fencers[1].stance != before.fencers[1].stance,
        do: tutorial.count + 1,
        else: tutorial.count

    {%{tutorial | count: count}, count >= 2}
  end

  defp check(:duck, tutorial, _before, later), do: {tutorial, later.fencers[1].action == :duck}

  defp check(:jump, tutorial, _before, later),
    do: {tutorial, not later.fencers[1].grounded and elem(later.fencers[1].velocity, 1) < 0}

  defp check(:lunge, tutorial, _before, later), do: {tutorial, later.fencers[1].action == :thrust}
  defp check(:disarm, tutorial, _before, later), do: {tutorial, {:disarmed, 2} in later.events}

  defp check(:pick_up, tutorial, before, later),
    do: {tutorial, later.fencers[1].armed and not before.fencers[1].armed}

  defp check(:throw, tutorial, _before, later), do: {tutorial, later.fencers[1].action == :throw}

  defp check(:block, tutorial, _before, later) do
    flying? = Enum.any?(later.swords, & &1.flying)
    {tutorial, tutorial.thrown and not flying? and later.fencers[1].action != :dead}
  end

  defp check(:divekick, tutorial, _before, later),
    do: {tutorial, later.fencers[1].action == :divekick}

  defp check(:heart, tutorial, _before, later), do: {tutorial, {:heart, 2} in later.events}
  defp check(:sweep, tutorial, _before, later), do: {tutorial, later.fencers[1].action == :sweep}

  defp check(:punch, tutorial, _before, later),
    do: {tutorial, later.fencers[1].action in [:punch, :punch2, :uppercut]}

  defp check(:right_of_way, tutorial, _before, later), do: {tutorial, later.advancing == 1}

  defp check(:finish, tutorial, _before, later),
    do: {tutorial, elem(later.fencers[1].position, 0) >= tutorial.finish}

  defp moving?(%Fencer{grounded: true, velocity: {vx, _vy}}, faster_than),
    do: abs(vx) > faster_than

  defp moving?(_fencer, _faster_than), do: false

  defp input(held, pressed),
    do: %{held: MapSet.new(held ++ pressed), pressed: MapSet.new(pressed), released: MapSet.new()}
end
