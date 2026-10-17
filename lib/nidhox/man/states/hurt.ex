defmodule Nidhox.Man.States.Hurt do
  @moduledoc """
  A fencer's states of being hit, stabbed, knocked down and dying, each step as
  `stateBehavior` runs them:

    * disarmed (13): 247; moving back at 1 a step; off the ground it grabs a ledge or
      falls; played once at 0.6, then the unarmed stance (78)
    * dizzy (17) and punched in the face (38): 288 and 299; off the ground it grabs a ledge
      or falls; played once at 0.4, then the unarmed stance
    * knocked off its feet (40): 277; gravity 0.33; once played at 0.6 and on the ground it
      lies down (47)
    * punched upwards (41): 300 cycling at 0.4; rising its frame moves on 0.7 more; falling
      it turns around and falls flat (28)
    * lying down (47): gravity 0.33; unarmed holding down it picks up a sword; its pose
      plays on at 0.6, cycling, settling into lying (287). Lying: forward hops up (59);
      back turns and hops up; jump or up flips up (2); down crawls (9)
    * getting up (33): 264; played once at 0.7 then crawls (9); meanwhile off the ground
      it grabs a ledge or falls, else stands still
    * tripping forward (77): 263; played once at 0.7 then gets up (33); meanwhile off the
      ground it grabs a ledge or falls
    * tripping backward (76): 350; played once at 0.7 then lies down (47); meanwhile off
      the ground it grabs a ledge or falls
    * stabbed standing (65): its stance's hit (high 274, middle 276, low 275); in the air
      it falls dead (26). Unless the swords touch, `stabCounter` counts and past 6 it
      collapses (66); touching, the count restarts. Past 600 steps it collapses; with no
      opponent, or one already falling or stabbed, it collapses. Else the blade pushes it
      (`Nidhox.Man.Push.pushed_by_sword/2`) and, after 10 steps in the state, it bleeds
      `irandom_range(0, 5 × pixels the blade moved across + 3)` drops at the blade's height
    * stabbed crouching (63): 273; in the air it falls dead; on the ground counting as
      standing, past 6 it collapses ducking (20); with an opponent the blade pushes it and
      it bleeds a drop for each pixel the blade moved, after 10 steps in the state
    * stabbed in the air (64): 290; on the ground it is stabbed standing (65); in the air
      counting as standing, past 6 it collapses (66) on the ground or falls dead; played
      once at 0.6 it does the same
    * standing collapse (66): its own collapse (`collapseAnimation`), still; in the air it
      falls dead. Played once at 0.6: past 0.66 of the way to its last frame on stairs it
      rolls down them (82); otherwise at the end it evaporates (24)
    * ducking collapse (20): 238, still; in the air it falls dead; played as the standing
      collapse is
    * falling dead (26): 246 played once at 0.6; landing it evaporates
    * evaporating (24): 261 played once at 0.4, throwing up three drops of blood a step in
      its body's colour, `random(width × 0.6)` across and `random_range(−2, 0)` down from
      its feet, `hspeed` `random_range(−1, 1)`, `vspeed` `random_range(0, −8)`; then it is
      gone
    * hit by a flying sword standing (39): 272, driven back 1.6 a step; in the air the
      sword falls from it and it falls dead; played once at 0.6 the sword falls and it
      evaporates turned around
    * hit by a flying sword in the air (37): 291, driven back 1.6; in the air played once
      at 0.6 the sword falls and it falls dead (or evaporates turned around on the
      ground); on the ground it evaporates turned around
    * stood on and stabbed (67): 329; an opponent is drawn onto its blade (7 pixels ahead,
      at once); played once at 0.6, then it fences low
    * stomped (68): drawn behind (depth −9); 332 played once at 0.6, then it evaporates
      turned around
    * killed without a body (46): nothing
    * rolling down stairs (82): 306 cycling at `|hspd| × 0.2 + 0.05`. Standing still after
      its first step it collapses (83). Beside stairs `hspd` approaches 3 down them by
      0.04; elsewhere on the ground friction 0.08 slows it. Each step it throws up three
      drops of blood `random_range(−8, 8)` across and `random_range(−2, 0)` down from its
      position, `hspeed` `random_range(−1, 1)`, `vspeed` `random_range(0, −8)`
    * rolled collapse (83): 305, still; in the air it falls dead; played once at 0.6 with
      three drops of blood a step as when rolling, then it evaporates (24)
  """

  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Gml
  alias Nidhox.Man.{Physics, Push, Query, Stairs, State, Weapon}
  alias Nidhox.Objects.BloodDrop

  @up 2
  @down 3
  @jump 4
  @forward 8
  @back 9
  @hits %{1 => 274, 3 => 276, 2 => 275}
  @lying 287
  @noone -4

  @doc "The world after fencer `self`'s step in hurt state `state`."
  @spec behave(World.t(), non_neg_integer(), integer()) :: World.t()
  def behave(world, self, 13) do
    world =
      world
      |> State.pose(self, 247)
      |> State.put(self, %{hspd: -State.get(world, self, :facingXScale)})

    grounded(world, self, &once(&1, &2, 0.6, 78))
  end

  def behave(world, self, state) when state in [17, 38] do
    sprite = if state == 17, do: 288, else: 299
    world |> State.pose(self, sprite) |> grounded(self, &once(&1, &2, 0.4, 78))
  end

  def behave(world, self, 40) do
    {past, world} =
      world
      |> State.pose(self, 277)
      |> Physics.apply_gravity(self, 0.33)
      |> State.animate(self, 0.6, false)

    if past and State.on_ground?(world, self), do: State.go(world, self, 47), else: world
  end

  def behave(world, self, 41) do
    {_past, world} = world |> State.pose(self, 300) |> State.animate(self, 0.4, true)

    if State.get(world, self, :vspd) > 1.0e-5,
      do:
        world
        |> State.put(self, %{facingXScale: -State.get(world, self, :facingXScale)})
        |> State.go(self, 28),
      else: State.put(world, self, %{frame: State.get(world, self, :frame) + 0.7})
  end

  def behave(world, self, 47) do
    world = Physics.apply_gravity(world, self, 0.33)

    world =
      if State.type(world, self) == 1 and State.down?(world, self, @down),
        do: Weapon.try_pickup(world, self),
        else: world

    sprite = World.fetch(world, State.get(world, self, :flesh)).sprite_index
    {past, world} = world |> State.pose(self, sprite) |> State.animate(self, 0.6, true)
    world = if past, do: State.pose(world, self, @lying), else: world

    if World.fetch(world, State.get(world, self, :flesh)).sprite_index == @lying,
      do: lying(world, self),
      else: world
  end

  def behave(world, self, 33) do
    {past, world} = world |> State.pose(self, 264) |> State.animate(self, 0.7, false)

    cond do
      past -> State.go(world, self, 9)
      not State.on_ground?(world, self) -> Physics.grab_ledge_or_fall(world, self)
      true -> State.put(world, self, %{hspd: 0})
    end
  end

  def behave(world, self, state) when state in [76, 77] do
    sprite = if state == 76, do: 350, else: 263
    next = if state == 76, do: 47, else: 33
    {past, world} = world |> State.pose(self, sprite) |> State.animate(self, 0.7, false)

    cond do
      past -> State.go(world, self, next)
      State.on_ground?(world, self) -> world
      true -> Physics.grab_ledge_or_fall(world, self)
    end
  end

  def behave(world, self, 65) do
    world = hit_pose(world, self)

    if State.on_ground?(world, self) do
      case count_stab(world, self) do
        {:collapse, world} -> State.go(world, self, 66)
        {:held, world} -> stabbed_standing(world, self)
      end
    else
      State.go(world, self, 26)
    end
  end

  def behave(world, self, 63) do
    world = State.pose(world, self, 273)

    if State.on_ground?(world, self) do
      case count_stab(world, self) do
        {:collapse, world} -> State.go(world, self, 20)
        {:held, world} -> stabbed_crouching(world, self)
      end
    else
      State.go(world, self, 26)
    end
  end

  def behave(world, self, 64) do
    world = State.pose(world, self, 290)

    if State.on_ground?(world, self) do
      State.go(world, self, 65)
    else
      case count_stab(world, self) do
        {:collapse, world} ->
          collapse_or_fall(world, self)

        {:held, world} ->
          collapse_when_played(world, self)
      end
    end
  end

  def behave(world, self, 66) do
    world =
      world
      |> State.pose(self, State.get(world, self, :collapseAnimation))
      |> State.put(self, %{hspd: 0})

    collapsing(world, self)
  end

  def behave(world, self, 20) do
    world |> State.put(self, %{hspd: 0}) |> State.pose(self, 238) |> collapsing(self)
  end

  def behave(world, self, 26) do
    {_past, world} = world |> State.pose(self, 246) |> State.animate(self, 0.6, false)
    if State.on_ground?(world, self), do: State.go(world, self, 24), else: world
  end

  def behave(world, self, 24) do
    case world |> State.pose(self, 261) |> State.animate(self, 0.4, false) do
      {true, world} -> World.destroy(world, self)
      {false, world} -> Enum.reduce(1..3, world, fn _drop, world -> spray(world, self) end)
    end
  end

  def behave(world, self, 39) do
    world = hit_by_flying(world, self, 272)

    if State.on_ground?(world, self) do
      case State.animate(world, self, 0.6, false) do
        {true, world} -> world |> sword_falls(self) |> turn_around(self) |> State.go(self, 24)
        {false, world} -> world
      end
    else
      world |> sword_falls(self) |> State.go(self, 26)
    end
  end

  def behave(world, self, 37) do
    world = hit_by_flying(world, self, 291)

    if State.on_ground?(world, self) do
      world |> turn_around(self) |> State.go(self, 24)
    else
      case State.animate(world, self, 0.6, false) do
        {true, world} -> world |> sword_falls(self) |> land_or_fall(self)
        {false, world} -> world
      end
    end
  end

  def behave(world, self, 67) do
    world = State.pose(world, self, 329)

    world =
      case Query.by_player(world, Query.other_player(State.get(world, self, :playerIndex))) do
        nil -> world
        other -> Push.tween_min_dist(world, self, other, 7, 1)
      end

    case State.animate(world, self, 0.6, false) do
      {true, world} -> world |> State.put(self, %{stance: 2}) |> State.go(self, 29)
      {false, world} -> world
    end
  end

  def behave(world, self, 68) do
    world = world |> World.update(self, &%{&1 | depth: -9}) |> State.pose(self, 332)

    case State.animate(world, self, 0.6, false) do
      {true, world} -> world |> turn_around(self) |> State.go(self, 24)
      {false, world} -> world
    end
  end

  def behave(world, self, 82) do
    {_past, world} =
      world
      |> State.pose(self, 306)
      |> State.animate(self, abs(State.hspd(world, self)) * 0.2 + 0.05, true)

    if Gml.eq?(State.hspd(world, self), 0) and Gml.gt?(State.get(world, self, :stateCounter), 0) do
      State.go(world, self, 83)
    else
      world |> roll_down(self) |> tumble_sprays(self)
    end
  end

  def behave(world, self, 83) do
    world = world |> State.pose(self, 305) |> State.put(self, %{hspd: 0})

    if State.on_ground?(world, self) do
      case State.animate(world, self, 0.6, false) do
        {true, world} -> State.go(world, self, 24)
        {false, world} -> tumble_sprays(world, self)
      end
    else
      State.go(world, self, 26)
    end
  end

  def behave(world, _self, 46), do: world

  defp grounded(world, self, fun) do
    if State.on_ground?(world, self),
      do: fun.(world, self),
      else: Physics.grab_ledge_or_fall(world, self)
  end

  defp once(world, self, speed, next) do
    case State.animate(world, self, speed, false) do
      {true, world} -> State.go(world, self, next)
      {false, world} -> world
    end
  end

  defp lying(world, self) do
    cond do
      State.pressed?(world, self, @forward) ->
        State.go(world, self, 59)

      State.pressed?(world, self, @back) ->
        world |> turn_around(self) |> State.go(self, 59)

      State.pressed?(world, self, @jump) or State.down?(world, self, @up) ->
        State.go(world, self, 2)

      State.pressed?(world, self, @down) ->
        State.go(world, self, 9)

      true ->
        world
    end
  end

  defp turn_around(world, self),
    do: State.put(world, self, %{facingXScale: -State.get(world, self, :facingXScale)})

  defp count_stab(world, self) do
    if Gml.truthy?(State.get(world, self, :swordCollision)) do
      {:held, State.put(world, self, %{stabCounter: 0})}
    else
      count = State.get(world, self, :stabCounter) + 1
      world = State.put(world, self, %{stabCounter: count})
      if count > 6, do: {:collapse, world}, else: {:held, world}
    end
  end

  defp collapse_or_fall(world, self),
    do: State.go(world, self, if(State.on_ground?(world, self), do: 66, else: 26))

  defp stabbed_standing(world, self) do
    other = Query.opponent(world, self)

    cond do
      State.get(world, self, :stateCounter) > 600 -> State.go(world, self, 66)
      other == nil -> State.go(world, self, 66)
      Query.collapsing?(world, other) or Query.stabbed?(world, other) -> State.go(world, self, 66)
      true -> bleed_from_blade(world, self, other)
    end
  end

  defp bleed_from_blade(world, self, other) do
    {_moved, world} = Push.pushed_by_sword(world, self)

    case World.fetch(world, Gml.var(world, other, :weapon, @noone)) do
      nil ->
        world

      %Instance{x: x} = blade ->
        reach = abs(x - Gml.var(world, blade.id, :previousX, x))
        {drops, world} = Gml.irandom_range(world, 0, trunc(reach * 5 + 3))
        bleed(world, self, blade.y + 1, drops)
    end
  end

  defp stabbed_crouching(world, self) do
    case Query.opponent(world, self) do
      nil ->
        world

      other ->
        {moved, world} = Push.pushed_by_sword(world, self)
        blade = World.fetch(world, Gml.var(world, other, :weapon, @noone))
        if blade, do: bleed(world, self, blade.y + 1, trunc(moved)), else: world
    end
  end

  defp bleed(world, self, y, drops) do
    Enum.reduce(List.duplicate(nil, max(drops, 0)), world, fn _drop, world ->
      drip(world, self, y)
    end)
  end

  defp drip(world, self, y) do
    if State.get(world, self, :stateCounter) > 10 do
      flesh = World.fetch(world, State.get(world, self, :flesh))
      %Instance{x: x} = World.fetch(world, self)

      case BloodDrop.bleed(world, {x, y}, flesh.image_blend) do
        {nil, world} -> world
        {_drop, world} -> State.put(world, self, %{bloodVol: 0.7})
      end
    else
      world
    end
  end

  defp collapse_when_played(world, self) do
    case State.animate(world, self, 0.6, false) do
      {true, world} -> collapse_or_fall(world, self)
      {false, world} -> world
    end
  end

  defp land_or_fall(world, self) do
    if State.on_ground?(world, self),
      do: world |> turn_around(self) |> State.go(self, 24),
      else: State.go(world, self, 26)
  end

  defp spray(world, self) do
    flesh = World.fetch(world, State.get(world, self, :flesh))
    {across, world} = Gml.random(world, sprite_width(world, flesh) * 0.6)
    spatter(world, self, across)
  end

  defp tumble_spray(world, self) do
    {across, world} = Gml.random_range(world, -8, 8)
    spatter(world, self, across)
  end

  defp spatter(world, self, across) do
    flesh = World.fetch(world, State.get(world, self, :flesh))
    %Instance{x: x, y: y} = World.fetch(world, self)
    {down, world} = Gml.random_range(world, -2, 0)
    object = World.object_index(world, "o_blood")
    {world, drop} = World.create(world, object, {x + across, y + down})
    {hspeed, world} = Gml.random_range(world, -1, 1)
    world = World.update(world, drop, &%{&1 | hspeed: hspeed, image_blend: flesh.image_blend})
    {vspeed, world} = Gml.random_range(world, 0, -8)
    World.update(world, drop, &%{&1 | vspeed: vspeed})
  end

  defp hit_pose(world, self) do
    case Map.fetch(@hits, State.get(world, self, :stance)) do
      {:ok, sprite} -> State.pose(world, self, sprite)
      :error -> world
    end
  end

  defp collapsing(world, self) do
    if State.on_ground?(world, self) do
      {past, world} = State.animate(world, self, 0.6, false)
      collapsed(world, self, past)
    else
      State.go(world, self, 26)
    end
  end

  defp collapsed(world, self, past) do
    cond do
      Gml.lt?(State.get(world, self, :frame), last_frame(world, self) * 0.66) ->
        evaporate_when(world, self, past)

      Stairs.under(world, self) == nil ->
        evaporate_when(world, self, past)

      true ->
        State.go(world, self, 82)
    end
  end

  defp evaporate_when(world, self, true), do: State.go(world, self, 24)
  defp evaporate_when(world, _self, false), do: world

  defp last_frame(world, self) do
    flesh = World.fetch(world, State.get(world, self, :flesh))
    length(World.sprite(world, flesh.sprite_index).frames) - 1
  end

  defp roll_down(world, self) do
    case Stairs.near(world, self) do
      nil ->
        if State.on_ground?(world, self),
          do: Physics.apply_horizontal_friction(world, self, 0.08),
          else: world

      stairs ->
        hspd = Gml.approach(State.hspd(world, self), -Stairs.dir(world, stairs) * 3, 0.04)
        State.put(world, self, %{hspd: hspd})
    end
  end

  defp tumble_sprays(world, self),
    do: Enum.reduce(1..3, world, fn _drop, world -> tumble_spray(world, self) end)

  defp hit_by_flying(world, self, sprite) do
    world
    |> State.pose(self, sprite)
    |> State.put(self, %{hspd: State.get(world, self, :facingXScale) * -1.6})
  end

  defp sword_falls(world, self) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    {world, _dropped} =
      Weapon.spawn_dropped(world, {x, y}, 0, 0, State.get(world, self, :facingXScale))

    world
  end

  defp sprite_width(world, %Instance{sprite_index: sprite, image_xscale: xscale}) do
    case World.sprite(world, sprite) do
      nil -> 0
      definition -> elem(definition.size, 0) * xscale
    end
  end
end
