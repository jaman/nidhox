defmodule Nidhox.Bout.Frame do
  @moduledoc """
  One frame of a match, as the game's `updateMatchFrame` runs it from `System`'s begin
  step (`system_step/2`, `updateSystemFrame`).

  `system_step/2`: with a `Match`, the frame runs once — twice in turbo mode; in slow
  mode only on even `System.metaFrame`s — unless the game is paused; with none,
  `System.frame` counts on its own.

  `run/2`, with the match `match`:

    1. `System.frame` counts; the players' buttons are kept (`Nidhox.Bout.Input.record/3`,
       `updateMatchInput`)
    2. in the tournament's warm-up (`System.flow` 4890734) the clock is full
       (`countDownTimer` 36000) and nobody leads; on the room's first frame of a
       faceoff, the match and the camera's centre move to the middle of the room
    3. user event 2 for every `Doorway`, `HeldWeapon`, `PickupContainer`,
       `DroppedWeapon`, `Smoosher`, `SpikeSmoosher` and `NewCloudBlock`; user event 3 for
       every `DefensiveBlock`; user event 2 for every `NidhoggHead`, `CloudPoof`,
       `FakeCloudPoof` and `Grass`; every fencer checked for falling out of the room
       (`Nidhox.Bout.RightOfWay.fell_off/3`); user event 0 for every `Brain`
    4. each player's fencer kept inside the room — only the leader, not entering, may
       go past the room's edge ahead of it
    5. user event 2 for every `FlyingWeapon`, then every fencer (`Man`), each then shown
    6. the faceoff counts down (`Nidhox.Bout.Outcome.faceoff/2`); outside an end room,
       with a time limit (`useCountDownTimer`), the clock counts down and at 0 the
       match goes into sudden death and the frame ends there
    7. the match forgets fencers that are gone (`yellowInstance`, `orangeInstance`,
       `priorityInstance`); its list of thrown swords (`flyingWeapons`) is rebuilt in the
       order of `playerIndex × 1000000 + round(x) × 1000 + round(y)`, ties in the order of
       the swords' ids (`rebuildFlyingWeaponList`)
    8. thrown swords meet thrown swords, held swords and bodies (`Nidhox.Bout.Clash`)
    9. with both fencers: swords crossing swords — clashing where the first
       `HeldWeapon` is when both hold swords and the last clash has cleared
       (`ClashPosition.cleared`), clearing it when they do not cross; the fencer whose
       state comes first in `System.priorityList` has priority (ties: the faster
       across, then the one whose sword moved more up or down, else as before); swords
       reaching bodies (`Nidhox.Bout.Hits.weapon_to_flesh/3`) — both when either is
       running (52), else the priority fencer's first; and two pushable fencers within
       36 pixels down and 7 across pushed apart by 0.2
    10. a closed `Doorway` (`opening` 3) is kicked open by a fencer in its high kick
        (45) at frame 3 reaching it — away from the kicker — and heard (2)
    11. fencers flagged to turn (`turnAroundFlag`) face their opponent
    12. in sudden death, the last fencer up wins, or with two the one not collapsing
    13. once the match is `finished` with a `winner` and no `ShowMatchStats`, the winner is
        shown (`Nidhox.Bout.Outcome.winner/2`); a finished match counts `finishTimer`, and
        from 180 with `ShowMatchStats` there it is `matchOver`
    14. respawns, the right of way, the leader (`Nidhox.Objects.Match.track_leader/2`)
        and the camera (`Nidhox.Bout.Spawn.respawns/2`, `Nidhox.Bout.RightOfWay.manage/2`,
        `Nidhox.Bout.CameraFollow.manage/2`); user event 2 for every `MinesCenterCamera`
    15. every `HeldWeapon` and `FleshCollisionMask` remembers where it is (`previousX`,
        `previousY`)
    16. on every 10th `System.frame` outside flow 9836834, with a `Block` in the room,
        each fencer inside a `Block` is lifted a pixel at a time (`floor(y) - 1`) until it
        is free; in sudden death nobody leads
  """

  alias Cauldron2D.GameMaker.{Collide, Instance, World}

  alias Nidhox.Bout.{
    Camera,
    CameraFollow,
    Clash,
    Hits,
    Input,
    Outcome,
    Overlap,
    RightOfWay,
    Sound,
    Spawn,
    Variants
  }

  alias Nidhox.Brain.Buttons
  alias Nidhox.Gml
  alias Nidhox.Man.Query
  alias Nidhox.Objects.{Brain, Match, System}

  @noone -4
  @user_event_0 10
  @user_event_2 12
  @user_event_3 13
  @first_updated ~w(Doorway HeldWeapon PickupContainer DroppedWeapon Smoosher SpikeSmoosher NewCloudBlock)
  @then_updated ~w(NidhoggHead CloudPoof FakeCloudPoof Grass)
  @entering 23
  @running 52
  @high_kick 45
  @closed 3
  @door_sound "sndSnap"
  @unlisted 99_999_999
  @lift_every 10
  @ending_frames 180
  @push_height 36
  @push_reach 7
  @push 0.2
  @sword 2
  @special_flow 9_836_834
  @warm_up_flow 4_890_734
  @full_clock 36_000

  @doc "The world after `System`'s begin step runs the match's frames (`updateSystemFrame`)."
  @spec system_step(World.t(), non_neg_integer()) :: World.t()
  def system_step(%World{} = world, system) do
    case Gml.first(world, "Match") do
      nil ->
        Gml.put(world, system, %{frame: Gml.var(world, system, :frame) + 1})

      match ->
        Enum.reduce(1..frames(world)//1, world, fn _frame, world -> run_if_here(world, match) end)
    end
  end

  defp frames(world) do
    times = if Variants.turbo?(world), do: 2, else: 1

    if Variants.slow?(world) do
      times = times - 1
      if times == 0 and rem(trunc(System.get(world, :metaFrame)), 2) == 0, do: 1, else: times
    else
      times
    end
  end

  defp run_if_here(world, match),
    do: if(World.fetch(world, match), do: run(world, match), else: world)

  @doc "The world one match frame on, for the match `match` (`updateMatchFrame`)."
  @spec run(World.t(), non_neg_integer()) :: World.t()
  def run(%World{} = world, match) do
    world =
      world
      |> count_frame()
      |> Input.record(match, held(world))
      |> warm_up(match)
      |> centre_on_faceoff(match)
      |> each_object(@first_updated, @user_event_2)
      |> each_object(["DefensiveBlock"], @user_event_3)
      |> each_object(@then_updated, @user_event_2)
      |> each_man(&RightOfWay.fell_off(&1, &2, match))
      |> each_object(["Brain"], @user_event_0)
      |> keep_in_room(match)
      |> each_object(["FlyingWeapon"], @user_event_2)
      |> each_man(&(&1 |> World.perform(&2, :other, @user_event_2) |> shown(&2)))
      |> Outcome.faceoff(match)

    case clock(world, match) do
      {:sudden_death, world} -> Outcome.sudden_death(world, match)
      {:running, world} -> fight(world, match)
    end
  end

  defp fight(world, match) do
    world
    |> forget_gone(match)
    |> rebuild_flying_weapons(match)
    |> Clash.flying_to_flying(match)
    |> each_man(&thrown_swords(&1, &2, match))
    |> both_fencers(match)
    |> kick_doors()
    |> each_man(&turn_around/2)
    |> sudden_death_winner(match)
    |> finish(match)
    |> Spawn.respawns(match)
    |> RightOfWay.manage(match)
    |> Match.track_leader(match)
    |> CameraFollow.manage(match)
    |> each_object(["MinesCenterCamera"], @user_event_2)
    |> remember_places()
    |> lift_out_of_blocks()
    |> then(
      &if(Gml.truthy?(Gml.var(&1, match, :sudden_death)),
        do: Gml.put(&1, match, %{leadingPlayerIndex: 0}),
        else: &1
      )
    )
  end

  defp count_frame(world) do
    case Gml.first(world, "System") do
      nil -> world
      system -> Gml.put(world, system, %{frame: Gml.var(world, system, :frame) + 1})
    end
  end

  defp held(%World{input: input} = world) do
    players = Map.get(input, :players, %{})

    Map.new([1, 2], fn player ->
      case Brain.for_player(world, player) do
        nil -> {player, players |> Map.get(player, %{}) |> Map.get(:held, MapSet.new())}
        brain -> {player, Buttons.held(world, brain)}
      end
    end)
  end

  defp warm_up(world, match) do
    if System.get(world, :flow) == @warm_up_flow,
      do: Gml.put(world, match, %{countDownTimer: @full_clock, leadingPlayerIndex: 0}),
      else: world
  end

  defp centre_on_faceoff(world, match) do
    if System.get(world, :flow) != @special_flow and
         Gml.truthy?(Gml.var(world, match, :firstFrameOfRoom)) and
         Gml.truthy?(Gml.var(world, match, :faceoff)) do
      middle = room_width(world) * 0.5

      world
      |> World.update(match, &%{&1 | x: middle})
      |> Camera.put_center_x(middle)
    else
      world
    end
  end

  defp each_object(world, names, event) do
    Enum.reduce(names, world, &each_instance(&2, &1, event))
  end

  defp each_instance(world, name, event) do
    Enum.reduce(Gml.all(world, name), world, &perform_other(&2, &1, event))
  end

  defp perform_other(world, id, event) do
    if World.fetch(world, id), do: World.perform(world, id, :other, event), else: world
  end

  defp each_man(world, fun) do
    Enum.reduce(Gml.all(world, "Man"), world, fn man, world ->
      if World.fetch(world, man), do: fun.(world, man), else: world
    end)
  end

  defp shown(world, man),
    do:
      if(World.fetch(world, man),
        do: World.update(world, man, &%{&1 | visible: true}),
        else: world
      )

  defp keep_in_room(world, match) do
    leader = Gml.var(world, match, :leadingPlayerIndex)
    width = room_width(world)

    world
    |> keep_player("YellowPlayer", leader, &max(&1, 0), width)
    |> keep_player("OrangePlayer", leader, &min(width, &1), width)
  end

  defp keep_player(world, name, leader, ahead, width) do
    Enum.reduce(Gml.all(world, name), world, fn man, world ->
      %Instance{vars: vars} = World.fetch(world, man)

      if Map.get(vars, :state) == @entering or leader != Map.get(vars, :playerIndex),
        do: World.update(world, man, &%{&1 | x: Gml.clamp(&1.x, 0, width)}),
        else: World.update(world, man, &%{&1 | x: ahead.(&1.x)})
    end)
  end

  defp clock(world, match) do
    if not Outcome.victory_lap?(world) and Gml.truthy?(Gml.var(world, match, :useCountDownTimer)) do
      left = Gml.var(world, match, :countDownTimer) - 1
      world = Gml.put(world, match, %{countDownTimer: left})
      if Gml.eq?(left, 0), do: {:sudden_death, world}, else: {:running, world}
    else
      {:running, world}
    end
  end

  defp forget_gone(world, match) do
    Enum.reduce([:yellowInstance, :orangeInstance, :priorityInstance], world, fn name, world ->
      id = Gml.var(world, match, name, @noone)

      if is_integer(id) and id >= 0 and World.fetch(world, id),
        do: world,
        else: Gml.put(world, match, %{name => @noone})
    end)
  end

  defp rebuild_flying_weapons(world, match) do
    swords = world |> Gml.all("FlyingWeapon") |> Enum.sort_by(&flying_order(world, &1))
    Gml.put(world, match, %{flyingWeapons: swords})
  end

  defp flying_order(world, sword) do
    %Instance{x: x, y: y, vars: vars} = World.fetch(world, sword)
    Map.get(vars, :playerIndex, 0) * 1_000_000 + Gml.round(x) * 1000 + Gml.round(y)
  end

  defp thrown_swords(world, man, match) do
    world = Clash.held_to_flying(world, match, Gml.var(world, man, :weapon, @noone))
    {struck, world} = Clash.flying_to_flesh(world, Gml.var(world, man, :flesh, @noone))
    if struck and World.fetch(world, man), do: Clash.collapse_by_flying(world, man), else: world
  end

  defp both_fencers(world, match) do
    yellow = Gml.var(world, match, :yellowInstance, @noone)
    orange = Gml.var(world, match, :orangeInstance, @noone)

    if yellow != @noone and orange != @noone do
      world
      |> crossed_swords(match, yellow, orange)
      |> pick_priority(match, yellow, orange)
      |> swords_to_bodies(match)
      |> push_apart(match)
    else
      world
    end
  end

  defp crossed_swords(world, match, yellow, orange) do
    case Clash.weapon_to_weapon(world, match) do
      {true, world} -> clash_if_cleared(world, yellow, orange)
      {false, world} -> put_cleared(world, 1)
    end
  end

  defp clash_if_cleared(world, yellow, orange) do
    swords? = weapon_type(world, yellow) == @sword and weapon_type(world, orange) == @sword
    clash = Gml.first(world, "ClashPosition")

    with true <- swords?,
         true <- clash != nil and Gml.truthy?(Gml.var(world, clash, :cleared)),
         weapon when weapon != nil <- Gml.first(world, "HeldWeapon") do
      %Instance{x: x, y: y} = World.fetch(world, weapon)
      world |> Clash.clash_at({x, y}) |> put_cleared(0)
    else
      _ -> world
    end
  end

  defp put_cleared(world, cleared) do
    case Gml.first(world, "ClashPosition") do
      nil -> world
      clash -> Gml.put(world, clash, %{cleared: cleared})
    end
  end

  defp weapon_type(world, man), do: Gml.var(world, Gml.var(world, man, :weapon, @noone), :type, 1)

  defp pick_priority(world, match, yellow, orange) do
    yellow_rank = Clash.priority(world, yellow)
    orange_rank = Clash.priority(world, orange)

    cond do
      yellow_rank < orange_rank -> Gml.put(world, match, %{priorityInstance: yellow})
      orange_rank < yellow_rank -> Gml.put(world, match, %{priorityInstance: orange})
      Gml.eq?(orange_rank, @unlisted) -> world
      true -> tie_break(world, match, yellow, orange)
    end
  end

  defp tie_break(world, match, yellow, orange) do
    yellow_speed = abs(Gml.var(world, yellow, :hspd))
    orange_speed = abs(Gml.var(world, orange, :hspd))
    yellow_lift = sword_lift(world, yellow)
    orange_lift = sword_lift(world, orange)

    cond do
      Gml.gt?(yellow_speed, orange_speed) -> Gml.put(world, match, %{priorityInstance: yellow})
      Gml.gt?(orange_speed, yellow_speed) -> Gml.put(world, match, %{priorityInstance: orange})
      Gml.gt?(yellow_lift, orange_lift) -> Gml.put(world, match, %{priorityInstance: yellow})
      Gml.gt?(orange_lift, yellow_lift) -> Gml.put(world, match, %{priorityInstance: orange})
      true -> world
    end
  end

  defp sword_lift(world, man) do
    case World.fetch(world, Gml.var(world, man, :weapon, @noone)) do
      %Instance{y: y, yprevious: previous} -> abs(y - previous)
      nil -> 0
    end
  end

  defp swords_to_bodies(world, match) do
    yellow = Gml.var(world, match, :yellowInstance, @noone)
    orange = Gml.var(world, match, :orangeInstance, @noone)
    priority = Gml.var(world, match, :priorityInstance, @noone)

    cond do
      Gml.var(world, yellow, :state) == @running or Gml.var(world, orange, :state) == @running ->
        world |> hit(match, yellow) |> hit(match, orange)

      priority != @noone ->
        other = if priority == yellow, do: orange, else: yellow
        world |> hit(match, priority) |> hit(match, other)

      true ->
        world
    end
  end

  defp hit(world, match, man) do
    case Gml.var(world, man, :flesh, @noone) do
      @noone ->
        world

      flesh ->
        if World.fetch(world, flesh), do: Hits.weapon_to_flesh(world, match, flesh), else: world
    end
  end

  defp push_apart(world, match) do
    yellow = Gml.var(world, match, :yellowInstance, @noone)
    orange = Gml.var(world, match, :orangeInstance, @noone)

    with %Instance{x: yx, y: yy} <- World.fetch(world, yellow),
         %Instance{x: ox, y: oy} <- World.fetch(world, orange),
         true <- Gml.lt?(abs(yy - oy), @push_height),
         true <- Clash.pushable?(world, yellow) and Clash.pushable?(world, orange),
         true <- Gml.lt?(abs(yx - ox), @push_reach) do
      away = if yx <= ox, do: -@push, else: @push

      world
      |> Gml.put(yellow, %{hspd: Gml.var(world, yellow, :hspd) + away})
      |> Gml.put(orange, %{hspd: Gml.var(world, orange, :hspd) - away})
    else
      _ -> world
    end
  end

  defp kick_doors(world) do
    Enum.reduce(Gml.all(world, "Doorway"), world, fn door, world ->
      if World.fetch(world, door) && Gml.var(world, door, :opening) == @closed,
        do: Enum.reduce(Gml.all(world, "Man"), world, &kick(&2, &1, door)),
        else: world
    end)
  end

  defp kick(world, man, door) do
    %Instance{x: x, vars: vars} = World.fetch(world, man)

    with @high_kick <- Map.get(vars, :state),
         3 <- Gml.round(Map.get(vars, :frame, 0)),
         true <- Overlap.kick?(world, man, door) do
      %Instance{x: door_x, y: door_y} = World.fetch(world, door)

      world
      |> Gml.put(door, %{opening: if(door_x <= x, do: 0, else: 1)})
      |> Sound.play_named(@door_sound, {door_x, door_y})
    else
      _ -> world
    end
  end

  defp turn_around(world, man) do
    if Gml.truthy?(Gml.var(world, man, :turnAroundFlag)),
      do: world |> Gml.put(man, %{turnAroundFlag: 0}) |> Query.face_opponent(man),
      else: world
  end

  defp sudden_death_winner(world, match) do
    if Gml.truthy?(Gml.var(world, match, :sudden_death)) do
      case Gml.all(world, "Man") do
        [man] -> Outcome.winner(world, Gml.var(world, man, :playerIndex))
        [_one, _two] -> collapsed_loser(world)
        _other -> world
      end
    else
      world
    end
  end

  defp collapsed_loser(world) do
    yellow = Gml.first(world, "YellowPlayer")
    orange = Gml.first(world, "OrangePlayer")

    cond do
      yellow != nil and Query.collapsing?(world, yellow) -> Outcome.winner(world, 2)
      orange != nil and Query.collapsing?(world, orange) -> Outcome.winner(world, 1)
      true -> world
    end
  end

  defp finish(world, match) do
    world =
      if Gml.truthy?(Gml.var(world, match, :finished)) and
           Gml.var(world, match, :winner) != 0 and not Gml.exists?(world, "ShowMatchStats"),
         do: Outcome.winner(world, Gml.var(world, match, :winner)),
         else: world

    if Gml.truthy?(Gml.var(world, match, :finished)) do
      timer = Gml.var(world, match, :finishTimer) + 1
      world = Gml.put(world, match, %{finishTimer: timer})

      if timer >= @ending_frames and Gml.exists?(world, "ShowMatchStats"),
        do: Gml.put(world, match, %{matchOver: 1}),
        else: world
    else
      world
    end
  end

  defp lift_out_of_blocks(world) do
    frame = System.get(world, :frame)

    if System.get(world, :flow) != @special_flow and
         Gml.eq?(:math.fmod(frame, @lift_every), 0) and Gml.exists?(world, "Block"),
       do: each_man(world, &lift_out/2),
       else: world
  end

  defp lift_out(world, man) do
    %Instance{x: x, y: y} = World.fetch(world, man)
    block = World.object_index(world, "Block")

    if Collide.meeting?(world, man, {x, y}, block),
      do: lift_out(World.update(world, man, &%{&1 | y: Kernel.floor(y) - 1}), man),
      else: world
  end

  defp remember_places(world) do
    Enum.reduce(["HeldWeapon", "FleshCollisionMask"], world, fn name, world ->
      Enum.reduce(Gml.all(world, name), world, fn id, world ->
        %Instance{x: x, y: y} = World.fetch(world, id)
        Gml.put(world, id, %{previousX: x, previousY: y})
      end)
    end)
  end

  defp room_width(world),
    do: world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size) |> elem(0)
end
