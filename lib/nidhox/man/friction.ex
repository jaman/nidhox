defmodule Nidhox.Man.Friction do
  @moduledoc """
  `stateFriction(state)`: what a fencer's state does to its speed each step, after the
  state's own behaviour, as the game's code does it.

  | states | each step |
  | --- | --- |
  | evaporate (24), gettingUp (33), standingCollapse (66), 83, duckingCollapse (20) | `hspd` 0 |
  | enteringScreen (23), run (52), runWeaponCocked (54), 80, 81 | run clamp (`clampHorizRunBasedOnWeapon`) |
  | crawl (9) | stair clamp ±1 |
  | slide (58) | friction 0.03, then 0.12 more while climbing stairs, stair clamp ±3.3 |
  | throwingWeapon (72) | friction 0.3 |
  | throwingWeaponMidAir (73) | friction 0.13, run clamp, gravity 0.33 |
  | dizzy (17), hitInFace (38) | friction 0.8 |
  | DiveKickSkid (16), 51 | friction 0.13 |
  | jumpUp (43), crouchJumpUp (11), 22, dropDown (18), crouchDropDown (10), jumpUpWeaponCocked (44), dropDownWeaponCocked (19) | run clamp, gravity 0.33, friction 0.02 |
  | diveKick (14), fallingDead (26), 82 | gravity 0.33 |
  | diveKickOver (15) | gravity 0.33, friction 0.8 |
  | hitUpwards (41), fallingHeadFirst (27), 28 | gravity 0.33, friction 0.02 |
  | fencing (29) | `hspd` held to ±1 while swords touch (`swordCollision`), else ±3; friction 0.1 |
  | 30, 31 | stair clamp ±1 while swords touch (`swordCollision`), else ±3; friction 0.1 |
  | 32 | stair clamp ±3, friction 0.1 |
  | unarmedStance (78) | stair clamp ±2, friction 0.1 |
  | lunging (48) | friction 0.1 |
  | punching (49), 45, secondPunching (55), sweepKick (70), craneStance (7) | friction 0.2 |
  | craneStanceKicking (8) | gravity 0.33, friction 0.1 |
  | stabbedMidAir (64) | gravity 0.0825 |
  | stabbedStanding (65), stabbedDucking (63) | `hspd` held to ±3, friction 0.2 |

  Every other state, trippingForward (77) and trippingBackward (76) among them, leaves
  the speed alone.
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.Gml
  alias Nidhox.Man.{Physics, Stairs}

  @doc "`clampHorizRunBasedOnWeapon` for fencer `self`: stair clamp ±2.9 with fists, ±2.5 otherwise."
  @spec clamp_run(World.t(), non_neg_integer()) :: World.t()
  def clamp_run(%World{} = world, self) do
    limit = if Physics.weapon_type(world, self) == 1, do: 2.9, else: 2.5
    Stairs.clamp(world, self, limit)
  end

  @doc "The world after `stateFriction` for fencer `self` in its current state."
  @spec apply(World.t(), non_neg_integer()) :: World.t()
  def apply(%World{} = world, self), do: friction(world, self, Gml.var(world, self, :state))

  defp friction(world, self, state) when state in [24, 33, 66, 83, 20], do: stop(world, self)

  defp friction(world, self, state) when state in [23, 52, 54, 80, 81],
    do: clamp_run(world, self)

  defp friction(world, self, 9), do: Stairs.clamp(world, self, 1)

  defp friction(world, self, 58) do
    world
    |> Physics.apply_horizontal_friction(self, 0.03)
    |> climbing_friction(self)
    |> Stairs.clamp(self, 3.3)
  end

  defp friction(world, self, 72), do: Physics.apply_horizontal_friction(world, self, 0.3)

  defp friction(world, self, 73) do
    world
    |> Physics.apply_horizontal_friction(self, 0.13)
    |> clamp_run(self)
    |> Physics.apply_gravity(self, 0.33)
  end

  defp friction(world, self, state) when state in [17, 38],
    do: Physics.apply_horizontal_friction(world, self, 0.8)

  defp friction(world, self, state) when state in [16, 51],
    do: Physics.apply_horizontal_friction(world, self, 0.13)

  defp friction(world, self, state) when state in [43, 11, 22, 18, 10, 44, 19] do
    world
    |> clamp_run(self)
    |> Physics.apply_gravity(self, 0.33)
    |> Physics.apply_horizontal_friction(self, 0.02)
  end

  defp friction(world, self, state) when state in [14, 26, 82],
    do: Physics.apply_gravity(world, self, 0.33)

  defp friction(world, self, 15),
    do: world |> Physics.apply_gravity(self, 0.33) |> Physics.apply_horizontal_friction(self, 0.8)

  defp friction(world, self, state) when state in [41, 27, 28],
    do:
      world |> Physics.apply_gravity(self, 0.33) |> Physics.apply_horizontal_friction(self, 0.02)

  defp friction(world, self, 29) do
    limit = if Gml.truthy?(Gml.var(world, self, :swordCollision)), do: 1, else: 3
    world |> hold(self, limit) |> Physics.apply_horizontal_friction(self, 0.1)
  end

  defp friction(world, self, state) when state in [30, 31] do
    limit = if Gml.truthy?(Gml.var(world, self, :swordCollision)), do: 1, else: 3
    world |> Stairs.clamp(self, limit) |> Physics.apply_horizontal_friction(self, 0.1)
  end

  defp friction(world, self, 32),
    do: world |> Stairs.clamp(self, 3) |> Physics.apply_horizontal_friction(self, 0.1)

  defp friction(world, self, 78),
    do: world |> Stairs.clamp(self, 2) |> Physics.apply_horizontal_friction(self, 0.1)

  defp friction(world, self, 48), do: Physics.apply_horizontal_friction(world, self, 0.1)

  defp friction(world, self, state) when state in [49, 45, 55, 70, 7],
    do: Physics.apply_horizontal_friction(world, self, 0.2)

  defp friction(world, self, 8),
    do: world |> Physics.apply_gravity(self, 0.33) |> Physics.apply_horizontal_friction(self, 0.1)

  defp friction(world, self, 64), do: Physics.apply_gravity(world, self, 0.0825)

  defp friction(world, self, state) when state in [65, 63],
    do: world |> hold(self, 3) |> Physics.apply_horizontal_friction(self, 0.2)

  defp friction(world, _self, _state), do: world

  defp climbing_friction(world, self) do
    if Stairs.climbing?(world, self),
      do: Physics.apply_horizontal_friction(world, self, 0.12),
      else: world
  end

  defp stop(world, self), do: Gml.put(world, self, %{hspd: 0})

  defp hold(world, self, limit),
    do: Gml.put(world, self, %{hspd: Gml.clamp(Gml.var(world, self, :hspd), -limit, limit)})
end
