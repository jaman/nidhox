defmodule Nidhox.Man.Flesh do
  @moduledoc """
  A fencer's body, the game's `FleshCollisionMask`: the instance a fencer (`mother`)
  makes when it is made, drawn in its player's colour and posed by the fencer's states.

    * create: `ducking`, `craneKicking`, `hasSword` 0; `stabbedWeapon` 2; `mother`
      none; `previousX`, `previousY` where it stands
    * draw: tinted its player's colour (`Nidhox.Bout.PlayerColour`) — in a tournament
      the colour of the tournament's player on that side (`Tournament.currentPlayer`
      + 1), in a single player run the computer's colour for a player the computer
      plays — drawn as itself; holding a sword,
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

  @swords %{
    202 => 203,
    200 => 201,
    234 => 146,
    168 => 143,
    159 => 109,
    217 => 118,
    263 => 139,
    244 => 119,
    245 => 120,
    248 => 123,
    247 => 122,
    246 => 121,
    242 => 115,
    258 => 135,
    236 => 108,
    264 => 140,
    241 => 114,
    218 => 124,
    228 => 129,
    261 => 138,
    266 => 144,
    259 => 136,
    255 => 131,
    257 => 134,
    267 => 145,
    256 => 133,
    237 => 110,
    260 => 130,
    169 => 148,
    161 => 113,
    174 => 149,
    167 => 142,
    206 => 149,
    173 => 149,
    249 => 125,
    243 => 116,
    238 => 111,
    239 => 112,
    265 => 141,
    250 => 126,
    216 => 117,
    251 => 127,
    252 => 128
  }
  @hit_by_flying [218, 228]
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
      stabbedWeapon: 2,
      mother: -4,
      previousX: x,
      previousY: y
    })
  end

  defp draw(world, self, _other) do
    %Instance{vars: vars, sprite_index: sprite} = World.fetch(world, self)
    player = Gml.var(world, Map.get(vars, :mother, -4), :playerIndex, 1)
    {colour, world} = PlayerColour.get(world, self, colour_index(world, player))
    world = World.update(world, self, &%{&1 | image_blend: colour})
    world = Draw.self(world, self)

    if Gml.truthy?(Map.get(vars, :hasSword, 0)) or sprite in @hit_by_flying,
      do: sword(world, World.fetch(world, self)),
      else: world
  end

  defp colour_index(world, player) do
    cond do
      (tournament = Gml.first(world, "Tournament")) != nil ->
        Map.get(Gml.var(world, tournament, :currentPlayer, %{}), player, 0) + 1

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
