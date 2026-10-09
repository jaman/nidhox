defmodule Nidhox.Objects.MinesCenterCamera do
  @moduledoc """
  The game's `MinesCenterCamera`, in the mines' tall centre room: in a match's first
  frames (`System.frame` under 3) the camera pans down (`pan`) 5 pixels a step until its
  bottom reaches the room's; arriving later, the camera's centre is put at once half
  the view's height above the room's bottom.
  """

  alias Nidhox.Bout.Camera
  alias Nidhox.Gml
  alias Nidhox.Objects.System

  @pan_step 5
  @first_frames 3

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_MinesCenterCamera_Create_0", &start/3},
      {"gml_Object_MinesCenterCamera_Step_0", &pan/3}
    ]
  end

  defp start(world, self, _other) do
    if System.get(world, :frame) < @first_frames,
      do: Gml.put(world, self, %{pan: 1}),
      else: world |> Gml.put(self, %{pan: 0}) |> Camera.put_center_y(bottom_centre(world))
  end

  defp pan(world, self, _other) do
    if Gml.truthy?(Gml.var(world, self, :pan)) and Camera.bottom(world) < room_height(world),
      do: Camera.put_center_y(world, min(bottom_centre(world), Camera.center_y(world) + @pan_step)),
      else: world
  end

  defp bottom_centre(world), do: room_height(world) - Camera.height(world) / 2

  defp room_height(world), do: world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size) |> elem(1)
end
