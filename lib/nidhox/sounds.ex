defmodule Nidhox.Sounds do
  @moduledoc """
  The sounds of the player's copy of the game, as `TuningFork` voices.

  An event the client plays is `{:recording, name}`, placed or not. For a sound effect,
  `voice/1` gives the voice of the copy's recording `name` at the volume its data file
  gives that sound (1 for one it does not list), decoded the first time it is asked for
  and kept; `warm/0` decodes every effect ahead of play. For music (`music_…`), which the
  world sends as keyed sounds with `music: true`, `recording/1` gives the recording in its
  own rate and channels, decoded when it is asked for and kept among the 8 asked for
  last, the one asked for longest ago let go; `voice/1` gives no music. Either is `nil`
  for any other event or a sound the copy lacks. The kept music is this server's table,
  started under NidhOX's supervisor.
  """

  use GenServer

  alias Nidhox.{Assets, Recordings}
  alias TuningFork.{Sample, Voice}

  @music "music_"
  @kept_music 8
  @table __MODULE__

  @doc "Start the owner of the kept music."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc """
  Decode and keep every sound effect of the copy's data file, so none is decoded while
  the game plays. Run it in a process of its own.
  """
  @spec warm() :: :ok
  def warm do
    if Assets.loaded?() do
      for %{name: name} <- Assets.get().data.sounds, not music?(name), do: named(name)
    end

    :ok
  end

  @doc "The voice an event makes: `{:recording, name}` gives the copy's sound effect `name`, anything else `nil`."
  @spec voice(term()) :: Voice.t() | nil
  def voice({:recording, name}) when is_binary(name), do: named(name)
  def voice(_event), do: nil

  @doc "The voice of the copy's sound effect called `name` (`Nidhox.Recordings`), `nil` when it has none or `name` is music."
  @spec named(String.t()) :: Voice.t() | nil
  def named(name) do
    if music?(name), do: nil, else: kept_effect(name)
  end

  @doc """
  The recording an event names, for `Cauldron2D.Audio`'s `:recordings`: `{:recording,
  name}` with `name` music gives `%{rate: rate, channels: channels, pcm: pcm}`, anything
  else `nil`.
  """
  @spec recording(term()) :: map() | nil
  def recording({:recording, name}) when is_binary(name) do
    if music?(name), do: kept_music(name)
  end

  def recording(_event), do: nil

  @impl GenServer
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end

  defp music?(name), do: String.starts_with?(name, @music)

  defp volume(name) do
    case Enum.find(Assets.get().data.sounds, &(&1.name == name)) do
      %{volume: volume} -> volume / 1
      nil -> 1.0
    end
  end

  defp kept_effect(name) do
    key = {__MODULE__, name}

    case :persistent_term.get(key, :unread) do
      :unread ->
        voice = decode(name)
        :persistent_term.put(key, voice)
        voice

      voice ->
        voice
    end
  end

  defp kept_music(name) do
    now = System.monotonic_time()

    case :ets.lookup(@table, name) do
      [{^name, wave, _used}] ->
        :ets.update_element(@table, name, {3, now})
        wave

      [] ->
        wave = wave(name)
        :ets.insert(@table, {name, wave, now})
        let_go_oldest()
        wave
    end
  end

  defp let_go_oldest do
    kept = :ets.tab2list(@table)

    kept
    |> Enum.sort_by(fn {_name, _wave, used} -> used end)
    |> Enum.take(max(length(kept) - @kept_music, 0))
    |> Enum.each(fn {name, _wave, _used} -> :ets.delete(@table, name) end)
  end

  defp wave(name) do
    with true <- Assets.loaded?(),
         {:ok, wave} <- Recordings.wave(name) do
      wave
    else
      _missing -> nil
    end
  end

  defp decode(name) do
    with true <- Assets.loaded?(),
         {:ok, wave} <- Recordings.wave(name) do
      sample =
        Sample.from_pcm(wave.pcm,
          rate: wave.rate,
          channels: wave.channels,
          root: 440.0,
          name: name
        )

      Voice.new(sample: sample, freq: 440.0, gain: volume(name))
    else
      _missing -> nil
    end
  end
end
