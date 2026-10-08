defmodule Nidhox.Sprites do
  @moduledoc """
  In-memory access to sprite frames and game data from Nidhogg's `data.win`.

  Provides access to all sprite frames, game objects (rooms/areas), and sprites
  organized by game entity type.

  ## Usage

      Nidhox.Sprites.list()                              # sprite inventory
      Nidhox.Sprites.list_areas()                        # list room names
      Nidhox.Sprites.sprite_by_name("sManStandResting")  # get sprite struct
      Nidhox.Sprites.frames("sManStandResting")          # frame rasters
      table = Nidhox.Sprites.table()                     # pose -> frame map

  If assets have not been loaded, these functions will attempt to find and load
  `data.win` automatically (raising a helpful error when no file is found).
  """

  alias Nidhox.Assets
  alias Cauldron2D.GameMaker.Pictures
  alias FrenchCurve.Raster, as: FR

  @doc "Full sprite inventory: [{name, frame_count, size, origin}]."
  @spec list() :: [
          {String.t(), non_neg_integer(), {integer(), integer()}, {integer(), integer()} | nil}
        ]
  def list do
    ensure_loaded!()
    sprites = extract(Assets.get().data.sprites)

    Enum.map(sprites, fn %{name: name, size: size, origin: origin} = sprite ->
      {name, length(sprite.frames), size, origin}
    end)
  end

  @doc """
  Returns all sprite names sorted alphabetically.

  ## Example

      Nidhox.Sprites.sprite_names()
      #=> ["sManStandResting", "sManRun", "sSword", ...]
  """
  @spec sprite_names() :: [String.t()]
  def sprite_names do
    list() |> Enum.map(fn {name, _, _, _} -> name end) |> Enum.sort()
  end

  @doc """
  Returns the sprite struct for the given name.

  Returns `%Cauldron2D.GameMaker.Sprite{}` with `name`, `size`, `origin`,
  `frames`, and `masks` fields.

  ## Examples

      Nidhox.Sprites.sprite_by_name("sManStandResting")
      #=> %Cauldron2D.GameMaker.Sprite{name: "sManStandResting", ...}

      Nidhox.Sprites.sprite_by_name("nonexistent")
      #=> ** (ArgumentError) unknown sprite: "nonexistent"
  """
  @spec sprite_by_name(String.t()) :: Cauldron2D.GameMaker.Sprite.t()
  def sprite_by_name(name) do
    sprites = extract(Assets.get().data.sprites)

    case Enum.find(sprites, &(&1.name == name)) do
      nil ->
        raise ArgumentError,
              "unknown sprite: #{inspect(name)} (call sprite_names() for valid names)"

      sprite ->
        sprite
    end
  end

  @doc """
  Returns all frames of sprite `name` as a list of `FrenchCurve.Raster`, index 0-based.

  ## Examples

      Nidhox.Sprites.frames("sManStandResting")
      #=> [raster1, raster2, raster3]
  """
  @spec frames(String.t()) :: [FrenchCurve.Raster.t()]
  def frames(name) do
    sprite = sprite_by_name(name)
    pics = Assets.get().pages

    Enum.map(0..(length(sprite.frames) - 1), fn frame_index ->
      Enum.at(Pictures.sprite(pics, sprite), frame_index)
    end)
  end

  @doc """
  Returns a single frame from sprite `name`, index 0-based.

  Raises `ArgumentError` if frame_index is out of range.

  ## Examples

      Nidhox.Sprites.frame("sManStandResting", 0)
      #=> %FrenchCurve.Raster{...}

      Nidhox.Sprites.frame("sManStandResting", 100)
      #=> ** (ArgumentError) frame 100 out of range...
  """
  @spec frame(String.t(), integer()) :: FrenchCurve.Raster.t()
  def frame(name, frame_index) do
    {_size, _origin, frames_count} = find!(name, list())

    case frame_index do
      index when index >= 0 and index < frames_count ->
        sprite = sprite_by_name(name)
        pics = Assets.get().pages
        Enum.at(Pictures.sprite(pics, sprite), frame_index)

      index ->
        raise ArgumentError,
              "frame #{index} out of range for #{name} (#{frames_count} frames: 0..#{frames_count - 1})"
    end
  end

  @doc """
  Lists all room/area names from the game data.

  ## Example

      Nidhox.Sprites.list_areas()
      #=> ["roomTitleScreen", "roomBattle", "roomForest", ...]
  """
  @spec list_areas() :: [String.t()]
  def list_areas do
    ensure_loaded!()
    Enum.map(Assets.get().data.rooms, fn room -> room.name end) |> Enum.sort()
  end

  @doc """
  Returns the room/area struct for the given name.

  ## Examples

      Nidhox.Sprites.room_by_name("roomBattle")
      #=> %Cauldron2D.GameMaker.Room{...}

      Nidhox.Sprites.room_by_name("nonexistent")
      #=> ** (ArgumentError) unknown room: "nonexistent"
  """
  @spec room_by_name(String.t()) :: Cauldron2D.GameMaker.Room.t()
  def room_by_name(name) do
    ensure_loaded!()

    case Enum.find(Assets.get().data.rooms, &(&1.name == name)) do
      nil ->
        raise ArgumentError, "unknown room: #{inspect(name)} (call list_areas() for valid names)"

      room ->
        room
    end
  end

  @doc """
  Lists all game object (entity) names.

  Objects are game entities like fencers, weapons, birds, blocks, etc.

  ## Example

      Nidhox.Sprites.object_names()
      #=> ["Man", "Bird", "HeldWeapon", "FlyingWeapon", "DefensiveBlock", ...]
  """
  @spec object_names() :: [String.t()]
  def object_names do
    ensure_loaded!()
    Enum.map(Assets.get().data.objects, fn object -> object.name end) |> Enum.sort()
  end

  @doc """
  Returns the game object struct for the given name.

  ## Examples

      Nidhox.Sprites.object_by_name("Man")
      #=> %Cauldron2D.GameMaker.Object{events: [...], ...}

      Nidhox.Sprites.object_by_name("nonexistent")
      #=> ** (ArgumentError) unknown object: "nonexistent"
  """
  @spec object_by_name(String.t()) :: Cauldron2D.GameMaker.Object.t()
  def object_by_name(name) do
    ensure_loaded!()

    case Enum.find(Assets.get().data.objects, &(&1.name == name)) do
      nil ->
        raise ArgumentError, "unknown room: #{inspect(name)} (call list_areas() for valid names)"

      object ->
        object
    end
  end

  @doc """
  Lists all scripts (game logic functions) by name.

  Scripts contain the game's source code logic (bytecode offsets).

  ## Example

      Nidhox.Scripts.script_names()
      #=> ["stateGraphic", "processNextState", "stateBehavior", ...]
  """
  @spec script_names() :: [String.t()]
  def script_names do
    ensure_loaded!()
    Enum.map(Assets.get().data.scripts, fn script -> script.name end) |> Enum.sort()
  end

  @doc """
  Returns the script struct for the given name.

  Scripts contain game logic (bytecode offsets).

  ## Examples

      Nidhox.Sprites.script_by_name("stateGraphic")
      #=> %Cauldron2D.GameMaker.Script{code: 486, ...}

      Nidhox.Sprites.script_by_name("nonexistent")
      #=> ** (ArgumentError) unknown script: "nonexistent"
  """
  @spec script_by_name(String.t()) :: Cauldron2D.GameMaker.Script.t()
  def script_by_name(name) do
    ensure_loaded!()

    case Enum.find(Assets.get().data.scripts, &(&1.name == name)) do
      nil ->
        raise ArgumentError,
              "unknown script: #{inspect(name)} (call script_names() for valid names)"

      script ->
        script
    end
  end

  @doc """
  Returns the sprite frame count for a given sprite name.

  ## Example

      Nidhox.Sprites.frame_count("sManStandResting")
      #=> 3

      Nidhox.Sprites.frame_count("sManRun")
      #=> 24
  """
  @spec frame_count(String.t()) :: non_neg_integer()
  def frame_count(name) do
    {_size, _origin, count} = find!(name, list())
    count
  end

  @doc """
  Returns the sprite size for a given sprite name.

  ## Example

      Nidhox.Sprites.size("sManStandResting")
      #=> {24, 35}

      Nidhox.Sprites.size("sManRun")
      #=> {23, 27}
  """
  @spec size(String.t()) :: {integer(), integer()}
  def size(name) do
    {size, _origin, _count} = find!(name, list())
    size
  end

  @doc """
  Returns the sprite origin for a given sprite name.

  Origin is the pivot point for drawing (typically foot position for fencers).

  ## Example

      Nidhox.Sprites.origin("sManStandResting")
      #=> {13, 30}

      Nidhox.Sprites.origin("sManRun")
      #=> {13, 27}
  """
  @spec origin(String.t()) :: {integer(), integer()} | nil
  def origin(name) do
    {_size, origin, _count} = find!(name, list())
    origin
  end

  @doc """
  Returns whether a sprite name exists in the data.

  ## Example

      Nidhox.Sprites.exists?("sManStandResting")
      #=> true

      Nidhox.Sprites.exists?("nonexistent")
      #=> false
  """
  @spec exists?(String.t()) :: boolean()
  def exists?(name) do
    list() |> Enum.any?(fn {n, _, _, _} -> n == name end)
  end

  @doc "Pose lookup table: maps `Nidhox.Look` keys to sprite frames."
  @spec table(Cauldron2D.GameMaker.Pictures.t(), Data.t()) :: %{term() => FrenchCurve.Raster.t()}
  def table(pics, data) do
    sprites = extract(data.sprites)

    Enum.reduce(
      body_frames(pics, sprites) ++
        blade_frames(pics, sprites) ++
        sword_frames(pics, sprites) ++
        bird_frames(pics, sprites) ++
        effect_frames(pics, sprites),
      %{},
      fn {key, raster}, acc -> Map.put(acc, key, raster) end
    )
  end

  @doc "Pose lookup table (auto-loads if needed)."
  @spec table() :: %{term() => FrenchCurve.Raster.t()}
  def table do
    ensure_loaded!()
    table(Assets.get().pages, Assets.get().data)
  end

  # -- Private helpers --

  defp ensure_loaded!() do
    unless Assets.loaded?() do
      case Assets.find(nil) do
        nil ->
          raise ArgumentError,
                "no data.win found — run `mix nidhox` first, or set NIDHOX_DATA"

        path ->
          case Assets.load(path) do
            {:ok, _} ->
              :ok

            {:error, reason} ->
              raise ArgumentError, "could not load data.win: #{inspect(reason)}"
          end
      end
    end
  end

  defp find!(name, list) do
    case Enum.find(list, fn {n, _, _, _} -> n == name end) do
      {_n, frames_count, size, origin} -> {size, origin, frames_count}
      nil -> raise(ArgumentError, "unknown sprite: #{inspect(name)} (call list() for names)")
    end
  end

  defp extract([]), do: []
  defp extract([sprite | rest]) when is_map(sprite), do: [sprite | extract(rest)]
  defp extract([_ | rest]), do: extract(rest)

  # ============================================================================
  # Pose-to-sprite mapping — each animation keeps its own frame count.
  #
  # Key: {:pose, side, frame_index}
  #
  # The frame count is intrinsic to the animation itself — a 2-frame idle
  # cycles through 2 frames, a 15-frame lunge cycles through 15 frames.
  # They are not squeezed into a shared bucket.
  #
  # Body colour maps (Art.colours/0):
  #   Side 1 (yellow): B = base {245,205,70}, D = dark {170,130,30},
  #                      H = highlight {255,236,160}
  #   Side 2 (orange): B = base {240,120,45}, D = dark {160,70,20},
  #                      H = highlight {255,190,140}
  #
  # Steel colour map (Art.steel/0):
  #   S = steel {214,218,228}, G = gold {130,96,46}
  #
  # Both sides share the same frame data for each pose — side only controls
  # the color tint via the colour maps.
  # ============================================================================

  # Source colour used in GameMaker sprite files — white pixels are the paint.
  @white {255, 255, 255}
  # Body base colours per side (yellow / orange).
  @side1_base {245, 205, 70}
  @side2_base {240, 120, 45}
  # Steel colour (swords, not tinted by side).
  @steel_color {214, 218, 228}

  defp find_sprite!(sprites, name) do
    case Enum.find(sprites, &(&1.name == name)) do
      nil -> raise ArgumentError, "sprite not found: #{inspect(name)}"
      sprite -> sprite
    end
  end

  # ---------------------------------------------------------------------------
  # Colorize a raster: replace every occurrence of `source_rgb` with
  # `target_rgb`, preserving alpha.  Pixels not matching the source are
  # passed through unchanged (e.g. background, shadows).
  # ---------------------------------------------------------------------------

  defp colorize(%FR{} = raster, source_rgb, target_rgb) do
    {width, height} = FR.dimensions(raster)

    Enum.reduce(0..(height - 1), raster, fn y, acc ->
      Enum.reduce(0..(width - 1), acc, fn x, acc ->
        {r, g, b, a} = FR.get_pixel(acc, x, y)

        case {r, g, b} do
          ^source_rgb ->
            FR.put_pixel(
              acc,
              x,
              y,
              {elem(target_rgb, 0), elem(target_rgb, 1), elem(target_rgb, 2), a}
            )

          _ ->
            acc
        end
      end)
    end)
    |> FR.finalize()
  end

  defp body_frames(pics, sprites) do
    # Extract body sprites (yellow sprite names — both sides share frames).
    stand = find_sprite!(sprites, "sManStandResting")
    run = find_sprite!(sprites, "sManRun")
    attack = find_sprite!(sprites, "sManSwordAttackMed")
    jump = find_sprite!(sprites, "sManJump")
    dead = find_sprite!(sprites, "sManLieOnBack")

    cheer = find_sprite!(sprites, "sManCheering")
    dance = find_sprite!(sprites, "sManDance1")
    shout = find_sprite!(sprites, "sManShouting")
    hop = find_sprite!(sprites, "sManHopping")

    # Throw animations (new).
    throw_stand = find_sprite!(sprites, "sManThrowStanding")
    throw_air = find_sprite!(sprites, "sManThrowMidAir")

    # Extract frames as rasters for each source sprite.
    stand_frames = Pictures.sprite(pics, stand)
    run_frames = Pictures.sprite(pics, run)
    attack_frames = Pictures.sprite(pics, attack)
    jump_frames = Pictures.sprite(pics, jump)
    dead_frames = Pictures.sprite(pics, dead)
    cheer_frames = Pictures.sprite(pics, cheer)
    dance_frames = Pictures.sprite(pics, dance)
    shout_frames = Pictures.sprite(pics, shout)
    hop_frames = Pictures.sprite(pics, hop)
    throw_stand_frames = Pictures.sprite(pics, throw_stand)
    throw_air_frames = Pictures.sprite(pics, throw_air)

    # Helper: colourize each frame for the given side.
    colorized_for_side = fn sprite_frames, frame_count, target_color ->
      Enum.map(0..(frame_count - 1), fn idx ->
        Enum.at(sprite_frames, idx)
      end)
      |> Enum.map(fn frame -> colorize(frame, @white, target_color) end)
    end

    side1_color = @side1_base
    side2_color = @side2_base

    stand_s1 = colorized_for_side.(stand_frames, 3, side1_color)
    stand_s2 = colorized_for_side.(stand_frames, 3, side2_color)
    run_s1 = colorized_for_side.(run_frames, 24, side1_color)
    run_s2 = colorized_for_side.(run_frames, 24, side2_color)
    attack_s1 = colorized_for_side.(attack_frames, 15, side1_color)
    attack_s2 = colorized_for_side.(attack_frames, 15, side2_color)
    jump_s1 = colorized_for_side.(jump_frames, 3, side1_color)
    jump_s2 = colorized_for_side.(jump_frames, 3, side2_color)
    dead_s1 = colorized_for_side.(dead_frames, 7, side1_color)
    dead_s2 = colorized_for_side.(dead_frames, 7, side2_color)
    cheer_s1 = colorized_for_side.(cheer_frames, 6, side1_color)
    cheer_s2 = colorized_for_side.(cheer_frames, 6, side2_color)
    dance_s1 = colorized_for_side.(dance_frames, 18, side1_color)
    dance_s2 = colorized_for_side.(dance_frames, 18, side2_color)
    shout_s1 = colorized_for_side.(shout_frames, 8, side1_color)
    shout_s2 = colorized_for_side.(shout_frames, 8, side2_color)
    hop_s1 = colorized_for_side.(hop_frames, 8, side1_color)
    hop_s2 = colorized_for_side.(hop_frames, 8, side2_color)
    throw_stand_s1 = colorized_for_side.(throw_stand_frames, 13, side1_color)
    throw_stand_s2 = colorized_for_side.(throw_stand_frames, 13, side2_color)
    throw_air_s1 = colorized_for_side.(throw_air_frames, 7, side1_color)
    throw_air_s2 = colorized_for_side.(throw_air_frames, 7, side2_color)

    # Map every keyed frame for both sides.
    # Idle — same frames for both sides.
    # Throw animations (grounded standing throw, air throw).
    Enum.map(0..2, &{{:stand, 1, &1}, Enum.at(stand_s1, &1)}) ++
      Enum.map(0..2, &{{:stand, 2, &1}, Enum.at(stand_s2, &1)}) ++
      Enum.map(0..23, &{{:walk, 1, &1}, Enum.at(run_s1, &1)}) ++
      Enum.map(0..23, &{{:walk, 2, &1}, Enum.at(run_s2, &1)}) ++
      Enum.map(0..23, &{{:run, 1, &1}, Enum.at(run_s1, &1)}) ++
      Enum.map(0..23, &{{:run, 2, &1}, Enum.at(run_s2, &1)}) ++
      Enum.map(0..14, &{{:lunge, 1, &1}, Enum.at(attack_s1, &1)}) ++
      Enum.map(0..14, &{{:lunge, 2, &1}, Enum.at(attack_s2, &1)}) ++
      Enum.map(0..2, &{{:air, 1, &1}, Enum.at(jump_s1, &1)}) ++
      Enum.map(0..2, &{{:air, 2, &1}, Enum.at(jump_s2, &1)}) ++
      Enum.map(0..6, &{{:down, 1, &1}, Enum.at(dead_s1, &1)}) ++
      Enum.map(0..6, &{{:down, 2, &1}, Enum.at(dead_s2, &1)}) ++
      Enum.map(0..5, &{{:cheer, 1, &1}, Enum.at(cheer_s1, &1)}) ++
      Enum.map(0..5, &{{:cheer, 2, &1}, Enum.at(cheer_s2, &1)}) ++
      Enum.map(0..17, &{{:dance, 1, &1}, Enum.at(dance_s1, &1)}) ++
      Enum.map(0..17, &{{:dance, 2, &1}, Enum.at(dance_s2, &1)}) ++
      Enum.map(0..7, &{{:shout, 1, &1}, Enum.at(shout_s1, &1)}) ++
      Enum.map(0..7, &{{:shout, 2, &1}, Enum.at(shout_s2, &1)}) ++
      Enum.map(0..7, &{{:hop, 1, &1}, Enum.at(hop_s1, &1)}) ++
      Enum.map(0..7, &{{:hop, 2, &1}, Enum.at(hop_s2, &1)}) ++
      Enum.map(0..12, &{{:throw, 1, &1}, Enum.at(throw_stand_s1, &1)}) ++
      Enum.map(0..12, &{{:throw, 2, &1}, Enum.at(throw_stand_s2, &1)}) ++
      Enum.map(0..6, &{{:throw_air, 1, &1}, Enum.at(throw_air_s1, &1)}) ++
      Enum.map(0..6, &{{:throw_air, 2, &1}, Enum.at(throw_air_s2, &1)})
  end

  # Standalone sword sprites (used only for weapon objects):
  # sSword (1 frame) — held/thrown weapon blade
  # sFlyingSword (1 frame) — flying/thrown weapon (yellow or orange)
  # Swords are NOT tinted — they use a fixed steel colour.
  defp blade_frames(pics, sprites) do
    sword_sprite = find_sprite!(sprites, "sSword")
    fly = find_sprite!(sprites, "sFlyingSword")

    sword_frames = Pictures.sprite(pics, sword_sprite)
    fly_frames = Pictures.sprite(pics, fly)

    [{:sword, colorize(Enum.at(sword_frames, 0), @white, @steel_color)}] ++
      [{:flying_sword, colorize(Enum.at(fly_frames, 0), @white, @steel_color)}]
  end

  defp sword_frames(_pics, _sprites) do
    []
  end

  defp bird_frames(pics, sprites) do
    Enum.flat_map(
      [
        {:fly, "sprBirdFly", 4},
        {:hover, "sprBirdHover", 4},
        {:stand, "sprBirdStand", 2}
      ],
      fn {behavior, name, frame_count} ->
        sprite = find_sprite!(sprites, name)
        sprite_frames = Pictures.sprite(pics, sprite)

        Enum.map(0..(frame_count - 1), fn frame_idx ->
          {{:bird, behavior}, Enum.at(sprite_frames, frame_idx)}
        end)
      end
    )
  end

  defp effect_frames(pics, sprites) do
    Enum.flat_map(
      [
        {:smoke, "sSmoke", 9},
        {:blood, "sBloodEffect", 12},
        {:snowflake, "sSnowflake", 3},
        {:block, "sDefensiveBlock", 1},
        {:block_animated, "sDefensiveAnimated", 3},
        {:moon, "sMoon", 2},
        {:cloud, "sClouds", 1},
        {:grass, "sGrassFlatten", 5},
        {:foreground, "sWindowForeground", 1},
        {:leaf_bg, "bDarkLeavesBG", 1},
        {:bg_stands, "bgStands", 1},
        {:bg_side_stands, "bgSideStands", 1},
        {:bg_back_stands, "bgBackStands", 1},
        {:sky_alpha, "background_sky_alpha", 1}
      ],
      fn {effect, name, frame_count} ->
        sprite = find_sprite!(sprites, name)
        sprite_frames = Pictures.sprite(pics, sprite)

        Enum.map(0..(frame_count - 1), fn frame_idx ->
          {{:effect, effect}, Enum.at(sprite_frames, frame_idx)}
        end)
      end
    )
  end
end
