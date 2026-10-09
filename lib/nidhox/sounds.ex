defmodule Nidhox.Sounds do
  @moduledoc """
  The sound effects of the player's copy of the game, as `TuningFork` voices.

  An event the client plays is `{:recording, name}`, placed or not; `voice/1` gives the
  voice of the copy's recording `name`, `nil` for any other event or a sound the copy
  lacks. A sound is decoded the first time it is asked for and kept; `warm/0` decodes
  every sound of the data file ahead of play.
  """

  alias Nidhox.{Assets, Recordings}
  alias TuningFork.{Sample, Voice}

  @doc """
  Decode and keep every sound of the copy's data file, so none is decoded while the game
  plays. Run it in a process of its own; it takes as long as decoding the copy's sounds
  does.
  """
  @spec warm() :: :ok
  def warm do
    if Assets.loaded?(), do: Enum.each(Assets.get().data.sounds, &named(&1.name))
    :ok
  end

  @doc "The voice an event makes: `{:recording, name}` gives the copy's recording `name`, anything else `nil`."
  @spec voice(term()) :: Voice.t() | nil
  def voice({:recording, name}) when is_binary(name), do: named(name)
  def voice(_event), do: nil

  @doc "The voice of the copy's recording called `name` (`Nidhox.Recordings`), `nil` when it has none."
  @spec named(String.t()) :: Voice.t() | nil
  def named(name) do
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

      Voice.new(sample: sample, freq: 440.0, gain: 0.8)
    else
      _missing -> nil
    end
  end
end
