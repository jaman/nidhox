defmodule Nidhox.Noises do
  @moduledoc """
  What a step of a bout sounded like: the sound events (`Nidhox.Sounds.event/2`), from
  the bout before the step and after it. Sounds of something in the room are placed, as
  `{event, {x, y}}` in tiles of `@tile` pixels; a room change and a win are not.

    * a fencer that starts a thrust, a throw, a divekick, a jump, or lands; a fencer on the ground
      running or walking, each time it covers another stride (`@run_stride` or
      `@walk_stride` pixels); one that picks a sword up
    * a death (a stab, a scream and the blood's hiss where the fencer fell), a parry (a clash where the
      blades met), a disarm (where the disarmed fencer stands)
    * a fencer knocked down, and a heart torn out, where that fencer is
    * the Nidhogg's roar, bite and slurp, where it is (`Nidhox.Ending`)
    * a sword coming to rest on the ground
    * the bout moving into another room, and the bout being won
  """

  alias Nidhox.{Fencer, Match, Sounds}

  @tile 16
  @run_stride 12
  @walk_stride 8
  @started [:thrust, :throw, :divekick]

  @doc "The placed sound events of the step from `before` to `after`."
  @spec step(Match.t(), Match.t()) :: [tuple()]
  def step(%Match{} = before, %Match{} = later) do
    seed = later.frame

    fencers =
      Enum.flat_map([1, 2], fn side ->
        fencer(before.fencers[side], later.fencers[side], seed + side)
      end)

    fencers ++ duel(later, seed) ++ swords(before, later, seed) ++ bout(before, later, seed)
  end

  defp fencer(%Fencer{} = was, %Fencer{} = now, seed) do
    started = for action <- @started, now.action == action and was.action != action, do: action

    [
      {was.grounded and not now.grounded and elem(now.velocity, 1) < 0, :jump},
      {not was.grounded and now.grounded and now.action != :dead, :land},
      {stepping?(was, now, 1.5, :infinity, @run_stride), :run_step},
      {stepping?(was, now, 0.2, 1.5, @walk_stride), :walk_step},
      {now.armed and not was.armed and now.action != :dead, :pickup}
    ]
    |> Enum.filter(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
    |> Enum.concat(started)
    |> Enum.map(&placed(&1, seed, now.position))
  end

  defp stepping?(
         %Fencer{position: {was_x, _}},
         %Fencer{grounded: true, action: :ready, velocity: {vx, _}, position: {x, _}},
         slowest,
         fastest,
         stride
       ) do
    abs(vx) > slowest and (fastest == :infinity or abs(vx) <= fastest) and
      floor(was_x / stride) != floor(x / stride)
  end

  defp stepping?(_was, _now, _slowest, _fastest, _stride), do: false

  defp duel(%Match{events: events, fencers: fencers}, seed) do
    Enum.flat_map(events, fn
      {:killed, _killer, victim} ->
        position = fencers[victim].position

        [
          placed(:stab, seed, position),
          placed(:scream, seed, position),
          placed(:blood, seed, position)
        ]

      {:parried, point} ->
        [placed(:clash, seed, point)]

      {:disarmed, side} ->
        [placed(:disarm, seed, fencers[side].position)]

      {:floored, side} ->
        [placed(:floored, seed, fencers[side].position)]

      {:heart, side} ->
        [placed(:heart, seed, fencers[side].position)]

      {{:nidhogg, kind}, point} ->
        [placed(kind, seed, point)]

      _other ->
        []
    end)
  end

  defp swords(%Match{swords: was}, %Match{swords: now}, seed) do
    if resting(now) > resting(was) do
      case Enum.find(now, &(resting([&1]) == 1)) do
        nil -> []
        sword -> [placed(:sword_ground, seed, sword.position)]
      end
    else
      []
    end
  end

  defp resting(swords),
    do:
      Enum.count(swords, fn %{flying: flying, velocity: {vx, vy}} ->
        not flying and vx == 0 and vy == 0
      end)

  defp bout(%Match{} = before, %Match{} = later, seed) do
    room = if later.index != before.index, do: [Sounds.event(:room, seed)], else: []

    won =
      if later.winner != nil and before.winner == nil, do: [Sounds.event(:cheer, seed)], else: []

    room ++ won
  end

  defp placed(kind, seed, {x, y}), do: {Sounds.event(kind, seed), {x / @tile, y / @tile}}
end
