defmodule Nidhox.Objects.Match do
  @moduledoc """
  The game's `Match`: one instance, kept across rooms, holding a match together. Its
  frames run from `System`'s begin step (`Nidhox.Bout.Frame`).

    * create: every fencer and the old `MatchStats` gone, a new `MatchStats`; no fencers
      (`yellowInstance`, `orangeInstance`, `priorityInstance` −4), no thrown swords or
      pickups; both players' swords (`yellowSword`, `orangeSword`) 1; kill streaks 0;
      `spawnDelay` 100 and the spawn timer at it; nobody leading, now or before;
      `change_animation`, `wrongWay`, `wrongWayCounter` 0; the camera's centre
      remembered (`pCameraCenterX`, `pCameraCenterY`); `System.frame` 0;
      `roomFrame` 0; `firstFrameOfRoom` 1; a faceoff of 120 steps; `idleTime` and
      `finished` 0; the clock from `System.time_limit` (`useCountDownTimer` when it is
      set, `countDownTimer` its frames); not in sudden death; no buttons kept
      (`inputMap`, `lastFramePolled` −1); `faceoffWinner` 0; `cleanHands`, `cleanFeet`,
      `cleanSword`, `perfect` 1; no comeback for either player. A demonstration
      (`System.flow` 1) has the computer play both players (`Brain`s for 1 and 2), a
      single player game (2) player 2. In flows 1 to 4 (and 790474) it makes the music
      (`LayeredMusic`)
    * room start: the camera at the room's left (unless in the tutorial); the right of
      way's arrow (`Arrow`) and the clash point (`ClashPosition`) made; the spawn timer
      from `spawnDelay`. In a room with entry points, a faceoff warps both players in
      64 pixels above their match entry points (`Nidhox.Bout.Spawn.warp_in/3`);
      otherwise the leader comes in at its room entry point, holding a sword when it
      had one leaving the last room, dropped to the ground. Then the camera's centre
      in the middle of the room, remembered; `firstFrameOfRoom` 1; and with sudden
      death only (`suddenDeathOnlyEnabled`) and not yet in it, sudden death begins
    * step: where the `Ear` is; while not finished, `MatchStats.frames` is
      `System.frame`; the first leader is the faceoff's winner (`faceoffWinner`); a
      perfect match (`perfect`) is lost once player 2 leads, or once nobody does after
      the faceoff was won
    * room end: whether each player's fencer leaves holding a sword (`yellowSword`,
      `orangeSword`); no thrown swords or pickups are kept; without persistent blood
      (`System.persistent_blood`) the blood bank's surfaces are freed (its `Other_20`,
      `Nidhox.Objects.BloodSurface.free_bank/2`)
    * alarm 0: the match is over and gone
    * destroy: its computer players (`Brain`), its music (`LayeredMusic`) and the
      tutorial (`Tutorial`) gone with it
    * draw: outside a demonstration and the faceoff, the clock or "SUDDEN DEATH" on
      the screen's bottom middle (160, 185) over its grey shadow one pixel lower — red
      (`make_color_hsv(0, 200, 255)`) in sudden death and in the last 600 frames,
      else white — the clock as `getTime(countDownTimer + 1)`, shown only with a time
      limit, frames left and outside an end room

  `create/1` makes one; `start_match/1` starts a match (`startMatch`); `get/2` reads a
  variable of the first `Match`.
  """

  alias Cauldron2D.GameMaker.{Data, Draw, Instance, World}
  alias Nidhox.Bout.{Camera, Outcome, Spawn, Variants}
  alias Nidhox.Gml
  alias Nidhox.Man.{Physics, Weapon}
  alias Nidhox.Objects.{BloodSurface, Ear, System}

  @noone -4
  @spawn_delay 100
  @faceoff_steps 120
  @warp_height 64
  @sword 2
  @demonstration 1
  @single_player 2
  @music_flows [1, 2, 3, 4, 790_474]
  @font "fMenu"
  @text_at {160, 185}
  @red {255, 55, 55}
  @white {255, 255, 255}
  @grey {128, 128, 128}
  @last_frames 600
  @gui_depth -1_000_000
  @centres %{
    25 => "rCemeteryCenter",
    20 => "rCastleCenter",
    22 => "rSkyCenter",
    23 => "rWildsCenter",
    21 => "rMinesCenter"
  }

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Match_Create_0", &start/3},
      {"gml_Object_Match_Other_4", &room_start/3},
      {"gml_Object_Match_Step_0", &step/3},
      {"gml_Object_Match_Other_5", &room_end/3},
      {"gml_Object_Match_Alarm_0", fn world, self, _other -> World.destroy(world, self) end},
      {"gml_Object_Match_Destroy_0", &gone/3},
      {"gml_Object_Match_Draw_0", &draw/3},
      {"gml_Object_Match_Other_20",
       fn world, self, _other -> BloodSurface.free_bank(world, self) end}
    ]
  end

  @doc "`{id, world}` with a `Match` made."
  @spec create(World.t()) :: {non_neg_integer(), World.t()}
  def create(%World{} = world) do
    {world, id} = World.create(world, World.object_index(world, "Match"), {0, 0})
    {id, world}
  end

  @doc """
  The world with a match started as the game's `startMatch` starts one: the level
  select (`VsLevelSelect`) and any match gone, a new `Match`, a room transition
  (`FinalFantasyVIIITransition`), the music's `firstChoice` 1, and the centre room of
  `System.level`'s area gone to (`World.goto/2`). `System.level` must be an area's
  level: castle 20, mines 21, sky 22, wilds 23 or cemetery 25.
  """
  @spec start_match(World.t()) :: World.t()
  def start_match(%World{} = world) do
    world = world |> kill_every("VsLevelSelect") |> kill_every("Match")
    {_match, world} = create(world)
    centre = Map.fetch!(@centres, round(System.get(world, :level)))

    world
    |> make("FinalFantasyVIIITransition")
    |> then(fn world ->
      Enum.reduce(Gml.all(world, "LayeredMusic"), world, &Gml.put(&2, &1, %{firstChoice: 1}))
    end)
    |> World.goto(Data.index(world.data, :rooms, centre))
  end

  @doc "Variable `name` of the first `Match`, `default` without one."
  @spec get(World.t(), atom(), term()) :: term()
  def get(%World{} = world, name, default \\ 0) do
    case Gml.first(world, "Match") do
      nil -> default
      match -> Gml.var(world, match, name, default)
    end
  end

  defp start(world, self, _other) do
    limit = System.get(world, :time_limit)

    world
    |> kill_every("Man")
    |> kill_every("MatchStats")
    |> then(&elem(World.create(&1, World.object_index(&1, "MatchStats"), {0, 0}), 0))
    |> Gml.put(self, %{
      z: 0,
      bloodbank: %{},
      yellowInstance: @noone,
      orangeInstance: @noone,
      priorityInstance: @noone,
      flyingWeapons: [],
      pickupContainers: [],
      yellowSword: 1,
      orangeSword: 1,
      yellowKillStreak: 0,
      orangeKillStreak: 0,
      spawnDelay: @spawn_delay,
      spawnTimer: @spawn_delay,
      change_animation: 0,
      leadingPlayerIndex: 0,
      previouslyLeadingPlayerIndex: 0,
      wrongWay: 0,
      wrongWayCounter: 0,
      pCameraCenterX: Camera.center_x(world),
      pCameraCenterY: Camera.center_y(world),
      parallaxTileLayers: [],
      roomFrame: 0,
      firstFrameOfRoom: 1,
      faceoff: 1,
      faceoffTimer: @faceoff_steps,
      idleTime: 0,
      finished: 0,
      useCountDownTimer: Gml.clamp(limit, 0, 1),
      countDownTimer: limit,
      sudden_death: 0,
      inputMap: %{},
      lastFramePolled: -1,
      faceoffWinner: 0,
      cleanHands: 1,
      cleanFeet: 1,
      cleanSword: 1,
      perfect: 1,
      sound: -1,
      comeback: %{1 => 0, 2 => 0}
    })
    |> zero_frame()
    |> brains()
    |> music()
  end

  defp kill_every(world, name),
    do: Enum.reduce(Gml.all(world, name), world, &World.destroy(&2, &1))

  defp zero_frame(world) do
    case Gml.first(world, "System") do
      nil -> world
      system -> Gml.put(world, system, %{frame: 0})
    end
  end

  defp brains(world) do
    case System.get(world, :flow) do
      @demonstration -> world |> brain(1) |> brain(2)
      @single_player -> brain(world, 2)
      _versus -> world
    end
  end

  defp music(world) do
    if System.get(world, :flow) in @music_flows, do: make(world, "LayeredMusic"), else: world
  end

  defp brain(world, player) do
    {world, brain} = World.create(world, World.object_index(world, "Brain"), {0, 0})
    Gml.put(world, brain, %{playerIndex: player})
  end

  defp room_start(world, self, _other) do
    world =
      if Gml.exists?(world, "Tutorial"), do: world, else: Camera.put_left(world, 0)

    world
    |> make("Arrow")
    |> Spawn.reset_timer(Gml.var(world, self, :spawnDelay))
    |> make("ClashPosition")
    |> enter_fencers(self)
    |> settle_camera(self)
    |> sudden_death_only(self)
  end

  defp make(world, name),
    do: world |> World.create(World.object_index(world, name), {0, 0}) |> elem(0)

  defp enter_fencers(world, match) do
    match_points =
      Gml.exists?(world, "YellowPlayerMatchEntryPoint") or
        Gml.exists?(world, "OrangePlayerMatchEntryPoint")

    room_points =
      Gml.exists?(world, "YellowPlayerRoomEntryPoint") or
        Gml.exists?(world, "OrangePlayerRoomEntryPoint")

    cond do
      not (match_points or room_points) -> world
      Gml.truthy?(Gml.var(world, match, :faceoff)) and match_points -> warp_both(world)
      true -> leader_enters(world, match)
    end
  end

  defp warp_both(world) do
    {_yellow, world} = Spawn.warp_in(world, above("YellowPlayerMatchEntryPoint", world), 1)
    {_orange, world} = Spawn.warp_in(world, above("OrangePlayerMatchEntryPoint", world), 2)
    world
  end

  defp above(name, world) do
    %Instance{x: x, y: y} = World.fetch(world, Gml.first(world, name))
    {x, y - @warp_height}
  end

  defp leader_enters(world, match) do
    case Gml.var(world, match, :leadingPlayerIndex) do
      1 -> enter_at(world, match, "YellowPlayerRoomEntryPoint", 1, :yellowInstance, :yellowSword)
      2 -> enter_at(world, match, "OrangePlayerRoomEntryPoint", 2, :orangeInstance, :orangeSword)
      _nobody -> world
    end
  end

  defp enter_at(world, match, point, player, instance, sword) do
    %Instance{x: x, y: y} = World.fetch(world, Gml.first(world, point))
    {man, world} = Spawn.player(world, {x, y}, player)
    world = Gml.put(world, match, %{instance => man})

    if Gml.truthy?(Gml.var(world, match, sword)),
      do: world |> Weapon.set_type(man, @sword) |> drop_to_ground(man),
      else: world
  end

  defp drop_to_ground(world, man) do
    if Physics.check_below?(world, man) or World.fetch(world, man).y >= room_height(world),
      do: world,
      else: world |> World.update(man, &%{&1 | y: &1.y + 1}) |> drop_to_ground(man)
  end

  defp settle_camera(world, match) do
    world = Camera.put_center_x(world, room_width(world) * 0.5)

    Gml.put(world, match, %{
      pCameraCenterX: Camera.center_x(world),
      pCameraCenterY: Camera.center_y(world),
      firstFrameOfRoom: 1
    })
  end

  defp sudden_death_only(world, match) do
    if not Gml.truthy?(Gml.var(world, match, :sudden_death)) and
         Variants.sudden_death_only?(world),
       do: Outcome.sudden_death(world, match),
       else: world
  end

  defp step(world, self, _other) do
    {x, y} = Ear.position(world)
    world = World.update(world, self, &%{&1 | x: x, y: y})
    world = if Gml.truthy?(Gml.var(world, self, :finished)), do: world, else: count_frames(world)
    world = first_leader(world, self)
    leader = Gml.var(world, self, :leadingPlayerIndex)

    if leader == 2 or (leader == 0 and Gml.var(world, self, :faceoffWinner) != 0),
      do: Gml.put(world, self, %{perfect: 0}),
      else: world
  end

  defp count_frames(world) do
    case Gml.first(world, "MatchStats") do
      nil -> world
      stats -> Gml.put(world, stats, %{frames: System.get(world, :frame)})
    end
  end

  defp first_leader(world, self) do
    if Gml.var(world, self, :faceoffWinner) == 0,
      do: Gml.put(world, self, %{faceoffWinner: Gml.var(world, self, :leadingPlayerIndex)}),
      else: world
  end

  defp room_end(world, self, _other) do
    world
    |> keep_sword(self, "YellowPlayer", :yellowSword)
    |> keep_sword(self, "OrangePlayer", :orangeSword)
    |> Gml.put(self, %{flyingWeapons: [], pickupContainers: []})
    |> then(
      &if(Gml.truthy?(System.get(&1, :persistent_blood)),
        do: &1,
        else: World.perform(&1, self, :other, 20)
      )
    )
  end

  defp gone(world, _self, _other) do
    ["Brain", "LayeredMusic", "Tutorial"]
    |> Enum.flat_map(&Gml.all(world, &1))
    |> Enum.reduce(world, &World.destroy(&2, &1))
  end

  defp keep_sword(world, match, name, flag) do
    Enum.reduce(Gml.all(world, name), world, fn man, world ->
      Gml.put(world, match, %{flag => if(Physics.weapon_type(world, man) != 1, do: 1, else: 0)})
    end)
  end

  defp draw(world, self, _other) do
    if System.get(world, :flow) != @demonstration and
         not Gml.truthy?(Gml.var(world, self, :faceoff)),
       do: clock_text(world, self),
       else: world
  end

  defp clock_text(world, match) do
    left = Gml.var(world, match, :countDownTimer)

    cond do
      Gml.truthy?(Gml.var(world, match, :sudden_death)) ->
        shadowed(world, "SUDDEN DEATH", @red)

      Gml.truthy?(Gml.var(world, match, :useCountDownTimer)) and left > 0 and
          not Outcome.victory_lap?(world) ->
        shadowed(world, time(left + 1), if(left <= @last_frames, do: @red, else: @white))

      true ->
        shadowed(world, "", @white)
    end
  end

  defp shadowed(world, "", _colour), do: world

  defp shadowed(world, text, colour) do
    {x, y} = @text_at
    left = Camera.left(world)
    top = Camera.top(world)
    options = [halign: :center, valign: :bottom, depth: @gui_depth]

    world
    |> Draw.text(@font, text, {left + x, top + y + 1}, [{:colour, @grey} | options])
    |> Draw.text(@font, text, {left + x, top + y}, [{:colour, colour} | options])
  end

  @doc "Frames `frames` as the game shows a time (`getTime(frames, 0)`): `[h:]mm:ss`."
  @spec time(number()) :: String.t()
  def time(frames) do
    hours = floor(frames / 60 / 60 / 60)
    minutes = rem(floor(frames / 60 / 60), 60)
    seconds = rem(floor(frames / 60), 60)
    lead = if hours > 0, do: "#{hours}:", else: ""
    lead <> pad(minutes) <> ":" <> pad(seconds)
  end

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")

  defp room_width(world),
    do: world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size) |> elem(0)

  defp room_height(world),
    do: world.data.rooms |> Enum.at(world.room) |> Map.fetch!(:size) |> elem(1)
end
