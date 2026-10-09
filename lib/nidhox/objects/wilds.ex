defmodule Nidhox.Objects.Wilds do
  @moduledoc """
  The wilds' living scenery, from the copy's sprites:

    * mistletoe and leaves (`Mistletoe`, and `LeavesBunch`, which is mistletoe): each
      starts on a frame of its own, chosen from its id, and sways through its frames at
      `@sway` a step
    * rain (`Rain`, a surface the copy keeps the code of compiled away): `@drops`
      `sRainDrop` streaks across the view, each falling `@fall` pixels a step and blown
      `@blow` to the side, coming round again, on a frame and at a place drawn from its
      number, at `@rain_alpha`
  """

  alias Cauldron2D.GameMaker.Draw
  alias Cauldron2D.GameMaker.World
  alias Nidhox.Assets

  @sway 0.1
  @drops 40
  @fall 7.0
  @blow -1.5
  @rain_alpha 0.55

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Mistletoe_Create_0", &sway/3},
      {"gml_Object_Rain_Draw_0", &rain/3}
    ]
  end

  defp sway(world, self, _other) do
    World.update(world, self, fn leaves ->
      frames = length(World.sprite(world, leaves.sprite_index).frames)
      %{leaves | image_index: :erlang.phash2(self, frames) / 1, image_speed: @sway}
    end)
  end

  defp rain(world, self, _other) do
    {view_x, view_y, view_width, view_height} = view(world)
    {drop, %{frames: frames, size: {_width, length}}} = Assets.sprite!("sRainDrop")
    depth = World.fetch(world, self).depth
    across = view_width + abs(@blow) * (view_height + length) / @fall

    for number <- 1..@drops, reduce: world do
      world ->
        start_x = :erlang.phash2({number, :x}, round(across))
        start_y = :erlang.phash2({number, :y}, view_height + length)
        fallen = Integer.mod(round(start_y + world.steps * @fall), view_height + length) - length
        blown = Integer.mod(round(start_x + world.steps * @blow), round(across))

        Draw.item(world, %{
          picture: {:sprite, drop, :erlang.phash2({number, :frame}, length(frames))},
          position: {view_x + blown, view_y + fallen},
          alpha: @rain_alpha,
          depth: depth
        })
    end
  end

  defp view(%World{views: [%{view: rectangle} | _]}), do: rectangle
  defp view(%World{}), do: {0, 0, 320, 200}
end
