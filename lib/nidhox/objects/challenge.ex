defmodule Nidhox.Objects.Challenge do
  @moduledoc """
  The game's challenge mode in `rChallengeMode`, as its code runs it: player 1 fences
  a computer player and scores each move it lands, a move's worth falling each time it
  is used and climbing back with time.

    * `ChallengeMode` create: a computer player (`Brain`) for player 2 at `difficulty`
      1; `playerIndex` 1; `streak`, `points`, `tweenedPoints`, `best` and `previous` 0;
      `opponentColor` silver (`12632256`); `pointValues` ten moves each worth 100; and
      the score (`ShowChallengeScore`)
    * step: every fencer not dead (23) kept 35 pixels inside the room, the opponent's
      body blended `opponentColor`; the match's `leadingPlayerIndex` 0 and its clock
      36000; a `PickupContainer` past 360 frames (`counter`) dusts away; every 20th
      frame each move's worth is `round(clamp(worth + 1, 1, 100))`; `tweenedPoints`
      moves 3 up or 9 down towards `points`
    * draw: "BEST: " and `best` in `fButton`, white, centred 2 above the camera's bottom
    * `ShowChallengeScore` draw: `tweenedPoints` in `fButton` 6 wide and 7.2 tall,
      centred 64 below the camera's top, maroon while falling, white while rising, else
      the player's colour (`getPlayerColor`), outlined 0.4 of the way to black
    * `ScorePopup` create: 48 higher for each other popup, turned 20° that many times
      either way (`choose(-1, 1)`), rising 0.2 a step, gone after 60 frames; step:
      after 30 frames its `text` becomes `text2`, if any; draw: on two frames in every
      four, its `text` in `fButton` 1.5 times its size, in its blend, outlined 0.1 of
      the way from black to it

  `move_completed/4` is `challengeMode_move_completed(player, move, x, y)`, with the
  moves 0 LUNGE, 1 SNAP, 2 KICK, 3 PUNCH, 4 SWEEP, 5 GUARD, 6 PARRY, 7 THROW and 8
  DODGE: a DODGE in the thrown sword lesson marks it (`Nidhox.Tutorial.Lessons.block/2`);
  in challenge mode, a move of the challenger's scores its worth, halves that move's
  worth and adds a tenth to the others' (each `round(clamp(…, 1, 100))`), and puts up
  a popup of the move's name turning into its worth, in the challenger's colour, with
  `sfx8bitGood`. `reset_points/2` is `challengeModeResetPointsForPlayer(player)`: the
  opponent dying raises its `difficulty` 0.1 and `opponentColor` to
  `make_color_hsv(difficulty × 255 / 6, 220, 255)`; the challenger dying puts up "NEW
  HIGHSCORE" in cyan over the camera's middle with `sfx8bitNewHighscore` when `points`
  beat `best`, else plays the sound its unset variable `sfx8bitReset` names (0), then keeps `points` as `previous` and the
  better of it and `best` as `best`, and starts over: no points, no streak, every move
  worth 100 and the computer player at `difficulty` 0.

  `drawTextXYXScaleYScaleAngleColorOutlinecolor` is `outlined/5`: the text four times
  one pixel to each side in the outline colour, then over them in its own.
  """

  alias Cauldron2D.GameMaker.{Colour, Draw, Instance, World}
  alias Nidhox.Bout.{Camera, PlayerColour, Sound}
  alias Nidhox.Gml
  alias Nidhox.Objects.{Particles, System}
  alias Nidhox.Tutorial.Lessons

  @font "fButton"
  @moves ~w(LUNGE SNAP KICK PUNCH SWEEP GUARD PARRY THROW DODGE)
  @dodge 8
  @move_count 10
  @full_worth 100
  @silver {192, 192, 192}
  @maroon {128, 0, 0}
  @white {255, 255, 255}
  @black {0, 0, 0}
  @cyan {0, 255, 255}
  @dead 23
  @margin 35
  @clock 36_000
  @container_life 360
  @recovery_every 20
  @tween_up 3
  @tween_down 9
  @good 124
  @new_highscore 125
  @popup_rise 48
  @popup_turn 20
  @popup_life 60
  @popup_swap 30
  @popup_vspeed -0.2

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_ChallengeMode_Create_0", &start/3},
      {"gml_Object_ChallengeMode_Step_0", &step/3},
      {"gml_Object_ChallengeMode_Draw_0", &draw_best/3},
      {"gml_Object_ShowChallengeScore_Draw_0", &draw_score/3},
      {"gml_Object_ScorePopup_Create_0", &popup_start/3},
      {"gml_Object_ScorePopup_Step_0", &popup_step/3},
      {"gml_Object_ScorePopup_Draw_0", &popup_draw/3},
      {"gml_Object_ScorePopup_Alarm_0", fn world, self, _other -> World.destroy(world, self) end}
    ]
  end

  @doc "The world after player `player` completed move `move` at `{x, y}` (`challengeMode_move_completed`)."
  @spec move_completed(World.t(), number(), 0..8, {number(), number()}) :: World.t()
  def move_completed(%World{} = world, player, move, at) do
    world = if move == @dodge, do: Lessons.block(world, player), else: world

    world
    |> Gml.all("ChallengeMode")
    |> Enum.reduce(world, &scored(&2, &1, player, move, at))
  end

  @doc "The world after player `player`'s fencer died in challenge mode (`challengeModeResetPointsForPlayer`)."
  @spec reset_points(World.t(), number()) :: World.t()
  def reset_points(%World{} = world, player) do
    world
    |> Gml.all("ChallengeMode")
    |> Enum.reduce(world, fn challenge, world ->
      if Gml.var(world, challenge, :playerIndex) != player,
        do: harder(world, challenge),
        else: started_over(world, challenge)
    end)
  end

  @doc """
  From draw code: `text` in `font` at `{x, y}`, `scale` `{x, y}` and turned `angle`, in
  `colour` over an outline of `outline` (`drawTextXYXScaleYScaleAngleColorOutlinecolor`),
  the outline `:spread` (default 1) pixels to each side.
  `opts` are `Cauldron2D.GameMaker.Text.items/5`'s alignment options.
  """
  @spec outlined(World.t(), String.t(), {number(), number()}, map(), keyword()) :: World.t()
  def outlined(
        %World{} = world,
        text,
        {x, y},
        %{font: font, scale: scale, angle: angle, colour: colour, outline: outline} = look,
        opts \\ []
      ) do
    style = [scale: scale, angle: angle] ++ opts
    spread = Map.get(look, :spread, 1)

    world =
      Enum.reduce(0..3, world, fn turn, world ->
        offset = {x + Gml.lengthdir_x(spread, turn * 90), y + Gml.lengthdir_y(spread, turn * 90)}
        Draw.text(world, font, text, offset, [{:colour, outline} | style])
      end)

    Draw.text(world, font, text, {x, y}, [{:colour, colour} | style])
  end

  defp start(world, self, _other) do
    {world, brain} = World.create(world, World.object_index(world, "Brain"), {0, 0})

    world
    |> Gml.put(brain, %{playerIndex: 2, difficulty: 1})
    |> Gml.put(self, %{
      playerIndex: 1,
      streak: 0,
      tweenedPoints: 0,
      points: 0,
      best: 0,
      previous: 0,
      opponentColor: @silver,
      pointValues: List.duplicate(@full_worth, @move_count)
    })
    |> World.create(World.object_index(world, "ShowChallengeScore"), {0, 0})
    |> elem(0)
  end

  defp step(world, self, _other) do
    world
    |> fenced_in(self)
    |> clock_held()
    |> containers_dusted()
    |> recovered(self)
    |> tweened(self)
  end

  defp clock_held(world) do
    world
    |> Gml.all("Match")
    |> Enum.reduce(world, &Gml.put(&2, &1, %{leadingPlayerIndex: 0, countDownTimer: @clock}))
  end

  defp fenced_in(world, self) do
    challenger = Gml.var(world, self, :playerIndex)
    colour = Gml.var(world, self, :opponentColor)

    world
    |> Gml.all("Man")
    |> Enum.reduce(world, fn man, world ->
      world
      |> kept_inside(man)
      |> then(
        &if(Gml.var(&1, man, :playerIndex) != challenger, do: blended(&1, man, colour), else: &1)
      )
    end)
  end

  defp kept_inside(world, man) do
    if Gml.var(world, man, :state) != @dead do
      width = Camera.room_width(world)
      World.update(world, man, &%{&1 | x: Gml.clamp(&1.x, @margin, width - @margin)})
    else
      world
    end
  end

  defp blended(world, man, colour) do
    flesh = Gml.var(world, man, :flesh, -4)

    if World.fetch(world, flesh),
      do: World.update(world, flesh, &%{&1 | image_blend: colour}),
      else: world
  end

  defp containers_dusted(world) do
    world
    |> Gml.all("PickupContainer")
    |> Enum.reduce(world, fn container, world ->
      if Gml.var(world, container, :counter) > @container_life do
        %Instance{x: x, y: y} = World.fetch(world, container)
        world |> Particles.dust_at({x, y}) |> World.destroy(container)
      else
        world
      end
    end)
  end

  defp recovered(world, self) do
    if rem(trunc(System.get(world, :frame)), @recovery_every) == 0 do
      worths = Enum.map(Gml.var(world, self, :pointValues), &worth(&1 + 1))
      Gml.put(world, self, %{pointValues: worths})
    else
      world
    end
  end

  defp tweened(world, self) do
    points = Gml.var(world, self, :points)
    shown = Gml.var(world, self, :tweenedPoints)

    shown =
      cond do
        points > shown -> min(shown + @tween_up, points)
        points < shown -> max(shown - @tween_down, points)
        true -> shown
      end

    Gml.put(world, self, %{tweenedPoints: shown})
  end

  defp worth(value), do: value |> Gml.clamp(1, @full_worth) |> round()

  defp reworth(worths, move) do
    worths
    |> Enum.with_index()
    |> Enum.map(fn {value, index} -> worth(value * worth_change(index, move)) end)
  end

  defp worth_change(move, move), do: 0.5
  defp worth_change(_index, _move), do: 1.1

  defp scored(world, challenge, player, move, at) do
    if Gml.var(world, challenge, :playerIndex) == player do
      worths = Gml.var(world, challenge, :pointValues)
      earned = Enum.at(worths, move)

      world
      |> Gml.put(challenge, %{
        pointValues: reworth(worths, move),
        points: Gml.var(world, challenge, :points) + earned
      })
      |> popup(at, Enum.at(@moves, move), Integer.to_string(earned), player_colour(world, player))
      |> sound(@good)
    else
      world
    end
  end

  defp harder(world, challenge) do
    {world, difficulty} =
      world
      |> Gml.all("Brain")
      |> Enum.reduce({world, 0}, fn brain, {world, _difficulty} ->
        difficulty = Gml.var(world, brain, :difficulty) + 0.1
        {Gml.put(world, brain, %{difficulty: difficulty}), difficulty}
      end)

    Gml.put(world, challenge, %{opponentColor: Colour.hsv(difficulty * 255 / 6, 220, 255)})
  end

  defp started_over(world, challenge) do
    points = Gml.var(world, challenge, :points)
    best = Gml.var(world, challenge, :best)

    world =
      if points > best,
        do:
          world
          |> popup({Camera.center_x(world), 96}, "NEW HIGHSCORE", "", @cyan)
          |> sound(@new_highscore),
        else: sound(world, Gml.var(world, challenge, :sfx8bitReset))

    world
    |> Gml.put(challenge, %{
      previous: points,
      best: max(points, best),
      points: 0,
      streak: 0,
      pointValues: List.duplicate(@full_worth, @move_count)
    })
    |> then(fn world ->
      world |> Gml.all("Brain") |> Enum.reduce(world, &Gml.put(&2, &1, %{difficulty: 0}))
    end)
  end

  defp popup(world, {x, y}, text, then_text, colour) do
    {world, popup} = World.create(world, World.object_index(world, "ScorePopup"), {x, y})
    world = World.update(world, popup, &%{&1 | image_blend: colour})
    Gml.put(world, popup, %{text: text, text2: then_text})
  end

  defp sound(world, sound) do
    case Gml.first(world, "Ear") do
      nil -> world
      ear -> Sound.play(world, sound, {World.fetch(world, ear).x, World.fetch(world, ear).y})
    end
  end

  defp player_colour(world, player) do
    {colour, _world} = PlayerColour.get(world, nil, player)
    colour
  end

  defp draw_best(world, self, _other) do
    text = "BEST: #{Gml.var(world, self, :best)}"

    Draw.text(world, @font, text, {Camera.center_x(world), Camera.bottom(world) - 2},
      halign: :center,
      valign: :middle,
      colour: @white
    )
  end

  defp draw_score(world, _self, _other) do
    world
    |> Gml.all("ChallengeMode")
    |> Enum.reduce(world, fn challenge, world ->
      shown = Gml.var(world, challenge, :tweenedPoints)
      points = Gml.var(world, challenge, :points)

      colour =
        cond do
          shown > points -> @maroon
          shown < points -> @white
          true -> player_colour(world, Gml.var(world, challenge, :playerIndex))
        end

      outlined(
        world,
        Integer.to_string(round(shown)),
        {Camera.center_x(world), Camera.top(world) + 64},
        %{
          font: @font,
          scale: {6, 7.2},
          angle: 0,
          colour: colour,
          outline: Colour.merge(colour, @black, 0.4)
        },
        halign: :center,
        valign: :middle
      )
    end)
  end

  defp popup_start(world, self, _other) do
    count = length(Gml.all(world, "ScorePopup"))
    {side, world} = Gml.choose(world, [-1, 1])
    frame = System.get(world, :frame)

    world
    |> World.update(self, fn popup ->
      %{
        popup
        | y: popup.y - (count * @popup_rise - @popup_rise),
          image_angle: side * (count - 1) * @popup_turn
      }
      |> Instance.put_alarm(0, @popup_life)
      |> Instance.put_motion(%{vspeed: @popup_vspeed})
    end)
    |> Gml.put(self, %{text: "", text2: "", counter: 0, startFrame: frame})
  end

  defp popup_step(world, self, _other) do
    counter = Gml.var(world, self, :counter) + 1
    world = Gml.put(world, self, %{counter: counter})

    case {counter > @popup_swap, Gml.var(world, self, :text2)} do
      {true, text} when text != "" -> Gml.put(world, self, %{text: text, text2: ""})
      _waiting -> world
    end
  end

  defp popup_draw(world, self, _other) do
    if rem(trunc(System.get(world, :frame)), 4) < 2 do
      %Instance{x: x, y: y, image_angle: angle, image_blend: colour} = World.fetch(world, self)

      outlined(
        world,
        Gml.var(world, self, :text),
        {x, y},
        %{
          font: @font,
          scale: {1.5, 1.5},
          angle: angle,
          colour: colour,
          outline: Colour.merge(@black, colour, 0.1)
        },
        halign: :center,
        valign: :middle
      )
    else
      world
    end
  end
end
