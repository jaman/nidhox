defmodule Nidhox.Objects.Arcade do
  @moduledoc """
  The single player run (`ArcadeMode`, kept across rooms) and its progress screen
  (`ShowProgress` in `rArcadeProgress`), as the game's code runs them.

  `start/1` is `startArcadeMode`: a room transition (`FinalFantasyVIIITransition`) and
  an `ArcadeMode`.

    * `ArcadeMode` create: `level` 1, `framesElapsed` 0, sixteen levels
      (`addArcadeModeLevel(area, personality)`, `locationMap` and `personalityMap` by
      level, `totalLevels`) — Mines 5, Sky 6, Wilds 2, Castle 9, Mines 1, Sky 4, Wilds 8,
      Castle 5, Mines 6, Sky 2, Wilds 9, Castle 1, then the four areas again against
      personality 5646466, which changes every second; `perfect`, `cleanHands`,
      `cleanFeet`, `cleanSword` 1; to `rArcadeProgress`; `playerAttacked` 0
    * step: in `rBeatGameStats` a press (`inputdog` 8 or 10) goes to the main menu; in
      `rMatchStats` a press goes back to `rArcadeProgress` for the same level when
      player 1 did not win, to `rBeatGameStats` after the last level, else to
      `rArcadeProgress` for the next. While the match runs unfinished `framesElapsed`
      counts on, and `playerAttacked` is set once player 2's fencer attacks
    * user event 0: `System.level` the level's area, and the match started
      (`startMatch`)
    * room start: `playerAttacked` 0
    * draw: in `rBeatGameStats`, "GAME COMPLETE", "TIME" and the time
      (`getTime(framesElapsed)`) centred on the camera, 32 above its middle
    * `ShowProgress` create: `cleared` 0; step: the camera eased 0.1 of the way to the
      level's area on the map (`setCameraToSelectedLevel`); with no press it is
      `cleared`, and a press of 8 or 10 then, or any press of 9, starts the level (the
      `ArcadeMode`'s user event 0); draw: a black band 64 tall across the camera's
      middle and over it, in `make_color_hsv(38, 150, 20)`, the run so far; a mark for
      every level 16 apart from 32 in, 12 above the band's bottom, at half size — the
      level's opponent (`sManNoWeaponStand`, facing left, its frames at `(frame + x) ×
      0.6`, or fallen, `sManCollapse`'s last frame, once beaten) in its colour
      (`getPlayerColorForLevel`), with player 1 standing 16 to its left at the current
      level — and the run's time above, white outlined in black
      (`drawTextXYXScaleYScaleAngleColorOutlinecolor`)

  `difficulty/1` is `getArcadeModeDifficulty`, `contains?/2` `levelContainsPersonality`,
  `personality/1` the current level's personality, and `room_percent/1`
  `getLevelRoomPercent`.

  The game's own button numbers for menus (`inputdog`) are 8 for `:attack`, 9 for `:jump`
  and 10 for `:start`.
  """

  alias Cauldron2D.GameMaker.{Colour, Data, Draw, Instance, Path, World}
  alias Nidhox.Bout.{Camera, PlayerColour}
  alias Nidhox.Gml
  alias Nidhox.Man.Query
  alias Nidhox.Objects.{Match, System}

  @levels [
    {21, 5},
    {22, 6},
    {23, 2},
    {20, 9},
    {21, 1},
    {22, 4},
    {23, 8},
    {20, 5},
    {21, 6},
    {22, 2},
    {23, 9},
    {20, 1},
    {21, 5_646_466},
    {22, 5_646_466},
    {23, 5_646_466},
    {20, 5_646_466}
  ]
  @map_points %{20 => 0, 21 => 1, 23 => 2, 22 => 3, 25 => 4}
  @buttons %{8 => :attack, 9 => :jump, 10 => :start}
  @room_percent %{
    "rCastleLeftB" => 0,
    "rWildsLeftB" => 0,
    "rSkyLeftB" => 0,
    "rMinesLeftC" => 0,
    "rMinesLeftB" => 0.125,
    "rCastleLeftA" => 0.25,
    "rWildsLeftA" => 0.25,
    "rSkyLeftA" => 0.25,
    "rMinesLeftA" => 0.25,
    "rCastleCenter" => 0.5,
    "rWildsCenter" => 0.5,
    "rSkyCenter" => 0.5,
    "rMinesCenter" => 0.5,
    "rCastleRightA" => 0.75,
    "rWildsRightA" => 0.75,
    "rSkyRightA" => 0.75,
    "rMinesRightA" => 0.75,
    "rMinesRightB" => 0.875
  }
  @standing 187
  @fallen 208
  @band 32
  @mark 0.5
  @ease 0.1

  @doc "The world with a single player run begun (`startArcadeMode`)."
  @spec start(World.t()) :: World.t()
  def start(%World{} = world) do
    world
    |> make("FinalFantasyVIIITransition")
    |> make("ArcadeMode")
  end

  @doc "Whether instance code's menu button `button` (8, 9 or 10) was pressed by any player this step."
  @spec pressed?(World.t(), 8 | 9 | 10) :: boolean()
  def pressed?(%World{input: input}, button) do
    action = Map.fetch!(@buttons, button)
    input |> Map.get(:players, %{}) |> Map.values() |> Enum.any?(&(action in Map.get(&1, :pressed, MapSet.new())))
  end

  @doc "The computer's difficulty in the run (`getArcadeModeDifficulty`), 0–1."
  @spec difficulty(World.t()) :: float()
  def difficulty(%World{} = world) do
    arcade = Gml.first(world, "ArcadeMode")
    total = map_size(Gml.var(world, arcade, :personalityMap, %{}))
    {_x, y, _speed} = Path.position(Enum.at(world.data.paths, 1), (Gml.var(world, arcade, :level) - 1) / total)
    base = (400 - y) / 400
    {room_width, screen_width} = {Camera.room_width(world), Camera.width(world)}
    across = if room_width > screen_width, do: Camera.left(world) / (room_width - screen_width), else: 0.5
    0.75 * base + 0.125 * room_percent(world) + 0.125 * across
  end

  @doc "How far through its area the room is (`getLevelRoomPercent`): 0 at the far left to 1 at the far right."
  @spec room_percent(World.t()) :: number()
  def room_percent(%World{} = world), do: Map.get(@room_percent, Enum.at(world.data.rooms, world.room).name, 1)

  @doc "Whether level `level` of the run is against `personality` (`levelContainsPersonality`)."
  @spec contains?(World.t(), number(), number()) :: boolean()
  def contains?(%World{} = world, level, personality) do
    arcade = Gml.first(world, "ArcadeMode")
    Map.get(Gml.var(world, arcade, :personalityMap, %{}), round(level)) == personality
  end

  @doc "The personality of the run's current level, `nil` outside a run."
  @spec personality(World.t()) :: number() | nil
  def personality(%World{} = world) do
    case Gml.first(world, "ArcadeMode") do
      nil -> nil
      arcade -> Map.get(Gml.var(world, arcade, :personalityMap, %{}), round(Gml.var(world, arcade, :level)))
    end
  end

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_ArcadeMode_Create_0", &arcade_start/3},
      {"gml_Object_ArcadeMode_Step_0", &arcade_step/3},
      {"gml_Object_ArcadeMode_Other_10", &start_level/3},
      {"gml_Object_ArcadeMode_Other_4", fn world, self, _other -> Gml.put(world, self, %{playerAttacked: 0}) end},
      {"gml_Object_ArcadeMode_Draw_0", &arcade_draw/3},
      {"gml_Object_ShowProgress_Create_0", fn world, self, _other -> Gml.put(world, self, %{cleared: 0}) end},
      {"gml_Object_ShowProgress_Step_0", &progress_step/3},
      {"gml_Object_ShowProgress_Draw_0", &progress_draw/3}
    ]
  end

  defp arcade_start(world, self, _other) do
    levels = Enum.with_index(@levels, 1)

    world
    |> Gml.put(self, %{
      level: 1,
      framesElapsed: 0,
      locationMap: Map.new(levels, fn {{area, _personality}, level} -> {level, area} end),
      personalityMap: Map.new(levels, fn {{_area, personality}, level} -> {level, personality} end),
      totalLevels: length(@levels),
      perfect: 1,
      cleanHands: 1,
      cleanFeet: 1,
      cleanSword: 1,
      playerAttacked: 0
    })
    |> goto("rArcadeProgress")
  end

  defp arcade_step(world, self, _other) do
    world
    |> rooms_by_press(self, room_name(world))
    |> count_time(self, Gml.first(world, "Match"))
  end

  defp rooms_by_press(world, _self, "rBeatGameStats") do
    if pressed?(world, 8) or pressed?(world, 10), do: goto(world, "rMainMenu"), else: world
  end

  defp rooms_by_press(world, self, "rMatchStats") do
    if pressed?(world, 8) or pressed?(world, 10), do: next_level(world, self), else: world
  end

  defp rooms_by_press(world, _self, _room), do: world

  defp next_level(world, self) do
    level = Gml.var(world, self, :level)

    cond do
      winner(world) != 1 -> goto(world, "rArcadeProgress")
      level >= map_size(Gml.var(world, self, :personalityMap, %{})) -> goto(world, "rBeatGameStats")
      true -> world |> Gml.put(self, %{level: level + 1}) |> goto("rArcadeProgress")
    end
  end

  defp winner(world) do
    case Gml.first(world, "MatchStats") do
      nil -> nil
      stats -> Gml.var(world, stats, :winningPlayerIndex)
    end
  end

  defp count_time(world, _self, nil), do: world

  defp count_time(world, self, match) do
    world =
      if Gml.truthy?(Gml.var(world, match, :finished)),
        do: world,
        else: Gml.put(world, self, %{framesElapsed: Gml.var(world, self, :framesElapsed) + 1})

    if Gml.truthy?(Gml.var(world, self, :playerAttacked)), do: world, else: watch_attack(world, self)
  end

  defp watch_attack(world, self) do
    attacker = Enum.find(Gml.all(world, "Man"), &Gml.eq?(Gml.var(world, &1, :playerIndex), 2))

    if attacker && Query.attacking?(world, attacker),
      do: Gml.put(world, self, %{playerAttacked: 1}),
      else: world
  end

  defp start_level(world, self, _other) do
    area = Map.fetch!(Gml.var(world, self, :locationMap), round(Gml.var(world, self, :level)))
    world |> Gml.put(Gml.first(world, "System"), %{level: area}) |> Match.start_match()
  end

  defp arcade_draw(world, self, _other) do
    if room_name(world) == "rBeatGameStats" do
      text = "GAME COMPLETE##TIME#" <> Match.time(Gml.var(world, self, :framesElapsed))
      Draw.text(world, 1, text, {Camera.center_x(world), Camera.center_y(world) - 32}, halign: :center, valign: :middle)
    else
      world
    end
  end

  defp progress_step(world, self, _other) do
    arcade = Gml.first(world, "ArcadeMode")
    area = Map.fetch!(Gml.var(world, arcade, :locationMap), round(Gml.var(world, arcade, :level)))
    world = camera_to(world, area)
    start = pressed?(world, 8) or pressed?(world, 10)
    world = if start, do: world, else: Gml.put(world, self, %{cleared: 1})

    cond do
      Gml.truthy?(Gml.var(world, self, :cleared)) and start -> World.perform(world, arcade, :other, 10)
      pressed?(world, 9) -> World.perform(world, arcade, :other, 10)
      true -> world
    end
  end

  defp camera_to(world, area) do
    case Map.fetch(@map_points, area) do
      {:ok, point} ->
        {px, py, _speed} = Enum.at(Enum.at(world.data.paths, 2).points, point)
        {_width, room_height} = Enum.at(world.data.rooms, world.room).size
        to_x = Gml.clamp(px, 160, Camera.room_width(world) - 160)
        to_y = Gml.clamp(py, 100, room_height - 100)

        world
        |> Camera.put_center_x(Camera.center_x(world) + (to_x - Camera.center_x(world)) * @ease)
        |> then(&Camera.put_center_y(&1, Camera.center_y(&1) + (to_y - Camera.center_y(&1)) * @ease))

      :error ->
        world
    end
  end

  defp progress_draw(world, _self, _other) do
    arcade = Gml.first(world, "ArcadeMode")
    level = Gml.var(world, arcade, :level)
    {left, right, middle} = {Camera.left(world), Camera.right(world), Camera.center_y(world)}

    world =
      world
      |> Draw.item(rectangle({left - 10, middle - @band}, {right + 10, middle + @band}, {0, 0, 0}))
      |> Draw.item(rectangle({left - 10, middle - @band}, {left + 32 + level * 16 - 16, middle + @band}, Colour.hsv(38, 150, 20)))

    world =
      Enum.reduce(1..Gml.var(world, arcade, :totalLevels)//1, world, fn mark, world ->
        level_mark(world, arcade, mark, {left + 32 + mark * 16, middle + @band - 12})
      end)

    time = Match.time(Gml.var(world, arcade, :framesElapsed))
    outlined(world, time, {Camera.center_x(world), middle - @band + 6})
  end

  defp level_mark(world, arcade, mark, {x, y}) do
    level = Gml.var(world, arcade, :level)
    %Instance{x: own_x} = World.fetch(world, Gml.first(world, "ShowProgress"))

    {sprite, frame} =
      if level > mark,
        do: {@fallen, length(World.sprite(world, @fallen).frames) - 1},
        else: {@standing, (System.get(world, :frame) + own_x) * 0.6}

    {colour, world} = colour_for_level(world, arcade, mark)
    world = Draw.sprite(world, sprite, frame, {x, y}, scale: {-@mark, @mark}, blend: colour)

    if Gml.eq?(level, mark) do
      {player, world} = PlayerColour.get(world, nil, 1)
      Draw.sprite(world, @standing, frame, {x - 16, y}, scale: {@mark, @mark}, blend: player)
    else
      world
    end
  end

  defp colour_for_level(world, arcade, mark) do
    level = Gml.var(world, arcade, :level)
    world = Gml.put(world, arcade, %{level: mark})
    {colour, world} = PlayerColour.get(world, nil, 123_456)
    {colour, Gml.put(world, arcade, %{level: level})}
  end

  defp outlined(world, text, {x, y}) do
    style = [halign: :center, valign: :top]

    world =
      Enum.reduce(0..3, world, fn turn, world ->
        Draw.text(world, 1, text, {x + Gml.lengthdir_x(1, turn * 90), y + Gml.lengthdir_y(1, turn * 90)}, [{:colour, {0, 0, 0}} | style])
      end)

    Draw.text(world, 1, text, {x, y}, [{:colour, {255, 255, 255}} | style])
  end

  defp rectangle({x1, y1}, {x2, y2}, colour),
    do: %{picture: :pixel, position: {x1, y1}, scale: {x2 - x1 + 1, y2 - y1 + 1}, blend: colour}

  defp make(world, name), do: world |> World.create(World.object_index(world, name), {0, 0}) |> elem(0)

  defp goto(world, room), do: World.goto(world, Data.index(world.data, :rooms, room))

  defp room_name(%World{room: nil}), do: nil
  defp room_name(world), do: Enum.at(world.data.rooms, world.room).name
end
