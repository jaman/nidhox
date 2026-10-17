defmodule Nidhox.Man.Flesh do
  @moduledoc """
  A fencer's body, the game's `FleshCollisionMask`: the instance a fencer (`mother`)
  makes when it is made, drawn in its player's colour and posed by the fencer's states.

    * create: `ducking`, `craneKicking`, `hasSword` 0; `stabbedWeapon` the array 0, 2, 1, 2;
      `mother` none; `previousX`, `previousY` where it stands
    * draw: tinted `color/3`, drawn as itself; holding a sword,
      or in `sManHitByFlying` or `sManMidairHitByFlying`, the sword drawn for its sprite
      (`@swords`) over it in white, at its frame, place, scale, angle and alpha

  `set_sprite/3` is `setFleshSprite(sprite)`: the body takes the sprite, the fencer's
  facing, the frame `round(frame) mod` its frame count, and `hasSword` from whether the
  fencer's weapon is a sword. `frame_speed_loop/4` is `frameSpeedLoop(speed, loop)`: the
  fencer's `frame` moves on by `speed`; once its ceiling is past the body's last frame it
  goes back once by one less than the frame count when looping, else stays on the last
  frame; it says whether it went past.
  """

  alias Cauldron2D.GameMaker.{Draw, Instance, World}
  alias Nidhox.Bout.PlayerColour
  alias Nidhox.Gml
  alias Nidhox.Man.Physics
  alias Nidhox.Objects.Tournament

  @swords %{
    326 => 481,
    314 => 431,
    333 => 486,
    329 => 483,
    231 => 448,
    264 => 457,
    322 => 478,
    266 => 458,
    267 => 459,
    270 => 462,
    269 => 461,
    268 => 460,
    260 => 454,
    313 => 474,
    228 => 447,
    323 => 479,
    250 => 453,
    272 => 463,
    291 => 468,
    320 => 477,
    330 => 484,
    318 => 475,
    308 => 471,
    311 => 473,
    312 => 473,
    310 => 471,
    331 => 485,
    309 => 472,
    240 => 449,
    319 => 470,
    334 => 488,
    248 => 452,
    349 => 489,
    328 => 482,
    362 => 489,
    348 => 489,
    282 => 464,
    262 => 455,
    241 => 450,
    242 => 451,
    324 => 480,
    283 => 465,
    263 => 456,
    284 => 466,
    285 => 467
  }
  @hit_by_flying [272, 291]
  @white {255, 255, 255}
  @computer 123_456

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_FleshCollisionMask_Create_0", &start/3},
      {"gml_Object_FleshCollisionMask_Draw_0", &draw/3}
    ]
  end

  @doc "`setFleshSprite(sprite)` for fencer `man`."
  @spec set_sprite(World.t(), non_neg_integer(), integer()) :: World.t()
  def set_sprite(%World{} = world, man, sprite) do
    flesh = Gml.var(world, man, :flesh, -4)
    frames = frames(world, sprite)
    frame = Gml.round(Gml.var(world, man, :frame))
    has_sword = if Physics.weapon_type(world, man) == 1, do: 0, else: 1

    world
    |> World.update(flesh, fn %Instance{} = body ->
      %{
        body
        | sprite_index: sprite,
          image_xscale: Gml.var(world, man, :facingXScale, 1),
          image_index: fmod(frame, frames) / 1,
          image_speed: 0.0
      }
    end)
    |> Gml.put(flesh, %{hasSword: has_sword})
  end

  @doc "`frameSpeedLoop(speed, loop)` for fencer `man`; `{went_past, world}`."
  @spec frame_speed_loop(World.t(), non_neg_integer(), number(), boolean()) ::
          {boolean(), World.t()}
  def frame_speed_loop(%World{} = world, man, speed, loop) do
    flesh = World.fetch(world, Gml.var(world, man, :flesh, -4))
    last = frames(world, flesh.sprite_index) - 1
    frame = Gml.var(world, man, :frame) + speed

    cond do
      Float.ceil(frame / 1) <= last -> {false, Gml.put(world, man, %{frame: frame})}
      loop -> {true, Gml.put(world, man, %{frame: frame - last})}
      true -> {true, Gml.put(world, man, %{frame: last})}
    end
  end

  defp start(world, self, _other) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    Gml.put(world, self, %{
      ducking: 0,
      craneKicking: 0,
      hasSword: 0,
      stabbedWeapon: [0, 2, 1, 2],
      mother: -4,
      previousX: x,
      previousY: y
    })
  end

  @doc """
  `fleshColor(man)` as run by instance `caller`: `{colour, world}`, the colour a fencer's
  body is tinted. In a tournament it is the colour of the tournament's player on the
  fencer's side (`Tournament.currentPlayer` + 1). In a single player run it is the
  computer's colour for a player the computer plays. Otherwise it is the colour of the
  fencer's player. The colours come from `Nidhox.Bout.PlayerColour`.
  """
  @spec color(World.t(), non_neg_integer() | nil, non_neg_integer()) ::
          {{byte(), byte(), byte()}, World.t()}
  def color(%World{} = world, caller, man) do
    player = Gml.var(world, man, :playerIndex, 1)
    PlayerColour.get(world, caller, colour_index(world, player))
  end

  defp draw(world, self, _other) do
    %Instance{vars: vars, sprite_index: sprite} = World.fetch(world, self)
    {colour, world} = color(world, self, Map.get(vars, :mother, -4))
    world = World.update(world, self, &%{&1 | image_blend: colour})
    world = Draw.self(world, self)

    if Gml.truthy?(Map.get(vars, :hasSword, 0)) or sprite in @hit_by_flying,
      do: sword(world, World.fetch(world, self)),
      else: world
  end

  defp colour_index(world, player) do
    cond do
      (playing = Tournament.player(world, player)) != nil ->
        playing + 1

      Gml.exists?(world, "ArcadeMode") and brain_for?(world, player) ->
        @computer

      true ->
        player
    end
  end

  defp brain_for?(world, player),
    do: Enum.any?(Gml.all(world, "Brain"), &(Gml.var(world, &1, :playerIndex) == player))

  defp sword(world, %Instance{sprite_index: sprite} = body) do
    case Map.fetch(@swords, sprite) do
      {:ok, overlay} ->
        Draw.sprite(world, overlay, body.image_index, {body.x, body.y},
          scale: {body.image_xscale, body.image_yscale},
          angle: body.image_angle,
          blend: @white,
          alpha: body.image_alpha
        )

      :error ->
        world
    end
  end

  defp frames(world, sprite) do
    case World.sprite(world, sprite) do
      nil -> 1
      definition -> length(definition.frames)
    end
  end

  defp fmod(value, divisor), do: value - trunc(value / divisor) * divisor
end
