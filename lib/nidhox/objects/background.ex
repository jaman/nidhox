defmodule Nidhox.Objects.Background do
  @moduledoc """
  The moving paper-like backdrop of every screen (`BackgroundObject`), made once when
  the game starts and kept across rooms (`create/1`).

  It keeps `@squares` surfaces, each 320 × 200 and first painted with background 357
  (`bLevelSelect`) at its corner, and a final surface the same size:

    * begin step: any missing surface is made again; `timer` counts down
    * draw: when `timer` has run out it is set to 1, 2 or 3 again and every square `i`
      has square `(i + 1) mod @squares` drawn onto it `@copies` times, each at a
      random place within 320 × 200, scaled by a random amount up to 1.3 each way,
      turned by a random angle up to 360°, drawn over one time in ten, else added two
      times in three and subtracted one;
      then the final surface is cleared, every square is added onto it at alpha
      `@square_alpha`, and the final surface is drawn at the view's top-left corner at
      alpha `@final_alpha`

  The random draws come from the world's step, the square and the copy, so a world
  stepped the same way draws the same backdrop.
  """

  alias Cauldron2D.GameMaker.{Draw, Surfaces, World}

  @object "BackgroundObject"
  @squares 3
  @copies 10
  @width 320
  @height 200
  @painting 357
  @square_alpha 0.3
  @final_alpha 0.15
  @white {255, 255, 255}

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_BackgroundObject_Create_0", &start/3},
      {"gml_Object_BackgroundObject_Step_1", &begin_step/3},
      {"gml_Object_BackgroundObject_Draw_0", &draw/3}
    ]
  end

  @doc "`world` with the backdrop made, as the game's start makes it."
  @spec create(World.t()) :: World.t()
  def create(%World{} = world) do
    case World.object_index(world, @object) do
      nil -> world
      object -> world |> World.create(object, {0, 0}) |> elem(0)
    end
  end

  defp start(world, self, _other),
    do:
      put_vars(world, self, %{
        squares: List.duplicate(nil, @squares),
        final: nil,
        timer: choice(world, self, :timer)
      })

  defp begin_step(world, self, _other) do
    vars = World.fetch(world, self).vars
    {world, final} = ensure(world, vars.final, &Function.identity/1)
    {world, squares} = Enum.map_reduce(vars.squares, world, &ensure_square/2) |> swap()
    put_vars(world, self, %{vars | final: final, squares: squares, timer: vars.timer - 1})
  end

  defp swap({squares, world}), do: {world, squares}

  defp ensure_square(id, world) do
    {world, id} = ensure(world, id, &paint/1)
    {id, world}
  end

  defp ensure(world, id, fill) do
    if id != nil and Surfaces.exists?(world, id) do
      {world, id}
    else
      {world, id} = Surfaces.create(world, @width, @height)
      {fill.({world, id}) |> elem(0), id}
    end
  end

  defp paint({world, id}) do
    painting = %{picture: {:sprite, @painting, 0}, position: {0, 0}, origin: {0, 0}}
    {Surfaces.draw(world, id, [painting]), id}
  end

  defp draw(world, self, _other) do
    vars = World.fetch(world, self).vars
    if ready?(world, vars), do: draw_ready(world, self, vars), else: world
  end

  defp ready?(world, %{final: final, squares: squares}),
    do: Enum.all?([final | squares], &Surfaces.exists?(world, &1))

  defp draw_ready(world, self, vars) do
    {world, vars} = reseed(world, self, vars)

    world
    |> put_vars(self, vars)
    |> compose(vars)
    |> Draw.item(
      Surfaces.item(world, vars.final, view_corner(world), alpha: @final_alpha, blend: @white)
    )
  end

  defp reseed(world, self, %{timer: timer} = vars) when timer <= 0 do
    world =
      Enum.reduce(0..(@squares - 1), world, fn index, world ->
        source = Enum.at(vars.squares, rem(index + 1, @squares))
        copies = for copy <- 1..@copies, do: copy(world, source, index, copy)
        Surfaces.draw(world, Enum.at(vars.squares, index), copies)
      end)

    {world, %{vars | timer: choice(world, self, :timer)}}
  end

  defp reseed(world, _self, vars), do: {world, vars}

  defp copy(world, source, index, copy) do
    random = &random(world, {index, copy, &1}, &2)

    Surfaces.item(world, source, {random.(:x, @width), random.(:y, @height)},
      scale: {random.(:xscale, 1.3), random.(:yscale, 1.3)},
      angle: random.(:angle, 360),
      mode: mode(random.(:normal, 100), random.(:choice, 3)),
      blend: @white
    )
  end

  defp mode(roll, _choice) when roll < 10, do: :over
  defp mode(_roll, choice) when choice < 2, do: :add
  defp mode(_roll, _choice), do: :subtract

  defp compose(world, %{final: final, squares: squares}) do
    world = Surfaces.clear(world, final, {0, 0, 0}, 0)

    layers =
      for square <- squares,
          do: Surfaces.item(world, square, {0, 0}, alpha: @square_alpha, mode: :add, blend: @white)

    Surfaces.draw(world, final, layers)
  end

  defp view_corner(%World{views: [%{view: {x, y, _width, _height}} | _]}), do: {x, y}
  defp view_corner(_world), do: {0, 0}

  defp choice(world, self, key), do: 1 + :erlang.phash2({world.steps, self, key}, 3)

  defp random(world, key, limit),
    do: :erlang.phash2({world.steps, key}, 1_000_000) / 1_000_000 * limit

  defp put_vars(world, self, vars),
    do: World.update(world, self, &%{&1 | vars: Map.merge(&1.vars, vars)})
end
