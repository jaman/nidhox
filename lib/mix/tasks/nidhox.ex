defmodule Mix.Tasks.Nidhox do
  @shortdoc "Play NidhOX in this terminal"

  @moduledoc """
  Play NidhOX in the terminal, from your own copy of the game's data file.

      mix nidhox
      mix nidhox --data path/to/data.win --area Wilds

  `--data` defaults to `config :nidhox, :data`: `NIDHOX_DATA`, else the first of the
  game's usual installs under the home directory (`config/runtime.exs`). `--area` is the area fought
  across (`Cemetery`, `Castle`, `Mines`, `Sky`, `Wilds`; default `Cemetery`); `--room`
  picks the area of the room of that name. `--name` is the player's name, by default
  `fencer`. `--port` is the port ONLINE VERSUS's host listens on
  for the joining machine, for a host that must open it to the internet; any free port
  without it. `--ssh-port` (or `NIDHOX_SSH_PORT`) is the port HOST OVER SSH offers to
  serve on; without it, any free port. `--picture` (or `NIDHOX_PICTURE`) is how the
  picture reaches a terminal that keeps images, for every player including those over
  ssh, as `Cauldron2D.Drafter.Client.Picture` reads it: any of `native`, `native:N`,
  `size:WxH`, `png` and `swap`, comma separated, or `none`; default `native:2,png,swap`.
  `--mute` (or `CAULDRON_MUTE=1`) plays no sound on this machine. Each bout's result is kept in NidhOX's ledger
  (`Cauldron2D.Paths.data(:nidhox, "ledger.dets")`). Notices, warnings and errors — each ssh
  player's session starting and ending, and a crashed one — go to `Cauldron2D.Paths.data(:nidhox, "nidhox.log")`.
  Quitting stops the VM in order,
  so a player connected over ssh is disconnected with their terminal restored.
  """

  use Mix.Task
  alias Cauldron2D.Drafter.Client.Picture
  alias Nidhox.Sounds

  @switches [
    data: :string,
    area: :string,
    room: :string,
    name: :string,
    port: :integer,
    ssh_port: :integer,
    picture: :string,
    mute: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: @switches)
    Mix.Task.run("app.start")

    configure_picture(opts[:picture] || System.get_env("NIDHOX_PICTURE"))
    if opts[:mute], do: Application.put_env(:cauldron_2d_drafter, :mute, true)

    case Nidhox.Assets.find(Keyword.get(opts, :data)) do
      nil ->
        Mix.raise("give the game's data file: mix nidhox --data path/to/data.win")

      path ->
        case Nidhox.Assets.load(path) do
          {:ok, _assets} -> play(opts)
          {:error, reason} -> Mix.raise(failure(path, reason))
        end
    end
  end

  defp failure(_path, {:no_executable, dir}),
    do:
      "#{dir} has no Nidhogg.exe: the Windows build's data.win is read with the Nidhogg.exe installed beside it"

  defp failure(_path, {:unreadable, path, reason}),
    do: "could not read #{path}: #{inspect(reason)}"

  defp failure(_path, reason) when reason in [:not_windows_executable, :no_depth_table],
    do: "this Nidhogg.exe is not a build NidhOX reads the object depths of"

  defp failure(_path, {:unknown_objects, names}),
    do:
      "Nidhogg.exe and data.win are from different builds: the executable names objects the data file lacks (#{Enum.join(names, ", ")})"

  defp failure(path, reason), do: "could not read #{path}: #{inspect(reason)}"

  defp configure_picture(nil), do: :ok

  defp configure_picture(options) do
    case Picture.parse(options) do
      {:ok, options} -> Application.put_env(:cauldron_2d_drafter, :picture, options)
      {:error, message} -> Mix.raise("--picture: " <> message)
    end
  end

  defp play(opts) do
    area = Keyword.get(opts, :area) || Nidhox.Bout.area(Keyword.get(opts, :room)) || "Cemetery"

    :ok =
      Cauldron2D.Worlds.register(Nidhox.Client.world_id(),
        game: Nidhox.Game,
        game_opts: [
          area: area,
          port: Keyword.get(opts, :port),
          ssh_port: Keyword.get(opts, :ssh_port)
        ],
        hz: 60,
        name: "NidhOX",
        children: fn %{world: world} ->
          [{Cauldron2D.Ledger.Recorder, world: world, label: "NidhOX", ledger: Nidhox.Ledger}]
        end
      )

    Task.start(&Sounds.warm/0)
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)

    log = Cauldron2D.Paths.data(:nidhox, "nidhox.log")
    File.mkdir_p!(Path.dirname(log))

    Drafter.run(Cauldron2D.Drafter.Client,
      refresh_rate: "60fps",
      log: log,
      level: :notice,
      props: %{
        game: Nidhox.Client,
        username: Keyword.get(opts, :name, "fencer")
      }
    )

    System.stop()
    Process.sleep(:infinity)
  end
end
