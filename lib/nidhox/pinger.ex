defmodule Nidhox.Pinger do
  @moduledoc """
  Round trips to the lobbies heard while searching, measured away from the game's
  steps: `want/2` names the `{address, port}` listeners to measure, and each is pinged
  with `Cauldron2D.Link.ping/3` at most once every five seconds; `results/1` gives the
  latest round trip of each in milliseconds, or `nil` while unknown or unreachable.

      {:ok, pinger} = Nidhox.Pinger.start_link()
      Nidhox.Pinger.want(pinger, [{{192, 168, 1, 5}, 40123}])
      Nidhox.Pinger.results(pinger)
  """

  use GenServer

  alias Cauldron2D.Link

  @again_ms 5_000
  @timeout_ms 2_000

  @type target :: {:inet.ip_address(), :inet.port_number()}

  @doc "Start a pinger with nothing to measure."
  @spec start_link() :: GenServer.on_start()
  def start_link, do: GenServer.start_link(__MODULE__, nil)

  @doc "Measure `targets` from now on, and forget any other."
  @spec want(pid(), [target()]) :: :ok
  def want(pinger, targets), do: GenServer.cast(pinger, {:want, targets})

  @doc "The latest round trip to each target wanted, in milliseconds, `nil` when unknown."
  @spec results(pid()) :: %{target() => number() | nil}
  def results(pinger), do: GenServer.call(pinger, :results)

  @doc "Stop measuring."
  @spec stop(pid()) :: :ok
  def stop(pinger), do: GenServer.stop(pinger, :normal)

  @impl GenServer
  def init(nil), do: {:ok, %{results: %{}, measured_at: %{}, running: MapSet.new()}}

  @impl GenServer
  def handle_cast({:want, targets}, state) do
    wanted = MapSet.new(targets)
    now = System.monotonic_time(:millisecond)

    state = %{
      state
      | results: Map.take(state.results, targets),
        measured_at: Map.take(state.measured_at, targets)
    }

    due =
      Enum.filter(wanted, fn target ->
        not MapSet.member?(state.running, target) and
          now - Map.get(state.measured_at, target, -@again_ms) >= @again_ms
      end)

    pinger = self()

    Enum.each(due, fn {address, port} = target ->
      Task.start(fn -> send(pinger, {:pinged, target, ping(address, port)}) end)
    end)

    {:noreply, %{state | running: Enum.into(due, state.running)}}
  end

  @impl GenServer
  def handle_call(:results, _from, state), do: {:reply, state.results, state}

  @impl GenServer
  def handle_info({:pinged, target, result}, state) do
    {:noreply,
     %{
       state
       | results: Map.put(state.results, target, result),
         measured_at: Map.put(state.measured_at, target, System.monotonic_time(:millisecond)),
         running: MapSet.delete(state.running, target)
     }}
  end

  defp ping(address, port) do
    case Link.ping(address, port, @timeout_ms) do
      {:ok, ms} -> ms
      {:error, _reason} -> nil
    end
  end
end
