defmodule Mix.Tasks.Nidhox do
  @shortdoc "Play NidhOX in this terminal"

  @moduledoc """
  Play NidhOX in the terminal, from your own copy of the game's data file.

      mix nidhox
      mix nidhox --data path/to/data.win --area Wilds

  `--data` defaults to `config :nidhox, :data` (which `NIDHOX_DATA` sets), then the
  usual install places `Nidhox.Assets.candidates/0` lists. `--area` is the area fought
  across (`Cemetery`, `Castle`, `Mines`, `Sky`, `Wilds`; default `Cemetery`); `--room`
  picks the area of the room of that name.
  """

  use Mix.Task

  @switches [data: :string, area: :string, room: :string, name: :string]

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

  defp play(opts) do
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)

    Drafter.run(Cauldron2D.Drafter.Client,
      refresh_rate: "60fps",
      props: %{
        game: Nidhox.Client,
        username: Keyword.get(opts, :name, "fencer"),
        room: Keyword.get(opts, :room),
        area: Keyword.get(opts, :area)
      }
    )
  end
end
