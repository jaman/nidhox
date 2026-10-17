defmodule Nidhox.Objects.InstanceCodes do
  @moduledoc """
  The creation code of the instances the rooms place, run after each one's create
  (`gml_RoomCC_<room>_<n>_Create`, the `n`th instance with code in the room):

    * the wilds' rain: `intensity` 0.05 in the A rooms, 0.2 in the B rooms
    * the wilds' and the sky's parallax references: `backgroundIndex` 0 or 1, and in
      `rSkyRightA` `depth` 300 and 200
    * a pedestal in `rWildsRightB`: `depth` 200
    * the wind surface: `type` `"swirly"` in `rSkyLeftA` and `rSkyRightA`;
      `image_alpha` 0.5 in `rCemeteryCenter`, 0.1 in `rMultiMenu`
    * the smasher in `rMinesCenter`: 16 pixels lower
    * the controls room's title: blended `{255, 160, 64}` (4235519) and its `text` "player 2"
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.Gml

  @vars [
    {"rWildsLeftA_0", %{intensity: 0.05}},
    {"rWildsRightA_0", %{intensity: 0.05}},
    {"rWildsLeftB_0", %{intensity: 0.2}},
    {"rWildsRightB_0", %{intensity: 0.2}},
    {"rWildsLeftA_1", %{backgroundIndex: 0}},
    {"rWildsLeftB_1", %{backgroundIndex: 0}},
    {"rWildsRightA_1", %{backgroundIndex: 0}},
    {"rWildsRightB_2", %{backgroundIndex: 0}},
    {"rWildsRightEnd_0", %{backgroundIndex: 0}},
    {"rWildsRightEnd_1", %{backgroundIndex: 0}},
    {"rWildsLeftA_2", %{backgroundIndex: 1}},
    {"rWildsLeftB_2", %{backgroundIndex: 1}},
    {"rWildsRightA_2", %{backgroundIndex: 1}},
    {"rWildsRightB_3", %{backgroundIndex: 1}},
    {"rSkyRightA_0", %{backgroundIndex: 0}},
    {"rSkyRightA_1", %{backgroundIndex: 1}},
    {"rSkyLeftA_0", %{type: "swirly"}},
    {"rSkyRightA_2", %{type: "swirly"}},
    {"rControlsRoom_0", %{text: "player 2"}}
  ]

  @fields [
    {"rSkyRightA_0", %{depth: 300}},
    {"rSkyRightA_1", %{depth: 200}},
    {"rWildsRightB_1", %{depth: 200}},
    {"rCemeteryCenter_0", %{image_alpha: 0.5}},
    {"rMultiMenu_0", %{image_alpha: 0.1}},
    {"rControlsRoom_0", %{image_blend: {255, 160, 64}}}
  ]

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    names = Enum.map(@vars ++ @fields, &elem(&1, 0)) ++ ["rMinesCenter_0"]

    Enum.map(
      Enum.uniq(names),
      &{"gml_RoomCC_#{&1}_Create", fn world, self, _other -> run(world, self, &1) end}
    )
  end

  defp run(world, self, "rMinesCenter_0"), do: World.update(world, self, &%{&1 | y: &1.y + 16})

  defp run(world, self, code) do
    vars = for {^code, values} <- @vars, reduce: %{}, do: (acc -> Map.merge(acc, values))
    fields = for {^code, values} <- @fields, reduce: %{}, do: (acc -> Map.merge(acc, values))

    world
    |> Gml.put(self, vars)
    |> World.update(self, &struct(&1, fields))
  end
end
