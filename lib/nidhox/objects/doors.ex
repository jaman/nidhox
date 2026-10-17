defmodule Nidhox.Objects.Doors do
  @moduledoc """
  The rooms' swinging doors (`Doorway`, and the darker `DoorwayDark`) and the facades
  that hide while somebody is behind them (`HideFacade`).

  `Doorway`:

    * create: `center` 6, `frame` at it (shut), `opening` 3 (shut), `maxTimer` 3 and
      `timer` at it; `DoorwayDark` is tinted `make_color_hsv(0, 0, 200)`
    * user event 2, each match frame, first looks for a toucher: the first of players 1
      and 2 (`findManByPlayerIndex`) whose fencer overlaps the door, else whose shown
      held sword (`weapon`) does; else the first shown sword in the match's
      `flyingWeapons` that overlaps it. A toucher of a shut door opens it away from
      itself (`opening` 0 when it is to the door's right, else 1), heard (`sndSnap`);
      a toucher of an open door keeps it open (`timer` back to `maxTimer`). Then
      opening 0 swings it 0.6 frames a step towards 0,
      opening 1 0.6 towards its last frame, shut holds it at `center`; closing (any
      other `opening`) it moves back towards `center` by at most 0.45 a step, and once
      within 0.45 it is shut, heard (`sndSnap`). Its frame is held to its sprite's frames. Swung
      all the way while opening, it waits out `timer`; then, unless the nearest fencer
      stands within 16 pixels across or the nearest held sword, shown, within 21, it
      starts closing (`opening` −1, `timer` back to `maxTimer`). It shows `frame`

  `HideFacade`, each step: its depth's tiles are shown, then every facade touched in
  the last 2 steps hides its depth's tiles (`tile_layer_hide`); `touchTimer` counts
  down. A fencer, or an open door, touching it sets `touchTimer` to 2.
  """

  alias Cauldron2D.GameMaker.{Collide, Colour, Data, Instance, World}
  alias Cauldron2D.{Overlap, Shape}
  alias Nidhox.Bout.Sound
  alias Nidhox.Gml
  alias Nidhox.Man.Query

  @centre 6
  @shut 3
  @max_timer 3
  @swing 0.6
  @settle 0.75
  @snap "sndSnap"
  @players [1, 2]
  @man_clear 16
  @sword_clear 21

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Doorway_Create_0", &start/3},
      {"gml_Object_DoorwayDark_Create_0", &dark/3},
      {"gml_Object_Doorway_Other_12", &update/3},
      {"gml_Object_HideFacade_Create_0",
       fn world, self, _other -> Gml.put(world, self, %{touchTimer: 0}) end},
      {"gml_Object_HideFacade_Step_0", &facade_step/3},
      {"gml_Object_HideFacade_Collision_Man", &facade_touched/3},
      {"gml_Object_HideFacade_Collision_Doorway", &facade_by_door/3}
    ]
  end

  defp start(world, self, _other) do
    world
    |> Gml.put(self, %{
      center: @centre,
      frame: @centre,
      opening: @shut,
      maxTimer: @max_timer,
      timer: @max_timer
    })
    |> World.update(self, &%{&1 | image_speed: 0.0, image_index: @centre / 1})
  end

  defp dark(world, self, other) do
    world
    |> World.inherited(self, "Doorway", :create, 0, other)
    |> World.update(self, &%{&1 | image_blend: Colour.hsv(0, 0, 200)})
  end

  defp update(world, self, _other) do
    world = touch(world, self)
    world = swing(world, self, Gml.var(world, self, :opening))
    last = frames(world, self) - 1
    frame = Gml.clamp(Gml.var(world, self, :frame), 0, last)
    world = Gml.put(world, self, %{frame: frame})
    opening = Gml.var(world, self, :opening)

    cond do
      not (Gml.eq?(frame, 0) or Gml.eq?(frame, last)) ->
        show(world, self)

      opening not in [0, 1] ->
        show(world, self)

      Gml.truthy?(Gml.var(world, self, :timer)) ->
        world |> Gml.put(self, %{timer: Gml.var(world, self, :timer) - 1}) |> show(self)

      held_open?(world, self) ->
        world

      true ->
        world
        |> Gml.put(self, %{timer: Gml.var(world, self, :maxTimer), opening: -1})
        |> show(self)
    end
  end

  defp touch(world, self) do
    case toucher(world, self) do
      nil -> world
      other -> touched(world, self, other)
    end
  end

  defp touched(world, self, other) do
    if Gml.var(world, self, :opening) == @shut do
      %Instance{x: x, y: y} = World.fetch(world, self)
      %Instance{x: other_x} = World.fetch(world, other)

      world
      |> Gml.put(self, %{opening: if(other_x >= x, do: 0, else: 1)})
      |> play_snap({x, y})
    else
      Gml.put(world, self, %{timer: Gml.var(world, self, :maxTimer)})
    end
  end

  defp toucher(world, self),
    do: Enum.find_value(@players, &player_toucher(world, self, &1)) || flying_toucher(world, self)

  defp player_toucher(world, self, player) do
    case Query.by_player(world, player) do
      nil -> nil
      man -> if meets?(world, self, man), do: man, else: held_toucher(world, self, man)
    end
  end

  defp held_toucher(world, self, man) do
    weapon = Gml.var(world, man, :weapon, -4)
    if shown_and_meeting?(world, self, weapon), do: weapon
  end

  defp flying_toucher(world, self) do
    case Gml.first(world, "Match") do
      nil ->
        nil

      match ->
        world
        |> Gml.var(match, :flyingWeapons, [])
        |> Enum.find(&shown_and_meeting?(world, self, &1))
    end
  end

  defp shown_and_meeting?(world, self, other) do
    case World.fetch(world, other) do
      %Instance{visible: true} -> meets?(world, self, other)
      _absent_or_hidden -> false
    end
  end

  defp meets?(world, self, other) do
    with %Instance{x: x, y: y} = door <- World.fetch(world, self),
         %Instance{x: other_x, y: other_y} = body <- World.fetch(world, other),
         %Shape{} = mine <- Collide.shape(world, door, {x, y}),
         %Shape{} = theirs <- Collide.shape(world, body, {other_x, other_y}) do
      Overlap.shapes?(mine, theirs)
    else
      _no_overlap -> false
    end
  end

  defp play_snap(world, position) do
    Sound.play(world, Data.index(world.data, :sounds, @snap), position)
  end

  defp swing(world, self, 0),
    do: Gml.put(world, self, %{frame: Gml.var(world, self, :frame) - @swing})

  defp swing(world, self, 1),
    do: Gml.put(world, self, %{frame: Gml.var(world, self, :frame) + @swing})

  defp swing(world, self, @shut),
    do: Gml.put(world, self, %{frame: Gml.var(world, self, :center)})

  defp swing(world, self, _closing) do
    gap = Gml.var(world, self, :center) - Gml.var(world, self, :frame)
    step = @swing * @settle

    if Gml.lt?(abs(gap) - step, 0) do
      %Instance{x: x, y: y} = World.fetch(world, self)
      world |> Gml.put(self, %{opening: @shut}) |> play_snap({x, y})
    else
      Gml.put(world, self, %{frame: Gml.var(world, self, :frame) + Gml.clamp(gap, -step, step)})
    end
  end

  defp held_open?(world, self) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    near_man?(world, {x, y}) or near_sword?(world, {x, y})
  end

  defp near_man?(world, {x, y}) do
    case Gml.nearest(world, {x, y}, "Man") do
      nil -> false
      man -> Gml.lt?(abs(x - World.fetch(world, man).x), @man_clear)
    end
  end

  defp near_sword?(world, {x, y}) do
    case Gml.nearest(world, {x, y}, "HeldWeapon") do
      nil ->
        false

      sword ->
        World.fetch(world, sword).visible and
          Gml.lt?(abs(x - World.fetch(world, sword).x), @sword_clear)
    end
  end

  defp show(world, self),
    do: World.update(world, self, &%{&1 | image_index: Gml.var(world, self, :frame) / 1})

  defp frames(world, self) do
    case World.sprite(world, World.fetch(world, self).sprite_index) do
      nil -> 1
      sprite -> length(sprite.frames)
    end
  end

  defp facade_step(world, self, _other) do
    world = World.hide_tiles(world, World.fetch(world, self).depth, false)

    world =
      world
      |> Gml.all("HideFacade")
      |> Enum.reduce(world, fn facade, world ->
        if Gml.var(world, facade, :touchTimer) > 0,
          do: World.hide_tiles(world, World.fetch(world, facade).depth, true),
          else: world
      end)

    Gml.put(world, self, %{touchTimer: Gml.var(world, self, :touchTimer) - 1})
  end

  defp facade_touched(world, self, _other), do: Gml.put(world, self, %{touchTimer: 2})

  defp facade_by_door(world, self, other) do
    if Gml.var(world, other, :opening) != @shut,
      do: Gml.put(world, self, %{touchTimer: 2}),
      else: world
  end
end
