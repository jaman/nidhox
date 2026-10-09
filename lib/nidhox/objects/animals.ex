defmodule Nidhox.Objects.Animals do
  @moduledoc """
  The squirrels, cats and birds of the rooms (`Squirrel`, `Cat` and `Bird`, all
  `GrassDisturbingAnimal`s), in their own sprites from the data file.

  A squirrel or a cat sits (`sprSquirrelStand`, `sprCatSit`) and now and then walks a
  short way about where it was placed (`sprSquirrelWalk`, `sprCatWalk`), each at its
  kind's pace (`@ground`). A bird perches (`sprBirdStand`) and now and then pecks.
  Either is startled — its user event 0 — when a fencer comes within `@startle` pixels:
  the squirrel runs off (`sprSquirrelRun`), the cat bounds off (`sprCatPounce`), the
  bird flies off (`sprBirdFly`), away from
  the nearest fencer, and is destroyed once it leaves the room; one placed outside the
  room stays.

  Fencers are read from the global `:fencers`, a list of `{x, y}` positions; with none
  set, nothing startles them. Pauses and directions are drawn from the instance id and
  the step count, so the same world steps the same way on every machine.
  """

  alias Cauldron2D.GameMaker.Data
  alias Cauldron2D.GameMaker.Instance
  alias Cauldron2D.GameMaker.World

  @startle 56
  @ground %{
    "Squirrel" => %{
      sit: {"sprSquirrelStand", 0.12},
      walk: {"sprSquirrelWalk", 0.2},
      run: {"sprSquirrelRun", 0.4}
    },
    "Cat" => %{sit: {"sprCatSit", 1.0}, walk: {"sprCatWalk", 1.0}, run: {"sprCatPounce", 1.0}}
  }
  @wander 24
  @walk_pace 0.35
  @run_pace 2.5
  @sit_steps 150..420
  @walk_steps 30..80
  @peck_steps 10
  @perch_steps 90..300
  @flap_speed 0.3
  @fly_pace {1.6, -1.4}

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Squirrel_Create_0", &squirrel_sits/3},
      {"gml_Object_Squirrel_Step_1", &squirrel_step/3},
      {"gml_Object_Squirrel_Other_10", &squirrel_runs/3},
      {"gml_Object_Squirrel_Other_0", &gone/3},
      {"gml_Object_Cat_Create_0", &squirrel_sits/3},
      {"gml_Object_Cat_Step_1", &squirrel_step/3},
      {"gml_Object_Cat_Other_10", &squirrel_runs/3},
      {"gml_Object_Cat_Other_0", &gone/3},
      {"gml_Object_Bird_Create_0", &bird_perches/3},
      {"gml_Object_Bird_Step_1", &bird_step/3},
      {"gml_Object_Bird_Other_10", &bird_flies/3},
      {"gml_Object_Bird_Other_0", &gone/3}
    ]
  end

  @doc "The world with the global `:fencers` set to `positions`, for the animals to see."
  @spec watch(World.t(), [{number(), number()}]) :: World.t()
  def watch(%World{} = world, positions), do: World.put_global(world, :fencers, positions)

  defp squirrel_sits(world, self, _other),
    do: world |> ground(self, :sit) |> still(self, :sitting, @sit_steps)

  defp squirrel_step(world, self, _other) do
    case World.fetch(world, self) do
      %Instance{vars: %{mode: :running}} -> world
      instance -> squirrel_idles(world, instance)
    end
  end

  defp squirrel_idles(world, %Instance{id: id} = instance) do
    cond do
      startled?(world, instance) -> World.perform(world, id, :other, 10)
      instance.vars.timer > 0 -> tick(world, id)
      instance.vars.mode == :sitting -> squirrel_walks(world, instance)
      true -> squirrel_sits(world, id, nil)
    end
  end

  defp squirrel_walks(world, %Instance{id: id} = instance) do
    heading = homeward(world, instance)

    world
    |> ground(id, :walk)
    |> World.update(
      id,
      &moving(&1, :walking, heading, {@walk_pace, 0.0}, draw(world, id, @walk_steps))
    )
  end

  defp squirrel_runs(world, self, _other) do
    instance = World.fetch(world, self)

    world
    |> ground(self, :run)
    |> World.update(self, &moving(&1, :running, away(world, instance), {@run_pace, 0.0}, 0))
  end

  defp ground(world, id, gait) do
    kind = World.object(world, World.fetch(world, id).object).name
    {sprite, speed} = @ground |> Map.fetch!(kind) |> Map.fetch!(gait)
    pose(world, id, sprite, speed)
  end

  defp bird_perches(world, self, _other) do
    world
    |> pose(self, "sprBirdStand", 0.0)
    |> World.update(self, &%{&1 | image_index: 0.0})
    |> still(self, :perched, @perch_steps)
  end

  defp bird_step(world, self, _other) do
    case World.fetch(world, self) do
      %Instance{vars: %{mode: :flying}} -> world
      instance -> bird_waits(world, instance)
    end
  end

  defp bird_waits(world, %Instance{id: id} = instance) do
    cond do
      startled?(world, instance) -> World.perform(world, id, :other, 10)
      instance.vars.timer > 0 -> tick(world, id)
      instance.vars.mode == :perched -> bird_pecks(world, id)
      true -> bird_perches(world, id, nil)
    end
  end

  defp bird_pecks(world, id),
    do:
      World.update(
        world,
        id,
        &%{&1 | image_index: 1.0, vars: %{&1.vars | mode: :pecking, timer: @peck_steps}}
      )

  defp bird_flies(world, self, _other) do
    instance = World.fetch(world, self)

    world
    |> pose(self, "sprBirdFly", @flap_speed)
    |> World.update(self, &moving(&1, :flying, away(world, instance), @fly_pace, 0))
  end

  defp gone(world, self, _other) do
    case World.fetch(world, self) do
      %Instance{vars: %{mode: mode}} when mode in [:running, :flying] ->
        World.destroy(world, self)

      _placed ->
        world
    end
  end

  defp pose(world, id, sprite, speed) do
    case Data.index(world.data, :sprites, sprite) do
      nil ->
        world

      index ->
        World.update(world, id, &posed(&1, index, speed))
    end
  end

  defp posed(%Instance{sprite_index: index} = instance, index, speed),
    do: %{instance | image_speed: speed}

  defp posed(%Instance{} = instance, index, speed),
    do: %{instance | sprite_index: index, image_speed: speed, image_index: 0.0}

  defp still(world, id, mode, steps) do
    World.update(world, id, fn instance ->
      instance
      |> Instance.put_motion(%{hspeed: 0.0, vspeed: 0.0})
      |> Map.put(:vars, Map.merge(instance.vars, %{mode: mode, timer: draw(world, id, steps)}))
    end)
  end

  defp moving(instance, mode, heading, {pace_x, pace_y}, timer) do
    %{
      Instance.put_motion(instance, %{hspeed: heading * pace_x, vspeed: pace_y})
      | image_xscale: heading * abs(instance.image_xscale),
        vars: Map.merge(instance.vars, %{mode: mode, timer: timer})
    }
  end

  defp tick(world, id),
    do: World.update(world, id, &%{&1 | vars: %{&1.vars | timer: &1.vars.timer - 1}})

  defp draw(world, id, first..last//_),
    do: first + :erlang.phash2({id, world.steps}, last - first + 1)

  defp homeward(world, %Instance{x: x, xstart: home} = instance) do
    cond do
      x - home > @wander -> -1
      home - x > @wander -> 1
      :erlang.phash2({instance.id, world.steps, :heading}, 2) == 0 -> -1
      true -> 1
    end
  end

  defp startled?(world, %Instance{x: x, y: y}),
    do:
      Enum.any?(fencers(world), fn {fx, fy} ->
        abs(fx - x) < @startle and abs(fy - y) < @startle
      end)

  defp away(world, %Instance{x: x}) do
    case Enum.min_by(fencers(world), fn {fx, _} -> abs(fx - x) end, fn -> nil end) do
      {fx, _} when fx > x -> -1
      _ -> 1
    end
  end

  defp fencers(world), do: World.global(world, :fencers, [])
end
