defmodule Nidhox.Objects.PickupContainer do
  @moduledoc """
  The game's `PickupContainer`: a sword lying on the ground for a fencer to take up
  (`Nidhox.Man.Weapon.try_pickup/2`). A `PhysicsObject`, run by the match's frame as
  user event 2; listed in the match's `pickupContainers` while it lasts.

    * create: the physics variables, `type` 2; a landing clatter (`sfxSwordHitGround1` to
      `4`); put out of any wall with the lying sword's mask (`sWidePickup`), keeping its
      height; let down until 2 pixels above the ground or the room's bottom; `counter` 0,
      `canGroundMove` 1
    * user event 2: counts on; while it may move with the ground — off the ground it
      falls again as a `DroppedWeapon` unless a `Slope` meets the box from 1 pixel left of it
      to 1 pixel right and from its height to 4 pixels below; resting on a block with no ground under its
      middle 2 pixels down, it slides a pixel a step away from the block edge it leans
      on; on a conveyor it rides it half a pixel a step (left on `ConveyorLeft`, right on
      `ConveyorRight`); on a cloud it waits; on anything but a `DefensiveBlock` it stops
      moving with the ground; gone once more than 64 pixels left of, right of or below
      the room
    * draw: itself (`draw_self`)
    * leaving the room: gone; destroyed: dropped from the match's list
  """

  alias Cauldron2D.GameMaker.{Collide, Data, Draw, Instance, World}
  alias Cauldron2D.Overlap
  alias Nidhox.Bout.Sound
  alias Nidhox.Gml
  alias Nidhox.Man.Physics

  @lying_mask "sWidePickup"
  @clatter [
    "sfxSwordHitGround1",
    "sfxSwordHitGround2",
    "sfxSwordHitGround3",
    "sfxSwordHitGround4"
  ]
  @room_margin 64

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_PickupContainer_Create_0", &start/3},
      {"gml_Object_PickupContainer_Other_12", &update/3},
      {"gml_Object_PickupContainer_Draw_0", fn world, self, _other -> Draw.self(world, self) end},
      {"gml_Object_PickupContainer_Other_0", &gone/3},
      {"gml_Object_PickupContainer_Destroy_0", &finish/3}
    ]
  end

  defp start(world, self, _other) do
    world =
      world |> World.inherited(self, "PickupContainer", :create, 0) |> Gml.put(self, %{type: 2})

    {clatter, world} = Gml.choose(world, @clatter)
    %Instance{x: x, y: y, mask_index: mask} = World.fetch(world, self)
    lying = Data.index(world.data, :sprites, @lying_mask)

    world
    |> Sound.play_named(clatter, {x, y})
    |> World.update(self, &%{&1 | mask_index: lying})
    |> Physics.force_out(self)
    |> World.update(self, &%{&1 | y: y, mask_index: mask})
    |> settle(self)
    |> Gml.put(self, %{counter: 0, canGroundMove: 1})
    |> listed(self)
  end

  defp settle(world, self) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    if meeting?(world, self, {x, y + 2}, "Block") or y >= room_height(world),
      do: world,
      else: world |> World.update(self, &%{&1 | y: &1.y + 1}) |> settle(self)
  end

  defp listed(world, self) do
    case match(world) do
      nil ->
        world

      match ->
        Gml.put(world, match, %{
          pickupContainers: Gml.var(world, match, :pickupContainers, []) ++ [self]
        })
    end
  end

  defp update(world, self, _other) do
    world = Gml.put(world, self, %{counter: Gml.var(world, self, :counter) + 1})

    world =
      if Gml.truthy?(Gml.var(world, self, :canGroundMove)),
        do: move_with_ground(world, self),
        else: world

    case World.fetch(world, self) do
      %Instance{} = container ->
        if outside_room?(world, container), do: World.destroy(world, self), else: world

      nil ->
        world
    end
  end

  defp move_with_ground(world, self) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    below = {x, y + 1}

    cond do
      not under?(world, below, "Block") -> off_ground(world, self, {x, y})
      under?(world, below, "ConveyorLeft") -> World.update(world, self, &%{&1 | x: &1.x - 0.5})
      under?(world, below, "ConveyorRight") -> World.update(world, self, &%{&1 | x: &1.x + 0.5})
      under?(world, below, "NewCloudBlock") -> world
      not under?(world, below, "DefensiveBlock") -> Gml.put(world, self, %{canGroundMove: 0})
      true -> world
    end
  end

  defp off_ground(world, self, {x, y}) do
    cond do
      slope_below?(world, {x, y}) ->
        world

      meeting?(world, self, {x, y + 1}, "Block") and not under?(world, {x, y + 2}, "Block") ->
        slide = if under?(world, {x + 1, y + 1}, "Block"), do: -1, else: 1
        World.update(world, self, &%{&1 | x: &1.x + slide})

      true ->
        fall(world, self, {x, y})
    end
  end

  defp slope_below?(world, {x, y}) do
    case World.object_index(world, "Slope") do
      nil ->
        false

      slope ->
        world
        |> World.instances_of(slope)
        |> Enum.any?(&crosses?(world, &1, {x - 1, y, x + 1, y + 4}))
    end
  end

  defp crosses?(world, slope, box) do
    instance = World.fetch(world, slope)

    case Collide.shape(world, instance, {instance.x, instance.y}) do
      nil -> false
      shape -> Overlap.rectangle?(shape, box)
    end
  end

  defp fall(world, self, {x, y}) do
    {world, _dropped} = World.create(world, World.object_index(world, "DroppedWeapon"), {x, y})
    World.destroy(world, self)
  end

  defp gone(world, self, _other), do: World.destroy(world, self)

  defp finish(world, self, _other) do
    case match(world) do
      nil ->
        world

      match ->
        Gml.put(world, match, %{
          pickupContainers: List.delete(Gml.var(world, match, :pickupContainers, []), self)
        })
    end
  end

  defp match(world) do
    with object when is_integer(object) <- World.object_index(world, "Match"),
         [match | _] <- World.instances_of(world, object) do
      match
    else
      _none -> nil
    end
  end

  defp under?(world, point, name) do
    case World.object_index(world, name) do
      nil -> false
      object -> Collide.at_point(world, point, object) != nil
    end
  end

  defp meeting?(world, self, position, name) do
    case World.object_index(world, name) do
      nil -> false
      object -> Collide.meeting?(world, self, position, object)
    end
  end

  defp room_height(world),
    do: world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size) |> elem(1)

  defp outside_room?(world, %Instance{x: x, y: y}) do
    {width, height} = world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size)
    x < -@room_margin or x > width + @room_margin or y > height + @room_margin
  end
end
