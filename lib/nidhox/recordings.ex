defmodule Nidhox.Recordings do
  @moduledoc """
  The player's copy's recordings, by sound name: the sound stored in its data file, or
  else the `.ogg` of that name beside the data file, its name matched whatever its case
  and decoded through `TuningFork.Sample.Decode`.

      {:ok, %{rate: 44_100, channels: 2, pcm: pcm}} = Nidhox.Recordings.wave("sfxWind")

  `Nidhox.Assets.load/1` must have run first.
  """

  alias Cauldron2D.GameMaker.Wave
  alias Nidhox.Assets
  alias TuningFork.Sample.Decode

  @doc "The recording called `name`, decoded; `{:error, :missing}` when the copy has none."
  @spec wave(String.t()) ::
          {:ok, %{rate: pos_integer(), channels: pos_integer(), pcm: binary()}} | {:error, term()}
  def wave(name) do
    with {:ok, bytes} <- bytes(name), do: Wave.read(bytes)
  end

  defp bytes(name) do
    %{data: data, path: path} = Assets.get()

    case Enum.find(data.sounds, &(&1.name == name)) do
      %{audio: index} when is_integer(index) -> {:ok, Enum.at(data.audio, index)}
      _outside -> beside(path, name)
    end
  end

  defp beside(path, name) do
    folder = Path.dirname(path)
    wanted = String.downcase(name <> ".ogg")

    with {:ok, files} <- File.ls(folder),
         file when is_binary(file) <- Enum.find(files, &(String.downcase(&1) == wanted)),
         {:ok, wav} <- Decode.to_wav(Path.join(folder, file)) do
      File.read(wav)
    else
      _missing -> {:error, :missing}
    end
  end
end
