defmodule Nidhox.Objects.PickupContainer do
  @moduledoc """
  The game's `PickupContainer`: a sword lying on the ground for a fencer to take up
  (`Nidhox.Man.Weapon.try_pickup/2`). A `PhysicsObject`, run by the match's frame as
  user event 2; listed in the match's `pickupContainers` while it lasts.

    * create: the physics variables, `type` 2; a landing clatter (60–63); put out of any
      wall with the lying sword's mask (156); let down until 2 pixels above the ground
      or the room's bottom; `counter` 0, `canGroundMove` 1
    * user event 2: counts on; while it may move with the ground — off the ground it
      falls again as a `DroppedWeapon` unless a slope is within 4 pixels below; on a
      conveyor it rides it half a pixel a step (left on `ConveyorLeft`, right on
      `ConveyorRight`); on a cloud it waits; on anything but a `DefensiveBlock` it stops
      moving with the ground
    * draw: itself (`draw_self`)
    * leaving the room: gone; destroyed: dropped from the match's list
  """

  alias Cauldron2D.GameMaker.{Collide, Draw, Instance, World}
  alias Nidhox.Bout.Sound
  alias Nidhox.Gml
  alias Nidhox.Man.Physics

  @lying_mask 156
  @clatter [60, 61, 62, 63]

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

    world
    |> Sound.play(clatter, {x, y})
    |> World.update(self, &%{&1 | mask_index: @lying_mask})
    |> Physics.force_out(self)
    |> World.update(self, &%{&1 | mask_index: mask})
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

    if Gml.truthy?(Gml.var(world, self, :canGroundMove)),
      do: move_with_ground(world, self),
      else: world
  end

  defp move_with_ground(world, self) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    below = {x, y + 1}

    cond do
      not under?(world, below, "Block") -> fall(world, self, {x, y})
      under?(world, below, "ConveyorLeft") -> World.update(world, self, &%{&1 | x: &1.x - 0.5})
      under?(world, below, "ConveyorRight") -> World.update(world, self, &%{&1 | x: &1.x + 0.5})
      under?(world, below, "NewCloudBlock") -> world
      not under?(world, below, "DefensiveBlock") -> Gml.put(world, self, %{canGroundMove: 0})
      true -> world
    end
  end

  defp fall(world, self, {x, y}) do
    if meeting?(world, self, {x, y + 4}, "Slope") do
      world
    else
      {world, _dropped} = World.create(world, World.object_index(world, "DroppedWeapon"), {x, y})
      World.destroy(world, self)
    end
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
end
