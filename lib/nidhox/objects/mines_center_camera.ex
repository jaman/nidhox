defmodule Nidhox.Objects.MinesCenterCamera do
  @moduledoc """
  The game's `MinesCenterCamera`, in the mines' tall centre room: each step and each
  user event 2, the camera's centre is put at the top of the room's first view plus half
  the camera's height plus 5 pixels for every `System.frame`, and not below half the
  camera's height above the room's bottom (`setCameraCenterY`).

  The game pauses the step while a pause menu is up. NidhOX pauses by not stepping the
  world, so the step never meets a pause.
  """

  alias Nidhox.Bout.Camera
  alias Nidhox.Objects.System

  @pan_step 5

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_MinesCenterCamera_Step_0", &pan/3},
      {"gml_Object_MinesCenterCamera_Other_12", &pan/3}
    ]
  end

  defp pan(world, _self, _other) do
    half = Camera.height(world) / 2
    start = first_view_top(world) + half
    finish = room_height(world) - half
    Camera.put_center_y(world, min(start + @pan_step * System.get(world, :frame), finish))
  end

  defp first_view_top(world) do
    case world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:views) do
      [%{view: {_x, y, _width, _height}} | _] -> y
      [] -> 0
    end
  end

  defp room_height(world),
    do: world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size) |> elem(1)
end
