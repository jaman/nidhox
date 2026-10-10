defmodule Nidhox.Code do
  @moduledoc """
  The game's code, as `Cauldron2D.GameMaker.Code` asks for it: each compiled name the
  data file's objects and rooms use, answered by a function written for NidhOX.

  The functions come from the modules in `objects/0`. Each implements `handlers/0`,
  returning `{name, function}` pairs — the name as GameMaker's compiler gives it
  (`gml_Object_<object>_<Event>_<subtype>`, `gml_Room_<room>_Create`, …) and the
  function `(world, self, other) -> world`. A name no module answers for runs nothing.
  """

  @behaviour Cauldron2D.GameMaker.Code

  @key {__MODULE__, :handlers}

  @doc "Every handler, by compiled name, from `objects/0`."
  @spec handlers() :: %{String.t() => Cauldron2D.GameMaker.Code.handler()}
  def handlers do
    case :persistent_term.get(@key, nil) do
      nil ->
        handlers = objects() |> Enum.flat_map(& &1.handlers()) |> Map.new()
        :persistent_term.put(@key, handlers)
        handlers

      handlers ->
        handlers
    end
  end

  @doc "The modules whose `handlers/0` make up the game's code."
  @spec objects() :: [module()]
  def objects,
    do: [
      Nidhox.Objects.Scenery,
      Nidhox.Objects.Animals,
      Nidhox.Objects.Ambience,
      Nidhox.Objects.Doors,
      Nidhox.Objects.Chandelier,
      Nidhox.Objects.Background,
      Nidhox.Objects.Wind,
      Nidhox.Objects.Torches,
      Nidhox.Objects.Clouds,
      Nidhox.Objects.DefensiveBlock,
      Nidhox.Objects.DarkenClouds,
      Nidhox.Objects.Sun,
      Nidhox.Objects.LastScreenText,
      Nidhox.Objects.LayeredMusic,
      Nidhox.Objects.Waterfall,
      Nidhox.Objects.Mines,
      Nidhox.Objects.Worms,
      Nidhox.Objects.Smoke,
      Nidhox.Objects.Crowd,
      Nidhox.Objects.Glass,
      Nidhox.Objects.FireClouds,
      Nidhox.Objects.PlayerOutlines,
      Nidhox.Objects.Arcade,
      Nidhox.Objects.Challenge,
      Nidhox.Objects.MainMenu,
      Nidhox.Objects.InstanceCodes,
      Nidhox.Objects.Wilds,
      Nidhox.Objects.Grass,
      Nidhox.Objects.Water,
      Nidhox.Objects.Rocks,
      Nidhox.Objects.Particles,
      Nidhox.Objects.System,
      Nidhox.Objects.Ear,
      Nidhox.Objects.RoomCodes,
      Nidhox.Objects.Transition,
      Nidhox.Objects.Match,
      Nidhox.Objects.Brain,
      Nidhox.Objects.DialogBox,
      Nidhox.Objects.CheerControl,
      Nidhox.Objects.Tutorial,
      Nidhox.Objects.Arrow,
      Nidhox.Objects.SpawnArea,
      Nidhox.Objects.BloodSurface,
      Nidhox.Objects.Blocks,
      Nidhox.Objects.MinesCenterCamera,
      Nidhox.Objects.Nidhogg,
      Nidhox.Objects.NidhoggHead,
      Nidhox.Objects.MatchStats,
      Nidhox.Objects.HeldWeapon,
      Nidhox.Objects.DroppedWeapon,
      Nidhox.Objects.FlyingWeapon,
      Nidhox.Objects.PickupContainer,
      Nidhox.Objects.BloodDrop,
      Nidhox.Objects.Effects,
      Nidhox.Man.Physics,
      Nidhox.Man.Flesh,
      Nidhox.Man
    ]

  @impl true
  def handler(name), do: Map.get(handlers(), name)
end
