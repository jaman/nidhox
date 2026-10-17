defmodule Nidhox.Objects.FireClouds do
  @moduledoc """
  The castle's burning sky (`oFireClouds`), as the game's code runs it: smoke rising
  from fire, made by drawing its last picture back onto itself a little wider and higher
  each step and adding new puffs at the bottom.

    * create: two clear 600 × 400 surfaces (`surfA`, `surfB`), `delay` 1, then 120 step
      events run at once so the smoke is already risen, then the begin step
    * begin step: when either surface was lost, both are freed and made again and 120
      step events run at once
    * step: when `delay` runs down to 0 (every step, back to 1): `surfB` cleared and
      `surfA` drawn onto it 1.025 wide, `(1 − 1.025) × 600 / 2 + random_range(−1, 1)`
      across and 5 up; `surfA` cleared and `surfB` drawn onto it; then `choose(3, 4)`
      puffs (`sCloud`) at `random_range(0, 600)` across, 50 above the
      bottom, in `make_color_hsv(random_range(0, 25), 220, 200)` (each also drawing
      `random_range(0, 360)`, which nothing uses). Every step it stands across at
      `room_width / 2 − (room_width / 2 − cameraCenterX) × 0.7 − 300` and is shown
    * end step: at the camera's top
    * draw: `surfA` at its place
    * destroy, room end and game end: its user event 15, the surfaces freed
  """

  alias Cauldron2D.GameMaker.{Colour, Data, Draw, Instance, Surfaces, World}
  alias Nidhox.Bout.Camera
  alias Nidhox.Gml

  @width 600
  @height 400
  @widen 1.025
  @rise -5
  @puff "sCloud"
  @warm_up 120
  @puff_lift 50
  @white {255, 255, 255}
  @follow 0.7
  @surfaces [:surfA, :surfB]

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_oFireClouds_Create_0", &start/3},
      {"gml_Object_oFireClouds_Step_1", &keep_surfaces/3},
      {"gml_Object_oFireClouds_Step_0", &burn/3},
      {"gml_Object_oFireClouds_Step_2",
       fn world, self, _other -> World.update(world, self, &%{&1 | y: Camera.top(world)}) end},
      {"gml_Object_oFireClouds_Draw_0", &draw/3},
      {"gml_Object_oFireClouds_Other_25", &free/3},
      {"gml_Object_oFireClouds_Destroy_0", &user_15/3},
      {"gml_Object_oFireClouds_Other_5", &user_15/3},
      {"gml_Object_oFireClouds_Other_3", &user_15/3}
    ]
  end

  defp start(world, self, _other) do
    {world, a} = clear_surface(world)
    {world, b} = clear_surface(world)

    world
    |> Gml.put(self, %{surfA: a, surfB: b, delay: 1})
    |> warm_up(self)
    |> World.perform(self, :step, 1)
  end

  defp warm_up(world, self),
    do:
      Enum.reduce(1..@warm_up, world, fn _step, world -> World.perform(world, self, :step, 0) end)

  defp clear_surface(world) do
    {world, surface} = Surfaces.create(world, @width, @height)
    {Surfaces.clear(world, surface, @white, 0), surface}
  end

  defp keep_surfaces(world, self, _other) do
    if Enum.all?(@surfaces, &Surfaces.exists?(world, Gml.var(world, self, &1, -1))),
      do: world,
      else: rebuild(world, self)
  end

  defp rebuild(world, self) do
    world = Enum.reduce(@surfaces, world, &free_surface(&2, Gml.var(&2, self, &1, -1)))
    {world, a} = clear_surface(world)
    {world, b} = clear_surface(world)

    world
    |> Gml.put(self, %{surfA: a, surfB: b})
    |> warm_up(self)
  end

  defp free_surface(world, surface),
    do: if(Surfaces.exists?(world, surface), do: Surfaces.free(world, surface), else: world)

  defp burn(world, self, _other) do
    delay = Gml.var(world, self, :delay) - 1
    world = Gml.put(world, self, %{delay: delay})
    world = if delay <= 0, do: world |> Gml.put(self, %{delay: 1}) |> rise(self), else: world
    room_middle = Camera.room_width(world) * 0.5
    x = room_middle - (room_middle - Camera.center_x(world)) * @follow - @width * 0.5
    World.update(world, self, &%{&1 | x: x, visible: true})
  end

  defp rise(world, self) do
    a = Gml.var(world, self, :surfA)
    b = Gml.var(world, self, :surfB)
    {jitter, world} = Gml.random_range(world, -1, 1)
    across = (1 - @widen) * @width * 0.5 + jitter

    world =
      world
      |> Surfaces.clear(b, @white, 0)
      |> Surfaces.draw(b, [
        Surfaces.item(world, a, {across, @rise}, scale: {@widen, 1}, blend: @white, alpha: 1.0)
      ])
      |> Surfaces.clear(a, @white, 0)
      |> then(&Surfaces.draw(&1, a, [Surfaces.item(&1, b, {0, 0})]))

    {count, world} = Gml.choose(world, [3, 4])
    {puffs, world} = Enum.map_reduce(1..count, world, fn _puff, world -> puff(world) end)
    Surfaces.draw(world, a, puffs)
  end

  defp puff(world) do
    {x, world} = Gml.random_range(world, 0, @width)
    {hue, world} = Gml.random_range(world, 0, 25)
    world = world |> Gml.random_range(0, 360) |> elem(1)
    puff = Data.index(world.data, :sprites, @puff)
    origin = World.sprite(world, puff).origin

    {%{
       picture: {:sprite, puff, 0},
       position: {x, @height - @puff_lift},
       origin: origin,
       blend: Colour.hsv(hue, 220, 200),
       alpha: 1.0
     }, world}
  end

  defp draw(world, self, _other) do
    %Instance{x: x, y: y} = World.fetch(world, self)
    surface = Gml.var(world, self, :surfA, -1)

    if Surfaces.exists?(world, surface),
      do: Draw.item(world, Surfaces.item(world, surface, {x, y})),
      else: world
  end

  defp user_15(world, self, _other), do: World.perform(world, self, :other, 25)

  defp free(world, self, _other),
    do: Enum.reduce(@surfaces, world, &free_surface(&2, Gml.var(&2, self, &1, -1)))
end
