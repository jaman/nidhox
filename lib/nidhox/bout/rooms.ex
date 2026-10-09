defmodule Nidhox.Bout.Rooms do
  @moduledoc """
  Moving to another room as the game's code asks: the room after or before the current
  one in the game's room order (`room_goto_next`, `room_goto_previous`), or a room by
  name. The change happens at the end of the step (`Cauldron2D.GameMaker.World.goto/2`).
  """

  alias Cauldron2D.GameMaker.{Data, World}

  @doc "The world going to the room after the current one in the room order (`room_goto_next`)."
  @spec next(World.t()) :: World.t()
  def next(%World{} = world), do: by_order(world, 1)

  @doc "The world going to the room before the current one in the room order (`room_goto_previous`)."
  @spec previous(World.t()) :: World.t()
  def previous(%World{} = world), do: by_order(world, -1)

  @doc "The world going to the room named `name` (`room_goto`); unchanged for no such room."
  @spec goto(World.t(), String.t()) :: World.t()
  def goto(%World{} = world, name) do
    case Data.index(world.data, :rooms, name) do
      nil -> world
      room -> World.goto(world, room)
    end
  end

  defp by_order(world, step) do
    order = world.data.general.room_order

    with at when at != nil <- Enum.find_index(order, &(&1 == world.room)),
         room when room != nil <- Enum.at(order, at + step),
         true <- at + step >= 0 do
      World.goto(world, room)
    else
      _none -> world
    end
  end
end
