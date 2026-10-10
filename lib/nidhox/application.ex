defmodule Nidhox.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    ledger =
      {Cauldron2D.Ledger,
       name: Nidhox.Ledger,
       path: Cauldron2D.Paths.data(:nidhox, "ledger.dets"),
       held: :idle,
       metrics: [wins: {:count, :won?}, bouts: &length/1]}

    Supervisor.start_link([ledger, Nidhox.TileLayerCache],
      strategy: :one_for_one,
      name: Nidhox.Supervisor
    )
  end
end
