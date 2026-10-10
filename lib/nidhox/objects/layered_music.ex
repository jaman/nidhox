defmodule Nidhox.Objects.LayeredMusic do
  @moduledoc """
  The game's `LayeredMusic`, made by the `Match` and kept across rooms: an area's music
  as layers that play together, each at its own level.

    * create: `mode` "random", `counter`, `maximumVol`, `movementCounter` 0,
      `firstChoice` 1, `dipLevels` 1, not playing; its `layers` by `System.level` —
      Cemetery (25) drums, distant melody, melody (sounds 1, 154, 0); Castle (20) 130–133;
      Mines (21) 138–141, 135–137; Sky (22) 149–152, 148; Wilds (23) 143–146
    * room start, the first time: every layer starts looping (`audio_play_sound(layer,
      1, true)`), its `mixer` and `volumes` 0
    * end step, while playing: `dipMusic` by the fencers — with two, `0.25 +
      clamp(|OrangePlayer.x − YellowPlayer.x| / 280, 0, 1)`; with one, 1; with none, 0.8.
      Unless paused, the speed `clamp(getManVelocity(), 0, 1)` adds to `movementCounter`
      (back to 0 below 0.2) and lifts `DRUMS` to it, which otherwise falls 1/180 a step;
      the area mixes (`Nidhox.Music.Mixer`); in rooms of `roomCode` 4 and 7 the music
      fades by where the first fencer is — `(x / room_width)²` in 4, `(1 − x /
      room_width)²` in 7, × 0.25, nothing without a fencer; `counter` counts on,
      `maximumVol` and `dipLevels` move towards 1 (by 0.05 and 0.015 of the way). Then
      each layer's `volumes` moves 0.05 of the way to `mixer × fade × maximumVol` and the
      layer plays at `volumes × System.musicVol`

  `dip/3` is `dipMusic`; `levels/1` the level each layer plays at.
  """

  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Bout.Camera
  alias Nidhox.Gml
  alias Nidhox.Music.Mixer
  alias Nidhox.Objects.{RoomCodes, System}

  @layers %{
    25 => [1, 154, 0],
    20 => [130, 131, 132, 133],
    21 => [138, 139, 140, 141, 135, 136, 137],
    22 => [149, 150, 151, 152, 148],
    23 => [143, 144, 145, 146]
  }
  @apart 280
  @pair_dip 0.25
  @lone_dip 1
  @empty_dip 0.8
  @still 0.2
  @drum_fall 1 / 180
  @fade_rooms [4, 7]
  @fade_scale 0.25
  @ease 0.05
  @dip_ease 0.015

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_LayeredMusic_Create_0", &start/3},
      {"gml_Object_LayeredMusic_Other_4", &begin/3},
      {"gml_Object_LayeredMusic_Step_2", &step/3}
    ]
  end

  @doc """
  `dipMusic(amount, add)`: every `LayeredMusic`'s `dipLevels` set to `clamp(amount, 0,
  1)`, or with `add` true, raised by it and clamped.
  """
  @spec dip(World.t(), number(), boolean()) :: World.t()
  def dip(%World{} = world, amount, add) do
    amount = Gml.clamp(amount, 0, 1)

    world
    |> Gml.all("LayeredMusic")
    |> Enum.reduce(world, fn music, world ->
      dip_levels = if add, do: Gml.clamp(Gml.var(world, music, :dipLevels, 1) + amount, 0, 1), else: amount
      Gml.put(world, music, %{dipLevels: dip_levels})
    end)
  end

  @doc """
  The level each layer of the first playing `LayeredMusic` plays at, by the sound's
  name (`volumes × System.musicVol`); `nil` without one.
  """
  @spec levels(World.t()) :: %{String.t() => float()} | nil
  def levels(%World{} = world) do
    with music when music != nil <- Gml.first(world, "LayeredMusic"),
         true <- Gml.truthy?(Gml.var(world, music, :playingMusic)) do
      volume = System.get(world, :musicVol, 1)

      world
      |> Gml.var(music, :volumes, %{})
      |> Map.new(fn {sound, level} -> {sound_name(world, sound), level * volume} end)
    else
      _none -> nil
    end
  end

  defp start(world, self, _other) do
    Gml.put(world, self, %{
      mode: "random",
      counter: 0,
      firstChoice: 1,
      maximumVol: 0,
      movementCounter: 0,
      z: ear_z(world),
      layers: Map.get(@layers, round(System.get(world, :level)), []),
      mixer: %{},
      volumes: %{},
      playingMusic: 0,
      dipLevels: 1
    })
  end

  defp begin(world, self, _other) do
    if Gml.truthy?(Gml.var(world, self, :playingMusic)) do
      world
    else
      silent = world |> Gml.var(self, :layers, []) |> Map.new(&{&1, 0})
      Gml.put(world, self, %{playingMusic: 1, mixer: silent, volumes: silent})
    end
  end

  defp step(world, self, _other) do
    if Gml.truthy?(Gml.var(world, self, :playingMusic)) do
      {world, fade} = world |> dip_by_fencers() |> unpaused(self)
      apply_volumes(world, self, fade)
    else
      world
    end
  end

  defp dip_by_fencers(world) do
    case length(Gml.all(world, "Man")) do
      2 -> dip(world, @pair_dip + Gml.clamp(abs(x_of(world, "OrangePlayer") - x_of(world, "YellowPlayer")) / @apart, 0, 1), false)
      1 -> dip(world, @lone_dip, false)
      0 -> dip(world, @empty_dip, false)
      _more -> world
    end
  end

  defp unpaused(world, self) do
    speed = Gml.clamp(man_velocity(world), 0, 1)
    world = Gml.put(world, self, %{movementCounter: Gml.var(world, self, :movementCounter) + speed})
    world = if speed < @still, do: Gml.put(world, self, %{movementCounter: 0}), else: world
    drums = Gml.var(world, self, :DRUMS)
    drums = if speed < drums, do: Gml.clamp(drums - @drum_fall, 0, 1), else: speed

    world =
      world
      |> Gml.put(self, %{DRUMS: drums})
      |> Mixer.mix(self, round(System.get(world, :level)))

    {settle(world, self), fade(world)}
  end

  defp settle(world, self) do
    counter = Gml.var(world, self, :counter) + 1
    maximum = Gml.var(world, self, :maximumVol)
    dip_levels = Gml.var(world, self, :dipLevels, 1)

    Gml.put(world, self, %{
      counter: counter,
      maximumVol: maximum + (1 - maximum) * @ease,
      dipLevels: dip_levels + (1 - dip_levels) * @dip_ease
    })
  end

  defp fade(world) do
    code = round(RoomCodes.room_code(world))

    case {code in @fade_rooms, Gml.first(world, "Man")} do
      {false, _man} -> 1
      {true, nil} -> 0
      {true, man} -> man_fade(world, code, World.fetch(world, man).x)
    end
  end

  defp man_fade(world, code, x) do
    across = x / Camera.room_width(world)
    across = if code == 7, do: 1 - across, else: across
    Gml.clamp(across * across * @fade_scale, 0, 1)
  end

  defp apply_volumes(world, self, fade) do
    maximum = Gml.var(world, self, :maximumVol)
    mixer = Gml.var(world, self, :mixer, %{})

    volumes =
      world
      |> Gml.var(self, :layers, [])
      |> Enum.reduce(Gml.var(world, self, :volumes, %{}), fn layer, volumes ->
        volume = Map.get(volumes, layer, 0)
        target = Map.get(mixer, layer, 0) * fade * maximum
        Map.put(volumes, layer, volume + (target - volume) * @ease)
      end)

    Gml.put(world, self, %{volumes: volumes})
  end

  defp man_velocity(world) do
    single = Gml.eq?(System.get(world, :flow), 2)

    world
    |> Gml.all("Man")
    |> Enum.map(&World.fetch(world, &1))
    |> Enum.filter(fn %Instance{vars: vars} -> not single or Gml.eq?(Map.get(vars, :playerIndex, 0), 1) end)
    |> Enum.reduce(0, fn %Instance{vars: vars}, total -> total + abs(Map.get(vars, :hspd, 0)) + abs(Map.get(vars, :vspd, 0)) end)
  end

  defp x_of(world, name) do
    case Gml.first(world, name) do
      nil -> 0
      id -> World.fetch(world, id).x
    end
  end

  defp ear_z(world) do
    case Gml.first(world, "Ear") do
      nil -> 0
      ear -> Gml.var(world, ear, :z)
    end
  end

  defp sound_name(world, sound) do
    case Enum.at(world.data.sounds, sound) do
      nil -> ""
      %{name: name} -> name
    end
  end
end
