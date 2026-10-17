defmodule Nidhox.Objects.Lobby do
  @moduledoc """
  The online lobby's own objects, in `rOnlineLobby`, a match room whose centre wall
  keeps the two fencers apart:

    * `OnlineLobby`: create, `depth` 200 and `hold` 0; step, while the lobby flow runs
      (`System.netFlowKind` 1), `hold` counts the steps in a row that every `ReadyZone`
      is occupied, else goes back to 0, and at 60 the lobby flow ends
      (`System.netFlowClose` 1, which `Nidhox.Flow` acts on); draw, every `Block` filled
      in `make_color_hsv(0, 0, 20)`
    * `ReadyZone`: create, `playerIndex` 2 when it is right of the room's middle, else 1,
      `occupied` false, `depth` 150; end step, `occupied` while that player's fencer
      (`findManByPlayerIndex`) touches it, and every `Torch` within 64 across of its
      middle and 32 of its bottom lit while it is occupied; draw, a strip along its
      bottom in the player's colour and the `sprLight` lamp 46 above its bottom, green
      (70, 230, 70) when occupied, else red (230, 50, 50)
  """

  alias Cauldron2D.GameMaker.{Collide, Colour, Data, Draw, Instance, World}
  alias Cauldron2D.Shape
  alias Nidhox.Bout.PlayerColour
  alias Nidhox.Gml
  alias Nidhox.Man.Query
  alias Nidhox.Objects.System

  @lobby_depth 200
  @zone_depth 150
  @ready_steps 60
  @lobby_flow 1
  @lit_across 64
  @lit_below 32
  @lamp_rise 46
  @ready_colour {70, 230, 70}
  @waiting_colour {230, 50, 50}

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_OnlineLobby_Create_0", &lobby_create/3},
      {"gml_Object_OnlineLobby_Step_0", &lobby_step/3},
      {"gml_Object_OnlineLobby_Draw_0", &lobby_draw/3},
      {"gml_Object_ReadyZone_Create_0", &zone_create/3},
      {"gml_Object_ReadyZone_Step_2", &zone_step/3},
      {"gml_Object_ReadyZone_Draw_0", &zone_draw/3}
    ]
  end

  defp lobby_create(world, self, _other) do
    world
    |> World.update(self, &%{&1 | depth: @lobby_depth})
    |> Gml.put(self, %{hold: 0})
  end

  defp lobby_step(world, self, _other) do
    if System.get(world, :netFlowKind, 0) == @lobby_flow,
      do: held(world, self, all_in?(world)),
      else: world
  end

  defp all_in?(world) do
    case Gml.all(world, "ReadyZone") do
      [] -> false
      zones -> Enum.all?(zones, &Gml.truthy?(Gml.var(world, &1, :occupied, false)))
    end
  end

  defp held(world, self, false), do: Gml.put(world, self, %{hold: 0})

  defp held(world, self, true) do
    hold = Gml.var(world, self, :hold, 0) + 1
    world = Gml.put(world, self, %{hold: hold})
    if hold == @ready_steps, do: System.put(world, %{netFlowClose: 1}), else: world
  end

  defp lobby_draw(world, _self, _other) do
    colour = Colour.hsv(0, 0, 20)

    world
    |> Gml.all("Block")
    |> Enum.reduce(world, fn block, world ->
      Draw.rectangle(world, bounds(world, block), colour)
    end)
  end

  defp zone_create(world, self, _other) do
    %Instance{x: x} = World.fetch(world, self)
    {room_width, _height} = Enum.at(world.data.rooms, world.room).size
    player = if x >= room_width / 2, do: 2, else: 1

    world
    |> World.update(self, &%{&1 | depth: @zone_depth})
    |> Gml.put(self, %{playerIndex: player, occupied: false})
  end

  defp zone_step(world, self, _other) do
    man = Query.by_player(world, Gml.var(world, self, :playerIndex))
    %Instance{x: x, y: y} = World.fetch(world, self)
    occupied = man != nil and Collide.meeting?(world, self, {x, y}, {:id, man})
    world = Gml.put(world, self, %{occupied: occupied})
    {left, _top, right, bottom} = bounds(world, self)
    middle = (left + right) / 2

    world
    |> Gml.all("Torch")
    |> Enum.reduce(world, fn torch, world ->
      %Instance{x: torch_x, y: torch_y} = World.fetch(world, torch)

      if abs(torch_x - middle) < @lit_across and abs(torch_y - bottom) < @lit_below,
        do: Gml.put(world, torch, %{lit: if(occupied, do: 1, else: 0)}),
        else: world
    end)
  end

  defp zone_draw(world, self, _other) do
    player = Gml.var(world, self, :playerIndex)
    {left, _top, right, bottom} = bounds(world, self)
    {colour, world} = PlayerColour.of_player(world, player)
    lamp_x = if player == 1, do: left + 7, else: right - 6

    lamp =
      if Gml.truthy?(Gml.var(world, self, :occupied, false)),
        do: @ready_colour,
        else: @waiting_colour

    world
    |> Draw.rectangle({left, bottom - 1, right, bottom}, colour)
    |> Draw.sprite(Data.index(world.data, :sprites, "sprLight"), 0, {lamp_x, bottom - @lamp_rise},
      blend: lamp
    )
  end

  defp bounds(world, id) do
    %Instance{x: x, y: y} = instance = World.fetch(world, id)
    world |> Collide.shape(instance, {x, y}) |> Shape.bounds()
  end
end
