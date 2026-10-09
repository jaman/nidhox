defmodule Nidhox.Man.Push do
  @moduledoc """
  How the game's scripts shove fencers across:

    * `force_shift/3` (`forceShiftObjectHorizontal(id, amount)`): the amount is added to
      the instance's `h_counter` and the whole pixels of it taken; it moves a pixel at a
      time against `Block`s, stepping down a pixel onto a slope below when on the ground,
      up a pixel over a step, and stopping at a wall it cannot climb, when its user event
      0 runs. `{moved, world}`: `false` when a wall stopped it
    * `tween_dist/5` (`tweenFromPlayerForPlayerDistPercent(from, to, dist, percent)`):
      `to` is drawn `percent` of the way towards the place `dist` pixels ahead of `from`
      (by `from`'s facing); stopped by a wall, `from` is pushed back instead
    * `tween_min_dist/5` (`tweenFromPlayerForPlayerMinDistPercent`): the same, only
      while the two stand no further apart than `dist`
    * `punch_tween/2` (`tryToPunchTween`): a punch draws its puncher towards a near (under
      27 pixels), slow (under 1 a step) opponent at the same height (`y_close?/3`), to 14
      pixels at 0.12
    * `y_close?/3` (`isYDistPlayerOpponentClose`): under a pixel apart up and down
    * `pushed_by_sword/2` (`getPushedBySword`): a stabbed fencer takes its opponent's
      stance; its frame follows how deep the blade's middle is in it (`5.5 − depth ÷ 10 ×
      5.5`, held to 0–11); it is pushed by 0.27 of how far the blade moved since last
      step (none past 5 pixels), 0.3 of that against the blade's facing; it keeps where
      the blade now is (`swordX`, `swordY`, `swordXScale`). It answers how far the blade
      moved, 0 without an opponent
  """

  alias Cauldron2D.GameMaker.{Collide, Instance, World}
  alias Nidhox.Gml
  alias Nidhox.Man.Query

  @noone -4

  @doc "`{moved, world}`: instance `id` shifted `amount` pixels across (`forceShiftObjectHorizontal`)."
  @spec force_shift(World.t(), non_neg_integer(), number()) :: {boolean(), World.t()}
  def force_shift(%World{} = world, id, amount) do
    h_counter = Gml.var(world, id, :h_counter) + amount
    v_counter = Gml.var(world, id, :v_counter)
    across = Gml.round(h_counter)
    down = Gml.round(v_counter)
    world = Gml.put(world, id, %{h_counter: h_counter - across, v_counter: v_counter - down})

    case shift(world, id, Gml.sign(across), abs(across)) do
      {:blocked, world} -> {false, World.perform(world, id, :other, 10)}
      {:moved, world} -> {true, world}
    end
  end

  @doc "The world after `to` is drawn towards `dist` pixels ahead of `from` by `percent`."
  @spec tween_dist(World.t(), non_neg_integer(), non_neg_integer(), number(), number()) :: World.t()
  def tween_dist(%World{} = world, from, to, dist, percent) do
    shift = shift_amount(world, from, to, dist, percent)

    case force_shift(world, to, shift) do
      {true, world} -> world
      {false, world} -> world |> force_shift(from, -shift) |> elem(1)
    end
  end

  @doc "`tween_dist/5`, only while `from` and `to` are no further apart than `dist`."
  @spec tween_min_dist(World.t(), non_neg_integer(), non_neg_integer(), number(), number()) ::
          World.t()
  def tween_min_dist(%World{} = world, from, to, dist, percent) do
    apart = abs(World.fetch(world, from).x - World.fetch(world, to).x)
    if apart - dist <= 1.0e-5, do: tween_dist(world, from, to, dist, percent), else: world
  end

  @doc "The world after a punch draws fencer `self` towards its opponent (`tryToPunchTween`)."
  @spec punch_tween(World.t(), non_neg_integer()) :: World.t()
  def punch_tween(%World{} = world, self) do
    with other when other != nil <-
           Query.by_player(world, Query.other_player(Gml.var(world, self, :playerIndex))),
         true <- abs(Gml.var(world, other, :hspd)) - 1 < -1.0e-5,
         true <- abs(World.fetch(world, self).x - World.fetch(world, other).x) - 27 < -1.0e-5,
         true <- y_close?(world, self, other) do
      tween_dist(world, other, self, 14, 0.12)
    else
      _ -> world
    end
  end

  @doc "Whether `a` and `b` stand under a pixel apart up and down (`isYDistPlayerOpponentClose`)."
  @spec y_close?(World.t(), non_neg_integer(), non_neg_integer()) :: boolean()
  def y_close?(%World{} = world, a, b),
    do: abs(World.fetch(world, a).y - World.fetch(world, b).y) - 1 < -1.0e-5

  @doc "`{moved, world}`: stabbed fencer `self` pushed by its opponent's blade (`getPushedBySword`)."
  @spec pushed_by_sword(World.t(), non_neg_integer()) :: {number(), World.t()}
  def pushed_by_sword(%World{} = world, self) do
    with other when other != nil <- Query.opponent(world, self),
         %Instance{} = blade <- World.fetch(world, Gml.var(world, other, :weapon, @noone)) do
      push(world, self, other, blade)
    else
      _ -> {0, world}
    end
  end

  defp push(world, self, other, %Instance{} = blade) do
    %Instance{x: x} = World.fetch(world, self)
    tip = blade.x + sprite_width(world, blade) * 0.5
    moved = Gml.var(world, self, :swordX) - blade.x
    moved = if abs(moved) - 5 > 1.0e-5, do: 0, else: moved
    frame = Gml.clamp(5.5 - (tip - x) / 10 * 5.5, 0, 11)
    shove = moved * 0.27
    facing = Gml.var(world, other, :facingXScale, 1)
    hspd = Gml.var(world, self, :hspd)
    hspd = if shove * facing < -1.0e-5, do: hspd + shove * 0.3, else: hspd + shove

    world =
      Gml.put(world, self, %{
        stance: Gml.var(world, other, :stance),
        frame: frame,
        hspd: hspd,
        swordX: blade.x,
        swordY: blade.y,
        swordXScale: facing
      })

    {abs(moved), world}
  end

  defp shift_amount(world, from, to, dist, percent) do
    %Instance{x: from_x} = World.fetch(world, from)
    %Instance{x: to_x} = World.fetch(world, to)
    (from_x + Gml.var(world, from, :facingXScale, 1) * dist - to_x) * percent
  end

  defp shift(world, _id, _step, 0), do: {:moved, world}

  defp shift(world, id, step, left) do
    %Instance{x: x, y: y} = World.fetch(world, id)

    cond do
      not blocked?(world, id, {x + step, y}) ->
        world
        |> down_slope(id, step)
        |> World.update(id, &%{&1 | x: &1.x + step})
        |> shift(id, step, left - 1)

      blocked?(world, id, {x + step, y - 1}) ->
        {:blocked, world}

      true ->
        world
        |> World.update(id, &%{&1 | x: &1.x + step, y: &1.y - 1})
        |> shift(id, step, left - 1)
    end
  end

  defp down_slope(world, id, step) do
    %Instance{x: x, y: y} = World.fetch(world, id)

    if Gml.truthy?(Gml.var(world, id, :onGround)) and not blocked?(world, id, {x + step, y + 1}) and
         blocked?(world, id, {x + step, y + 2}),
       do: World.update(world, id, &%{&1 | y: &1.y + 1}),
       else: world
  end

  defp blocked?(world, id, position) do
    case World.object_index(world, "Block") do
      nil -> false
      block -> Collide.meeting?(world, id, position, block)
    end
  end

  defp sprite_width(world, %Instance{sprite_index: sprite, image_xscale: xscale}) do
    case World.sprite(world, sprite) do
      nil -> 0
      definition -> elem(definition.size, 0) * xscale
    end
  end
end
