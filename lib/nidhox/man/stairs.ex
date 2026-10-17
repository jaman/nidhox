defmodule Nidhox.Man.Stairs do
  @moduledoc """
  What a fencer's stairs are: `Stairs` instances laid one after another, each as wide
  and as high as the mask of its `mask_index` (or `sprite_index`), rising to the right
  when its `image_xscale` is positive and to the left when it is negative.

    * `dir/2` (`stairDir`): 1 for a stair that rises to the right, -1 for one that
      rises to the left
    * `ratio/2` (`stairRatio`): the stair's mask height over its width
    * `slope/2` (`stairSlope`): `-dir × ratio`
    * `near/2` (`stairsNear`): the first stair whose mask meets the box from 5 pixels
      left to 5 pixels right of fencer `man` and from its feet to 6 pixels below them
    * `facing_up?/3` (`facingUpStairs`): whether fencer `man` faces the way stair
      `stairs` rises
    * `under/2` (`stairsUnder`): the stair `near/2` finds, once the run of stairs
      continuing from it (at most 64 stairs, down the stairs when `man` faces away from
      the way they rise, up them when it faces that way) ends no more than 2 pixels
      from `man`'s feet; `nil` for none
    * `on?/2` (`isOnStairs`): whether `under/2` finds stairs for fencer `man`
    * `feet/2` (`feetOnStairs`): the first stair whose mask meets the box from 1 pixel
      left to 1 pixel right of fencer `man` and from its feet to 6 pixels below them
    * `climbing?/2` (`climbingStairs`): whether `feet/2` finds a stair and fencer `man`
      moves the way it rises
    * `clamp/3` (`stairClamp`): fencer `man`'s `hspd` held to `±limit`; climbing, one
      above 0.8 × `limit` first eases towards it by 0.35
    * `hand_rise/2` (`stairHandRise`): how far fencer `man`'s weapon stands above where
      it would on the level, `slope × (weapon.x - man.x)`, 0 off the stairs
    * `hold_sword/3` (`holdSwordAlongStairs`): sets fencer `man`'s `stairYModifier` to the
      width of `sSword` × the ratio of stair `stairs`, negative when `man` faces the way
      the stair rises, positive when it faces away
    * `fencing_state/2` (`fencingStateHere`): the fencing state for fencer `man`: 29, 30 or 31
    * `run_state/2` (`runStateHere`): the run state for fencer `man`: 52, 80 or 81
    * `ground/2` (`groundOnStairs`): lifts fencer `man` out of blocks and lowers it to the ground
      when a stair is within 5 pixels sideways and 48 pixels up or down
  """

  alias Cauldron2D.GameMaker.{Collide, Data, Instance, World}
  alias Cauldron2D.Overlap
  alias Nidhox.Gml
  alias Nidhox.Man.{Physics, Query}

  @reach 64
  @side 5
  @below 6
  @close 2
  @sword_sprite "sSword"
  @ground_reach 48

  @doc "Stair `stairs`'s direction: 1 rising to the right, -1 rising to the left."
  @spec dir(World.t(), non_neg_integer()) :: 1 | -1
  def dir(%World{} = world, stairs) do
    if World.fetch(world, stairs).image_xscale < 0, do: -1, else: 1
  end

  @doc "Stair `stairs`'s mask height over its mask width."
  @spec ratio(World.t(), non_neg_integer()) :: float()
  def ratio(%World{} = world, stairs) do
    {width, height} = size(world, stairs)
    height / width
  end

  @doc "Stair `stairs`'s slope: its ratio, negative when it rises to the right."
  @spec slope(World.t(), non_neg_integer()) :: float()
  def slope(%World{} = world, stairs), do: -dir(world, stairs) * ratio(world, stairs)

  @doc "The first stair meeting the box around fencer `man`'s feet, `nil` for none."
  @spec near(World.t(), non_neg_integer()) :: non_neg_integer() | nil
  def near(%World{} = world, man) do
    %Instance{x: x, y: y} = World.fetch(world, man)
    first_meeting(world, {x - @side, y, x + @side, y + @below})
  end

  @doc "Whether fencer `man` faces the way stair `stairs` rises."
  @spec facing_up?(World.t(), non_neg_integer(), non_neg_integer()) :: boolean()
  def facing_up?(%World{} = world, man, stairs),
    do: Gml.eq?(Gml.var(world, man, :facingXScale), dir(world, stairs))

  @doc "The stairs fencer `man` stands on, `nil` for none."
  @spec under(World.t(), non_neg_integer()) :: non_neg_integer() | nil
  def under(%World{} = world, man) do
    with near when near != nil <- near(world, man),
         object = World.object_index(world, "Stairs"),
         %Instance{y: feet} <- World.fetch(world, man) do
      up? = facing_up?(world, man, near)
      end_of_run = run_end(world, near, object, up?)
      if gap(world, end_of_run, feet, up?) <= @close, do: nil, else: near
    end
  end

  @doc "Whether fencer `man` stands on stairs."
  @spec on?(World.t(), non_neg_integer()) :: boolean()
  def on?(%World{} = world, man) do
    World.fetch(world, man) != nil and under(world, man) != nil
  end

  @doc "The first stair whose mask meets the box under fencer `man`'s feet, `nil` for none."
  @spec feet(World.t(), non_neg_integer()) :: non_neg_integer() | nil
  def feet(%World{} = world, man) do
    %Instance{x: x, y: y} = World.fetch(world, man)
    first_meeting(world, {x - 1, y, x + 1, y + @below})
  end

  @doc "Whether fencer `man` moves up the stair under its feet."
  @spec climbing?(World.t(), non_neg_integer()) :: boolean()
  def climbing?(%World{} = world, man) do
    hspd = Gml.var(world, man, :hspd)

    case feet(world, man) do
      nil -> false
      stairs -> hspd != 0 and Gml.sign(hspd) == dir(world, stairs)
    end
  end

  @doc "The world with fencer `man`'s `hspd` held to `±limit`, eased first while climbing."
  @spec clamp(World.t(), non_neg_integer(), number()) :: World.t()
  def clamp(%World{} = world, man, limit) do
    world = ease_climb(world, man, limit * 0.8)
    Gml.put(world, man, %{hspd: Gml.clamp(Gml.var(world, man, :hspd), -limit, limit)})
  end

  @doc "How far above the level fencer `man`'s weapon stands because of the stairs under it."
  @spec hand_rise(World.t(), non_neg_integer()) :: number()
  def hand_rise(%World{} = world, man) do
    case under(world, man) do
      nil ->
        0

      stairs ->
        weapon = Gml.var(world, man, :weapon)
        slope(world, stairs) * (World.fetch(world, weapon).x - World.fetch(world, man).x)
    end
  end

  @doc "The world with fencer `man`'s `stairYModifier` set to hold its sword along stair `stairs`."
  @spec hold_sword(World.t(), non_neg_integer(), non_neg_integer()) :: World.t()
  def hold_sword(%World{} = world, man, stairs) do
    direction = if facing_up?(world, man, stairs), do: 1, else: -1
    {width, _height} = World.sprite(world, Data.index(world.data, :sprites, @sword_sprite)).size
    Gml.put(world, man, %{stairYModifier: -direction * width * ratio(world, stairs)})
  end

  @doc "`fencingStateHere` for fencer `man`: 29 off the stairs, else 31 when it faces the way the stairs rise and 30 when it faces away. It faces its opponent unless that one is collapsing or stands at the same x."
  @spec fencing_state(World.t(), non_neg_integer()) :: 29 | 30 | 31
  def fencing_state(%World{} = world, man) do
    case under(world, man) do
      nil -> 29
      stairs -> if Gml.eq?(facing_opponent(world, man), dir(world, stairs)), do: 31, else: 30
    end
  end

  @doc "`runStateHere` for fencer `man`: 52 off the stairs, else 80 when it moves (or faces, standing still) the way the stairs rise and 81 when it does not."
  @spec run_state(World.t(), non_neg_integer()) :: 52 | 80 | 81
  def run_state(%World{} = world, man) do
    case under(world, man) do
      nil ->
        52

      stairs ->
        hspd = Gml.var(world, man, :hspd)

        heading =
          if Gml.eq?(hspd, 0), do: Gml.var(world, man, :facingXScale), else: Gml.sign(hspd)

        if Gml.eq?(heading, dir(world, stairs)), do: 80, else: 81
    end
  end

  @doc "`groundOnStairs` for fencer `man`: `{found, world}`. With a stair in the 10 by 96 box centred on `man`, `man` is lifted out of blocks and lowered to the ground, at most 48 pixels each way."
  @spec ground(World.t(), non_neg_integer()) :: {boolean(), World.t()}
  def ground(%World{} = world, man) do
    %Instance{x: x, y: y} = World.fetch(world, man)

    case first_meeting(world, {x - 5, y - 48, x + 5, y + 48}) do
      nil -> {false, world}
      _stairs -> {true, world |> lift(man, @ground_reach) |> lower(man, @ground_reach)}
    end
  end

  defp facing_opponent(world, man) do
    facing = Gml.var(world, man, :facingXScale)

    with other when other != nil <- Query.opponent(world, man),
         false <- Query.collapsing?(world, other),
         %Instance{x: other_x} <- World.fetch(world, other),
         %Instance{x: x} <- World.fetch(world, man),
         true <- other_x != x do
      Gml.sign(other_x - x)
    else
      _ -> facing
    end
  end

  defp lift(world, _man, 0), do: world

  defp lift(world, man, left) do
    %Instance{x: x, y: y} = World.fetch(world, man)

    if blocked?(world, man, {x, y}) do
      world |> World.update(man, &%{&1 | y: &1.y - 1}) |> lift(man, left - 1)
    else
      world
    end
  end

  defp lower(world, _man, 0), do: world

  defp lower(world, man, left) do
    if Physics.check_below?(world, man),
      do: world,
      else: world |> World.update(man, &%{&1 | y: &1.y + 1}) |> lower(man, left - 1)
  end

  defp blocked?(world, man, position) do
    case World.object_index(world, "Block") do
      nil -> false
      object -> Collide.meeting?(world, man, position, object)
    end
  end

  defp ease_climb(world, man, ceiling) do
    hspd = Gml.var(world, man, :hspd)

    if climbing?(world, man) and abs(hspd) > ceiling,
      do: Gml.put(world, man, %{hspd: Gml.approach(hspd, Gml.sign(hspd) * ceiling, 0.35)}),
      else: world
  end

  defp first_meeting(world, box) do
    with object when is_integer(object) <- World.object_index(world, "Stairs") do
      world
      |> World.instances_of(object)
      |> Enum.find(&meets?(world, &1, box))
    end
  end

  defp run_end(world, stairs, object, up?) do
    Enum.reduce_while(1..@reach, stairs, fn _count, current ->
      case Collide.at_point(world, next_point(world, current, up?), object) do
        nil -> {:halt, current}
        following -> {:cont, following}
      end
    end)
  end

  defp next_point(world, current, up?) do
    %Instance{x: x, y: y} = World.fetch(world, current)
    {width, height} = size(world, current)
    rising = dir(world, current)

    cond do
      up? and rising > 0 -> {x + width, y - 1}
      up? -> {x - width - 1, y - 1}
      rising > 0 -> {x - 1, y + height}
      true -> {x, y + height}
    end
  end

  defp gap(world, last, feet, true), do: feet - World.fetch(world, last).y

  defp gap(world, last, feet, false) do
    {_width, height} = size(world, last)
    World.fetch(world, last).y + height - feet
  end

  defp meets?(world, stairs, box) do
    instance = World.fetch(world, stairs)

    case Collide.shape(world, instance, {instance.x, instance.y}) do
      nil -> false
      shape -> Overlap.rectangle?(shape, box)
    end
  end

  defp size(world, stairs) do
    %Instance{mask_index: mask, sprite_index: sprite} = World.fetch(world, stairs)
    World.sprite(world, if(mask >= 0, do: mask, else: sprite)).size
  end
end
