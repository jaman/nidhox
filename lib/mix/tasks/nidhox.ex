defmodule Mix.Tasks.Nidhox do
  @shortdoc "Play NidhOX in this terminal"

  @moduledoc """
  Play NidhOX in the terminal, from your own copy of the game's data file.

      mix nidhox
      mix nidhox --data path/to/data.win --area Wilds

  `--data` defaults to `config :nidhox, :data` (which `NIDHOX_DATA` sets), then the
  usual install places `Nidhox.Assets.candidates/0` lists. `--area` is the area fought
  across (`Cemetery`, `Castle`, `Mines`, `Sky`, `Wilds`; default `Cemetery`); `--room`
  picks the area of the room of that name. `--name` is the player's name, by default
  `fencer@<this machine's host name>`. `--port` is the port ONLINE VERSUS's host listens on
  for the joining machine, for a host that must open it to the internet; any free port
  without it. Each bout's result is kept in NidhOX's ledger
  (`Cauldron2D.Paths.data(:nidhox, "ledger.dets")`).
  """

  use Mix.Task
  alias Nidhox.Sounds

  @switches [data: :string, area: :string, room: :string, name: :string, port: :integer]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: @switches)
    Mix.Task.run("app.start")

    case Nidhox.Assets.find(Keyword.get(opts, :data)) do
      nil ->
        Mix.raise("give the game's data file: mix nidhox --data path/to/data.win")

      path ->
        case Nidhox.Assets.load(path) do
          {:ok, _assets} -> play(opts)
          {:error, reason} -> Mix.raise("could not read #{path}: #{inspect(reason)}")
        end
    end
  end

  defp default_name do
    {:ok, host} = :inet.gethostname()
    "fencer@#{host}"
  end

  defp play(opts) do
    area = Keyword.get(opts, :area) || Nidhox.Bout.area(Keyword.get(opts, :room)) || "Cemetery"

    :ok =
      Cauldron2D.Worlds.register(Nidhox.Client.world_id(),
        game: Nidhox.Game,
        game_opts: [area: area, port: Keyword.get(opts, :port)],
        hz: 60,
        name: "NidhOX",
        children: fn %{world: world} ->
          [{Cauldron2D.Ledger.Recorder, world: world, label: "NidhOX", ledger: Nidhox.Ledger}]
        end
      )

    Task.start(&Sounds.warm/0)
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)

    Drafter.run(Cauldron2D.Drafter.Client,
      refresh_rate: "60fps",
      props: %{
        game: Nidhox.Client,
        username: Keyword.get_lazy(opts, :name, &default_name/0)
      }
    )
  end
end
