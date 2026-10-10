defmodule Nidhox.Objects.System do
  @moduledoc """
  The game's `System` object: one instance, made as the game starts and kept across
  rooms, holding the settings and counters the rest of the game's code reads as
  `System.<name>`.

  Its create sets, as the game's does:

    * `frame` and `metaFrame` 0; `level` 20; `time_limit` 0; `freezeTimer` 0
    * `musicVol` and `sfxVol` 1; `gui` and `pauseSurface` −1; `vsync` 0; `FEEDBACK`,
      `specialEffects` and `aperture` 1
    * `details` `[9000, 9001, 9002]` and `detail` the first of them; `windowed`,
      `flashing` and `persistent_blood` 1
    * `flow` 4
    * `priorityList` `[48, 49, 55, 29, 14, 70, 8]`
    * the variants: `throws` and `divekicks` 1; `noSwords`, `lowGravity`,
      `suddenDeathOnly`, `throwsOnly`, `babyMode`, `skippyMode`, `turboMode`,
      `slowMode`, `spineSwords`, `boomerangSwords` and `trails` 0

  and makes the listener (`Ear`), the backdrop (`BackgroundObject`), the particles
  (`Particles`) and the fencers' outlines (`PlayerOutlines`).

  Each begin step `metaFrame` counts and the match's frames run (`Nidhox.Bout.Frame.system_step/2`).
  Each room start sets `aperture` to 1 and the lighting (`setLightingLightDarkAlpha(140,
  0.15)`: `lightAmount` 140, `darkAmount` 0.15, `darknessAlpha` 0); each end step takes
  0.1 from `aperture`; and its GUI draw, while `aperture` is above 0, covers the
  320 × 200 GUI in black at alpha `aperture`, the screen coming up out of black over
  the first ten steps of every room.

  `create/1` makes it; `get/2` reads one of its variables.
  """

  alias Cauldron2D.GameMaker.{Draw, World}
  alias Nidhox.Bout.Frame
  alias Nidhox.Gml

  @object "System"
  @gui_width 320
  @gui_height 200
  @made ["Ear", "BackgroundObject", "Particles", "PlayerOutlines"]

  @start %{
    frame: 0,
    metaFrame: 0,
    level: 20,
    time_limit: 0,
    freezeTimer: 0,
    musicVol: 1,
    sfxVol: 1,
    gui: -1,
    vsync: 0,
    FEEDBACK: 1,
    specialEffects: 1,
    aperture: 1,
    pauseSurface: -1,
    details: [9000, 9001, 9002],
    detail: 9000,
    windowed: 1,
    flashing: 1,
    persistent_blood: 1,
    flow: 4,
    priorityList: [48, 49, 55, 29, 14, 70, 8],
    throws: 1,
    divekicks: 1,
    noSwords: 0,
    lowGravity: 0,
    suddenDeathOnly: 0,
    throwsOnly: 0,
    babyMode: 0,
    skippyMode: 0,
    turboMode: 0,
    slowMode: 0,
    spineSwords: 0,
    boomerangSwords: 0,
    trails: 0
  }

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers,
    do: [
      {"gml_Object_System_Create_0", &start/3},
      {"gml_Object_System_Step_1", &begin_step/3},
      {"gml_Object_System_Other_4", &room_start/3},
      {"gml_Object_System_Step_2", &end_step/3},
      {"gml_Object_System_Draw_64", &draw_gui/3}
    ]

  @doc "`world` with the `System` object made, as the game makes it when it starts."
  @spec create(World.t()) :: World.t()
  def create(%World{} = world) do
    case World.object_index(world, @object) do
      nil -> world
      object -> world |> World.create(object, {0, 0}) |> elem(0)
    end
  end

  @doc "`System`'s variable `name` (`System.<name>`), `default` when there is no `System`."
  @spec get(World.t(), atom(), term()) :: term()
  def get(%World{} = world, name, default \\ 0) do
    case instance(world) do
      nil -> default
      id -> Gml.var(world, id, name, default)
    end
  end

  @doc "`world` with `System`'s variables in `vars` set; unchanged when there is no `System`."
  @spec put(World.t(), map()) :: World.t()
  def put(%World{} = world, vars) do
    case instance(world) do
      nil -> world
      id -> Gml.put(world, id, vars)
    end
  end

  defp instance(world) do
    with object when is_integer(object) <- World.object_index(world, @object),
         [id | _] <- World.instances_of(world, object) do
      id
    else
      _none -> nil
    end
  end

  defp room_start(world, self, _other),
    do: Gml.put(world, self, %{aperture: 1, lightAmount: 140, darkAmount: 0.15, darknessAlpha: 0})

  defp end_step(world, self, _other),
    do: Gml.put(world, self, %{aperture: Gml.var(world, self, :aperture) - 0.1})

  defp draw_gui(world, self, _other) do
    aperture = Gml.var(world, self, :aperture)
    if Gml.gt?(aperture, 0), do: Draw.item(world, blackout(world, aperture)), else: world
  end

  defp blackout(%World{data: %{general: %{window: {width, _height}}}}, aperture) do
    zoom = width / @gui_width

    %{
      picture: :pixel,
      position: {0, 0},
      scale: {@gui_width * zoom, @gui_height * zoom},
      blend: {0, 0, 0},
      alpha: aperture,
      depth: 0
    }
  end

  defp begin_step(world, self, _other) do
    world
    |> Gml.put(self, %{metaFrame: Gml.var(world, self, :metaFrame) + 1})
    |> Frame.system_step(self)
  end

  defp start(world, self, _other) do
    world = Gml.put(world, self, @start)

    Enum.reduce(@made, world, fn name, world ->
      case World.object_index(world, name) do
        nil -> world
        object -> world |> World.create(object, {0, 0}) |> elem(0)
      end
    end)
  end
end
