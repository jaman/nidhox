defmodule Nidhox.Objects.Tutorial do
  @moduledoc """
  The game's `Tutorial`, placed in `rTutorial`: the lessons of HOW TO PLAY
  (`Nidhox.Tutorial.Lessons`), taught one after another to the yellow player against a
  computer partner.

    * create: the lessons in order, the first one current, no marks, `moveCounter` 0,
      a delay of 5 frames between a lesson done and the next (`maxDelay`, `delay`); a
      `Match` made, and a `Brain` playing player 2; the tutorial's music
      (`music_Castle_Drms1`) going round
    * end step: the current lesson's instruction shown when no `DialogBox` is
      (`Nidhox.Objects.DialogBox.show/2`). Before the last lesson the match has nobody
      leading, the camera at the room's left and the match at 0, and a yellow fencer
      missing is made at its match entry point holding a sword. With the yellow fencer
      there, the partner plays at no difficulty and the lesson is checked; a lesson done
      waits out the delay, then the marks are cleared, the dialog gone and the next
      lesson taken — after the last, the tutorial ends (user event 0). Moving on to the
      last lesson takes the tutorial's block away and starts the crowd cheering
      (`CheerControl` at 672, 92); moving on to picking up swords drops a sword near the
      yellow fencer (up to 120 pixels from the camera's centre) and disarms it. Until
      then each frame counts up `moveCounter`. Before the last lesson the cheering is
      stopped and every fencer kept 8 pixels inside the screen; the match's spawn timer
      stays at 100 and its clock at 36000. Outside the running and last lessons, every
      60 frames a missing partner comes in at its room entry point, unarmed — armed for
      disarming and for throwing at the learner. The music follows `System.musicVol`, on the client's music level
    * user event 0: the tutorial over — `System.flow` 1 and the match gone
    * destroy: the music let go

  `TutorialFinishLine` ends the tutorial (its user event 0) once the yellow fencer
  touches it.

  The game's on-screen CONFIGURE CONTROLS button for the first three lessons (alarm 0,
  `ConfigureControlsButton`) is a mouse button of its menus; NidhOX's menus are its own
  screens and have no such button.
  """

  alias Cauldron2D.Audio
  alias Cauldron2D.GameMaker.{Collide, Instance, World}
  alias Nidhox.Bout.Camera
  alias Nidhox.Gml
  alias Nidhox.Man.{Physics, Weapon}
  alias Nidhox.Objects.{DialogBox, Match, System}
  alias Nidhox.Tutorial.Lessons

  @noone -4
  @partner 2
  @standing 4_890_894
  @music "music_Castle_Drms1"
  @max_delay 5
  @last 6
  @running 7
  @pick_up 13
  @disarming 12
  @thrown 2
  @inside 8
  @fists 1
  @sword 2
  @entering 23
  @disarmed 13
  @drop_reach 120

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Tutorial_Create_0", &create/3},
      {"gml_Object_Tutorial_Step_2", &teach/3},
      {"gml_Object_Tutorial_Other_10", &finish/3},
      {"gml_Object_Tutorial_Destroy_0", fn world, self, _other -> World.emit(world, Audio.stopped({:tutorial, self})) end},
      {"gml_Object_TutorialFinishLine_Step_0", &finish_line/3}
    ]
  end

  defp create(world, self, _other) do
    [first | _] = Lessons.order()

    world =
      Gml.put(world, self, %{
        moves: Lessons.order(),
        currentMove: first,
        moveCounter: 0,
        check: %{0 => 0, 1 => 0, 2 => 0},
        maxDelay: @max_delay,
        delay: @max_delay,
        COMPLETED_MOVE: 0
      })

    {_match, world} = Match.create(world)
    {world, brain} = World.create(world, World.object_index(world, "Brain"), {0, 0})

    world
    |> Gml.put(brain, %{playerIndex: @partner, personality: @standing})
    |> World.emit(Audio.keyed({:tutorial, self}, {:recording, @music}, {:level, System.get(world, :musicVol, 1), 0.0}, loop: true, music: true))
    |> Gml.put(self, %{sound: {:tutorial, self}})
  end

  defp finish(world, _self, _other) do
    world =
      case Gml.first(world, "System") do
        nil -> world
        system -> Gml.put(world, system, %{flow: 1})
      end

    world |> Gml.all("Match") |> Enum.reduce(world, &World.destroy(&2, &1))
  end

  defp finish_line(world, self, _other) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    with yellow when is_integer(yellow) <- World.object_index(world, "YellowPlayer"),
         true <- Gml.exists?(world, "YellowPlayer"),
         true <- Collide.meeting?(world, self, {x, y}, yellow) do
      world |> Gml.all("Tutorial") |> Enum.reduce(world, &World.perform(&2, &1, :other, 10))
    else
      _ -> world
    end
  end

  defp teach(world, self, _other) do
    world
    |> show_instruction(self)
    |> hold_start(self)
    |> bring_learner(self)
    |> lesson(self)
    |> stop_cheering(self)
    |> follow_music(self)
    |> keep_on_screen(self)
    |> hold_match()
    |> bring_partner(self)
  end

  defp show_instruction(world, self) do
    move = current(world, self)

    if Gml.truthy?(move) and not Gml.exists?(world, "DialogBox"),
      do: DialogBox.show(world, Lessons.instruction(move)),
      else: world
  end

  defp hold_start(world, self) do
    if current(world, self) == @last do
      world
    else
      world
      |> Gml.all("Match")
      |> Enum.reduce(Camera.put_left(world, 0), fn match, world ->
        world |> Gml.put(match, %{leadingPlayerIndex: 0}) |> World.update(match, &%{&1 | x: 0})
      end)
    end
  end

  defp bring_learner(world, self) do
    if Gml.exists?(world, "YellowPlayer") or current(world, self) == @last do
      world
    else
      {_yellow, world} = enter(world, "YellowPlayer", "YellowPlayerMatchEntryPoint", @sword)
      world
    end
  end

  defp enter(world, object, entry, weapon) do
    %Instance{x: x, y: y} = World.fetch(world, Gml.first(world, entry))
    {world, man} = World.create(world, World.object_index(world, object), {x, y})
    {man, Weapon.set_type(world, man, weapon)}
  end

  defp lesson(world, self) do
    case Gml.first(world, "YellowPlayer") do
      nil ->
        world

      yellow ->
        orange = Gml.first(world, "OrangePlayer") || @noone

        world
        |> Gml.all("Brain")
        |> Enum.reduce(world, &Gml.put(&2, &1, %{difficulty: 0}))
        |> Lessons.check(self, yellow, orange)
        |> move_on(self, yellow)
    end
  end

  defp move_on(world, self, yellow) do
    if Gml.truthy?(Gml.var(world, self, :COMPLETED_MOVE)) do
      delay = max(Gml.var(world, self, :delay) - 1, 0)
      world = Gml.put(world, self, %{moveCounter: 0, delay: delay})
      if delay == 0, do: next_lesson(world, self, yellow), else: world
    else
      Gml.put(world, self, %{moveCounter: Gml.var(world, self, :moveCounter) + 1})
    end
  end

  defp next_lesson(world, self, yellow) do
    moves = Gml.var(world, self, :moves)
    next = following(moves, current(world, self))

    world =
      world
      |> Gml.put(self, %{
        COMPLETED_MOVE: 0,
        delay: Gml.var(world, self, :maxDelay),
        check: %{0 => 0, 1 => 0, 2 => 0},
        currentMove: next
      })
      |> then(&Enum.reduce(Gml.all(&1, "DialogBox"), &1, fn box, world -> World.destroy(world, box) end))

    world = if next == hd(moves), do: World.perform(world, self, :other, 10), else: world
    begin_lesson(world, next, yellow)
  end

  defp following(moves, move) do
    case Enum.drop_while(moves, &(&1 != move)) do
      [_move, next | _] -> next
      _last -> hd(moves)
    end
  end

  defp begin_lesson(world, @last, _yellow) do
    world = world |> Gml.all("TutorialBlock") |> Enum.reduce(world, &World.destroy(&2, &1))
    {world, _cheer} = World.create(world, World.object_index(world, "CheerControl"), {672, 92})
    world
  end

  defp begin_lesson(world, @pick_up, yellow) do
    centre = Camera.center_x(world)
    offset = Gml.clamp(1000 * (World.fetch(world, yellow).x - centre), -@drop_reach, @drop_reach)
    {world, _sword} = World.create(world, World.object_index(world, "DroppedWeapon"), {centre - offset, 0})

    if World.fetch(world, yellow) != nil and Physics.weapon_type(world, yellow) == @sword do
      world = Physics.next_state(world, yellow, @disarmed)
      {_dropped, world} = Weapon.drop(world, yellow)
      world
    else
      world
    end
  end

  defp begin_lesson(world, _move, _yellow), do: world

  defp stop_cheering(world, self) do
    if current(world, self) == @last,
      do: world,
      else: world |> Gml.all("CheerControl") |> Enum.reduce(world, &World.destroy(&2, &1))
  end

  defp follow_music(world, self) do
    World.emit(world, Audio.moved(Gml.var(world, self, :sound), {:level, System.get(world, :musicVol, 1), 0.0}))
  end

  defp keep_on_screen(world, self) do
    if current(world, self) == @last do
      world
    else
      left = Camera.left(world) + @inside
      right = Camera.right(world) - @inside

      world
      |> Gml.all("Man")
      |> Enum.reduce(world, fn man, world -> World.update(world, man, &%{&1 | x: Gml.clamp(&1.x, left, right)}) end)
    end
  end

  defp hold_match(world) do
    world
    |> Gml.all("Match")
    |> Enum.reduce(world, &Gml.put(&2, &1, %{spawnTimer: 100, countDownTimer: 36_000}))
  end

  defp bring_partner(world, self) do
    move = current(world, self)

    if move not in [@running, @last] and rem(trunc(System.get(world, :frame)), 60) == 0 and
         not Gml.exists?(world, "OrangePlayer") do
      armed = move in [@disarming, @thrown]
      {orange, world} = enter(world, "OrangePlayer", "OrangePlayerRoomEntryPoint", if(armed, do: @sword, else: @fists))
      Physics.next_state(world, orange, @entering)
    else
      world
    end
  end

  defp current(world, self), do: Gml.var(world, self, :currentMove)
end
