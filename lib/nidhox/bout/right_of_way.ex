defmodule Nidhox.Bout.RightOfWay do
  @moduledoc """
  Who may run where, as the game's scripts hold the fencers to the screen. The fencer
  with the right of way (`Match.leadingPlayerIndex`) runs on to the next room; the other
  dies left behind; neither may otherwise leave the camera's view.

    * `manage/2` (`manageRightOfWay`): when the right of way changes hands,
      `change_animation` 30 and `wrongWay`, `wrongWayCounter` 0; `change_animation`
      counts down to 0. Each step the leader moves back towards its own side
      `wrongWayCounter` counts, and it is cleared (with `wrongWay`) when the leader
      moves on; past 100 the leader is going the wrong way (`wrongWay` 1). Then every
      fencer is held to the screen (`hold/3`)
    * `stay_in_view/2` (`stayInView`): a fencer not entering (23) is held to the screen
    * `hold/3`: the screen's edge advanced past (`activateScreenAdvance`), the side
      that means death (`whichSideMeansDeath`, `activateKillzone`), and the left and
      right barriers (`whereIsMyLeftBarrier`, `whereIsMyRightBarrier`,
      `activateLeftBarrier`, `activateRightBarrier`)
    * `fell_off/2` (`checkFellOffCamera`): a fencer 32 pixels below the room is gone —
      when it led, the other player leads (nobody when it was alone); unless it was
      already collapsing or stabbed it counts as a suicide (`MatchStats.suicides`); it
      is heard (8), the spawn timer starts again from `spawnDelay`, and it is destroyed

  The screen's edge: outside sudden death, the leader past the room's right edge
  (player 1) or left edge (player 2) — neither collapsing nor stabbed — takes the bout
  on: the spawn timer is 60, it keeps the right of way, the screen wipes
  (`roomAdvanceTransition`) and the next or previous room follows. In sudden death
  every fencer is kept inside the room.

  Death's side: nobody leading, none; the leader, none; the other, the side behind the
  leader — left when player 1 leads, right when player 2 does. A fencer not entering
  that is more than 16 pixels past that edge of the view is heard (8), the spawn timer
  starts again at 40, and it is destroyed.

  The barriers, by leader and player:

  | leader | player | left | right |
  | --- | --- | --- | --- |
  | none | either | view left + 8 | view right − 8 |
  | 1 | 1 | view left + 8, or − 1000 alone | view right + 1000 |
  | 1 | 2 | the greater of 8 and view left − 1000 | view right − 8 |
  | 2 | 2 | view left − 1000 | view right − 8, or + 1000 alone |
  | 2 | 1 | view left + 8 | the lesser of room width − 8 and view right + 1000 |

  A fencer past a barrier is put on it and stops across (`hspd` 0).
  """

  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Bout.{Camera, PlayerColour, Rooms, Sound, Spawn}
  alias Nidhox.Gml
  alias Nidhox.Man.Query
  alias Nidhox.Objects.{MatchStats, Transition}

  @entering 23
  @change_animation 30
  @wrong_way_after 100
  @advance_delay 60
  @killzone_margin 16
  @killzone_delay 40
  @fell_below 32
  @death_sound 8
  @inside 8
  @far 1000

  @doc "The world after the match `match` holds the fencers to the screen (`manageRightOfWay`)."
  @spec manage(World.t(), non_neg_integer()) :: World.t()
  def manage(%World{} = world, match) do
    world = world |> changed_hands(match) |> wrong_way(match)
    Enum.reduce(Gml.all(world, "Man"), world, &if(World.fetch(&2, &1), do: hold(&2, &1, match), else: &2))
  end

  @doc "The world with fencer `man` held to the screen unless it is entering (`stayInView`)."
  @spec stay_in_view(World.t(), non_neg_integer(), non_neg_integer()) :: World.t()
  def stay_in_view(%World{} = world, man, match) do
    if Gml.var(world, man, :state) == @entering, do: world, else: hold(world, man, match)
  end

  @doc "The world with fencer `man` held to the screen's edges, death side and barriers."
  @spec hold(World.t(), non_neg_integer(), non_neg_integer()) :: World.t()
  def hold(%World{} = world, man, match) do
    leader = Gml.var(world, match, :leadingPlayerIndex)
    player = Gml.var(world, man, :playerIndex)

    world
    |> screen_advance(man, match, player, leader)
    |> while_here(man, &killzone(&1, man, death_side(player, leader)))
    |> while_here(man, &left_barrier(&1, man, left_edge(&1, player, leader)))
    |> while_here(man, &right_barrier(&1, man, right_edge(&1, player, leader)))
  end

  @doc "The world after fencer `man` is checked for falling out of the room (`checkFellOffCamera`)."
  @spec fell_off(World.t(), non_neg_integer(), non_neg_integer()) :: World.t()
  def fell_off(%World{} = world, man, match) do
    %Instance{x: x, y: y} = World.fetch(world, man)

    if y > room_height(world) + @fell_below do
      player = Gml.var(world, man, :playerIndex)

      world
      |> hand_over(match, player)
      |> count_suicide(man, player)
      |> Sound.play(@death_sound, {x, y})
      |> Spawn.reset_timer(Gml.var(world, match, :spawnDelay))
      |> World.destroy(man)
    else
      world
    end
  end

  @doc "The side of the screen that kills `player` while `leader` leads (`whichSideMeansDeath`)."
  @spec death_side(integer(), integer()) :: :neither | :left | :right
  def death_side(1, 1), do: :neither
  def death_side(_player, 1), do: :left
  def death_side(2, 2), do: :neither
  def death_side(_player, 2), do: :right
  def death_side(_player, _leader), do: :neither

  defp changed_hands(world, match) do
    leader = Gml.var(world, match, :leadingPlayerIndex)

    world =
      if Gml.var(world, match, :previouslyLeadingPlayerIndex) != leader,
        do: Gml.put(world, match, %{change_animation: @change_animation, wrongWay: 0, wrongWayCounter: 0}),
        else: world

    world = Gml.put(world, match, %{previouslyLeadingPlayerIndex: leader})
    change = Gml.var(world, match, :change_animation)
    if change > 0, do: Gml.put(world, match, %{change_animation: change - 1}), else: world
  end

  defp wrong_way(world, match) do
    world =
      case Gml.var(world, match, :leadingPlayerIndex) do
        1 -> leader_moved(world, match, Gml.var(world, match, :yellowInstance, -4), 1)
        2 -> leader_moved(world, match, Gml.var(world, match, :orangeInstance, -4), -1)
        _nobody -> world
      end

    if Gml.var(world, match, :wrongWayCounter) > @wrong_way_after,
      do: Gml.put(world, match, %{wrongWay: 1}),
      else: world
  end

  defp leader_moved(world, match, man, forward) do
    case World.fetch(world, man) do
      %Instance{x: x, vars: vars} when man > 0 ->
        moved = x - Map.get(vars, :previousX, x)

        cond do
          moved * forward < 0 -> Gml.put(world, match, %{wrongWayCounter: Gml.var(world, match, :wrongWayCounter) + 1})
          moved * forward > 0 -> Gml.put(world, match, %{wrongWayCounter: 0, wrongWay: 0})
          true -> world
        end

      _gone ->
        world
    end
  end

  defp screen_advance(world, man, match, player, leader) do
    cond do
      Query.collapsing?(world, man) or Query.stabbed?(world, man) -> world
      Gml.truthy?(Gml.var(world, match, :sudden_death)) -> keep_in_room(world, man)
      player == leader -> advance(world, man, match, leader)
      true -> world
    end
  end

  defp keep_in_room(world, man) do
    width = room_width(world)
    World.update(world, man, &%{&1 | x: &1.x |> min(width) |> max(0)})
  end

  defp advance(world, man, match, 1) do
    if World.fetch(world, man).x > room_width(world),
      do: world |> advanced(man, match) |> Rooms.next(),
      else: world
  end

  defp advance(world, man, match, 2) do
    if World.fetch(world, man).x < 0,
      do: world |> advanced(man, match) |> Rooms.previous(),
      else: world
  end

  defp advance(world, _man, _match, _leader), do: world

  defp advanced(world, man, match) do
    world
    |> Spawn.reset_timer(@advance_delay)
    |> Gml.put(match, %{leadingPlayerIndex: Gml.var(world, man, :playerIndex)})
    |> room_advance_transition(match)
  end

  defp room_advance_transition(world, match) do
    leader = Gml.var(world, match, :leadingPlayerIndex)
    {wipe, world} = Transition.start(world, if(leader == 2, do: 1, else: 0))
    {colour, world} = PlayerColour.of_player(world, leader)
    World.update(world, wipe, &%{&1 | image_blend: colour})
  end

  defp killzone(world, man, side) do
    %Instance{x: x, y: y, vars: vars} = World.fetch(world, man)

    if Map.get(vars, :state) != @entering and past?(world, x, side) do
      world
      |> Sound.play(@death_sound, {x, y})
      |> Spawn.reset_timer(@killzone_delay)
      |> World.destroy(man)
    else
      world
    end
  end

  defp past?(world, x, :right), do: x > Camera.right(world) + @killzone_margin
  defp past?(world, x, :left), do: x < Camera.left(world) - @killzone_margin
  defp past?(_world, _x, :neither), do: false

  defp left_edge(world, 1, 1), do: if(alone?(world), do: Camera.left(world) - @far, else: Camera.left(world) + @inside)
  defp left_edge(world, _player, 1), do: max(@inside, Camera.left(world) - @far)
  defp left_edge(world, 2, 2), do: Camera.left(world) - @far
  defp left_edge(world, _player, _leader), do: Camera.left(world) + @inside

  defp right_edge(world, 1, 1), do: Camera.right(world) + @far
  defp right_edge(world, 2, 2), do: if(alone?(world), do: Camera.right(world) + @far, else: Camera.right(world) - @inside)
  defp right_edge(world, _player, 2), do: min(room_width(world) - @inside, Camera.right(world) + @far)
  defp right_edge(world, _player, _leader), do: Camera.right(world) - @inside

  defp left_barrier(world, man, barrier) do
    if World.fetch(world, man).x < barrier,
      do: world |> World.update(man, &%{&1 | x: barrier}) |> Gml.put(man, %{hspd: 0}),
      else: world
  end

  defp right_barrier(world, man, barrier) do
    if World.fetch(world, man).x > barrier,
      do: world |> World.update(man, &%{&1 | x: barrier}) |> Gml.put(man, %{hspd: 0}),
      else: world
  end

  defp alone?(world), do: length(Gml.all(world, "Man")) == 1

  defp hand_over(world, match, player) do
    if Gml.var(world, match, :leadingPlayerIndex) == player do
      world = Gml.put(world, match, %{leadingPlayerIndex: Query.other_player(player)})
      if alone?(world), do: Gml.put(world, match, %{leadingPlayerIndex: 0}), else: world
    else
      world
    end
  end

  defp count_suicide(world, man, player) do
    if Query.collapsing?(world, man) or Query.stabbed?(world, man),
      do: world,
      else: MatchStats.add_suicide(world, player)
  end

  defp while_here(world, man, fun), do: if(World.fetch(world, man), do: fun.(world), else: world)

  defp room_width(world), do: world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size) |> elem(0)
  defp room_height(world), do: world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size) |> elem(1)
end
