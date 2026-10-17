defmodule Nidhox.Music.Mixer do
  @moduledoc """
  Each area's mixing rule from `LayeredMusic`'s end step, run once a step while the
  game is not paused: it sets the instance's `mixer`, a map from each of the area's
  music sounds (by index in the data file) to the level it should reach.

  `DRUMS` is the fencers' speed, held at its highest and falling by 1/180 a step. A drum
  layer's `mixer` moves 0.05 of the way to `DRUMS` each step. `counter` counts steps.

    * Cemetery (level 25): every 240 steps, or at first (`airPart` 0), the next
      `airPart` (1 to 4) picks a part with `choose`: from 1 `(1, 2, 2, 1)`, from 2
      `(2, 3, 3, 1)`, from 3 `(3, 4, 4, 1)`, from 4 `(4, 5, 5, 1)`; the first is part 1.
      Each part sets the drums (`music_Cemetery_Drums`), the distant melody (`music_Cemetery_Distant`) and the melody
      (`music_Cemetery_Melody`) on
      or off: 1 all on; 2 drums and distant; 3 melody; 4 distant and melody; 5 drums
      and melody
    * Castle (levels 20 and 26): drums 1 (`music_Castle_Drms1`) at `DRUMS`, at least 0.5 with synth 3; drums 2
      (`music_Castle_Drms2`) moving 0.005 of the way to `DRUMS`, never above drums 1
    * Wilds (level 23): drums (`music_Forest_Drums`) at `DRUMS`, at least 0.5 with synth 4
    * Mines (level 21): basic drums (`music_Mines_BasicDrums`) at `DRUMS`, at least 0.5 with no synths;
      drums 4 part 2 (`music_Mines_Drums4Part2`) moving 0.005 of the way to 0.3 × the basic drums, never above
      them; the mechanical layer (`music_Mines_MechanicalLayer`) by `global.roomCode`: 1 in 1, 0.75 in 2 and 5,
      0.5 in 3 and 6, 0.25 in 9 and 11, 0 elsewhere
    * Sky (level 22): drums (`music_Clouds_Drums`) at `DRUMS`; every 960 steps, or at first, the next
      `airPart` (1 to 4) picks the one synth part playing: from 1 `choose(1, 2)`, from
      2 `(2, 3)`, from 3 `(3, 4)`, from 4 `(4, 1)`; the first is part 1

  The Castle, Wilds and Mines change their synths in `mode` "random": every 240 steps
  all off and a new choice — Castle `SYNTH` `choose(1, 1, 2, 2, 3)`, synth 1 (`music_Castle_Synth1`)
  for 1, synth 2 (`music_Castle_Synth2`) for 2; Wilds `SYNTH` `choose(1, 1, 2, 2, 3, 3, 4)`, synth 1 to 3
  (`music_Forest_Synth1` to `Synth3`) for 1 to 3; Mines `SYNTH1` `choose(0, 1)` and `SYNTH2` `choose(0, 0.5, 1)`,
  synth 1 (`music_Mines_Synth1`) at `SYNTH1`, synth 2 (`music_Mines_Synth2`) at `SYNTH2`,
  part 2 of synth 4 (`music_Mines_Synth4Part2`)
  `choose(0, 1)` when `SYNTH2` is 0 and part 3 (`music_Mines_Synth4Part3`) `choose(0, 1)` when `SYNTH1` is 0.
  The first choice is synth 1 (Mines: both synths 1) and turns `mode` to "set". After
  720 steps "random" becomes "set", after 1200 "set" becomes "random", `counter` back
  to 0 each time.
  """

  alias Cauldron2D.GameMaker.{Data, World}
  alias Nidhox.Gml
  alias Nidhox.Objects.RoomCodes

  @drum_ease 0.05
  @slow_ease 0.005
  @drum_floor 0.5
  @period 240
  @to_set 720
  @to_random 1200
  @sky_period 960
  @parts 4

  @cemetery_parts %{1 => [1, 2, 2, 1], 2 => [2, 3, 3, 1], 3 => [3, 4, 4, 1], 4 => [4, 5, 5, 1]}
  @cemetery_layers %{
    1 => {1, 1, 1},
    2 => {1, 1, 0},
    3 => {0, 0, 1},
    4 => {0, 1, 1},
    5 => {1, 0, 1}
  }
  @sky_parts %{1 => [1, 2], 2 => [2, 3], 3 => [3, 4], 4 => [4, 1]}
  @sky_synths [:sky_synth1, :sky_synth2, :sky_synth3, :sky_synth4]
  @sounds %{
    cemetery_drums: "music_Cemetery_Drums",
    cemetery_distant: "music_Cemetery_Distant",
    cemetery_melody: "music_Cemetery_Melody",
    castle_drums1: "music_Castle_Drms1",
    castle_drums2: "music_Castle_Drms2",
    castle_synth1: "music_Castle_Synth1",
    castle_synth2: "music_Castle_Synth2",
    wilds_drums: "music_Forest_Drums",
    wilds_synth1: "music_Forest_Synth1",
    wilds_synth2: "music_Forest_Synth2",
    wilds_synth3: "music_Forest_Synth3",
    mines_drums: "music_Mines_BasicDrums",
    mines_deep_drums: "music_Mines_Drums4Part2",
    mines_mechanical: "music_Mines_MechanicalLayer",
    mines_synth1: "music_Mines_Synth1",
    mines_synth2: "music_Mines_Synth2",
    mines_synth4_part2: "music_Mines_Synth4Part2",
    mines_synth4_part3: "music_Mines_Synth4Part3",
    sky_drums: "music_Clouds_Drums",
    sky_synth1: "music_Clouds_SynthsPart1",
    sky_synth2: "music_Clouds_SynthsPart2",
    sky_synth3: "music_Clouds_SynthsPart3",
    sky_synth4: "music_Clouds_SynthsPart4"
  }
  @mechanical %{
    1 => 1.0,
    2 => 0.75,
    5 => 0.75,
    3 => 0.5,
    6 => 0.5,
    9 => 0.25,
    11 => 0.25
  }

  @doc "The world after `LayeredMusic` `self` mixes for its `System.level`."
  @spec mix(World.t(), non_neg_integer(), number()) :: World.t()
  def mix(world, self, 25), do: cemetery(world, self)
  def mix(world, self, level) when level in [20, 26], do: castle(world, self)
  def mix(world, self, 23), do: wilds(world, self)
  def mix(world, self, 21), do: mines(world, self)
  def mix(world, self, 22), do: sky(world, self)
  def mix(world, _self, _level), do: world

  defp cemetery(world, self) do
    if Gml.gt?(var(world, self, :counter), @period) or Gml.eq?(var(world, self, :airPart), 0),
      do: cemetery_part(world, self),
      else: world
  end

  defp cemetery_part(world, self) do
    {world, part} = next_part(world, self, @cemetery_parts)
    {drums, distant, melody} = Map.fetch!(@cemetery_layers, part)

    world
    |> put_mix(self, :cemetery_drums, drums)
    |> put_mix(self, :cemetery_distant, distant)
    |> put_mix(self, :cemetery_melody, melody)
  end

  defp next_part(world, self, choices) do
    air_part = var(world, self, :airPart) + 1
    air_part = if Gml.gt?(air_part, @parts), do: 1, else: air_part
    world = Gml.put(world, self, %{counter: 0, airPart: air_part})
    {part, world} = Gml.choose(world, Map.fetch!(choices, round(air_part)))
    first_choice(world, self, part)
  end

  defp first_choice(world, self, part) do
    if Gml.truthy?(var(world, self, :firstChoice)),
      do: {Gml.put(world, self, %{firstChoice: 0}), 1},
      else: {world, part}
  end

  defp castle(world, self) do
    world
    |> ease_drums(self, :castle_drums1, @drum_ease, fn mix -> mix || 1 end)
    |> floor_drums(self, :castle_drums1, Gml.eq?(var(world, self, :SYNTH), 3), fn mix ->
      mix || 1
    end)
    |> ease_drums(self, :castle_drums2, @slow_ease, fn mix -> mix || 1 end)
    |> synths(self, &castle_synths/2)
    |> cap(self, :castle_drums2, :castle_drums1)
  end

  defp castle_synths(world, self) do
    world = world |> put_mix(self, :castle_synth1, 0) |> put_mix(self, :castle_synth2, 0)
    {synth, world} = Gml.choose(world, [1, 1, 2, 2, 3])
    world = world |> Gml.put(self, %{SYNTH: synth}) |> first_synth(self, %{SYNTH: 1})

    case round(var(world, self, :SYNTH)) do
      1 -> put_mix(world, self, :castle_synth1, 1)
      2 -> put_mix(world, self, :castle_synth2, 1)
      _none -> world
    end
  end

  defp wilds(world, self) do
    world
    |> ease_drums(self, :wilds_drums, @drum_ease, &(&1 || 0))
    |> floor_drums(self, :wilds_drums, Gml.eq?(var(world, self, :SYNTH), 4), &(&1 || 0))
    |> synths(self, &wilds_synths/2)
  end

  defp wilds_synths(world, self) do
    world =
      Enum.reduce([:wilds_synth1, :wilds_synth2, :wilds_synth3], world, &put_mix(&2, self, &1, 0))

    {synth, world} = Gml.choose(world, [1, 1, 2, 2, 3, 3, 4])
    world = world |> Gml.put(self, %{SYNTH: synth}) |> first_synth(self, %{SYNTH: 1})

    case round(var(world, self, :SYNTH)) do
      1 -> put_mix(world, self, :wilds_synth1, 1)
      2 -> put_mix(world, self, :wilds_synth2, 1)
      3 -> put_mix(world, self, :wilds_synth3, 1)
      _none -> world
    end
  end

  defp mines(world, self) do
    world = ease_drums(world, self, :mines_drums, @drum_ease, &(&1 || 0))
    basic = mix_of(world, self, :mines_drums) || 0
    deep = mix_of(world, self, :mines_deep_drums) || 0
    world = put_mix(world, self, :mines_deep_drums, deep + (basic * 0.3 - deep) * @slow_ease)
    silent = Gml.eq?(var(world, self, :SYNTH1), 0) and Gml.eq?(var(world, self, :SYNTH2), 0)

    world
    |> floor_drums(self, :mines_drums, silent, &(&1 || 0))
    |> put_mix(
      self,
      :mines_mechanical,
      Map.get(@mechanical, round(RoomCodes.room_code(world)), 0)
    )
    |> synths(self, &mines_synths/2)
    |> cap(self, :mines_deep_drums, :mines_drums)
  end

  defp mines_synths(world, self) do
    world =
      Enum.reduce(
        [:mines_synth1, :mines_synth2, :mines_synth4_part2, :mines_synth4_part3],
        world,
        &put_mix(&2, self, &1, 0)
      )

    {first, world} = Gml.choose(world, [0, 1])
    world = Gml.put(world, self, %{SYNTH1: first})
    {second, world} = Gml.choose(world, [0, 0.5, 1])

    world =
      world
      |> Gml.put(self, %{SYNTH2: second})
      |> first_synth(self, %{SYNTH1: 1, SYNTH2: 1})

    synth_two = var(world, self, :SYNTH2)

    world =
      world
      |> put_mix(self, :mines_synth2, synth_two)
      |> part_of_four(self, :mines_synth4_part2, Gml.eq?(synth_two, 0))

    synth_one = var(world, self, :SYNTH1)

    world
    |> put_mix(self, :mines_synth1, synth_one)
    |> part_of_four(self, :mines_synth4_part3, Gml.eq?(synth_one, 0))
  end

  defp part_of_four(world, self, layer, true) do
    {on, world} = Gml.choose(world, [0, 1])
    put_mix(world, self, layer, on)
  end

  defp part_of_four(world, self, layer, false), do: put_mix(world, self, layer, 0)

  defp sky(world, self) do
    world = ease_drums(world, self, :sky_drums, @drum_ease, &(&1 || 0))

    if Gml.gt?(var(world, self, :counter), @sky_period) or Gml.eq?(var(world, self, :airPart), 0),
      do: sky_part(world, self),
      else: world
  end

  defp sky_part(world, self) do
    {world, part} = next_part(world, self, @sky_parts)

    world
    |> then(&Enum.reduce(@sky_synths, &1, fn synth, world -> put_mix(world, self, synth, 0) end))
    |> put_mix(self, Enum.at(@sky_synths, part - 1), 1)
  end

  defp synths(world, self, change) do
    if Gml.var(world, self, :mode, "random") == "random",
      do: random_synths(world, self, change),
      else: set_synths(world, self)
  end

  defp random_synths(world, self, change) do
    counter = var(world, self, :counter)
    world = if Gml.eq?(:math.fmod(counter, @period), 0), do: change.(world, self), else: world

    if Gml.gt?(var(world, self, :counter), @to_set),
      do: Gml.put(world, self, %{mode: "set", counter: 0}),
      else: world
  end

  defp set_synths(world, self) do
    if Gml.gt?(var(world, self, :counter), @to_random),
      do: Gml.put(world, self, %{mode: "random", counter: 0}),
      else: world
  end

  defp first_synth(world, self, firsts) do
    if Gml.truthy?(var(world, self, :firstChoice)),
      do: Gml.put(world, self, Map.merge(firsts, %{firstChoice: 0, mode: "set"})),
      else: world
  end

  defp ease_drums(world, self, layer, ease, start) do
    mix = start.(mix_of(world, self, layer))
    put_mix(world, self, layer, mix + (var(world, self, :DRUMS) - mix) * ease)
  end

  defp floor_drums(world, _self, _layer, false, _start), do: world

  defp floor_drums(world, self, layer, true, start),
    do: put_mix(world, self, layer, max(@drum_floor, start.(mix_of(world, self, layer))))

  defp cap(world, self, layer, by),
    do:
      put_mix(
        world,
        self,
        layer,
        min(mix_of(world, self, by) || 0, mix_of(world, self, layer) || 0)
      )

  defp mix_of(world, self, layer),
    do: world |> Gml.var(self, :mixer, %{}) |> Map.get(sound(world, layer))

  defp put_mix(world, self, layer, value) do
    mixer = world |> Gml.var(self, :mixer, %{}) |> Map.put(sound(world, layer), value)
    Gml.put(world, self, %{mixer: mixer})
  end

  defp sound(world, layer), do: Data.index(world.data, :sounds, Map.fetch!(@sounds, layer))

  defp var(world, self, name), do: Gml.var(world, self, name, 0)
end
