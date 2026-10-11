defmodule Nidhox.Objects.Animals do
  @moduledoc """
  The squirrels, cats and birds of the rooms (`Squirrel`, `Cat`, `Bird`, all
  `GrassDisturbingAnimal`s and so `PhysicsObject`s), moving under the game's physics
  (`Nidhox.Man.Physics.begin_step/2` and `end_step/2`).

  Squirrels and cats wander:

    * create: a `PhysicsObject`; a place to go across the room (`targetX`, at random),
      no wait (`waitTimer`), standing still (`imageSpeed` 0); a squirrel tinted
      `hsv(15, 40, 200)`, a cat `hsv(random 255, random 18, 40–140)`
    * end step: within 64 of its place it picks another, 200 pixels inside the room's
      ends. On the ground, waiting it counts down and slows (×0.97); else it makes for
      its place at 0.1 a step, now and then hops (`vspd` −0.2 to −2.25 for a squirrel,
      −0.8 to −9 for a cat, while moving faster than 0.125) and now and then waits 60 to
      120 frames. In the air it falls at 0.12. It faces its way, slows (×0.99 both
      ways) and keeps to 1 across and 2.5 down. On the ground moving it walks — a
      squirrel running past 0.3 — at `|hspd| × 0.25` (a cat `× 1.5`), still it stands
      at 0.4; in the air its jump frame follows `vspd`
    * user event 0 (into a wall): a new place, stopped (a cat also back where it was)

  Birds fly between perches (`RespawnPoint`s):

    * create: a `PhysicsObject` on the ground, not flying, `stamina` 240, its perch
      itself, its alarm in 1 to 600 frames, `idealAltitude` 48; drifting at −1 to 1 each
      way; its wings flapping (`sndFlap`) round and round where it is
      (`Nidhox.Objects.Ear.attach/3`)
    * alarm 0, every 120 to 600 frames: a new perch — the nearest `RespawnPoint` to a
      random place in the room's top half, flown to `idealAltitude` 12 to 150 above it
    * end step: its frame from `vspd`. Flying it sinks at 0.03; more than 48 from where
      it means to be, below that height it climbs (−0.1, 60 in 100) leaning forward, and
      it steers towards the perch (0.025, 60 in 100), gliding forward (0.01) while
      sinking. Not flying it falls at 0.04. On the ground it stands, slowed (×0.2), and
      takes off now and then (2 in 100, `vspd` −2); in the air it flies (sprite 10)
      moving across faster than 0.25 and faster than down, else hovers (8). It slows
      (×0.998 across, ×0.98 down), keeps to 1 each way and faces its way
    * user event 0 (into a wall): it turns back; user event 1 (into a ceiling) rising, it
      thinks of a new perch; through a doorway or a window it goes back and turns back
      at half speed

  Leaving the room each wraps round it by its built-in speed (`action_wrap`), which
  these animals do not use, so they go on past the edge.
  """

  alias Cauldron2D.GameMaker.{Colour, Instance, World}
  alias Nidhox.Gml
  alias Nidhox.Man.Physics
  alias Nidhox.Objects.Ear

  @walkers %{
    "Squirrel" => %{
      hop: {2, 0.2, 2.25},
      wait: 0.5,
      walk: 23,
      run: 24,
      stand: 25,
      jump: 26,
      pace: 0.25
    },
    "Cat" => %{hop: {0.5, 0.8, 9}, wait: 2, walk: 360, run: 360, stand: 373, jump: 366, pace: 1.5}
  }
  @near 64
  @inside 200
  @accel 0.1
  @gravity 0.12
  @most_across 1
  @most_down 2.5
  @flap 10
  @fly 10
  @hover 8
  @stand 9

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_GrassDisturbingAnimal_Create_0", &inherit/3},
      {"gml_Object_Squirrel_Create_0", &squirrel/3},
      {"gml_Object_Squirrel_Step_1", &begin_step/3},
      {"gml_Object_Squirrel_Step_2", &wander/3},
      {"gml_Object_Squirrel_Other_10", &bump/3},
      {"gml_Object_Squirrel_Other_0", &wrap(&1, &2, &3, :both)},
      {"gml_Object_Cat_Create_0", &cat/3},
      {"gml_Object_Cat_Step_1", &begin_step/3},
      {"gml_Object_Cat_Step_2", &wander/3},
      {"gml_Object_Cat_Other_10", &cat_bump/3},
      {"gml_Object_Cat_Other_0", &wrap(&1, &2, &3, :both)},
      {"gml_Object_Bird_Create_0", &bird/3},
      {"gml_Object_Bird_Alarm_0", &new_perch/3},
      {"gml_Object_Bird_Step_1", &begin_step/3},
      {"gml_Object_Bird_Step_2", &fly/3},
      {"gml_Object_Bird_Other_10", &turn_back/3},
      {"gml_Object_Bird_Other_11", &ceiling/3},
      {"gml_Object_Bird_Collision_Doorway", &bounce/3},
      {"gml_Object_Bird_Collision_Window", &bounce/3},
      {"gml_Object_Bird_Other_0", &wrap(&1, &2, &3, :across)}
    ]
  end

  defp inherit(world, self, _other),
    do: World.inherited(world, self, "GrassDisturbingAnimal", :create, 0)

  defp squirrel(world, self, _other) do
    world = World.inherited(world, self, "Squirrel", :create, 0)
    {target, world} = Gml.random(world, room_width(world))

    world
    |> Gml.put(self, %{targetX: target, waitTimer: 0, imageSpeed: 0})
    |> World.update(self, &%{&1 | image_blend: hsv(15, 40, 200)})
  end

  defp cat(world, self, _other) do
    world = World.inherited(world, self, "Cat", :create, 0)
    {target, world} = Gml.random(world, room_width(world))
    world = Gml.put(world, self, %{targetX: target, waitTimer: 0})
    {hue, world} = Gml.random(world, 255)
    {saturation, world} = Gml.random(world, 18)
    {value, world} = Gml.random_range(world, 40, 140)

    world
    |> World.update(self, &%{&1 | image_blend: hsv(hue, saturation, value)})
    |> Gml.put(self, %{imageSpeed: 0})
  end

  defp begin_step(world, self, _other), do: Physics.begin_step(world, self)

  defp wander(world, self, _other) do
    kind = Map.fetch!(@walkers, object_name(world, self))

    world
    |> World.update(self, &%{&1 | image_speed: Gml.var(world, self, :imageSpeed)})
    |> new_place_when_near(self)
    |> walk(self, kind)
    |> settle(self, kind)
    |> Physics.end_step(self)
  end

  defp new_place_when_near(world, self) do
    %Instance{x: x} = World.fetch(world, self)

    if Gml.lt?(abs(x - Gml.var(world, self, :targetX)), @near) do
      {target, world} = Gml.random_range(world, @inside, room_width(world) - @inside)
      Gml.put(world, self, %{targetX: target})
    else
      world
    end
  end

  defp walk(world, self, kind) do
    if Gml.truthy?(Gml.var(world, self, :onGround)),
      do: on_ground(world, self, kind),
      else: Gml.put(world, self, %{vspd: Gml.var(world, self, :vspd) + @gravity})
  end

  defp on_ground(world, self, kind) do
    wait = Gml.var(world, self, :waitTimer)

    if Gml.truthy?(wait),
      do: Gml.put(world, self, %{waitTimer: wait - 1, hspd: Gml.var(world, self, :hspd) * 0.97}),
      else: world |> make_for_place(self) |> hop(self, kind) |> pause(self, kind)
  end

  defp make_for_place(world, self) do
    %Instance{x: x} = World.fetch(world, self)
    target = Gml.var(world, self, :targetX)
    hspd = Gml.var(world, self, :hspd)
    hspd = if Gml.lt?(target, x), do: hspd - @accel, else: hspd
    hspd = if Gml.gt?(target, x), do: hspd + @accel, else: hspd
    Gml.put(world, self, %{hspd: hspd})
  end

  defp hop(world, self, %{hop: {chance, low, high}}) do
    if Gml.gt?(abs(Gml.var(world, self, :hspd)), 0.125) do
      case Gml.prob(world, chance) do
        {true, world} ->
          {height, world} = Gml.random_range(world, low, high)
          Gml.put(world, self, %{vspd: -height})

        {false, world} ->
          world
      end
    else
      world
    end
  end

  defp pause(world, self, %{wait: chance}) do
    case Gml.prob(world, chance) do
      {true, world} ->
        {wait, world} = Gml.random_range(world, 60, 120)
        Gml.put(world, self, %{waitTimer: wait})

      {false, world} ->
        world
    end
  end

  defp settle(world, self, kind) do
    world
    |> face(self)
    |> slow(self, 0.99, 0.99, @most_across, @most_down)
    |> pose(self, kind)
  end

  defp pose(world, self, kind) do
    hspd = Gml.var(world, self, :hspd)

    cond do
      not Gml.truthy?(Gml.var(world, self, :onGround)) ->
        jump_frame(world, self, kind.jump)

      Gml.gt?(abs(hspd), 0) ->
        sprite = if Gml.gt?(abs(hspd) - @most_across * 0.3, 0), do: kind.run, else: kind.walk
        world |> sprite(self, sprite) |> Gml.put(self, %{imageSpeed: abs(hspd) * kind.pace})

      true ->
        world |> sprite(self, kind.stand) |> Gml.put(self, %{imageSpeed: 0.4})
    end
  end

  defp jump_frame(world, self, sprite) do
    world = sprite(world, self, sprite)
    frames = frames(world, self)
    frame = frames * 0.5 + Gml.var(world, self, :vspd) / @most_down * frames * 0.5
    World.update(world, self, &%{&1 | image_index: frame})
  end

  defp bump(world, self, _other) do
    {target, world} = Gml.random(world, room_width(world))
    Gml.put(world, self, %{targetX: target, hspd: 0})
  end

  defp cat_bump(world, self, other) do
    world = bump(world, self, other)
    World.update(world, self, &%{&1 | x: &1.xprevious})
  end

  defp bird(world, self, _other) do
    world = World.inherited(world, self, "Bird", :create, 0)
    {alarm, world} = Gml.random_range(world, 1, 600)

    world =
      world
      |> Gml.put(self, %{flying: 0, stamina: 240, perch: self, frameNum: 0, idealAltitude: 48})
      |> World.update(self, &Instance.put_alarm(&1, 0, alarm))

    {_perch, world} = find_perch(world, self)
    {hspd, world} = Gml.random_range(world, -1, 1)
    {vspd, world} = Gml.random_range(world, -1, 1)
    world = Gml.put(world, self, %{hspd: hspd, vspd: vspd})
    {_sound, world} = Ear.attach(world, self, @flap)
    world
  end

  defp new_perch(world, self, _other) do
    {alarm, world} = Gml.random_range(world, 120, 600)
    world = World.update(world, self, &Instance.put_alarm(&1, 0, alarm))
    {perch, world} = find_perch(world, self)
    Gml.put(world, self, %{perch: perch})
  end

  defp find_perch(world, self) do
    {x, world} = Gml.random_range(world, 0, room_width(world))
    {y, world} = Gml.random_range(world, 0, room_height(world) * 0.5)
    perch = Gml.nearest(world, {x, y}, "RespawnPoint")
    {altitude, world} = Gml.random_range(world, 12, 150)
    world = Gml.put(world, self, %{idealAltitude: altitude})
    {perch || self, world}
  end

  defp fly(world, self, _other) do
    world
    |> flap_frame(self)
    |> airborne(self)
    |> land_or_fly(self)
    |> slow(self, 0.998, 0.98, 1, 1)
    |> face(self)
    |> Physics.end_step(self)
  end

  defp flap_frame(world, self) do
    frames = frames(world, self)

    World.update(
      world,
      self,
      &%{&1 | image_index: frames / 2 + Gml.var(world, self, :vspd) * frames * 2, image_speed: 0}
    )
  end

  defp airborne(world, self) do
    cond do
      Gml.truthy?(Gml.var(world, self, :flying)) ->
        world
        |> Gml.put(self, %{vspd: Gml.var(world, self, :vspd) + 0.03})
        |> head_for_perch(self)

      Gml.truthy?(Gml.var(world, self, :onGround)) ->
        world

      true ->
        Gml.put(world, self, %{vspd: Gml.var(world, self, :vspd) + 0.04})
    end
  end

  defp head_for_perch(world, self) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    case World.fetch(world, Gml.var(world, self, :perch, self)) do
      %Instance{x: px, y: py} ->
        target_y = py - Gml.var(world, self, :idealAltitude)

        if Gml.gt?(distance({x, y}, {px, target_y}), 48),
          do: world |> climb(self, y, target_y) |> steer(self, x, px) |> glide(self),
          else: world

      nil ->
        world
    end
  end

  defp climb(world, self, y, target_y) do
    if Gml.gt?(y, target_y - 8) do
      case Gml.prob(world, 60) do
        {true, world} ->
          lean = 0.02 * World.fetch(world, self).image_xscale

          Gml.put(world, self, %{
            vspd: Gml.var(world, self, :vspd) - 0.1,
            hspd: Gml.var(world, self, :hspd) + lean
          })

        {false, world} ->
          world
      end
    else
      world
    end
  end

  defp steer(world, self, x, px) do
    world = if Gml.lt?(px, x), do: nudge(world, self, -0.025), else: world
    if Gml.gt?(px, x), do: nudge(world, self, 0.025), else: world
  end

  defp nudge(world, self, amount) do
    case Gml.prob(world, 60) do
      {true, world} -> Gml.put(world, self, %{hspd: Gml.var(world, self, :hspd) + amount})
      {false, world} -> world
    end
  end

  defp glide(world, self) do
    if Gml.gt?(Gml.var(world, self, :vspd), 0),
      do:
        Gml.put(world, self, %{
          hspd: Gml.var(world, self, :hspd) + 0.01 * World.fetch(world, self).image_xscale
        }),
      else: world
  end

  defp land_or_fly(world, self) do
    if Gml.truthy?(Gml.var(world, self, :onGround)) do
      world =
        world
        |> Gml.put(self, %{flying: 0, hspd: Gml.var(world, self, :hspd) * 0.2})
        |> sprite(self, @stand)

      case Gml.prob(world, 2) do
        {true, world} -> Gml.put(world, self, %{flying: 1, vspd: -2})
        {false, world} -> world
      end
    else
      hspd = abs(Gml.var(world, self, :hspd))
      vspd = abs(Gml.var(world, self, :vspd))
      sprite(world, self, if(Gml.gt?(hspd, 0.25) and Gml.lt?(vspd, hspd), do: @fly, else: @hover))
    end
  end

  defp turn_back(world, self, _other) do
    world = Gml.put(world, self, %{hspd: -Gml.var(world, self, :hspd)})
    {_perch, world} = find_perch(world, self)
    world
  end

  defp ceiling(world, self, _other) do
    if Gml.lt?(Gml.var(world, self, :vspd), 0) do
      {_perch, world} = find_perch(world, self)
      world
    else
      world
    end
  end

  defp bounce(world, self, _other) do
    world
    |> World.update(self, &%{&1 | x: &1.xprevious})
    |> Gml.put(self, %{hspd: Gml.var(world, self, :hspd) * -0.5})
  end

  defp wrap(world, self, _other, way) do
    %Instance{x: x, y: y, hspeed: hspeed, vspeed: vspeed} = instance = World.fetch(world, self)
    {width, height} = sprite_size(world, instance)
    x = wrapped(x, hspeed, width, room_width(world))
    y = if way == :both, do: wrapped(y, vspeed, height, room_height(world)), else: y
    World.update(world, self, &%{&1 | x: x, y: y})
  end

  defp wrapped(position, speed, size, span) when speed < 0 and position < 0,
    do: position + span + size

  defp wrapped(position, speed, size, span) when speed > 0 and position >= span,
    do: position - (span + size)

  defp wrapped(position, _speed, _size, _span), do: position

  defp face(world, self) do
    hspd = Gml.var(world, self, :hspd)

    cond do
      Gml.gt?(hspd, 0) -> World.update(world, self, &%{&1 | image_xscale: 1})
      Gml.lt?(hspd, 0) -> World.update(world, self, &%{&1 | image_xscale: -1})
      true -> world
    end
  end

  defp slow(world, self, across, down, most_across, most_down) do
    hspd = Gml.clamp(Gml.var(world, self, :hspd) * across, -most_across, most_across)
    vspd = Gml.clamp(Gml.var(world, self, :vspd) * down, -most_down, most_down)
    Gml.put(world, self, %{hspd: hspd, vspd: vspd})
  end

  defp sprite(world, self, sprite), do: World.update(world, self, &%{&1 | sprite_index: sprite})

  defp frames(world, self) do
    case World.sprite(world, World.fetch(world, self).sprite_index) do
      nil -> 1
      definition -> length(definition.frames)
    end
  end

  defp sprite_size(world, %Instance{
         sprite_index: sprite,
         image_xscale: xscale,
         image_yscale: yscale
       }) do
    case World.sprite(world, sprite) do
      nil -> {0, 0}
      %{size: {width, height}} -> {width * xscale, height * yscale}
      _other -> {0, 0}
    end
  end

  defp hsv(hue, saturation, value), do: Colour.hsv(hue, saturation, value)
  defp distance({x1, y1}, {x2, y2}), do: :math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))
  defp object_name(world, self), do: World.object(world, World.fetch(world, self).object).name

  defp room_width(world),
    do: world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size) |> elem(0)

  defp room_height(world),
    do: world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size) |> elem(1)
end
