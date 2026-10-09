defmodule Nidhox.Objects.Doors do
  @moduledoc """
  The rooms' swinging doors (`Doorway`, `DoorwayDark`), drawn from the copy's
  `sDoorway`: frame 0 is the door shut, frame 6 edge-on and open, frames 7–12 the door
  swung the other way, back to shut at 12.

  A door rests shut. `swing/2`, each step of a bout, pushes every door that a fencer is
  passing through — within `@reach` pixels of it across, and overlapping it up and down
  — the way the fencer runs, by `@push` of its speed; the door springs back towards
  shut by `@spring` of its swing and loses `@damping` of its speed each step. Its swing
  runs from `-@open` to `@open` frames, shown as the frame at that swing, and as shut
  within `@shut` of it.
  """

  alias Cauldron2D.GameMaker.Instance
  alias Cauldron2D.GameMaker.World

  @open 6
  @shut 0.6
  @reach 10
  @height 32
  @push 0.9
  @spring 0.04
  @damping 0.12

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Doorway_Create_0", &shut/3},
      {"gml_Object_DoorwayDark_Create_0", &shut/3}
    ]
  end

  @doc "`world` with every door swung one step by `bodies` (`Nidhox.Match.bodies/1`)."
  @spec swing(World.t(), [%{position: {number(), number()}, velocity: {number(), number()}}]) ::
          World.t()
  def swing(%World{} = world, bodies) do
    case World.object_index(world, "Doorway") do
      nil ->
        world

      door ->
        world
        |> World.instances_of(door)
        |> Enum.reduce(world, fn id, world -> World.update(world, id, &step(&1, bodies)) end)
    end
  end

  defp shut(world, self, _other),
    do:
      World.update(
        world,
        self,
        &%{
          &1
          | image_speed: 0.0,
            image_index: 0.0,
            vars: Map.merge(&1.vars, %{swing: 0.0, turning: 0.0})
        }
      )

  defp step(%Instance{} = door, bodies) do
    swing = Map.get(door.vars, :swing, 0.0)

    turning =
      Map.get(door.vars, :turning, 0.0) * (1 - @damping) - swing * @spring + push(door, bodies)

    {swing, turning} = stopped(swing + turning, turning)

    %{
      door
      | image_speed: 0.0,
        image_index: frame(swing),
        vars: Map.merge(door.vars, %{swing: swing, turning: turning})
    }
  end

  defp push(%Instance{x: x, y: y}, bodies) do
    bodies
    |> Enum.filter(fn %{position: {bx, by}} ->
      abs(bx - x) < @reach and by > y - @height and by - @height < y
    end)
    |> Enum.map(fn %{velocity: {vx, _vy}} -> vx * @push end)
    |> Enum.sum()
  end

  defp stopped(swing, _turning) when swing > @open, do: {@open / 1, 0.0}
  defp stopped(swing, _turning) when swing < -@open, do: {-@open / 1, 0.0}
  defp stopped(swing, turning), do: {swing, turning}

  defp frame(swing) when abs(swing) < @shut, do: 0.0
  defp frame(swing) when swing >= 0, do: Float.round(swing / 1, 0)
  defp frame(swing), do: Float.round(13 + swing / 1, 0) |> min(12.0)
end
