defmodule Nidhox.Art do
  @moduledoc """
  NidhOX's own fencers and swords, drawn as text pictures and coloured per side.

  `table/0` gives every picture by the key `Nidhox.Look` names it with:

    * `{:fencer, side, frame}` — a fencer's body, standing on the bottom middle of the
      picture and facing right. `frame` is `:stand`, `{:walk, 0..1}`, `{:run, 0..3}`,
      `:lunge`, `:air` or `:down` (lying, for a fencer killed)
    * `{:arm, side, stance}` — the sword arm from the shoulder to the hand, for `:high`,
      `:middle`, `:low` and `:extended`; the hand is at the picture's right edge
    * `:sword` — the blade, hilt at the left; `:flying_sword` — a sword in flight
  """

  @colours %{
    1 => %{B: {245, 205, 70}, D: {170, 130, 30}, H: {255, 236, 160}},
    2 => %{B: {240, 120, 45}, D: {160, 70, 20}, H: {255, 190, 140}}
  }

  @steel %{S: {214, 218, 228}, G: {130, 96, 46}}

  @head """
  ...HHHH...
  ..HHHHHH..
  ..HDDDHH..
  ..HHHHHH..
  ...HHHH...
  ....BB....
  """

  @torso """
  ...BBBB...
  ..BBBBBB..
  ..BBBBBB..
  ..BBBBBB..
  ..BBBBBB..
  ..BBBBBB..
  ..DDDDDD..
  """

  @legs %{
    stand: """
    ..BB..BB..
    ..BB..BB..
    ..BB..BB..
    ..BB..BB..
    ..BB..BB..
    ..BB..BB..
    ..BB..BB..
    ..BB..BB..
    ..BB..BB..
    .DDD..DDD.
    """,
    walk_0: """
    ..BB..BB..
    ..BB..BB..
    .BB....BB.
    .BB....BB.
    .BB....BB.
    BB......BB
    BB......BB
    BB......BB
    BB......BB
    DD......DD
    """,
    walk_1: """
    ..BB..BB..
    ..BB..BB..
    ..BBB.BB..
    ...BB.BB..
    ...BBBB...
    ...BBBB...
    ....BB....
    ...BBBB...
    ...BBBB...
    ...DDDD...
    """,
    run_0: """
    ..BB..BB..
    .BB....BB.
    BB......BB
    B........B
    B.........
    BB........
    .B........
    ..........
    ..........
    ..........
    """,
    run_1: """
    ..BB..BB..
    ..BB...BB.
    ..BB....BB
    ..BB.....B
    ..BB.....B
    ..BB......
    ..BB......
    ..BB......
    ..BB......
    .DDD......
    """,
    run_2: """
    ..BB..BB..
    .BB....BB.
    BB......BB
    B........B
    .........B
    ........BB
    ........B.
    ..........
    ..........
    ..........
    """,
    run_3: """
    ..BB..BB..
    .BB...BB..
    BB....BB..
    B.....BB..
    B.....BB..
    ......BB..
    ......BB..
    ......BB..
    ......BB..
    ......DDD.
    """,
    lunge: """
    ..BB..BB..
    .BB....BB.
    BB......BB
    BB.......B
    B........B
    B.........
    B.........
    B.........
    B.........
    DD........
    """,
    air: """
    ..BB..BB..
    ..BB..BB..
    ..BBB.BBB.
    ...BB..BB.
    ...BB...B.
    ...BB.....
    ..........
    ..........
    ..........
    ..........
    """
  }

  @down """
  ..........................
  .HHHH.....................
  HHDDHH..BBBBBBBBBBB.......
  HHHHHH.BBBBBBBBBBBBDBBBBB.
  .HHHH..BBBBBBBBBBBBDBBBBBD
  ........BBBBBBBBBBB....DDD
  """

  @arms %{
    high: """
    ......
    ....BB
    ..BBB.
    BBB...
    """,
    middle: """
    BB....
    .BBB..
    ...BBB
    """,
    low: """
    BB....
    BB....
    .BB...
    .BB...
    ..BB..
    ..BB..
    ...BB.
    ...BBB
    """,
    extended: """
    BBBBBBBB
    """
  }

  @sword """
  GSSSSSSSSSSSSSS
  GSSSSSSSSSSSSS.
  """

  @flying_sword """
  ..SSSSSSSSSSSSS
  GGSSSSSSSSSSSSS
  """

  @doc "Every picture by its key."
  @spec table() :: %{term() => FrenchCurve.Raster.t()}
  def table do
    for side <- [1, 2],
        reduce: %{:sword => steel(@sword), :flying_sword => steel(@flying_sword)} do
      table ->
        table
        |> Map.merge(bodies(side))
        |> Map.merge(
          Map.new(@arms, fn {stance, text} -> {{:arm, side, stance}, paint(text, side)} end)
        )
    end
  end

  @doc "Where a body's shoulder sits, above its feet."
  @spec shoulder() :: number()
  def shoulder, do: 18

  defp bodies(side) do
    frames = %{
      :stand => :stand,
      {:walk, 0} => :walk_0,
      {:walk, 1} => :walk_1,
      {:run, 0} => :run_0,
      {:run, 1} => :run_1,
      {:run, 2} => :run_2,
      {:run, 3} => :run_3,
      :lunge => :lunge,
      :air => :air
    }

    frames
    |> Map.new(fn {frame, legs} ->
      {{:fencer, side, frame}, paint(@head <> @torso <> @legs[legs], side)}
    end)
    |> Map.put({:fencer, side, :down}, paint(@down, side))
  end

  defp paint(text, side), do: Linocut.sprite(text, Map.to_list(@colours[side]))
  defp steel(text), do: Linocut.sprite(text, Map.to_list(@steel))
end
