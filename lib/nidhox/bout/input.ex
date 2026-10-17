defmodule Nidhox.Bout.Input do
  @moduledoc """
  The players' buttons in a match, recorded and read as the game's code does it.

  Buttons are numbered as the code numbers them: 0 left, 1 right, 2 up, 3 down,
  4 jump, 5 attack; 8 is forward and 9 back, which a fencer turns into left or right by
  the way it faces (`facingXScale`).

  `record/3` is `updateMatchInput` for players at this machine: once a frame
  (`System.frame` past `Match.lastFramePolled`) it reads each player's buttons and keeps
  them in `Match.inputMap` under the frame — when the player has nothing kept yet, when
  the frame is a multiple of 60, or when the buttons differ from the last kept. It reads
  nothing in a flow the game keeps no buttons in (`System.flow` other than 1, 2, 3, 4,
  656686433, 9836834, 62831853 and 4890734). A match starts from `initial_map/0`, which
  holds every button up at frame 0.

  `check/6` is `checkButton(player, button, window, pressed)`. It finds the buttons kept
  last at or before `frame − window`; with none, the button is not down. Then over the
  frames from there to now:

    * pressed: true if a kept frame has the button down where the one before had it up
    * not pressed: true if the button is down at the start or on any kept frame

  `down?/4` is `checkPlayerIndexButtonDown` (the current frame) and `pressed?/4`
  `checkPlayerIndexButtonPressed` (a window of 1), each true for a button a variant
  holds down (`variantInterrupt`): up under throws-only unless down is held, down in
  baby mode, and jump in skippy mode while the player's fencer is on the ground moving
  faster than 1.1 a step.
  """

  alias Cauldron2D.GameMaker.{Instance, World}
  alias Nidhox.Bout.Variants
  alias Nidhox.Gml
  alias Nidhox.Objects.System

  @buttons [:left, :right, :up, :down, :jump, :attack]
  @players [1, 2]
  @keyframe 60
  @forward 8
  @back 9
  @up 2
  @down 3
  @jump 4
  @recorded_flows [1, 2, 3, 4, 656_686_433, 9_836_834, 62_831_853, 4_890_734]

  @doc """
  The world with the buttons `held` (`%{player => MapSet of actions}`) kept for the
  current frame in the match `match`'s `inputMap`, as `updateMatchInput` keeps them.
  """
  @spec record(World.t(), non_neg_integer(), %{integer() => MapSet.t()}) :: World.t()
  def record(%World{} = world, match, held) do
    frame = System.get(world, :frame)

    if System.get(world, :flow) in @recorded_flows and
         frame > Gml.var(world, match, :lastFramePolled, -1) do
      map = Gml.var(world, match, :inputMap, %{})
      map = Enum.reduce(@players, map, &keep(&2, &1, frame, buttons(Map.get(held, &1))))
      Gml.put(world, match, %{lastFramePolled: frame, inputMap: map})
    else
      world
    end
  end

  @doc "The kept buttons of a new match: every button up at frame 0, for both players."
  @spec initial_map() :: %{integer() => [{integer(), tuple()}]}
  def initial_map, do: Map.new(@players, &{&1, [{0, buttons(nil)}]})

  @doc "Whether `player`'s `button` is down now, or a variant holds it down (`checkPlayerIndexButtonDown`)."
  @spec down?(World.t(), non_neg_integer(), integer(), non_neg_integer()) :: boolean()
  def down?(world, self, player, button),
    do:
      interrupted?(world, self, player, button) or
        check(world, self, player, button, 0, false)

  @doc "Whether `player`'s `button` was just pressed, or a variant holds it down (`checkPlayerIndexButtonPressed`)."
  @spec pressed?(World.t(), non_neg_integer(), integer(), non_neg_integer()) :: boolean()
  def pressed?(world, self, player, button),
    do:
      interrupted?(world, self, player, button) or
        check(world, self, player, button, 1, true)

  @doc "`checkButton(player, button, window, pressed)` asked by instance `self`."
  @spec check(World.t(), non_neg_integer(), integer(), non_neg_integer(), number(), boolean()) ::
          boolean()
  def check(%World{} = world, self, player, button, window, pressed) do
    button = facing_button(world, self, button)
    frame = System.get(world, :frame)
    start = frame - window

    case match(world) do
      nil ->
        false

      match ->
        look(
          Gml.var(world, match, :inputMap, %{}) |> Map.get(player, []),
          button,
          start,
          frame,
          pressed
        )
    end
  end

  defp look(kept, button, start, frame, pressed) do
    case Enum.find(kept, fn {at, _bits} -> at <= start and at >= 0 end) do
      nil ->
        false

      {_at, bits} ->
        window =
          kept |> Enum.filter(fn {at, _bits} -> at >= start and at <= frame end) |> Enum.reverse()

        seen(window, button, elem(bits, button), pressed)
    end
  end

  defp seen(window, button, before, true) do
    window
    |> Enum.reduce_while(before, fn {_at, bits}, previous ->
      now = elem(bits, button)
      if now == 1 and previous == 0, do: {:halt, :pressed}, else: {:cont, now}
    end)
    |> Kernel.==(:pressed)
  end

  defp seen(window, button, before, false),
    do: before == 1 or Enum.any?(window, fn {_at, bits} -> elem(bits, button) == 1 end)

  defp facing_button(world, self, @forward), do: if(facing_right?(world, self), do: 1, else: 0)
  defp facing_button(world, self, @back), do: if(facing_right?(world, self), do: 0, else: 1)
  defp facing_button(_world, _self, button), do: button

  defp facing_right?(world, self), do: Gml.truthy?(Gml.var(world, self, :facingXScale, 1))

  defp interrupted?(world, self, player, @up) do
    Variants.throws_only?(world) and match(world) != nil and
      not down?(world, self, player, @down)
  end

  defp interrupted?(world, _self, _player, @down),
    do: Variants.baby_mode?(world) and match(world) != nil

  defp interrupted?(world, _self, player, @jump) do
    with true <- Variants.skippy_mode?(world),
         match when match != nil <- match(world),
         %Instance{vars: vars} <- man(world, player) do
      Gml.truthy?(Map.get(vars, :onGround, 0)) and abs(Map.get(vars, :hspd, 0)) - 1.1 > 0
    else
      _ -> false
    end
  end

  defp interrupted?(_world, _self, _player, _button), do: false

  defp keep(map, player, frame, bits) do
    kept = Map.get(map, player, [])

    cond do
      Enum.any?(kept, fn {at, _bits} -> at == frame end) -> map
      kept == [] or rem(frame, @keyframe) == 0 -> Map.put(map, player, [{frame, bits} | kept])
      elem(hd(kept), 1) != bits -> Map.put(map, player, [{frame, bits} | kept])
      true -> map
    end
  end

  defp buttons(nil), do: buttons(MapSet.new())

  defp buttons(held),
    do: @buttons |> Enum.map(&if(MapSet.member?(held, &1), do: 1, else: 0)) |> List.to_tuple()

  defp match(world), do: first(world, "Match")

  defp man(world, player) do
    with object when is_integer(object) <- World.object_index(world, "Man") do
      world
      |> World.instances_of(object)
      |> Enum.map(&World.fetch(world, &1))
      |> Enum.find(&(Map.get(&1.vars, :playerIndex) == player))
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
