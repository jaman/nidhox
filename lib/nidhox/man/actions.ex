defmodule Nidhox.Man.Actions do
  @moduledoc """
  The small scripts a fencer's states call, as the game's code does them:

    * `footsteps/2` (`playFootsteps`): on frames 0, 5, 11 and 16 of the run (its frame
      rounded, brought into 0–22), once each, a step `sfxRunStep1`–`7` and a rustle
      `sfxClothRun1`–`4`
    * `skids/2` (`playSkids`): `sfxRunSkid1` when left is pressed moving right, or right
      moving left
    * `footwork/4` (`stepLeftAndRightAccelFric(accel, fric)`): a step sound is picked
      (`choose(45, 48, 49, 50, 51)`); pressing right adds `accel × 0.5` moving left,
      `× 0.75` standing, `× 1.8` moving right, and plays it; left the same the other
      way; then `hspd` eases to 0 by `fric`
    * `slide_or_crawl/2` (`landSlidingOrCrawling`): holding down, forward while running
      slides (61), forward otherwise crawls on (58), else crawls (9); `{true, world}`
      when it set a state
    * `lunge_or_butt/2` (`lungeOrSwordButt`): 49 when the opponent is on the ground,
      neither low, collapsing nor stabbed, within 16 pixels across; else 48
    * `try_stomp/2` (`tryToStomp`): the fencers within 20 pixels and the opponent
      knocked down: stomping (69)
    * `combo?/3` (`checkPlayerIndexCombo(player, 0)`): the throw — up and attack each
      pressed within the last 4 frames, unless throws are off
    * `throws_disabled?/1`, `divekicks_disabled?/1`, `spine_swords?/1`
    * `shift_stance/3` (`shift_weapon_stance(way)`): up (2) raises the stance low (2) →
      middle (3) → high (1), down (3) lowers it; a change plays a `sfxChangeLevel` and a
      cloth sound and clears `runButtonHeldCounter`
    * `turn_around_timer/2` (`updateTurnAroundTimer`)
  """

  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Bout.{Input, Sound, Variants}
  alias Nidhox.Gml
  alias Nidhox.Man.{Physics, Query}
  alias Nidhox.Objects.System

  @step_frames [11, 0, 16, 5]
  @run_cycle 23
  @steps 35..41
  @rustles [88, 91, 89, 90]
  @skid 42
  @footwork [45, 48, 49, 50, 51]
  @stance_sounds 65..73
  @cloth [85, 86, 87]

  @doc "`playFootsteps` for fencer `self`."
  @spec footsteps(World.t(), non_neg_integer()) :: World.t()
  def footsteps(%World{} = world, self) do
    frame = in_cycle(Gml.round(Gml.var(world, self, :frame)))

    if frame in @step_frames and Gml.var(world, self, :lastStepFrame, -1) != frame do
      world = Gml.put(world, self, %{lastStepFrame: frame})
      {step, world} = Gml.choose(world, Enum.to_list(@steps))
      world = play(world, self, step)
      {rustle, world} = Gml.choose(world, @rustles)
      play(world, self, rustle)
    else
      world
    end
  end

  @doc "`playSkids` for fencer `self`."
  @spec skids(World.t(), non_neg_integer()) :: World.t()
  def skids(%World{} = world, self) do
    player = Gml.var(world, self, :playerIndex)
    hspd = Gml.var(world, self, :hspd)

    if (Input.pressed?(world, self, player, 0) and hspd > 0) or
         (Input.pressed?(world, self, player, 1) and hspd < 0),
       do: play(world, self, @skid),
       else: world
  end

  @doc "`stepLeftAndRightAccelFric(accel, fric)` for fencer `self`."
  @spec footwork(World.t(), non_neg_integer(), number(), number()) :: World.t()
  def footwork(%World{} = world, self, accel, fric) do
    {sound, world} = Gml.choose(world, @footwork)
    player = Gml.var(world, self, :playerIndex)

    world
    |> step(self, Input.pressed?(world, self, player, 1), 1, accel, sound)
    |> then(&step(&1, self, Input.pressed?(&1, self, player, 0), -1, accel, sound))
    |> Physics.apply_horizontal_friction(self, fric)
  end

  @doc "`landSlidingOrCrawling` for fencer `self`: `{set_a_state, world}`."
  @spec slide_or_crawl(World.t(), non_neg_integer()) :: {boolean(), World.t()}
  def slide_or_crawl(%World{} = world, self) do
    player = Gml.var(world, self, :playerIndex)

    cond do
      not Input.down?(world, self, player, 3) -> {false, world}
      not Input.down?(world, self, player, 8) -> {true, Physics.next_state(world, self, 9)}
      Gml.var(world, self, :state) in [52, 54] -> {true, Physics.next_state(world, self, 61)}
      true -> {true, Physics.next_state(world, self, 58)}
    end
  end

  @doc "`lungeOrSwordButt` for fencer `self`: the state to attack with."
  @spec lunge_or_butt(World.t(), non_neg_integer()) :: integer()
  def lunge_or_butt(%World{} = world, self) do
    other = Query.by_player(world, Query.other_player(Gml.var(world, self, :playerIndex)))

    if other != nil and not Query.crouched?(world, other) and
         not Query.collapsing?(world, other) and not Query.stabbed?(world, other) and
         Gml.truthy?(Gml.var(world, other, :onGround)) and
         abs(World.fetch(world, self).x - World.fetch(world, other).x) < 16,
       do: 49,
       else: 48
  end

  @doc "`tryToStomp` for fencer `self`: `{stomped, world}`."
  @spec try_stomp(World.t(), non_neg_integer()) :: {boolean(), World.t()}
  def try_stomp(%World{} = world, self) do
    if close_enough_to_stomp?(world) and stompable?(world, self),
      do: {true, Physics.next_state(world, self, 69)},
      else: {false, world}
  end

  @doc "`checkPlayerIndexCombo(player, 0)`: the throw combination, asked by fencer `self`."
  @spec combo?(World.t(), non_neg_integer(), integer()) :: boolean()
  def combo?(%World{} = world, self, player) do
    not throws_disabled?(world) and Input.check(world, self, player, 2, 4, true) and
      Input.check(world, self, player, 5, 4, true)
  end

  @doc "Whether throws are off (`throwsDisabled`)."
  @spec throws_disabled?(World.t()) :: boolean()
  def throws_disabled?(world), do: Variants.active?(world) and System.get(world, :throws) == 0

  @doc "Whether divekicks are off (`divekicksDisabled`)."
  @spec divekicks_disabled?(World.t()) :: boolean()
  def divekicks_disabled?(world),
    do: Variants.active?(world) and System.get(world, :divekicks) == 0

  @doc "Whether spine swords are on (`spineSwordsEnabled`)."
  @spec spine_swords?(World.t()) :: boolean()
  def spine_swords?(world),
    do: Variants.active?(world) and Gml.truthy?(System.get(world, :spineSwords))

  @doc "`shift_weapon_stance(way)` for fencer `self`: 2 up, 3 down."
  @spec shift_stance(World.t(), non_neg_integer(), 2 | 3) :: World.t()
  def shift_stance(%World{} = world, self, way) do
    stance = Gml.var(world, self, :stance)
    world = raise_or_lower(world, self, way, stance)

    if Gml.var(world, self, :stance) != stance do
      {change, world} = Gml.choose(world, Enum.to_list(@stance_sounds))
      world = play(world, self, change)
      {cloth, world} = Gml.choose(world, @cloth)

      world
      |> play(self, cloth)
      |> Gml.put(self, %{runButtonHeldCounter: 0})
    else
      world
    end
  end

  @doc "`updateTurnAroundTimer` for fencer `self`."
  @spec turn_around_timer(World.t(), non_neg_integer()) :: World.t()
  def turn_around_timer(%World{} = world, self) do
    timer = Gml.var(world, self, :turnAroundTimer) - 1

    if timer < 0,
      do: Gml.put(world, self, %{turnAroundTimer: 10, turnAroundFlag: 1}),
      else: Gml.put(world, self, %{turnAroundTimer: timer})
  end

  @doc "Sound number `sound` played where fencer `self` stands."
  @spec play(World.t(), non_neg_integer(), non_neg_integer()) :: World.t()
  def play(%World{} = world, self, sound) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    Sound.play(world, sound, {x, y})
  end

  defp raise_or_lower(world, self, 2, 2),
    do: Gml.put(world, self, %{stance: 3, inBetweenHeight: -1})

  defp raise_or_lower(world, self, 2, 3),
    do: Gml.put(world, self, %{stance: 1, inBetweenHeight: -1})

  defp raise_or_lower(world, self, 3, 3), do: Gml.put(world, self, %{stance: 2})
  defp raise_or_lower(world, self, 3, 1), do: Gml.put(world, self, %{stance: 3})
  defp raise_or_lower(world, _self, _way, _stance), do: world

  defp step(world, _self, false, _way, _accel, _sound), do: world

  defp step(world, self, true, way, accel, sound) do
    hspd = Gml.var(world, self, :hspd)

    factor =
      cond do
        hspd * way < 0 -> 0.5
        hspd == 0 -> 0.75
        true -> 1.8
      end

    world
    |> Gml.put(self, %{hspd: hspd + way * accel * factor})
    |> play(self, sound)
  end

  defp in_cycle(frame) when frame < 0, do: in_cycle(frame + @run_cycle)
  defp in_cycle(frame), do: frame

  defp close_enough_to_stomp?(world) do
    with yellow when yellow != nil <- first(world, "YellowPlayer"),
         orange when orange != nil <- first(world, "OrangePlayer") do
      %Instance{x: yx, y: yy} = World.fetch(world, yellow)
      %Instance{x: ox, y: oy} = World.fetch(world, orange)
      :math.sqrt((yx - ox) * (yx - ox) + (yy - oy) * (yy - oy)) < 20
    else
      _ -> false
    end
  end

  defp stompable?(world, self) do
    case Query.by_player(world, Query.other_player(Gml.var(world, self, :playerIndex))) do
      nil -> false
      other -> Query.knocked_down?(world, other)
    end
  end

  defp first(world, name) do
    with object when is_integer(object) <- World.object_index(world, name),
         [id | _] <- World.instances_of(world, object) do
      id
    else
      _none -> nil
    end
  end
end
