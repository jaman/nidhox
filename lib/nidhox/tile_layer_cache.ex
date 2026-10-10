defmodule Nidhox.TileLayerCache do
  @moduledoc """
  The tile layer pictures (`Cauldron2D.GameMaker.TileLayers`) the client has drawn, kept
  for the room they belong to.

  `fetch/2` gives the picture for a key, drawing it with the given function the first
  time; asking for a layer of another room lets go of every kept layer of the room before.
  Any process may fetch; the table belongs to this server, started under NidhOX's
  supervisor.
  """

  use GenServer

  alias Cauldron2D.GameMaker.TileLayers
  alias FrenchCurve.Raster

  @table __MODULE__

  @doc "Start the cache's owner."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "The picture `key` names, from the cache or made by `draw` and kept."
  @spec fetch(TileLayers.key(), (-> Raster.t() | nil)) :: Raster.t() | nil
  def fetch({:tile_layer, room, _layer, _blend} = key, draw) do
    case :ets.lookup(@table, key) do
      [{^key, picture}] ->
        picture

      [] ->
        picture = draw.()

        :ets.select_delete(@table, [
          {{{:tile_layer, :"$1", :_, :_}, :_}, [{:"=/=", :"$1", room}], [true]}
        ])

        :ets.insert(@table, {key, picture})
        picture
    end
  end

  @impl GenServer
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end
end
