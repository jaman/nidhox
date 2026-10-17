defmodule Nidhox.Objects.RoomCodes do
  @moduledoc """
  The rooms' creation code: each fighting room names where it stands in its area
  (`global.roomCode`), and most also hand out swords (`global.swords` 1); the tutorial
  takes them away (`global.swords` 0). The cemetery's rooms also turn their birds black
  (`with (Bird) image_blend = 0`); the sky's centre sets its first background's alpha to
  0.1 (`__background_set(14, 0, 0.1)`). The left B and right B rooms of the castle,
  the stairs castle, the cemetery and the wilds make a `LastScreenText` ("Final Screen");
  the mines' and the sky's last rooms place theirs themselves.

  | code | room |
  | --- | --- |
  | 1 | centre (also the castle's B centre, the online lobby, the pre-match, the controls and challenge rooms, the tutorial, and the sky's right B) |
  | 2, 3, 11 | left A, left B, left C |
  | 4 | left end |
  | 5, 6, 9 | right A, right B, right C |
  | 7 | right end |
  | 8 | sudden death |

  `room_code/1` reads the code (`getRoomCode`), `swords?/1` the swords switch.
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.{Backgrounds, Gml}

  @rooms %{
    "rCaslteBRightA" => {5, 1},
    "rCaslteWithYardSketch" => {1, 1},
    "rCastleBCenter" => {1, 1},
    "rCastleCenter" => {1, 1},
    "rCastleLeftA" => {2, nil},
    "rCastleLeftB" => {3, nil},
    "rCastleLeftEnd" => {4, nil},
    "rCastleRightA" => {5, nil},
    "rCastleRightB" => {6, nil},
    "rCastleRightEnd" => {7, nil},
    "rCastleSuddenDeath" => {8, 1},
    "rCastleStairs" => {5, nil},
    "rCastleStairsCenter" => {1, 1},
    "rCastleStairsLeftA" => {2, nil},
    "rCastleStairsLeftB" => {3, nil},
    "rCastleStairsLeftEnd" => {4, nil},
    "rCastleStairsRightA" => {5, nil},
    "rCastleStairsRightB" => {6, nil},
    "rCastleStairsRightEnd" => {7, nil},
    "rCastleStairsSuddenDeath" => {8, 1},
    "rCemeteryCenter" => {1, 1},
    "rCemeteryLeftA" => {2, nil},
    "rCemeteryLeftB" => {3, nil},
    "rCemeteryLeftEnd" => {4, 1},
    "rCemeteryRightA" => {5, nil},
    "rCemeteryRightB" => {6, nil},
    "rCemeteryRightEnd" => {7, 1},
    "rCemeterySuddenDeath" => {8, 1},
    "rChallengeMode" => {1, 1},
    "rControlsRoom" => {1, 1},
    "rMinesCenter" => {1, 1},
    "rMinesLeftA" => {2, 1},
    "rMinesLeftB" => {3, 1},
    "rMinesLeftC" => {11, 1},
    "rMinesLeftEnd" => {4, nil},
    "rMinesRightA" => {5, 1},
    "rMinesRightB" => {6, 1},
    "rMinesRightC" => {9, 1},
    "rMinesRightEnd" => {7, nil},
    "rMinesSuddenDeath" => {8, 1},
    "rOnlineLobby" => {1, 1},
    "rPreMatch" => {1, 1},
    "rSkyCenter" => {1, 1},
    "rSkyLeftA" => {2, 1},
    "rSkyLeftB" => {3, 1},
    "rSkyLeftEnd" => {4, nil},
    "rSkyRightA" => {5, 1},
    "rSkyRightB" => {1, 1},
    "rSkyRightEnd" => {7, nil},
    "rSkySuddenDeath" => {8, 1},
    "rTutorial" => {1, 0},
    "rWildsCenter" => {1, 1},
    "rWildsLeftA" => {2, nil},
    "rWildsLeftB" => {3, nil},
    "rWildsLeftEnd" => {4, nil},
    "rWildsRightA" => {5, nil},
    "rWildsRightB" => {6, nil},
    "rWildsRightEnd" => {7, nil},
    "rWildsSuddenDeath" => {8, 1}
  }

  @final_screens ~w(rCastleLeftB rCastleRightB rCastleStairsLeftB rCastleStairsRightB rCemeteryLeftB rCemeteryRightB rWildsLeftB rWildsRightB)

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    for {room, {code, swords}} <- @rooms do
      {"gml_Room_#{room}_Create", fn world, _self, _other -> enter(world, room, code, swords) end}
    end
  end

  @doc "The room's code (`getRoomCode`), 0 before any room gave one."
  @spec room_code(World.t()) :: number()
  def room_code(%World{} = world), do: World.global(world, :roomCode, 0)

  @doc "Whether the rooms hand out swords (`global.swords`)."
  @spec swords?(World.t()) :: boolean()
  def swords?(%World{} = world), do: Gml.truthy?(World.global(world, :swords, 0))

  defp enter(world, room, code, swords) do
    world
    |> World.put_global(:roomCode, code)
    |> then(&if(swords == nil, do: &1, else: World.put_global(&1, :swords, swords)))
    |> blacken_birds(room)
    |> fade_sky(room)
    |> final_screen(room)
  end

  defp final_screen(world, room) when room in @final_screens,
    do: world |> World.create(World.object_index(world, "LastScreenText"), {0, 0}) |> elem(0)

  defp final_screen(world, _room), do: world

  defp fade_sky(world, "rSkyCenter"), do: Backgrounds.set(world, 14, 0, 0.1)
  defp fade_sky(world, _room), do: world

  defp blacken_birds(world, "rCemetery" <> _part) do
    world
    |> Gml.all("Bird")
    |> Enum.reduce(world, &World.update(&2, &1, fn bird -> %{bird | image_blend: {0, 0, 0}} end))
  end

  defp blacken_birds(world, _room), do: world
end
