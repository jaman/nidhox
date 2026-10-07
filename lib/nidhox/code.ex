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
  def objects, do: [Nidhox.Objects.Scenery]

  @impl true
  def handler(name), do: Map.get(handlers(), name)
end
