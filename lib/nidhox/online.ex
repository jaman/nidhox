defmodule Nidhox.Online do
  @moduledoc """
  ONLINE's work outside the game's state: hosting a lobby, hearing the lobbies on the
  local network, measuring the round trip to each, and serving the game over ssh.
  `Nidhox.Flow` lists what it wants done in the state's `effects`; `Nidhox.Game` calls
  `perform/1` after each step.

  A lobby is a `Cauldron2D.Link` listener for this machine's world, announced by a
  `Cauldron2D.Beacon` whose fields are the game's lobby fields: `game` (`"Nidhogg"`),
  `version` (`"77"`), `title`, `owner` (the host's id), `name` (the host's name),
  `kind` (`"public"` for matchmaking, `"friends"` for a lobby a friend is invited to,
  `"standby"` for the lobby kept open on the online menu), `port` (the listener's
  port), `slots`, `players`, `avail`, `open`, and those the search publishes
  (`region`, `anyping`, and `invite`, the invited player's id). A machine
  that joins a lobby enters the host's world over the link (`Nidhox.Client`'s `source:
  {:link, address, port}`), and the two worlds play with rollback.

  The state's `online` is `new/2`'s map:

    * `listener`, `port` — the link listener and its port while this machine hosts
    * `beacon` — the beacon announcing the lobby
    * `hosted` — the lobby's kind while hosting (`:public`, `:friends`, `:standby`),
      else `nil`
    * `published` — the beacon's fields as last published
    * `ear` — the `Cauldron2D.Beacon.Listener` while lobbies are listened for
    * `lobbies_at` — the step the lobbies were last heard at, `nil` before
    * `lobbies` — the lobbies heard, refreshed every `@listen_every` steps, each
      `%{owner, name, kind, address, port, players, slots, open, region, anyping,
      invite}`
    * `pinger`, `pings` — the `Nidhox.Pinger` measuring the lobbies heard, and its
      latest round trips by `{address, port}`
    * `owner` — the player whose client chose ONLINE
    * `link_port` — the port to host on, `nil` for any free one
    * `status` — a line to show the players, or `nil`
    * `ssh`, `ssh_port`, `quitting`, `closing` — serving over ssh
      (`Cauldron2D.Drafter.Server`), as before: `ssh` is `%{server, addresses, port}`
      while serving

  Effects:

    * `{:host, kind, fields}` — host a lobby of `kind` announcing `fields`; a lobby
      already hosted is closed first
    * `:unhost` — stop hosting, closing every connection made to the lobby
    * `{:publish, fields}` — merge `fields` into the beacon's
    * `:drop` — close every connection made to the lobby, which keeps hosting
    * `:listen`, `:unlisten` — start and stop hearing lobbies and measuring them
    * `{:join, lobby, side, invited?}` — ask the client of the player on `side` to enter
      `lobby`'s world, joining it as invited (`netInvite`) when `invited?`
    * `{:join_address, address, port, side}` — the same for a lobby typed by address
    * `{:ssh_host, port}`, `:ssh_unhost` — serve the game over ssh on `port` (`0` for any
      free one), and stop
    * `:prefill_address` — the state's `entry` started as this machine's address up to
      its last dot, and the client of the player typing it (`typer`) asked to type it
  """

  alias Cauldron2D.Beacon
  alias Cauldron2D.Beacon.Listener
  alias Cauldron2D.Distribution
  alias Cauldron2D.Drafter.Server
  alias Cauldron2D.Link
  alias Nidhox.{Flow, Pinger}

  @game "NidhOX"
  @lobby_game "Nidhogg"
  @version "77"
  @slots 2
  @listen_every 30
  @shown_addresses 3
  @ssh_closed "NidhOX: the host stopped hosting."

  @type lobby :: %{
          owner: integer(),
          name: String.t(),
          kind: String.t(),
          address: :inet.ip_address(),
          port: :inet.port_number(),
          players: non_neg_integer(),
          slots: non_neg_integer(),
          open: boolean(),
          region: String.t(),
          anyping: boolean(),
          invite: integer() | nil
        }

  @type t :: %{
          listener: pid() | nil,
          port: :inet.port_number() | nil,
          beacon: pid() | nil,
          hosted: :public | :friends | :standby | nil,
          published: %{String.t() => String.t()},
          ear: pid() | nil,
          lobbies: [lobby()],
          lobbies_at: non_neg_integer() | nil,
          pinger: pid() | nil,
          pings: %{{:inet.ip_address(), :inet.port_number()} => number() | nil},
          owner: term(),
          link_port: :inet.port_number() | nil,
          status: String.t() | nil,
          ssh: %{server: Server.t(), addresses: [String.t()], port: pos_integer()} | nil,
          ssh_port: pos_integer() | nil,
          quitting: [term()],
          closing: non_neg_integer() | nil
        }

  @doc "No hosting or listening; a lobby is hosted on `link_port` (`nil` for any free port) and ssh offered on `ssh_port`."
  @spec new(:inet.port_number() | nil, pos_integer() | nil) :: t()
  def new(link_port \\ nil, ssh_port \\ nil),
    do: %{
      listener: nil,
      port: nil,
      beacon: nil,
      hosted: nil,
      published: %{},
      ear: nil,
      lobbies: [],
      lobbies_at: nil,
      pinger: nil,
      pings: %{},
      owner: nil,
      link_port: link_port,
      status: nil,
      ssh: nil,
      ssh_port: ssh_port,
      quitting: [],
      closing: nil
    }

  @doc "Whether players from another machine can be in this machine's game: it hosts a lobby or serves over ssh."
  @spec hosting?(%{online: t()}) :: boolean()
  def hosting?(%{online: %{listener: listener, ssh: ssh}}), do: listener != nil or ssh != nil

  @doc "Whether `player` plays from another machine while this one hosts."
  @spec remote_player?(%{online: t()}, %{owner: term()}) :: boolean()
  def remote_player?(%{online: online} = state, %{owner: owner}),
    do: hosting?(state) and owner != online.owner

  @doc "The round trip to `lobby` in milliseconds, `nil` while unknown."
  @spec ping(t(), lobby()) :: number() | nil
  def ping(online, lobby), do: Map.get(online.pings, {lobby.address, lobby.port})

  @doc "The fields every hosted lobby announces, for a host named `name` with id `owner`."
  @spec lobby_fields(integer(), String.t(), atom()) :: %{String.t() => String.t()}
  def lobby_fields(owner, name, kind),
    do: %{
      "id" => Integer.to_string(owner),
      "game" => @lobby_game,
      "version" => @version,
      "title" => if(kind == :public, do: "", else: name),
      "owner" => Integer.to_string(owner),
      "name" => name,
      "kind" => Atom.to_string(kind),
      "slots" => Integer.to_string(@slots),
      "players" => "1",
      "avail" => Integer.to_string(@slots - 1),
      "open" => "1"
    }

  @doc """
  `state` with its `effects` carried out and emptied, and the lobbies heard and their
  round trips refreshed. A state that follows a host on another machine (`following:
  true`) has its effects emptied without carrying them out: the host carries out its own.
  """
  @spec perform(map()) :: map()
  def perform(%{following: true} = state), do: %{state | effects: []}

  def perform(%{effects: effects} = state) do
    effects
    |> Enum.reverse()
    |> Enum.reduce(%{state | effects: []}, &effect/2)
    |> refresh()
  end

  defp effect({:host, kind, fields}, state) do
    state = effect(:unhost, state)
    online = state.online

    with {:ok, listener} <- Link.listen(self(), port: online.link_port || 0),
         port = Link.port(listener),
         published = Map.put(fields, "port", Integer.to_string(port)),
         {:ok, beacon} <-
           Beacon.start_link(game: @game, host: host_name(), fields: published) do
      Process.unlink(listener)
      Process.unlink(beacon)

      %{
        state
        | online: %{
            online
            | listener: listener,
              port: port,
              beacon: beacon,
              hosted: kind,
              published: published,
              status: nil
          }
      }
    else
      {:error, reason} -> put_status(state, "could not host: #{inspect(reason)}")
    end
  end

  defp effect(:unhost, %{online: %{listener: nil}} = state), do: state

  defp effect(:unhost, %{online: online} = state) do
    Link.drop(online.listener)
    Link.close(online.listener)
    if online.beacon, do: GenServer.stop(online.beacon, :normal)

    %{
      state
      | online: %{online | listener: nil, port: nil, beacon: nil, hosted: nil, published: %{}}
    }
  end

  defp effect({:publish, _fields}, %{online: %{beacon: nil}} = state), do: state

  defp effect({:publish, fields}, %{online: online} = state) do
    published = Map.merge(online.published, fields)

    if published != online.published, do: Beacon.put(online.beacon, published)
    %{state | online: %{online | published: published}}
  end

  defp effect(:drop, %{online: %{listener: nil}} = state), do: state

  defp effect(:drop, %{online: %{listener: listener}} = state) do
    Link.drop(listener)
    state
  end

  defp effect(:listen, %{online: %{ear: nil} = online} = state) do
    {:ok, ear} = Listener.start_link(game: @game, name: nil)
    {:ok, pinger} = Pinger.start_link()
    Process.unlink(ear)
    Process.unlink(pinger)

    %{
      state
      | online: %{online | ear: ear, pinger: pinger, lobbies: [], lobbies_at: nil, pings: %{}}
    }
  end

  defp effect(:listen, state), do: state
  defp effect(:unlisten, %{online: %{ear: nil}} = state), do: state

  defp effect(:unlisten, %{online: online} = state) do
    GenServer.stop(online.ear, :normal)
    Pinger.stop(online.pinger)
    %{state | online: %{online | ear: nil, pinger: nil, lobbies: [], lobbies_at: nil, pings: %{}}}
  end

  defp effect({:join, lobby, side, invited?}, state),
    do:
      Flow.ask(
        state,
        side,
        {:enter, %{source: {:link, lobby.address, lobby.port}, invited: invited?}}
      )

  defp effect({:join_address, address, port, side}, state),
    do: Flow.ask(state, side, {:enter, %{source: {:link, address, port}, invited: false}})

  defp effect({:ssh_host, port}, %{online: %{ssh: nil} = online} = state) do
    with [_first | _others] = addresses <- Enum.take(Distribution.addresses(), @shown_addresses),
         {:ok, server} <-
           Server.start(
             game: Nidhox.Client,
             port: port,
             ip: {0, 0, 0, 0},
             beacon: false,
             node: false
           ) do
      %{
        state
        | online: %{
            online
            | ssh: %{server: server, addresses: addresses, port: server.port},
              status: nil
          }
      }
    else
      [] -> put_status(state, "this machine has no network")
      {:error, reason} -> put_status(state, ssh_failure(port, reason))
    end
  end

  defp effect({:ssh_host, _port}, state), do: state
  defp effect(:ssh_unhost, %{online: %{ssh: nil}} = state), do: state

  defp effect(:ssh_unhost, %{online: %{ssh: %{server: server}} = online} = state) do
    Server.stop(server, @ssh_closed)
    %{state | online: %{online | ssh: nil}}
  end

  defp effect(:prefill_address, %{entry: {kind, label, alphabet, longest, _text}} = state) do
    prefix =
      case Distribution.address() do
        {:ok, address} ->
          address |> String.split(".") |> Enum.drop(-1) |> Enum.map_join(&(&1 <> "."))

        {:error, _reason} ->
          ""
      end

    state = %{state | entry: {kind, label, alphabet, longest, prefix}}
    Flow.ask(state, state.typer, {:menu, {:typing, state.entry}})
  end

  defp ssh_failure(port, {:shutdown, {:failed_to_start_child, _child, :eaddrinuse}}),
    do: ssh_port_taken(port)

  defp ssh_failure(port, :eaddrinuse), do: ssh_port_taken(port)
  defp ssh_failure(_port, reason), do: "could not serve over ssh: #{inspect(reason)}"

  defp ssh_port_taken(port), do: "port #{port} is taken: choose another"

  defp refresh(%{online: %{ear: ear} = online, steps: steps} = state)
       when ear != nil and rem(steps, @listen_every) == 0 do
    lobbies = ear |> Listener.found() |> Enum.flat_map(&lobby/1)
    Pinger.want(online.pinger, Enum.map(lobbies, &{&1.address, &1.port}))

    %{
      state
      | online: %{
          online
          | lobbies: lobbies,
            lobbies_at: steps,
            pings: Pinger.results(online.pinger)
        }
    }
  end

  defp refresh(state), do: state

  defp lobby(%{fields: %{"game" => @lobby_game, "version" => @version} = fields, from: from}) do
    with {owner, ""} <- Integer.parse(Map.get(fields, "owner", "")),
         {port, ""} <- Integer.parse(Map.get(fields, "port", "")) do
      [
        %{
          owner: owner,
          name: Map.get(fields, "name", ""),
          kind: Map.get(fields, "kind", "public"),
          address: from,
          port: port,
          players: number(fields, "players"),
          slots: number(fields, "slots"),
          open: Map.get(fields, "open") == "1",
          region: Map.get(fields, "region", "0"),
          anyping: Map.get(fields, "anyping") == "1",
          invite: invite(Map.get(fields, "invite"))
        }
      ]
    else
      _bad -> []
    end
  end

  defp lobby(_server), do: []

  defp number(fields, key) do
    case Integer.parse(Map.get(fields, key, "0")) do
      {value, ""} -> value
      _bad -> 0
    end
  end

  defp invite(nil), do: nil

  defp invite(text) do
    case Integer.parse(text) do
      {id, ""} when id != 0 -> id
      _none -> nil
    end
  end

  defp host_name do
    {:ok, name} = :inet.gethostname()
    to_string(name)
  end

  defp put_status(%{online: online} = state, status),
    do: %{state | online: %{online | status: status}}
end
