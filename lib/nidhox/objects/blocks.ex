defmodule Nidhox.Objects.Blocks do
  @moduledoc """
  The solid things of a room that move or move what stands on them, as the game's code
  runs them:

    * `Block` create: `hspd`, `vspd` and `conveyor` 0 — what a fencer standing on it is
      carried by (`Nidhox.Man.Physics`)
    * `Conveyor` (a `Block`): its frames run at `conveyor` a step (none while paused);
      depth 99; drawn as its sprite repeated across its width, at its frame.
      `ConveyorLeft` and `conveyorUp` carry at −0.5 a step, `ConveyorRight` at 0.5
    * `Smoosher` (a `Block`) and `SpikeSmoosher`, crushers that drop and climb back, run
      as physics objects each match frame (user event 2): falling (`moving` 3) they
      speed up by 0.1 a step until a `Block` is at their foot — the `Smoosher` checks
      both bottom corners (`x ± sprite_width / 2`), the `SpikeSmoosher` its middle —
      then stop; climbing they slow by 0.1 a step until back at their starting height,
      then fall again; `vspd` is held between −4 and 8. A `Smoosher` that lands is
      heard (129) and waits 60 steps (`timer`) before climbing; a `SpikeSmoosher`
      climbs at once. Each keeps a hidden `BloodSurface` (`blood`) stretched over its
      sprite (its create run again at that size) and moved with it, gone when it is
  """

  alias Cauldron2D.GameMaker.{Draw, Instance, Surfaces, World}
  alias Nidhox.Bout.Sound
  alias Nidhox.Gml
  alias Nidhox.Man.Physics

  @falling 3
  @climbing 2
  @landing_sound 129
  @landed_wait 60
  @conveyor_depth 99

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Block_Create_0", fn world, self, _other -> Gml.put(world, self, %{vspd: 0, hspd: 0, conveyor: 0}) end},
      {"gml_Object_PassThroughBlock_Create_0", fn world, self, _other -> Gml.put(world, self, %{hspd: 0, vspd: 0}) end},
      {"gml_Object_Conveyor_Create_0", &conveyor/3},
      {"gml_Object_Conveyor_Step_0", &conveyor_step/3},
      {"gml_Object_Conveyor_Draw_0", &conveyor_draw/3},
      {"gml_Object_ConveyorLeft_Create_0", &belt(&1, &2, &3, -0.5)},
      {"gml_Object_ConveyorRight_Create_0", &belt(&1, &2, &3, 0.5)},
      {"gml_Object_conveyorUp_Create_0", &belt(&1, &2, &3, -0.5)},
      {"gml_Object_Smoosher_Create_0", &smoosher/3},
      {"gml_Object_SpikeSmoosher_Create_0", &spike_smoosher/3},
      {"gml_Object_Smoosher_Other_12", &smoosher_update/3},
      {"gml_Object_SpikeSmoosher_Other_12", &spike_update/3},
      {"gml_Object_Smoosher_Destroy_0", &lose_blood/3},
      {"gml_Object_SpikeSmoosher_Destroy_0", &lose_blood/3},
      {"gml_Object_Smoosher_Draw_0", fn world, self, _other -> Draw.self(world, self) end},
      {"gml_Object_SpikeSmoosher_Draw_0", fn world, self, _other -> Draw.self(world, self) end}
    ]
  end

  defp conveyor(world, self, other) do
    world
    |> World.inherited(self, "Block", :create, 0, other)
    |> World.update(self, &%{&1 | image_speed: Gml.var(world, self, :conveyor) / 1, depth: @conveyor_depth})
  end

  defp belt(world, self, other, speed) do
    world
    |> World.inherited(self, "Conveyor", :create, 0, other)
    |> Gml.put(self, %{conveyor: speed})
    |> World.update(self, &%{&1 | image_speed: speed})
  end

  defp conveyor_step(world, self, _other),
    do: World.update(world, self, &%{&1 | image_speed: Gml.var(world, self, :conveyor) / 1})

  defp conveyor_draw(world, self, _other) do
    %Instance{x: x, y: y, sprite_index: sprite, image_index: frame, image_xscale: xscale} = World.fetch(world, self)
    width = world |> World.sprite(sprite) |> Map.fetch!(:size) |> elem(0)
    repeats = floor(width * xscale / width)

    Enum.reduce(0..(repeats - 1)//1, world, fn i, world ->
      Draw.sprite(world, sprite, frame, {x + i * width, y})
    end)
  end

  defp smoosher(world, self, other) do
    world
    |> Physics.create(self)
    |> World.inherited(self, "Block", :create, 0, other)
    |> crusher(self)
  end

  defp spike_smoosher(world, self, _other), do: world |> Physics.create(self) |> crusher(self)

  defp crusher(world, self) do
    %Instance{sprite_index: sprite, image_xscale: xscale, image_yscale: yscale} = World.fetch(world, self)
    {width, height} = world |> World.sprite(sprite) |> Map.fetch!(:size)
    {world, blood} = World.create(world, World.object_index(world, "BloodSurface"), {0, 0})
    %Instance{sprite_index: blood_sprite} = World.fetch(world, blood)
    {blood_width, blood_height} = world |> World.sprite(blood_sprite) |> Map.fetch!(:size)
    stale = Gml.var(world, blood, :blood, -1)

    world
    |> World.update(blood, &%{&1 | image_xscale: width * xscale / blood_width, image_yscale: height * yscale / blood_height})
    |> free_surface(stale)
    |> World.perform(blood, :create, 0)
    |> Gml.put(self, %{moving: @falling, blood: blood, timer: 0})
  end

  defp free_surface(world, surface) do
    if Surfaces.exists?(world, surface),
      do: Surfaces.free(world, surface),
      else: world
  end

  defp smoosher_update(world, self, _other) do
    world = Physics.begin_step(world, self)
    %Instance{x: x, y: y, ystart: start} = World.fetch(world, self)
    half = sprite_width(world, self) / 2

    world =
      if Gml.var(world, self, :moving) == @falling do
        if not Physics.block_at?(world, {x - half, y}) and not Physics.block_at?(world, {x + half, y}),
          do: Gml.put(world, self, %{vspd: Gml.var(world, self, :vspd) + 0.1}),
          else: smoosher_landed(world, self, {x, y})
      else
        climb(world, self, y, start)
      end

    world |> clamp_speed(self) |> Physics.end_step(self) |> carry_blood(self) |> count_down(self)
  end

  defp smoosher_landed(world, self, {x, y}) do
    world =
      if Gml.var(world, self, :vspd) > 0,
        do: world |> Gml.put(self, %{vspd: 0, timer: @landed_wait}) |> Sound.play(@landing_sound, {x, y}),
        else: world

    if Gml.var(world, self, :timer) < 0,
      do: world |> Gml.put(self, %{moving: @climbing}) |> Gml.put(self, %{vspd: Gml.var(world, self, :vspd) - 0.1}),
      else: world
  end

  defp spike_update(world, self, _other) do
    world = Physics.begin_step(world, self)
    %Instance{x: x, y: y, ystart: start} = World.fetch(world, self)

    world =
      if Gml.var(world, self, :moving) == @falling do
        if Physics.block_at?(world, {x, y}),
          do: Gml.put(world, self, %{vspd: 0, moving: @climbing}),
          else: Gml.put(world, self, %{vspd: Gml.var(world, self, :vspd) + 0.1})
      else
        climb(world, self, y, start)
      end

    world |> clamp_speed(self) |> Physics.end_step(self) |> carry_blood(self)
  end

  defp climb(world, self, y, start) do
    if y > start,
      do: Gml.put(world, self, %{vspd: Gml.var(world, self, :vspd) - 0.1}),
      else: Gml.put(world, self, %{vspd: 0, moving: @falling})
  end

  defp clamp_speed(world, self), do: Gml.put(world, self, %{vspd: Gml.clamp(Gml.var(world, self, :vspd), -4, 8)})

  defp carry_blood(world, self) do
    case World.fetch(world, self) do
      nil ->
        world

      %Instance{x: x, y: y, sprite_index: sprite} ->
        {origin_x, origin_y} = World.sprite(world, sprite).origin
        blood = Gml.var(world, self, :blood, -4)

        if World.fetch(world, blood),
          do: World.update(world, blood, &%{&1 | x: x - origin_x, y: y - origin_y, visible: false}),
          else: world
    end
  end

  defp count_down(world, self), do: Gml.put(world, self, %{timer: Gml.var(world, self, :timer) - 1})

  defp lose_blood(world, self, _other) do
    blood = Gml.var(world, self, :blood, -4)
    if World.fetch(world, blood), do: World.destroy(world, blood), else: world
  end

  defp sprite_width(world, self) do
    %Instance{sprite_index: sprite, image_xscale: xscale} = World.fetch(world, self)
    elem(World.sprite(world, sprite).size, 0) * xscale
  end
end
