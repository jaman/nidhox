defmodule Nidhox.Objects.BloodSurface do
  @moduledoc """
  The game's `BloodSurface`: a stretch of ground that keeps the blood spilt on it, in a
  surface (`blood`) its size (`w`, `h`: its scaled sprite's width and height) that
  blood drops paint on (`Nidhox.Objects.BloodDrop`).

    * create: no surfaces yet, then user event 0; `alarm[0]` 4; `active` 0
    * user event 0: its surface found by its key — the room's name, its `x`, `y`, and
      rounded `w` and `h` — in the match's blood bank (`Match.bloodbank`), so blood
      stays in a room the bout comes back to; one made clear when there is none (and
      put in the bank with a match); and a clear `previous_blood` of the same size
    * alarm 0, every 3 steps: while `active` (drops landed lately), the blood runs —
      the surface copied to `previous_blood`, then 4 times a 10-pixel-wide strip from a
      random place (`random(w − 10)`, `random(h − 10)`), as tall as its top is far down
      plus 10, drawn back 1 or 2 pixels higher and again 1 or 2 lower, one time in five
      shifted across by up to a tenth of its height (`irandom_range`); `active` counts
      down
    * draw: the surface (made again if it was lost) at its place
    * room end, game end and destroy: `previous_blood` freed

  `free_bank/1` is the match's `Other_20`: every surface in the blood bank freed, which
  the match does at a room's end without persistent blood (`System.persistent_blood`).
  """

  alias Cauldron2D.GameMaker.{Draw, Instance, Surfaces, World}
  alias Nidhox.Gml

  @run_every 3
  @first_run 4
  @strips 4
  @strip 10

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_BloodSurface_Create_0", &start/3},
      {"gml_Object_BloodSurface_Other_10",
       fn world, self, _other -> find_surface(world, self) end},
      {"gml_Object_BloodSurface_Alarm_0", &run/3},
      {"gml_Object_BloodSurface_Draw_0", &draw/3},
      {"gml_Object_BloodSurface_Other_5", &free_previous/3},
      {"gml_Object_BloodSurface_Other_3", &free_previous/3},
      {"gml_Object_BloodSurface_Destroy_0", &free_previous/3}
    ]
  end

  @doc "The world with every surface in the match `match`'s blood bank freed."
  @spec free_bank(World.t(), non_neg_integer()) :: World.t()
  def free_bank(%World{} = world, match) do
    world
    |> Gml.var(match, :bloodbank, %{})
    |> Map.values()
    |> Enum.reduce(world, fn surface, world ->
      if Surfaces.exists?(world, surface), do: Surfaces.free(world, surface), else: world
    end)
  end

  defp start(world, self, _other) do
    %Instance{} = instance = World.fetch(world, self)
    {width, height} = scaled_size(world, instance)

    world
    |> Gml.put(self, %{w: width, h: height, blood: -1, previous_blood: -1})
    |> find_surface(self)
    |> World.update(self, &Instance.put_alarm(&1, 0, @first_run))
    |> Gml.put(self, %{active: 0})
  end

  defp scaled_size(world, %Instance{
         sprite_index: sprite,
         image_xscale: xscale,
         image_yscale: yscale
       }) do
    case World.sprite(world, sprite) do
      nil -> {0, 0}
      definition -> {elem(definition.size, 0) * xscale, elem(definition.size, 1) * yscale}
    end
  end

  defp find_surface(world, self) do
    %Instance{x: x, y: y, vars: vars} = World.fetch(world, self)
    width = Map.get(vars, :w)
    height = Map.get(vars, :h)
    key = key(world, {x, y}, {width, height})
    match = Gml.first(world, "Match")

    world = if match, do: from_bank(world, self, match, key, {width, height}), else: world

    world =
      if Surfaces.exists?(world, Gml.var(world, self, :blood, -1)) do
        world
      else
        {world, blood} = clear_surface(world, width, height)
        world = Gml.put(world, self, %{blood: blood})
        if match, do: put_in_bank(world, match, key, blood), else: world
      end

    {world, previous} = clear_surface(world, width, height)
    Gml.put(world, self, %{previous_blood: previous})
  end

  defp from_bank(world, self, match, key, {width, height}) do
    bank = Gml.var(world, match, :bloodbank, %{})
    world = if Map.has_key?(bank, key), do: Gml.put(world, self, %{blood: bank[key]}), else: world

    if Surfaces.exists?(world, Gml.var(world, self, :blood, -1)) do
      world
    else
      {world, blood} = clear_surface(world, width, height)
      world |> put_in_bank(match, key, blood) |> Gml.put(self, %{blood: blood})
    end
  end

  defp put_in_bank(world, match, key, blood),
    do:
      Gml.put(world, match, %{
        bloodbank: Map.put(Gml.var(world, match, :bloodbank, %{}), key, blood)
      })

  defp clear_surface(world, width, height) do
    {world, surface} = Surfaces.create(world, max(round(width), 1), max(round(height), 1))
    {Surfaces.clear(world, surface, {0, 0, 0}, 0), surface}
  end

  defp key(world, {x, y}, {width, height}) do
    room = Enum.at(world.data.rooms, world.room).name
    room <> string(x) <> string(y) <> string(Gml.round(width)) <> string(Gml.round(height))
  end

  defp string(value) when is_integer(value), do: Integer.to_string(value)

  defp string(value) do
    if value == Float.round(value / 1, 0),
      do: Integer.to_string(trunc(value)),
      else: :erlang.float_to_binary(value / 1, decimals: 2)
  end

  defp run(world, self, _other) do
    world = World.update(world, self, &Instance.put_alarm(&1, 0, @run_every))

    if Gml.var(world, self, :active) > 0 do
      world = ensure_blood(world, self)
      blood = Gml.var(world, self, :blood)
      previous = Gml.var(world, self, :previous_blood)
      world = Surfaces.copy(world, previous, {0, 0}, blood)
      {strips, world} = strips(world, self, previous)

      world
      |> Surfaces.draw(blood, strips)
      |> Gml.put(self, %{active: Gml.var(world, self, :active) - 1})
    else
      world
    end
  end

  defp ensure_blood(world, self) do
    if Surfaces.exists?(world, Gml.var(world, self, :blood, -1)),
      do: world,
      else: world |> find_surface(self) |> ensure_blood(self)
  end

  defp strips(world, self, previous) do
    width = Gml.var(world, self, :w)
    height = Gml.var(world, self, :h)

    Enum.reduce(1..@strips, {[], world}, fn _strip, {items, world} ->
      {across, world} = Gml.random(world, width - @strip)
      {down, world} = Gml.random(world, height - @strip)
      {shift, world} = shift(world, down)
      {up, world} = Gml.choose(world, [1, 2])
      {lower, world} = Gml.choose(world, [1, 2])
      part = {across, down, @strip, down + @strip}

      drawn =
        [
          Surfaces.part_item(world, previous, part, {across + shift, down - up}),
          Surfaces.part_item(world, previous, part, {across + shift, down + lower})
        ]
        |> Enum.reject(&is_nil/1)

      {items ++ drawn, world}
    end)
  end

  defp shift(world, down) do
    {drifts, world} = Gml.prob(world, 20)

    if drifts do
      reach = Gml.round(down * 0.1)
      {roll, world} = Gml.irandom(world, reach - Gml.round(-down * 0.1))
      {Gml.round(-down * 0.1) + roll, world}
    else
      {0, world}
    end
  end

  defp draw(world, self, _other) do
    world =
      if Surfaces.exists?(world, Gml.var(world, self, :blood, -1)),
        do: world,
        else: find_surface(world, self)

    %Instance{x: x, y: y} = World.fetch(world, self)
    blood = Gml.var(world, self, :blood)

    if Surfaces.exists?(world, blood),
      do: Draw.item(world, Surfaces.item(world, blood, {x, y})),
      else: world
  end

  defp free_previous(world, self, _other) do
    previous = Gml.var(world, self, :previous_blood, -1)
    if Surfaces.exists?(world, previous), do: Surfaces.free(world, previous), else: world
  end
end
