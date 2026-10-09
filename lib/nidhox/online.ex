defmodule Nidhox.Online do
  @moduledoc """
  ONLINE VERSUS's work outside the game's state, over `Cauldron2D.Distribution`:
  hosting, hearing hosts on the local network, and joining one. `Nidhox.Flow` lists
  what it wants done in the state's `effects`; `Nidhox.Game` calls `perform/1` after
  each step and `pending/1` before the next.

  The state's `online` is `new/1`'s map:

    * `host` — `Cauldron2D.Distribution.host/2`'s host while this machine hosts, else
      `nil`
    * `owner` — the player whose client chose to host or join
    * `listener` — the `Cauldron2D.Beacon.Listener` while hosts are being looked for
    * `found` — the hosts heard, each `%{host, node}`, refreshed every `@listen_every`
      steps while looking
    * `joining` — `{address, code, side}` to join at the start of the next step
    * `status` — a line to show the players, or `nil`
    * `port` — the port a host listens on for joining nodes, `nil` for any free one

  Effects:

    * `:host` — host as `@name`, calling on the network as `@game`
    * `:unhost` — stop hosting
    * `:listen`, `:unlisten` — start and stop looking for hosts
    * `:prefill_address` — the state's `entry` started over as this machine's address
      up to its last dot, the part a host on the same network shares
    * `{:join, address, code, side}` — join the host at `address` with `code` at the
      start of the next step, the status "connecting.." until then; once joined, the
      client of the player on `side` is asked to enter the host's world
      (`{:enter, %{source: {:node, node}}}`), and when the host cannot be reached the
      status says so
  """

  alias Cauldron2D.Beacon.Listener
  alias Cauldron2D.Distribution
  alias Nidhox.Flow
  alias Nidhox.Screen.Entry

  @name "nidhox"
  @game "NidhOX"
  @listen_every 30

  @type t :: %{
          host: Distribution.host() | nil,
          owner: term(),
          listener: pid() | nil,
          found: [%{host: String.t(), node: node()}],
          joining: {String.t(), String.t(), 1 | 2} | nil,
          status: String.t() | nil,
          port: pos_integer() | nil
        }

  @doc "No hosting, looking or joining; a host listens on `port`, `nil` for any free port."
  @spec new(pos_integer() | nil) :: t()
  def new(port \\ nil),
    do: %{host: nil, owner: nil, listener: nil, found: [], joining: nil, status: nil, port: port}

  @doc "The name a host's node and a joining node's take: `<name>@<address>`."
  @spec name() :: String.t()
  def name, do: @name

  @doc "`state` with its `effects` carried out and emptied, and the hosts heard refreshed."
  @spec perform(map()) :: map()
  def perform(%{effects: effects} = state) do
    effects
    |> Enum.reverse()
    |> Enum.reduce(%{state | effects: []}, &effect/2)
    |> refresh()
  end

  @doc "`state` after joining the host its `online.joining` names, if any."
  @spec pending(map()) :: map()
  def pending(%{online: %{joining: nil}} = state), do: state

  def pending(%{online: %{joining: {address, code, side}} = online} = state) do
    state = %{state | online: %{online | joining: nil}}

    case Distribution.join(@name, address, code) do
      {:ok, node} ->
        state
        |> Flow.ask(side, {:enter, %{source: {:node, node}}})
        |> put_status("connected")

      {:error, _reason} ->
        put_status(state, "could not connect")
    end
  end

  defp effect(:host, %{online: %{host: nil} = online} = state) do
    case Distribution.host(@name, game: @game, port: online.port) do
      {:ok, host} -> %{state | online: %{online | host: host, status: nil}}
      {:error, reason} -> put_status(state, "could not host: #{inspect(reason)}")
    end
  end

  defp effect(:host, state), do: state

  defp effect(:unhost, %{online: %{host: nil}} = state), do: state

  defp effect(:unhost, %{online: %{host: host} = online} = state) do
    Distribution.stop(host)
    %{state | online: %{online | host: nil}}
  end

  defp effect(:listen, %{online: %{listener: nil} = online} = state) do
    {:ok, listener} = Listener.start_link(game: @game, name: nil)
    %{state | online: %{online | listener: listener, found: []}}
  end

  defp effect(:listen, state), do: state

  defp effect(:unlisten, %{online: %{listener: nil}} = state), do: state

  defp effect(:unlisten, %{online: %{listener: listener} = online} = state) do
    GenServer.stop(listener)
    %{state | online: %{online | listener: nil, found: []}}
  end

  defp effect(:prefill_address, %{entry: %Entry{} = entry} = state) do
    case Distribution.address() do
      {:ok, address} ->
        prefix = address |> String.split(".") |> Enum.drop(-1) |> Enum.map_join(&(&1 <> "."))
        %{state | entry: Entry.new(entry.label, entry.alphabet, entry.longest, prefix)}

      {:error, _reason} ->
        state
    end
  end

  defp effect({:join, address, code, side}, %{online: online} = state),
    do: %{state | online: %{online | joining: {address, code, side}, status: "connecting.."}}

  defp refresh(%{online: %{listener: listener} = online, steps: steps} = state)
       when listener != nil and rem(steps, @listen_every) == 0 do
    found =
      for %{host: host, node: node} <- Listener.found(listener),
          node != nil,
          do: %{host: host, node: node}

    %{state | online: %{online | found: found}}
  end

  defp refresh(state), do: state

  defp put_status(%{online: online} = state, status),
    do: %{state | online: %{online | status: status}}
end
