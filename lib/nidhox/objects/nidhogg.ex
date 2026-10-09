defmodule Nidhox.Objects.Nidhogg do
  @moduledoc """
  The Nidhogg's body and what wakes it, as the game's code runs them, in an area's end
  rooms.

    * `Nidhogg` create: 60 segments (`Dragable`) laid back from it 15 pixels apart
      (`segmentLength`), in its `parts`; each after the first follows the one before
      (`targetObj`), set straight on it (`snapToTarget`), its frame `floor(i / 60 × 12)`;
      the first is hidden and is its `head`. Then its `NidhoggHead`
    * `NidhoggZone`: a fencer touching it wakes the Nidhogg (`active`), heard (115) at
      the head, across held 80 pixels inside the camera's edges
    * `Dragable` create: no speeds or turning; `targetDist` −1; following nothing;
      `X`, `Y` where it is; `maxSpeed` 8; `bgFrame` `irandom(3)`
    * `Dragable` step: a following segment aims at its place on the one before
      (`X`, `Y`: `segmentLength` behind it along its angle) — turning towards it by
      `tween × r × 0.4`, at most 30 degrees, and moving by `r` of the way, at most 30
      pixels each way, `r` being half the first segment's speed over its `maxSpeed` —
      and is shown upright (`image_yscale` 0.8) when it moved right, upside down
      (−0.8) when it moved left. The first segment, asleep (`NidhoggZone.active` 0),
      stays still; awake, it chases the nearest fencer (aiming 12 above its feet,
      turning at most 9 degrees a step); with none, before eating it heads for the
      nearest `ScreenEdge` (at most 7 degrees a step), stopping within 30 pixels; after
      eating it goes straight on. Chasing or heading out it moves at `maxSpeed`; the
      head (`NidhoggHead.headYScale`) faces the way it moves across
    * paused, a segment holds its speed (`holdSpeed`) and takes it back after

  `tween/2` is `Nidhox.Objects.NidhoggHead.tween/2`.
  """

  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Bout.{Camera, Sound}
  alias Nidhox.Gml
  alias Nidhox.Objects.NidhoggHead

  @segments 60
  @segment_length 15
  @frames 12
  @max_speed 8
  @wake_sound 115
  @wake_margin 80
  @aim_above 12
  @edge_stop 30
  @body_turn 30
  @chase_turn 9
  @edge_turn 7
  @upright 0.8

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Nidhogg_Create_0", &start/3},
      {"gml_Object_Dragable_Create_0", &segment/3},
      {"gml_Object_Dragable_Step_0", &crawl/3},
      {"gml_Object_NidhoggZone_Create_0", fn world, self, _other -> Gml.put(world, self, %{active: 0}) end},
      {"gml_Object_NidhoggZone_Collision_Man", &wake/3}
    ]
  end

  defp start(world, self, _other) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    world = Gml.put(world, self, %{segmentLength: @segment_length, head: -4, parts: []})
    object = World.object_index(world, "Dragable")

    world =
      Enum.reduce(0..(@segments - 1), world, fn i, world ->
        {world, part} = World.create(world, object, {x - i * @segment_length, y})
        parts = Gml.var(world, self, :parts)
        world = world |> Gml.put(part, %{text: Integer.to_string(i)}) |> Gml.put(self, %{parts: parts ++ [part]})
        follow(world, self, part, i, parts)
      end)

    world |> World.create(World.object_index(world, "NidhoggHead"), {x, y}) |> elem(0)
  end

  defp follow(world, body, part, 0, _parts) do
    world
    |> World.update(part, &%{&1 | visible: false})
    |> Gml.put(body, %{head: part})
  end

  defp follow(world, _body, part, i, parts) do
    world
    |> Gml.put(part, %{targetObj: List.last(parts)})
    |> snap_to_target(part)
    |> World.update(part, &%{&1 | image_index: floor(i / @segments * @frames) / 1, image_speed: 0.0})
  end

  defp snap_to_target(world, part) do
    world = update_target(world, part)
    World.update(world, part, &%{&1 | x: Gml.var(world, part, :X), y: Gml.var(world, part, :Y), image_angle: Gml.var(world, part, :targetAngle) / 1})
  end

  defp update_target(world, part) do
    target = Gml.var(world, part, :targetObj, -4)

    case target > 0 && World.fetch(world, target) do
      %Instance{x: x, y: y, image_angle: angle} ->
        length = Gml.var(world, Gml.first(world, "Nidhogg") || -4, :segmentLength, @segment_length)
        Gml.put(world, part, %{X: x + Gml.lengthdir_x(length, angle + 180), Y: y + Gml.lengthdir_y(length, angle + 180)})

      _none ->
        %Instance{x: x} = World.fetch(world, part)
        Gml.put(world, part, %{X: x, Y: x})
    end
  end

  defp segment(world, self, _other) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    {frame, world} = Gml.irandom(world, 3)

    Gml.put(world, self, %{
      angleSpeed: 0,
      targetDist: -1,
      targetAngle: 0,
      hspd: 0,
      vspd: 0,
      bgFrame: frame,
      targetObj: -4,
      X: x,
      Y: y,
      text: "",
      maxSpeed: @max_speed,
      holdSpeed: 0
    })
  end

  defp crawl(world, self, _other) do
    world =
      if Gml.var(world, self, :holdSpeed) > 0,
        do: world |> World.update(self, &Instance.put_motion(&1, %{speed: Gml.var(world, self, :holdSpeed)})) |> Gml.put(self, %{holdSpeed: 0}),
        else: world

    world = update_target(world, self)
    %Instance{x: before} = World.fetch(world, self)
    ratio = pace(world)

    if Gml.var(world, self, :targetObj, -4) > 0,
      do: world |> follow_target(self, ratio) |> show_way(self, before),
      else: lead(world, self, ratio)
  end

  defp pace(world) do
    case Gml.var(world, Gml.first(world, "Nidhogg") || -4, :parts, []) do
      [first | _] ->
        %Instance{speed: speed} = World.fetch(world, first)
        speed / Gml.var(world, first, :maxSpeed, @max_speed) * 0.5

      [] ->
        0
    end
  end

  defp follow_target(world, self, ratio) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    target = {Gml.var(world, self, :X), Gml.var(world, self, :Y)}
    {target_x, target_y} = target
    distance = :math.sqrt((target_x - x) * (target_x - x) + (target_y - y) * (target_y - y))
    world = Gml.put(world, self, %{targetDist: distance})

    if distance > 0 do
      angle = Gml.point_direction({x, y}, target)
      world = world |> Gml.put(self, %{targetAngle: angle}) |> turn_towards(self, angle, ratio, @body_turn)

      World.update(world, self, fn segment ->
        %{
          segment
          | x: segment.x + Gml.clamp((target_x - segment.x) * ratio, -@body_turn, @body_turn),
            y: segment.y + Gml.clamp((target_y - segment.y) * ratio, -@body_turn, @body_turn)
        }
      end)
    else
      world
    end
  end

  defp turn_towards(world, self, aim, ratio, most) do
    %Instance{image_angle: angle} = World.fetch(world, self)
    swing = -NidhoggHead.tween(angle, aim)
    World.update(world, self, &%{&1 | image_angle: angle + Gml.clamp(swing * ratio * 0.4, -most, most)})
  end

  defp show_way(world, self, before) do
    %Instance{x: x} = World.fetch(world, self)

    cond do
      x > before -> World.update(world, self, &%{&1 | image_yscale: @upright})
      x < before -> World.update(world, self, &%{&1 | image_yscale: -@upright})
      true -> world
    end
  end

  defp lead(world, self, ratio) do
    if Gml.truthy?(Gml.var(world, Gml.first(world, "NidhoggZone") || -4, :active)) do
      %Instance{x: x, y: y} = World.fetch(world, self)

      world
      |> chase(self, Gml.nearest(world, {x, y}, "Man"), ratio)
      |> face_head(self)
    else
      World.update(world, self, &Instance.put_motion(&1, %{speed: 0}))
    end
  end

  defp chase(world, self, man, ratio) when man != nil do
    %Instance{x: x, y: y} = World.fetch(world, self)
    %Instance{x: man_x, y: man_y} = World.fetch(world, man)

    world
    |> turn_towards(self, Gml.point_direction({x, y}, {man_x, man_y - @aim_above}), ratio, @chase_turn)
    |> run_on(self)
  end

  defp chase(world, self, nil, ratio) do
    if Gml.truthy?(Gml.var(world, Gml.first(world, "NidhoggHead") || -4, :eaten)),
      do: run_on(world, self),
      else: head_out(world, self, ratio)
  end

  defp head_out(world, self, ratio) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    case Gml.nearest(world, {x, y}, "ScreenEdge") do
      nil ->
        world

      edge ->
        %Instance{x: edge_x, y: edge_y} = World.fetch(world, edge)

        if :math.sqrt((edge_x - x) * (edge_x - x) + (edge_y - y) * (edge_y - y)) < @edge_stop,
          do: World.update(world, self, &Instance.put_motion(&1, %{speed: 0})),
          else: world |> turn_towards(self, Gml.point_direction({x, y}, {edge_x, edge_y}), ratio, @edge_turn) |> run_on(self)
    end
  end

  defp run_on(world, self) do
    World.update(world, self, fn segment ->
      Instance.put_motion(segment, %{direction: segment.image_angle, speed: Gml.var(world, self, :maxSpeed)})
    end)
  end

  defp face_head(world, self) do
    %Instance{hspeed: hspeed} = World.fetch(world, self)

    cond do
      hspeed > 0 -> Enum.reduce(Gml.all(world, "NidhoggHead"), world, &Gml.put(&2, &1, %{headYScale: 1}))
      hspeed < 0 -> Enum.reduce(Gml.all(world, "NidhoggHead"), world, &Gml.put(&2, &1, %{headYScale: -1}))
      true -> world
    end
  end

  defp wake(world, self, _man) do
    if Gml.truthy?(Gml.var(world, self, :active)) do
      world
    else
      %Instance{y: y} = World.fetch(world, self)

      world
      |> Gml.all("NidhoggHead")
      |> Enum.reduce(world, fn head, world ->
        %Instance{x: x} = World.fetch(world, head)
        across = Gml.clamp(x, Camera.left(world) + @wake_margin, Camera.right(world) - @wake_margin)
        Sound.play(world, @wake_sound, {across, y})
      end)
      |> Gml.put(self, %{active: 1})
    end
  end
end
