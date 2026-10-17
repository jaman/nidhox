defmodule Nidhox.Objects.NidhoggHead do
  @moduledoc """
  The Nidhogg's head (`NidhoggHead`) and the parts it is drawn from, as the game's
  code runs them.

    * create: frame 0; its parts made — `NidhoggEyeball`, `NidhoggEyebrow`,
      `NidhoggLowerJaw`, `NidhoggTongue`, `NidhoggUpperSkull`, `NidhoggUpperLip`,
      `NidhoggLowerLip`, `NidhoggInnerMouth`; a 128 × 128 surface (`headSurface`);
      `headYScale` 1; nothing eaten (`eaten` −1); not simulated (`simActive` 0, `simX` and `simY` where
      it is, `simAngle` 0); `bodyColor` white
    * end step: unless it is simulated and nothing is eaten, it sits on the body's first
      segment (`Nidhogg.head`), a quarter of a segment's width (`sDragonSegment`) behind it
      along its angle, turned as it is;
      the parts move with it — skull and upper lip on it, eyeball 12 across and 17 up,
      eyebrow 12 across and 29 up, jaw, lower lip and inner mouth 26 back, tongue 16
      back. The surface is cleared and each part draws itself on it (its user event 0)
      with the head's place at `(40, 50)`: inner mouth, tongue, jaw, skull, eyeball,
      eyebrow, upper lip, lower lip; with a fencer eaten, `sManInJaw` is drawn where
      the jaw is, as the jaw is, in the eaten fencer's colour (`bodyColor`)
    * draw: the surface, turned by its angle and flipped up or down by `headYScale`,
      with its `(40, 50)` on the head
    * user event 2, run each match frame: a `NidhoggZone` not yet active wakes when the
      fencer of player 1 or 2 touches it, heard (`sfxNidhoggNyah`) at each head, across
      held 80 pixels inside the camera's edges, at the zone's height. With a zone active
      and nothing eaten, the head is simulated: it starts at the body's place facing the
      room's middle, then each frame turns by `0.2` of the way to the nearest fencer
      (aiming 12 above its feet), at most 9 degrees, and moves 8 pixels along its angle.
      It sits at that place, faces the way it moves across (`headYScale`), and a fencer
      it touches is eaten: `eaten` its player, `bodyColor` its body's colour, the player
      wins (`Nidhox.Bout.Outcome.winner/2`), the bite heard (`sfxBite`), and the fencer
      gone
    * room end and destroy: the surface freed

  The parts, each step:

    * eyeball: drifts `0.1` of the way to `targetDist` (shown as its frame, a fraction
      of its frames) and turns `0.1` of the way to `targetAngle`; settled within 0.2 of
      both, with the lid shut (`lidCleared`) it looks somewhere new — `targetDist`
      `random(1)`, `targetAngle` `(random_range(0, 180) + 270) mod 360`, at least 0.4
      away — and opens its lid three times in ten (`lidOpening`); otherwise the lid
      keeps shut. Opening, a fully shut lid starts opening one time in ten and then
      opens 0.1 a step; shutting, it closes 0.1 a step and, shut, is `lidCleared`.
      Drawn as itself with `sprEyelid` at `lidPos` of its frames, 2 across
    * eyebrow: `sprEyebrow` at the eyeball's lid frame
    * jaw: turns `angleSpeed` of the way to `targetAngle`; within 4 degrees, one time in
      ten a new `targetAngle` `random_range(350, 360) mod 360` and `angleSpeed`
      `random_range(0.025, 0.1)`, else it sags 0.01
    * tongue: the same towards `random_range(315, 380) mod 360`, sagging 0.03, also
      whenever the jaw's angle is past it; never above the jaw; drawn 15 degrees under
      its angle
    * inner mouth and lower lip: turned as the jaw is
    * lips run their frames at 0.2 a step, the tongue at 0.1
  """

  alias Cauldron2D.GameMaker.{Collide, Data, Draw, Instance, Surfaces, World}
  alias Cauldron2D.Overlap
  alias Cauldron2D.Shape
  alias Nidhox.Bout.{Camera, Outcome, Sound}
  alias Nidhox.Gml
  alias Nidhox.Man.Query

  @parts [
    eyeball: "NidhoggEyeball",
    eyebrow: "NidhoggEyebrow",
    lowerJaw: "NidhoggLowerJaw",
    tongue: "NidhoggTongue",
    upperSkull: "NidhoggUpperSkull",
    upperLip: "NidhoggUpperLip",
    lowerLip: "NidhoggLowerLip",
    innerMouth: "NidhoggInnerMouth"
  ]
  @drawn_in_order [
    :innerMouth,
    :tongue,
    :lowerJaw,
    :upperSkull,
    :eyeball,
    :eyebrow,
    :upperLip,
    :lowerLip
  ]
  @surface_size 128
  @anchor {40, 50}
  @segment_sprite "sDragonSegment"
  @eyelid "sprEyelid"
  @eyebrow_sprite "sprEyebrow"
  @man_in_jaw "sManInJaw"
  @bite "sfxBite"
  @wake_sound "sfxNidhoggNyah"
  @wake_margin 80
  @aim_above 12
  @turn_most 9
  @sim_step 8
  @sim_turn 0.2
  @players [1, 2]
  @white {255, 255, 255}

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_NidhoggHead_Create_0", &start/3},
      {"gml_Object_NidhoggHead_Step_2", &end_step/3},
      {"gml_Object_NidhoggHead_Draw_0", &draw/3},
      {"gml_Object_NidhoggHead_Other_12", &simulate/3},
      {"gml_Object_NidhoggHead_Other_5", &free_surface/3},
      {"gml_Object_NidhoggHead_Destroy_0", &free_surface/3},
      {"gml_Object_NidhoggEyeball_Create_0", &eyeball/3},
      {"gml_Object_NidhoggEyeball_Step_0", &look/3},
      {"gml_Object_NidhoggEyeball_Other_10", &draw_eyeball/3},
      {"gml_Object_NidhoggEyebrow_Other_10", &draw_eyebrow/3},
      {"gml_Object_NidhoggLowerJaw_Create_0", &swinging(&1, &2, &3, nil)},
      {"gml_Object_NidhoggLowerJaw_Step_0", &jaw/3},
      {"gml_Object_NidhoggLowerJaw_Other_10",
       fn world, self, _other -> Draw.self(world, self) end},
      {"gml_Object_NidhoggTongue_Create_0", &swinging(&1, &2, &3, 0.1)},
      {"gml_Object_NidhoggTongue_Step_0", &tongue/3},
      {"gml_Object_NidhoggTongue_Other_10", fn world, self, _other -> Draw.self(world, self) end},
      {"gml_Object_NidhoggInnerMouth_Create_0", &swinging(&1, &2, &3, nil)},
      {"gml_Object_NidhoggInnerMouth_Other_10", &as_jaw/3},
      {"gml_Object_NidhoggLowerLip_Create_0",
       fn world, self, _other -> World.update(world, self, &%{&1 | image_speed: 0.2}) end},
      {"gml_Object_NidhoggLowerLip_Other_10", &as_jaw/3},
      {"gml_Object_NidhoggUpperLip_Create_0",
       fn world, self, _other -> World.update(world, self, &%{&1 | image_speed: 0.2}) end},
      {"gml_Object_NidhoggUpperLip_Other_10",
       fn world, self, _other -> Draw.self(world, self) end},
      {"gml_Object_NidhoggUpperSkull_Other_10",
       fn world, self, _other -> Draw.self(world, self) end},
      {"gml_Object_NidhoggFur_Create_0",
       fn world, self, _other -> World.update(world, self, &%{&1 | image_speed: 0.0}) end}
    ]
  end

  @doc "`tween(a, b)`: how far angle `a` is past angle `b`, between −180 and 180."
  @spec tween(number(), number()) :: float()
  def tween(a, b), do: :math.fmod(:math.fmod(a - b, 360) + 540, 360) - 180

  defp sprite(world, name), do: Data.index(world.data, :sprites, name)

  defp start(world, self, _other) do
    world = World.update(world, self, &%{&1 | image_index: 0.0, image_speed: 0.0})

    world =
      Enum.reduce(@parts, world, fn {name, object}, world ->
        {world, part} = World.create(world, World.object_index(world, object), {0, 0})
        Gml.put(world, self, %{name => part})
      end)

    {world, surface} = Surfaces.create(world, @surface_size, @surface_size)
    %Instance{x: x, y: y} = World.fetch(world, self)

    Gml.put(world, self, %{
      headSurface: surface,
      headYScale: 1,
      eaten: -1,
      simActive: 0,
      simX: x,
      simY: y,
      simAngle: 0,
      bodyColor: @white
    })
  end

  defp end_step(world, self, _other) do
    world
    |> sit_on_segment(self)
    |> place_parts(self)
    |> paint(self)
  end

  defp sit_on_segment(world, self) do
    if Gml.truthy?(Gml.var(world, self, :simActive)) and Gml.var(world, self, :eaten) == -1,
      do: world,
      else: sit_on_body(world, self)
  end

  defp sit_on_body(world, self) do
    case Gml.first(world, "Nidhogg") do
      nil ->
        world

      body ->
        segment = Gml.var(world, body, :head, -4)
        sit_on(world, self, segment > 0 && World.fetch(world, segment))
    end
  end

  defp sit_on(world, self, %Instance{x: x, y: y, image_angle: angle}) do
    behind = elem(World.sprite(world, sprite(world, @segment_sprite)).size, 0) * -0.25

    World.update(world, self, fn head ->
      %{
        head
        | x: x + Gml.lengthdir_x(behind, angle),
          y: y + Gml.lengthdir_y(behind, angle),
          image_angle: angle
      }
    end)
  end

  defp sit_on(world, _self, _none), do: world

  defp place_parts(world, self) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    [
      upperSkull: {x, y},
      upperLip: {x, y},
      eyeball: {x + 12, y - 17},
      eyebrow: {x + 12, y - 29},
      lowerJaw: {x - 26, y},
      lowerLip: {x - 26, y},
      innerMouth: {x - 26, y},
      tongue: {x - 16, y}
    ]
    |> Enum.reduce(world, fn {name, {px, py}}, world ->
      part = Gml.var(world, self, name, -4)

      if World.fetch(world, part),
        do: World.update(world, part, &%{&1 | x: px, y: py}),
        else: world
    end)
  end

  defp paint(world, self) do
    {world, surface} = head_surface(world, self)
    world = Surfaces.clear(world, surface, {0, 0, 0}, 0)
    head = World.fetch(world, self)

    world =
      Enum.reduce(
        @drawn_in_order,
        world,
        &draw_part(&2, Gml.var(&2, self, &1, -4), head, surface)
      )

    if Gml.var(world, self, :eaten) != -1,
      do: draw_eaten(world, self, head, surface),
      else: world
  end

  defp head_surface(world, self) do
    surface = Gml.var(world, self, :headSurface, -1)

    if Surfaces.exists?(world, surface) do
      {world, surface}
    else
      {world, surface} = Surfaces.create(world, @surface_size, @surface_size)
      {Gml.put(world, self, %{headSurface: surface}), surface}
    end
  end

  defp draw_part(world, part, %Instance{x: head_x, y: head_y}, surface) do
    case World.fetch(world, part) do
      %Instance{x: x, y: y} ->
        {anchor_x, anchor_y} = @anchor
        drawing = world.drawing

        world =
          %{world | drawing: []}
          |> World.update(part, &%{&1 | x: x - head_x + anchor_x, y: y - head_y + anchor_y})
          |> World.perform(part, :other, 10)

        items = Enum.reverse(world.drawing)

        %{world | drawing: drawing}
        |> World.update(part, &%{&1 | x: x, y: y})
        |> Surfaces.draw(surface, items)

      nil ->
        world
    end
  end

  defp draw_eaten(world, self, %Instance{x: head_x, y: head_y}, surface) do
    case World.fetch(world, Gml.var(world, self, :lowerJaw, -4)) do
      %Instance{} = jaw ->
        {anchor_x, anchor_y} = @anchor

        item = %{
          picture: {:sprite, sprite(world, @man_in_jaw), 0},
          position: {jaw.x - head_x + anchor_x, jaw.y - head_y + anchor_y},
          origin: World.sprite(world, sprite(world, @man_in_jaw)).origin,
          scale: {jaw.image_xscale, jaw.image_yscale},
          angle: jaw.image_angle,
          blend: Gml.var(world, self, :bodyColor, @white)
        }

        Surfaces.draw(world, surface, [item])

      nil ->
        world
    end
  end

  defp draw(world, self, _other) do
    %Instance{x: x, y: y, image_angle: angle} = World.fetch(world, self)
    surface = Gml.var(world, self, :headSurface, -1)
    flip = Gml.clamp(Gml.var(world, self, :headYScale) * 100, -1, 1)
    {anchor_x, anchor_y} = @anchor
    reach = :math.sqrt(anchor_x * anchor_x + anchor_y * anchor_y)
    turn = Gml.point_direction({0, 0}, {-anchor_x, anchor_y}) * flip
    corner = {x + Gml.lengthdir_x(reach, angle - turn), y + Gml.lengthdir_y(reach, angle - turn)}

    if Surfaces.exists?(world, surface),
      do: Draw.item(world, Surfaces.item(world, surface, corner, scale: {1, flip}, angle: angle)),
      else: world
  end

  defp simulate(world, self, _other) do
    world
    |> wake_zones()
    |> hunt(self)
  end

  defp wake_zones(world) do
    Enum.reduce(Gml.all(world, "NidhoggZone"), world, &wake_zone(&2, &1))
  end

  defp wake_zone(world, zone) do
    if Gml.truthy?(Gml.var(world, zone, :active)) do
      world
    else
      touched = Enum.any?(@players, &touching?(world, zone, Query.by_player(world, &1)))

      if touched do
        %Instance{y: y} = World.fetch(world, zone)

        world
        |> Gml.put(zone, %{active: 1})
        |> sound_wake(y)
      else
        world
      end
    end
  end

  defp sound_wake(world, y) do
    Enum.reduce(Gml.all(world, "NidhoggHead"), world, fn head, world ->
      %Instance{x: x} = World.fetch(world, head)

      across =
        Gml.clamp(x, Camera.left(world) + @wake_margin, Camera.right(world) - @wake_margin)

      Sound.play_named(world, @wake_sound, {across, y})
    end)
  end

  defp hunt(world, self) do
    zone = Gml.first(world, "NidhoggZone")

    if (zone && Gml.truthy?(Gml.var(world, zone, :active))) and Gml.var(world, self, :eaten) == -1 do
      world
      |> start_simulation(self)
      |> steer(self)
      |> settle_on_simulation(self)
      |> bite(self)
    else
      world
    end
  end

  defp start_simulation(world, self) do
    body = Gml.first(world, "Nidhogg")

    if Gml.truthy?(Gml.var(world, self, :simActive)) or body == nil do
      world
    else
      %Instance{x: x, y: y} = World.fetch(world, body)

      Gml.put(world, self, %{
        simActive: 1,
        simX: x,
        simY: y,
        simAngle: Gml.point_direction({x, y}, {Camera.room_width(world) / 2, y})
      })
    end
  end

  defp steer(world, self) do
    sim_x = Gml.var(world, self, :simX)
    sim_y = Gml.var(world, self, :simY)

    case nearest_fencer(world, {sim_x, sim_y}) do
      nil ->
        world

      %Instance{x: x, y: y} ->
        angle = Gml.var(world, self, :simAngle)
        aim = Gml.point_direction({sim_x, sim_y}, {x, y - @aim_above})
        angle = angle + Gml.clamp(-tween(angle, aim) * @sim_turn, -@turn_most, @turn_most)

        Gml.put(world, self, %{
          simAngle: angle,
          simX: sim_x + Gml.lengthdir_x(@sim_step, angle),
          simY: sim_y + Gml.lengthdir_y(@sim_step, angle)
        })
    end
  end

  defp nearest_fencer(world, {sim_x, sim_y}) do
    @players
    |> Enum.map(&Query.by_player(world, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&World.fetch(world, &1))
    |> Enum.reduce({nil, nil}, fn %Instance{x: x, y: y} = man, {best, best_distance} ->
      distance = :math.sqrt(:math.pow(sim_x - x, 2) + :math.pow(sim_y - (y - @aim_above), 2))
      if best == nil or distance < best_distance, do: {man, distance}, else: {best, best_distance}
    end)
    |> elem(0)
  end

  defp settle_on_simulation(world, self) do
    angle = Gml.var(world, self, :simAngle)
    across = Gml.lengthdir_x(1, angle)

    world
    |> World.update(self, fn head ->
      %{head | x: Gml.var(world, self, :simX), y: Gml.var(world, self, :simY), image_angle: angle}
    end)
    |> face(self, across)
  end

  defp face(world, self, across) when across > 0, do: Gml.put(world, self, %{headYScale: 1})
  defp face(world, self, across) when across < 0, do: Gml.put(world, self, %{headYScale: -1})
  defp face(world, _self, _across), do: world

  defp bite(world, self) do
    man =
      @players
      |> Enum.map(&Query.by_player(world, &1))
      |> Enum.find(&touching?(world, self, &1))

    if man, do: eat(world, self, man), else: world
  end

  defp touching?(_world, _self, nil), do: false

  defp touching?(world, self, man) do
    with %Instance{x: x, y: y} = body <- World.fetch(world, self),
         %Instance{x: man_x, y: man_y} = fencer <- World.fetch(world, man),
         %Shape{} = mine <- Collide.shape(world, body, {x, y}),
         %Shape{} = theirs <- Collide.shape(world, fencer, {man_x, man_y}) do
      Overlap.shapes?(mine, theirs)
    else
      _no_overlap -> false
    end
  end

  defp eat(world, self, man) do
    player = Gml.var(world, man, :playerIndex)
    body = World.fetch(world, Gml.var(world, man, :flesh, -4))
    %Instance{x: x, y: y} = World.fetch(world, self)

    world
    |> Gml.put(self, %{eaten: player, bodyColor: if(body, do: body.image_blend, else: @white)})
    |> Outcome.winner(player)
    |> Sound.play_named(@bite, {x, y})
    |> World.destroy(man)
  end

  defp free_surface(world, self, _other) do
    surface = Gml.var(world, self, :headSurface, -1)
    if Surfaces.exists?(world, surface), do: Surfaces.free(world, surface), else: world
  end

  defp eyeball(world, self, _other) do
    {distance, world} = Gml.random(world, 1)
    {angle, world} = Gml.random(world, 360)

    world
    |> World.update(self, &%{&1 | image_index: 0.0, image_speed: 0.0})
    |> Gml.put(self, %{
      currentDist: 0,
      currentAngle: 0,
      targetDist: distance,
      targetAngle: angle,
      lidPos: 0,
      lidOpening: 0,
      lidCleared: 0
    })
  end

  defp look(world, self, _other) do
    current_angle = Gml.var(world, self, :currentAngle)
    turn = tween(current_angle, Gml.var(world, self, :targetAngle))
    distance = Gml.var(world, self, :currentDist)
    distance = distance + (Gml.var(world, self, :targetDist) - distance) * 0.1
    current_angle = current_angle - turn * 0.1
    world = Gml.put(world, self, %{currentDist: distance, currentAngle: current_angle})

    world =
      if Gml.lt?(abs(distance - Gml.var(world, self, :targetDist)) - 0.2, 0) and
           Gml.lt?(abs(turn) - 0.2, 0),
         do: settle(world, self),
         else: world

    frames = frames(world, self)

    world
    |> World.update(
      self,
      &%{
        &1
        | image_index: Gml.var(world, self, :currentDist) * frames,
          image_angle: Gml.var(world, self, :currentAngle)
      }
    )
    |> blink(self)
  end

  defp settle(world, self) do
    if Gml.truthy?(Gml.var(world, self, :lidCleared)),
      do: look_elsewhere(world, self),
      else: Gml.put(world, self, %{lidOpening: 0})
  end

  defp look_elsewhere(world, self) do
    if Gml.lt?(
         abs(Gml.var(world, self, :currentDist) - Gml.var(world, self, :targetDist)) - 0.4,
         0
       ) do
      {distance, world} = Gml.random(world, 1)
      {angle, world} = Gml.random_range(world, 0, 180)

      world =
        Gml.put(world, self, %{targetDist: distance, targetAngle: :math.fmod(angle + 270, 360)})

      {opens, world} = Gml.prob(world, 30)
      world = if opens, do: Gml.put(world, self, %{lidCleared: 0, lidOpening: 1}), else: world
      look_elsewhere(world, self)
    else
      world
    end
  end

  defp blink(world, self) do
    lid = Gml.var(world, self, :lidPos)

    world =
      if Gml.truthy?(Gml.var(world, self, :lidOpening)),
        do: lid_opening(world, self, lid),
        else: lid_closing(world, self, lid + 0.1)

    Gml.put(world, self, %{lidPos: Gml.clamp(Gml.var(world, self, :lidPos), 0, 1)})
  end

  defp lid_opening(world, self, lid) do
    if Gml.eq?(lid, 1) do
      {starts, world} = Gml.prob(world, 10)
      if starts, do: Gml.put(world, self, %{lidPos: lid - 0.1}), else: world
    else
      Gml.put(world, self, %{lidPos: lid - 0.1})
    end
  end

  defp lid_closing(world, self, lid) do
    world = Gml.put(world, self, %{lidPos: lid})
    if lid >= 1, do: Gml.put(world, self, %{lidCleared: 1}), else: world
  end

  defp draw_eyeball(world, self, _other) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    eyelid = sprite(world, @eyelid)
    lid_frames = length(World.sprite(world, eyelid).frames)
    lid = floor(Gml.var(world, self, :lidPos) * lid_frames)

    world
    |> Draw.self(self)
    |> Draw.sprite(eyelid, lid, {x + 2, y})
  end

  defp draw_eyebrow(world, self, _other) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    lid_frames = length(World.sprite(world, sprite(world, @eyelid)).frames)
    lid = Gml.var(world, Gml.first(world, "NidhoggEyeball") || -4, :lidPos)
    Draw.sprite(world, sprite(world, @eyebrow_sprite), floor(lid * lid_frames), {x, y})
  end

  defp swinging(world, self, _other, nil),
    do: Gml.put(world, self, %{currentAngle: 0, targetAngle: 0, angleSpeed: 0.1})

  defp swinging(world, self, other, image_speed) do
    world
    |> swinging(self, other, nil)
    |> World.update(self, &%{&1 | image_speed: image_speed})
  end

  defp jaw(world, self, _other) do
    {turn, world} = swing(world, self)

    world =
      if Gml.lt?(abs(turn) - 4, 0),
        do: jaw_moves(world, self),
        else: world

    World.update(world, self, &%{&1 | image_angle: Gml.var(world, self, :currentAngle)})
  end

  defp jaw_moves(world, self) do
    {moves, world} = Gml.prob(world, 10)

    if moves do
      {target, world} = Gml.random_range(world, 350, 360)
      {speed, world} = Gml.random_range(world, 0.025, 0.1)
      Gml.put(world, self, %{targetAngle: :math.fmod(target, 360), angleSpeed: speed})
    else
      Gml.put(world, self, %{currentAngle: Gml.var(world, self, :currentAngle) - 0.01})
    end
  end

  defp tongue(world, self, _other) do
    {turn, world} = swing(world, self)
    jaw_angle = jaw_angle(world)

    world =
      if Gml.lt?(abs(turn) - 4, 0) or jaw_angle > Gml.var(world, self, :currentAngle),
        do: tongue_moves(world, self),
        else: world

    current = max(Gml.var(world, self, :currentAngle), jaw_angle)

    world
    |> Gml.put(self, %{currentAngle: current})
    |> World.update(self, &%{&1 | image_angle: current - 15})
  end

  defp tongue_moves(world, self) do
    {moves, world} = Gml.prob(world, 10)

    if moves do
      {target, world} = Gml.random_range(world, 315, 380)
      {speed, world} = Gml.random_range(world, 0.025, 0.1)
      Gml.put(world, self, %{targetAngle: :math.fmod(target, 360), angleSpeed: speed})
    else
      Gml.put(world, self, %{currentAngle: Gml.var(world, self, :currentAngle) - 0.03})
    end
  end

  defp swing(world, self) do
    current = Gml.var(world, self, :currentAngle)
    turn = tween(current, Gml.var(world, self, :targetAngle))

    {turn,
     Gml.put(world, self, %{currentAngle: current - turn * Gml.var(world, self, :angleSpeed)})}
  end

  defp jaw_angle(world) do
    case Gml.first(world, "NidhoggLowerJaw") do
      nil -> 0
      jaw -> World.fetch(world, jaw).image_angle
    end
  end

  defp as_jaw(world, self, _other) do
    world
    |> World.update(self, &%{&1 | image_angle: jaw_angle(world)})
    |> Draw.self(self)
  end

  defp frames(world, self) do
    case World.sprite(world, World.fetch(world, self).sprite_index) do
      nil -> 1
      definition -> length(definition.frames)
    end
  end
end
