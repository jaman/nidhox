defmodule Nidhox.Objects.Tournament do
  @moduledoc """
  The game's `Tournament`, kept across rooms, and the code of `rTournamentIntro`, as the
  game runs them. Its bracket is a `Nidhox.Tournament` (`bracket`).

    * `rTournamentIntro`'s code: any `Tournament` gone, a new one made, and the next
      room (`rShowLadder`) gone to
    * create: a bracket for `global.players` players (`playerCount`), `counter` 0, no
      winner waiting (`nextWinner` −9), `busyTimer` 60
    * room start: `counter` 0 and `busyTimer` 60; in `rShowLadder` alarm 0 in 60
      steps; with no `Match`, a screen wipe (`ScreenWipe`)
    * alarm 0: `sfxChangeLevel2` at the `Ear`
    * step: in `rShowLadder`, once `busyTimer` is down to 0 — the waiting winner wins
      their match; then with a champion, `inputdog` 8 or 10 goes to `rShowChampion`,
      and without one, 10 or 8 goes to `rPreMatch` and the camera's centre eases 0.1 of
      the way to x 160. Every step `counter` counts up and `busyTimer` down
    * draw: in `rShowLadder` the bracket over the whole room from its top left, 320
      wide (`Nidhox.Tournament.Drawing.brackets/5`); in `rShowChampion` the champion
      (`Nidhox.Tournament.Drawing.champion/3`)

  `won/2` is the part of `showWinningPlayerIndex(side)` that tells the tournament: the
  player on that side waits to win (`nextWinner = currentPlayer[side]`). `player/2`
  reads the player on a side of the match being played, `champion/1` the champion.
  """

  alias Cauldron2D.GameMaker.{Data, Instance, World}
  alias Nidhox.Bout.{Camera, Sound}
  alias Nidhox.Gml
  alias Nidhox.Objects.{Arcade, Ear}
  alias Nidhox.Tournament, as: Bracket
  alias Nidhox.Tournament.Drawing

  @object "Tournament"
  @no_winner -9
  @busy_steps 60
  @level_sound "sfxChangeLevel2"
  @ladder "rShowLadder"
  @champion_room "rShowChampion"
  @pre_match "rPreMatch"
  @camera_centre 160
  @ease 0.1
  @width 320

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Room_rTournamentIntro_Create", &intro/3},
      {"gml_Object_Tournament_Create_0", &create/3},
      {"gml_Object_Tournament_Other_4", &room_start/3},
      {"gml_Object_Tournament_Alarm_0", &alarm/3},
      {"gml_Object_Tournament_Step_0", &step/3},
      {"gml_Object_Tournament_Draw_0", &draw/3}
    ]
  end

  @doc "The world with the player on `side` (1 or 2) of the match being played waiting to win it."
  @spec won(World.t(), 1 | 2) :: World.t()
  def won(%World{} = world, side) do
    world
    |> Gml.all(@object)
    |> Enum.reduce(world, fn tournament, world ->
      winner = elem(bracket(world, tournament).playing, side - 1)
      Gml.put(world, tournament, %{nextWinner: winner})
    end)
  end

  @doc "The player on `side` (1 or 2) of the match being played, `nil` outside a tournament."
  @spec player(World.t(), 1 | 2) :: Bracket.slot() | nil
  def player(%World{} = world, side) do
    case Gml.first(world, @object) do
      nil -> nil
      tournament -> elem(bracket(world, tournament).playing, side - 1)
    end
  end

  @doc "The tournament's champion, `nil` outside a tournament or before one is decided."
  @spec champion(World.t()) :: Bracket.player() | nil
  def champion(%World{} = world) do
    case Gml.first(world, @object) do
      nil -> nil
      tournament -> Bracket.champion(bracket(world, tournament))
    end
  end

  @doc """
  The first `Tournament`'s bracket drawn in the box `{x, y, width, height}`
  (`drawBracketsListXYWH`), as the draw list items it adds, in the box's units; `[]`
  with no `Tournament`.
  """
  @spec drawn_bracket(World.t(), {number(), number(), number(), number()}) :: [map()]
  def drawn_bracket(%World{} = world, box) do
    case Gml.first(world, @object) do
      nil ->
        []

      self ->
        busy? = Gml.var(world, self, :busyTimer) > 0
        drawn = Drawing.brackets(%{world | drawing: []}, self, bracket(world, self), box, busy?)
        Enum.reverse(drawn.drawing)
    end
  end

  @doc "The world with every `Tournament` gone and, for `players` above 1, a new one of that many players."
  @spec remade(World.t(), non_neg_integer()) :: World.t()
  def remade(%World{} = world, players) do
    world = world |> Gml.all(@object) |> Enum.reduce(world, &World.destroy(&2, &1))

    if players > 1 do
      world = World.put_global(world, :players, players)
      world |> World.create(World.object_index(world, @object), {0, 0}) |> elem(0)
    else
      world
    end
  end

  @doc "The world with every `Tournament`'s `busyTimer` at 60, so nothing on its bracket flashes."
  @spec held(World.t()) :: World.t()
  def held(%World{} = world),
    do:
      world
      |> Gml.all(@object)
      |> Enum.reduce(world, &Gml.put(&2, &1, %{busyTimer: @busy_steps}))

  defp intro(world, _self, _other) do
    world = world |> Gml.all(@object) |> Enum.reduce(world, &World.destroy(&2, &1))
    {world, _tournament} = World.create(world, World.object_index(world, @object), {0, 0})
    World.goto(world, next_room(world))
  end

  defp create(world, self, _other) do
    players = round(World.global(world, :players, 0))
    {bracket, world} = Bracket.new(players, world)

    Gml.put(world, self, %{
      playerCount: players,
      bracket: bracket,
      counter: 0,
      nextWinner: @no_winner,
      busyTimer: @busy_steps
    })
  end

  defp room_start(world, self, _other) do
    world = Gml.put(world, self, %{counter: 0, busyTimer: @busy_steps})

    world =
      if in_room?(world, @ladder),
        do: World.update(world, self, &Instance.put_alarm(&1, 0, @busy_steps)),
        else: world

    if Gml.exists?(world, "Match"),
      do: world,
      else:
        world
        |> World.create(World.object_index(world, "ScreenWipe"), {0, 0})
        |> elem(0)
  end

  defp alarm(world, _self, _other),
    do: Sound.play(world, Data.index(world.data, :sounds, @level_sound), Ear.position(world))

  defp step(world, self, _other) do
    world = if in_room?(world, @ladder), do: ladder(world, self), else: world
    counter = Gml.var(world, self, :counter)
    busy = Gml.var(world, self, :busyTimer)
    Gml.put(world, self, %{counter: counter + 1, busyTimer: busy - 1})
  end

  defp ladder(world, self) do
    if Gml.var(world, self, :busyTimer) <= 0 do
      world = settle(world, self)

      case Bracket.champion(bracket(world, self)) do
        nil -> world |> pressed_goto([10, 8], @pre_match) |> ease_camera()
        _champion -> pressed_goto(world, [8, 10], @champion_room)
      end
    else
      world
    end
  end

  defp settle(world, self) do
    case Gml.var(world, self, :nextWinner) do
      @no_winner ->
        world

      winner ->
        Gml.put(world, self, %{
          bracket: Bracket.won(bracket(world, self), winner),
          nextWinner: @no_winner
        })
    end
  end

  defp pressed_goto(world, buttons, room) do
    if Enum.any?(buttons, &Arcade.pressed?(world, &1)),
      do: World.goto(world, Data.index(world.data, :rooms, room)),
      else: world
  end

  defp ease_camera(world) do
    centre = Camera.center_x(world)
    Camera.put_center_x(world, centre + (@camera_centre - centre) * @ease)
  end

  defp draw(world, self, _other) do
    cond do
      in_room?(world, @ladder) ->
        %{x: x, y: y} = World.fetch(world, self)
        box = {x, y, @width, elem(Enum.at(world.data.rooms, world.room).size, 1)}

        Drawing.brackets(
          world,
          self,
          bracket(world, self),
          box,
          Gml.var(world, self, :busyTimer) > 0
        )

      in_room?(world, @champion_room) ->
        Drawing.champion(world, self, bracket(world, self))

      true ->
        world
    end
  end

  defp bracket(world, tournament), do: Gml.var(world, tournament, :bracket)

  defp in_room?(%World{room: room} = world, name),
    do: room != nil and Enum.at(world.data.rooms, room).name == name

  defp next_room(%World{room: room} = world) do
    order = world.data.general.room_order
    Enum.at(order, Enum.find_index(order, &(&1 == room)) + 1)
  end
end
