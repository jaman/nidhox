defmodule Nidhox.Bout.Spiral do
  @moduledoc """
  The wide view of the castle stairs rooms: while a `SpiralZone` exists, the room's first
  view is 373 × 233 pixels (the 320 × 200 screen times 7/6) and the camera's edges
  (`Nidhox.Bout.Camera`) lie inside it by margins (`viewMarginL`, `viewMarginR`,
  `viewMarginY`).

    * `active?/1`: whether the room has a `SpiralZone` (`spiralViewActive`)
    * `side_amount/2`: how far the view's left (`true`) or right (`false`) edge lies
      inside the zone's span (`stairsX0` to `stairsX1`), as a fraction of 128 pixels
      from 0 to 1 (`spiralSideAmount`); 0 without a zone
    * `margin_left/1`, `margin_right/1`: `(1 − side_amount) × 80/3` pixels while active,
      0 otherwise
    * `margin_y/1`: half of the view's height less that height divided by 7/6 while
      active, 0 otherwise
    * `widen/1`: the first view made 373 × 233 pixels shown in a 1194 × 746 port
      (`spiralViewApply`)

  A `SpiralZone` made sets the globals `stairsX0` and `stairsX1` to its left and right
  edges after applying the wide view.

  The wide view is shown through a warp (`System`'s draw end event):

    * `amounts/1`: `{left, right}` side amounts to hand to `warp/3`, `nil` without a
      zone
    * `warp/3`: a raster of the wide view remapped to the 320 × 200 screen. The middle
      half of the screen shows the world at 1:1. Beyond it the world is compressed
      more towards each side, by that side's amount, and darkened by 0.45 of the
      squared distance past the middle half
    * `columns/2`: the same remapping as one `{u, v_scale, shade}` per screen column,
      as `CauldronGPU.ColumnLayer` takes it

  The picture of a frame in the wide view is drawn at the zoom of the 320 × 200 screen,
  the view shown 373 × 233 pixels at that zoom, then warped to 320 × 200 at that zoom.
  """

  alias Cauldron2D.GameMaker.{Collide, Instance, World}
  alias Cauldron2D.Shape
  alias FrenchCurve.Raster
  alias Nidhox.Gml

  @object "SpiralZone"
  @scale 7 / 6
  @port_scale 3.2
  @screen {320, 200}
  @fade_width 128
  @side_margin 80 / 3
  @shade 0.45
  @half_width 160.0
  @full_width 320.0

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers, do: [{"gml_Object_#{@object}_Create_0", &start/3}]

  @doc "The screen the wide view is warped to, `{320, 200}` pixels."
  @spec screen_size() :: {pos_integer(), pos_integer()}
  def screen_size, do: @screen

  @doc "Whether the wide view is in use."
  @spec active?(World.t()) :: boolean()
  def active?(%World{} = world), do: Gml.exists?(world, @object)

  @doc "How far the view's left (`true`) or right (`false`) edge is inside the zone, from 0 to 1."
  @spec side_amount(World.t(), boolean()) :: float()
  def side_amount(%World{} = world, left?) do
    with true <- active?(world),
         x0 when x0 != nil <- World.global(world, :stairsX0),
         x1 when x1 != nil <- World.global(world, :stairsX1),
         [%{view: {x, _y, width, _height}} | _] <- world.views do
      edge = if left?, do: x, else: x + width
      Gml.clamp(min(edge - x0, x1 - edge) / @fade_width, 0, 1)
    else
      _inactive -> 0.0
    end
  end

  @doc "The margin inside the view's left edge (`viewMarginL`)."
  @spec margin_left(World.t()) :: number()
  def margin_left(%World{} = world), do: side_margin(world, true)

  @doc "The margin inside the view's right edge (`viewMarginR`)."
  @spec margin_right(World.t()) :: number()
  def margin_right(%World{} = world), do: side_margin(world, false)

  @doc "The margin inside the view's top and bottom edges (`viewMarginY`)."
  @spec margin_y(World.t()) :: number()
  def margin_y(%World{views: [%{view: {_x, _y, _width, height}} | _]} = world) do
    if active?(world), do: (height - height / @scale) * 0.5, else: 0
  end

  def margin_y(%World{}), do: 0

  @doc "The world with the first view 373 × 233 pixels in a 1194 × 746 port (`spiralViewApply`)."
  @spec widen(World.t()) :: World.t()
  def widen(
        %World{views: [%{view: {x, y, _width, _height}, port: {port_x, port_y, _, _}} | _]} =
          world
      ) do
    {screen_width, screen_height} = @screen
    width = Gml.round(screen_width * @scale)
    height = Gml.round(screen_height * @scale)
    port = {port_x, port_y, Gml.round(width * @port_scale), Gml.round(height * @port_scale)}

    views =
      List.update_at(world.views, 0, &%{&1 | view: {x, y, width, height}, port: port})

    %{world | views: views}
  end

  def widen(%World{} = world), do: world
  @doc "The `{left, right}` side amounts for `warp/3`, `nil` without a zone."
  @spec amounts(World.t()) :: {float(), float()} | nil
  def amounts(%World{} = world) do
    if active?(world), do: {side_amount(world, true), side_amount(world, false)}
  end

  @doc """
  The raster `source` (the whole wide view) remapped to `{width, height}` pixels for the
  screen, with the side amounts `{left, right}`.
  """
  @spec warp(Raster.t(), {pos_integer(), pos_integer()}, {number(), number()}) :: Raster.t()
  def warp(%Raster{} = source, {width, height}, amounts) do
    rgba = Raster.to_rgba_binary(source)
    columns = columns(width, amounts)

    pixels =
      for row <- 0..(height - 1), column <- columns, into: <<>> do
        screen_pixel(rgba, source, column, (row + 0.5) / height)
      end

    Raster.from_rgba(width, height, pixels)
  end

  @doc """
  For each of `width` screen columns, left to right, `{u, v_scale, shade}`: the wide
  view's horizontal position it shows (0 to 1), how its rows are stretched about the
  middle (a row `down` of the way shows the view at `0.5 + (down − 0.5) × v_scale`),
  and the factor its colours are darkened by.
  """
  @spec columns(pos_integer(), {number(), number()}) :: [{float(), float(), float()}]
  def columns(width, amounts),
    do: for(column <- 0..(width - 1), do: column((column + 0.5) / width, amounts))

  defp column(across, {left, right}) do
    across_screen = across * 2 - 1
    distance = abs(across_screen)
    amount = if across_screen < 0, do: left, else: right
    beyond = max(0.0, (distance - 0.5) * 2)

    reach =
      if distance <= 0.5,
        do: @half_width * distance,
        else: @half_width * (0.5 + 0.5 * (beyond + amount * beyond * beyond * beyond / 3))

    stretch = 1 + (@scale - 1) * beyond * beyond * amount
    u = 0.5 + sign(across_screen) * reach / (@full_width * @scale)
    {u, stretch / @scale, 1 - @shade * beyond * beyond * amount}
  end

  defp screen_pixel(rgba, source, {u, v_scale, shade}, down) do
    v = 0.5 + (down - 0.5) * v_scale

    if u < 0 or u > 1 or v < 0 or v > 1,
      do: <<0, 0, 0, 255>>,
      else: shaded(sample(rgba, source, u, v), shade)
  end

  defp sign(value) when value < 0, do: -1
  defp sign(_value), do: 1

  defp shaded({red, green, blue, alpha}, factor),
    do: <<round(red * factor), round(green * factor), round(blue * factor), round(alpha)>>

  defp sample(rgba, %Raster{width: width, height: height}, u, v) do
    x = u * width - 0.5
    y = v * height - 0.5
    left = floor(x)
    top = floor(y)
    across = x - left
    down = y - top

    [
      {texel(rgba, width, height, left, top), (1 - across) * (1 - down)},
      {texel(rgba, width, height, left + 1, top), across * (1 - down)},
      {texel(rgba, width, height, left, top + 1), (1 - across) * down},
      {texel(rgba, width, height, left + 1, top + 1), across * down}
    ]
    |> Enum.reduce({0.0, 0.0, 0.0, 0.0}, fn {{r, g, b, a}, weight}, {sr, sg, sb, sa} ->
      {sr + r * weight, sg + g * weight, sb + b * weight, sa + a * weight}
    end)
  end

  defp texel(rgba, width, height, x, y) do
    offset = (min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)) * 4
    <<_::binary-size(offset), red, green, blue, alpha, _::binary>> = rgba
    {red, green, blue, alpha}
  end

  defp side_margin(%World{} = world, left?) do
    if active?(world), do: (1 - side_amount(world, left?)) * @side_margin, else: 0
  end

  defp start(world, self, _other) do
    world = widen(world)

    case World.fetch(world, self) do
      %Instance{} = zone ->
        with %Shape{} = shape <- Collide.shape(world, zone, {zone.x, zone.y}),
             {left, _top, right, _bottom} <- Shape.bounds(shape) do
          world |> World.put_global(:stairsX0, left) |> World.put_global(:stairsX1, right)
        else
          _none -> world
        end

      nil ->
        world
    end
  end
end
