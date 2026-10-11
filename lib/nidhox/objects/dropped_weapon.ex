defmodule Nidhox.Objects.DroppedWeapon do
  @moduledoc """
  The game's `DroppedWeapon`: a sword knocked loose, tumbling under gravity until it
  lands. A `PhysicsObject`, run by the match's frame as user event 2.

    * create: the physics variables, `type` 2, `previousAngle` −1, the sword's sprite
      (153, `pick_droppedWeapon_graphic`)
    * user event 2: the physics begin step; `vspd` eases towards 8 by 0.33; turned by
      `hspd × 20` degrees; the physics end step; gone below the room
    * user event 0 (a wall): pushed 3 pixels back from it and bounced at 0.7 of its speed
    * user event 1 (floor or ceiling): coming down it kicks up dust and comes to rest as a
      `PickupContainer` pointing the way its blade fell; going up it starts to fall
      (`vspd` 1)
    * draw: itself (`draw_self`)
    * leaving the room: gone
  """

  alias Cauldron2D.GameMaker.{Draw, Instance, World}
  alias Nidhox.Gml
  alias Nidhox.Man.{Physics, Weapon}
  alias Nidhox.Objects.Particles

  @sword_sprite 153

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_DroppedWeapon_Create_0", &start/3},
      {"gml_Object_DroppedWeapon_Other_12", &update/3},
      {"gml_Object_DroppedWeapon_Draw_0", fn world, self, _other -> Draw.self(world, self) end},
      {"gml_Object_DroppedWeapon_Other_10", &wall/3},
      {"gml_Object_DroppedWeapon_Other_11", &floor/3},
      {"gml_Object_DroppedWeapon_Other_0", &gone/3}
    ]
  end

  @doc "The world with weapon `self` showing its type's sprite (`pick_droppedWeapon_graphic`)."
  @spec pick_graphic(World.t(), non_neg_integer()) :: World.t()
  def pick_graphic(world, self) do
    if Gml.var(world, self, :type) == 2,
      do: World.update(world, self, &%{&1 | sprite_index: @sword_sprite}),
      else: world
  end

  defp start(world, self, _other) do
    world
    |> World.inherited(self, "DroppedWeapon", :create, 0)
    |> Gml.put(self, %{type: 2, previousAngle: -1})
    |> pick_graphic(self)
  end

  defp update(world, self, _other) do
    world = Physics.begin_step(world, self)
    world = Gml.put(world, self, %{vspd: Gml.approach(Gml.var(world, self, :vspd), 8, 0.33)})
    world = pick_graphic(world, self)
    %Instance{image_angle: angle} = World.fetch(world, self)

    world =
      world
      |> Gml.put(self, %{previousAngle: angle})
      |> World.update(self, &%{&1 | image_angle: angle - Gml.var(world, self, :hspd) * 20})
      |> Physics.end_step(self)

    case World.fetch(world, self) do
      %Instance{y: y} -> if y > room_height(world), do: World.destroy(world, self), else: world
      nil -> world
    end
  end

  defp wall(world, self, _other) do
    hspd = Gml.var(world, self, :hspd)
    away = Gml.clamp(hspd * 100_000, -1, 1)

    world
    |> World.update(self, &%{&1 | x: &1.x - away * 3})
    |> Gml.put(self, %{hspd: -hspd * 0.7})
  end

  defp floor(world, self, _other) do
    if Gml.var(world, self, :vspd) >= -1.0e-5 do
      %Instance{x: x, y: y, image_angle: angle, image_xscale: xscale} = World.fetch(world, self)
      way = if :math.fmod(angle * 1.0, 360.0) - 180 < -1.0e-5, do: 1, else: -1

      world
      |> Particles.dust_at({x, y})
      |> Weapon.spawn_pickup({x, y}, way * xscale)
      |> elem(0)
      |> World.destroy(self)
    else
      Gml.put(world, self, %{vspd: 1})
    end
  end

  defp gone(world, self, _other), do: World.destroy(world, self)

  defp room_height(world),
    do: world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size) |> elem(1)
end
