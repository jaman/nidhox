defmodule Nidhox.Bout.Hits do
  @moduledoc """
  What a fencer's attack does to the other fencer this step, as the game's
  `check_HeldWeapon_to_FleshCollisionMask(flesh)` resolves it: the attacker is the
  body's fencer (`mother`), the defender the match's other fencer (`yellowInstance`,
  `orangeInstance`). An attacker already stabbed or falling does nothing. The
  defender's `swordCollision` is cleared, then by the attacker's state:

    * fencing (29) or standing on a stab (67): a blade crossing the defender's body
      with an impact of 1 or more (`Nidhox.Bout.Overlap.impact/3`) — or any impact on a
      defender already stabbed — marks the swords touching (`swordCollision`) and lifts
      the blade's tip by its stance's stab offset (high 1, middle ⅓, low −1) × 4, less as
      the two stand further apart (none at 32 pixels). A defender not yet stabbed is run
      through: a blood spurt (`BloodEffect`, sprite 280, its colour, the attacker's
      facing) where the blade is, it is drawn onto the blade (18 pixels, at once), and
      in the air (unless the attacker stands on a stab) it is caught on the sword (5)
      with the attacker catching (4); on the ground crouched it is stabbed crouching
      (63), else stabbed standing (65) — the attacker standing on its stab (67) when it
      was crouched last step. This is how a fencer running onto a sword is impaled
    * lunging (48): as fencing, without the tip lift; the defender in the air falls dead
      (26), crouched is stabbed crouching, else stabbed standing
    * stomping (69): a knocked-down defender close enough is stomped (68)
    * sweeping (70): a defender not down, falling, stabbed or getting up (33) that the
      sweep reaches is drawn to 14 pixels at 0.2; at frame 5, at once, and it trips
      backward (76), hit
    * ground pound (35): a defender the pound reaches is drawn to 4 pixels at 0.7 and
      is stomped (68) when down, else knocked upwards (41), hit; the attacker bounces
      over (15)
    * dive kick (14): a defender not down that the kick reaches is drawn to 14 pixels at
      once, knocked upwards (41), hit; the attacker kicks over (15)
    * punch (49), second punch (55): a defender the fist reaches is drawn to 14 pixels
      at 0.2; at frame 3 (5 for the second) at once, and it is punched in the face (38),
      or tripped backward (76, hit) when it already was
    * high kick (45): the same at 17 pixels and frame 3, knocking the defender off its
      feet (40, hit)
    * crane kick (8): a defender the kick reaches is knocked upwards (41, hit), drawn to
      14 pixels at once unless it already was
  """

  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Bout.Overlap
  alias Nidhox.Gml
  alias Nidhox.Man.{Push, Query, State}

  @noone -4
  @stab_offset %{1 => 1.0, 3 => 0.3333333333333333, 2 => -1.0}
  @spurt_sprite 280

  @doc "The world after the attack of the fencer whose body is `flesh` (`check_HeldWeapon_to_FleshCollisionMask`)."
  @spec weapon_to_flesh(World.t(), non_neg_integer(), non_neg_integer()) :: World.t()
  def weapon_to_flesh(%World{} = world, match, flesh) do
    with attacker when attacker != @noone <- Gml.var(world, flesh, :mother, @noone),
         defender when defender != nil <- defender(world, match, attacker),
         false <- Query.stabbed?(world, attacker),
         false <- Query.collapsing?(world, attacker) do
      world
      |> State.put(defender, %{swordCollision: 0})
      |> attack(attacker, defender, Gml.var(world, attacker, :state))
    else
      _ -> world
    end
  end

  defp defender(world, match, attacker) do
    yellow = Gml.var(world, match, :yellowInstance, @noone)
    orange = Gml.var(world, match, :orangeInstance, @noone)

    cond do
      attacker == yellow -> live(world, orange)
      attacker == orange -> live(world, yellow)
      true -> nil
    end
  end

  defp live(world, id), do: if(World.fetch(world, id), do: id)

  defp attack(world, _attacker, defender, 69) do
    if Query.knocked_down?(world, defender) and stomp_range?(world),
      do: State.go(world, defender, 68),
      else: world
  end

  defp attack(world, attacker, defender, 70) do
    if not Query.knocked_down?(world, defender) and fresh?(world, defender) and
         Gml.var(world, defender, :state) != 33 and
         Overlap.sweep?(world, attacker, flesh(world, defender)) do
      world = Push.tween_dist(world, attacker, defender, 14, 0.2)

      if Gml.round(Gml.var(world, attacker, :frame)) == 5,
        do: world |> Push.tween_dist(attacker, defender, 14, 1) |> hit(defender, 76),
        else: world
    else
      world
    end
  end

  defp attack(world, attacker, defender, 35) do
    if fresh?(world, defender) and Overlap.ground_pound?(world, flesh(world, attacker), flesh(world, defender)) do
      world = Push.tween_dist(world, attacker, defender, 4, 0.7)
      next = if Query.knocked_down?(world, defender), do: 68, else: 41

      world
      |> State.go(defender, next)
      |> State.put(defender, %{hitFlag: 1})
      |> State.go(attacker, 15)
    else
      world
    end
  end

  defp attack(world, attacker, defender, 14) do
    if fresh?(world, defender) and not Query.knocked_down?(world, defender) and
         Overlap.divekick?(world, flesh(world, attacker), flesh(world, defender)) do
      world
      |> Push.tween_dist(attacker, defender, 14, 1)
      |> hit(defender, 41)
      |> State.go(attacker, 15)
    else
      world
    end
  end

  defp attack(world, attacker, defender, state) when state in [29, 67] do
    weapon = Gml.var(world, attacker, :weapon, @noone)

    with true <- World.fetch(world, weapon) != nil,
         true <- Overlap.held?(world, weapon, flesh(world, defender)),
         true <- Overlap.impact(world, weapon, flesh(world, defender)) - 1 >= -1.0e-5 or
                   Query.stabbed?(world, defender) do
      world
      |> State.put(defender, %{swordCollision: 1})
      |> lift_tip(attacker, defender, weapon)
      |> run_through(attacker, defender, weapon, :impale)
    else
      _ -> world
    end
  end

  defp attack(world, attacker, defender, 48) do
    weapon = Gml.var(world, attacker, :weapon, @noone)

    with true <- World.fetch(world, weapon) != nil,
         true <- Overlap.held?(world, weapon, flesh(world, defender)),
         true <- Overlap.impact(world, weapon, flesh(world, defender)) - 1 >= -1.0e-5 or
                   Query.stabbed?(world, defender) do
      world
      |> State.put(defender, %{swordCollision: 1})
      |> run_through(attacker, defender, weapon, :lunge)
    else
      _ -> world
    end
  end

  defp attack(world, attacker, defender, state) when state in [49, 55] do
    knock_frame = if state == 49, do: 3, else: 5
    punched(world, attacker, defender, 14, knock_frame, &face_or_trip/2)
  end

  defp attack(world, attacker, defender, 45),
    do: punched(world, attacker, defender, 17, 3, &hit(&1, &2, 40))

  defp attack(world, attacker, defender, 8) do
    if fresh?(world, defender) and Overlap.punch?(world, attacker, flesh(world, defender)) do
      world =
        if Gml.var(world, defender, :state) != 41,
          do: Push.tween_dist(world, attacker, defender, 14, 1),
          else: world

      hit(world, defender, 41)
    else
      world
    end
  end

  defp attack(world, _attacker, _defender, _state), do: world

  defp punched(world, attacker, defender, reach, knock_frame, knock) do
    if fresh?(world, defender) and kick_or_punch?(world, attacker, defender, reach) do
      world = Push.tween_dist(world, attacker, defender, reach, 0.2)

      if Gml.round(Gml.var(world, attacker, :frame)) == knock_frame,
        do: world |> Push.tween_dist(attacker, defender, reach, 1) |> knock.(defender),
        else: world
    else
      world
    end
  end

  defp kick_or_punch?(world, attacker, defender, 17), do: Overlap.kick?(world, attacker, flesh(world, defender))
  defp kick_or_punch?(world, attacker, defender, _reach), do: Overlap.punch?(world, attacker, flesh(world, defender))

  defp face_or_trip(world, defender) do
    if Gml.var(world, defender, :state) == 38,
      do: hit(world, defender, 76),
      else: State.go(world, defender, 38)
  end

  defp hit(world, defender, state),
    do: world |> State.go(defender, state) |> State.put(defender, %{hitFlag: 1})

  defp lift_tip(world, attacker, defender, weapon) do
    %Instance{y: y} = World.fetch(world, weapon)
    apart = Gml.clamp(abs(World.fetch(world, attacker).x - World.fetch(world, defender).x), 0, 32)
    offset = Map.get(@stab_offset, Gml.var(world, attacker, :stance), 0) * 4
    Gml.put(world, weapon, %{tipY: y + offset * (1 - apart / 32)})
  end

  defp run_through(world, attacker, defender, weapon, how) do
    cond do
      Query.stabbed?(world, defender) or Query.collapsing?(world, defender) ->
        world

      how == :impale ->
        world
        |> spurt(attacker, defender, weapon, true)
        |> Push.tween_min_dist(attacker, defender, 18, 1)
        |> impaled(attacker, defender)

      true ->
        world
        |> Push.tween_min_dist(attacker, defender, 18, 1)
        |> spurt(attacker, defender, weapon, false)
        |> lunged(attacker, defender)
    end
  end

  defp spurt(world, attacker, defender, weapon, sprite?) do
    %Instance{x: x} = World.fetch(world, defender)
    %Instance{y: y} = World.fetch(world, weapon)
    {world, spurt} = World.create(world, World.object_index(world, "BloodEffect"), {x, y})
    colour = World.fetch(world, flesh(world, defender)).image_blend
    facing = Gml.var(world, attacker, :facingXScale, 1)

    World.update(world, spurt, fn spurt ->
      spurt = %{spurt | image_blend: colour, image_xscale: facing}
      if sprite?, do: %{spurt | sprite_index: @spurt_sprite}, else: spurt
    end)
  end

  defp impaled(world, attacker, defender) do
    cond do
      not State.on_ground?(world, defender) and Gml.var(world, attacker, :state) != 67 ->
        world |> State.go(defender, 5) |> State.go(attacker, 4)

      Query.ducking?(world, defender) ->
        State.go(world, defender, 63)

      Gml.truthy?(Gml.var(world, attacker, :lastCrouched)) ->
        world |> State.go(attacker, 67) |> State.go(defender, 65)

      true ->
        State.go(world, defender, 65)
    end
  end

  defp lunged(world, _attacker, defender) do
    cond do
      not State.on_ground?(world, defender) -> State.go(world, defender, 26)
      Query.ducking?(world, defender) -> State.go(world, defender, 63)
      true -> State.go(world, defender, 65)
    end
  end

  defp fresh?(world, defender),
    do: not Query.collapsing?(world, defender) and not Query.stabbed?(world, defender)

  defp stomp_range?(world) do
    with yellow when yellow != nil <- first(world, "YellowPlayer"),
         orange when orange != nil <- first(world, "OrangePlayer") do
      %Instance{x: yx, y: yy} = World.fetch(world, yellow)
      %Instance{x: ox, y: oy} = World.fetch(world, orange)
      :math.sqrt((yx - ox) * (yx - ox) + (yy - oy) * (yy - oy)) < 20
    else
      _ -> false
    end
  end

  defp flesh(world, man), do: Gml.var(world, man, :flesh, @noone)

  defp first(world, name) do
    with object when is_integer(object) <- World.object_index(world, name),
         [id | _] <- World.instances_of(world, object) do
      id
    else
      _none -> nil
    end
  end
end
