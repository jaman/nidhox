defmodule Nidhox.Screen.Online do
  @moduledoc """
  ONLINE VERSUS's screens under the title's logo, as GUI items for a window
  `{width, height}`:

    * `hosting/2` — HOST, this machine's address and the join code to tell the player
      joining, and "waiting for player.." until they join (or why hosting failed), with
      the status under it, such as that the last player left
    * `ssh_hosting/2` — HOST OVER SSH: the command the other player connects with, one
      for each of this machine's addresses (the other player uses the one on a network
      they share), and
      "waiting for player.." until they join (or why serving failed)
    * `notice/2` — the status line under ONLINE VERSUS's menu, such as why a hosted
      game ended
    * `entry/3` — an address or a join code being typed (typed on a client, `Nidhox.Typing`), with
      the joining's status under it
  """

  alias Nidhox.Screen.Art

  @logo {160, 52}
  @top 100
  @spacing 14
  @status_y 150
  @notice_y 186

  @doc "The hosting screen's GUI items for `online` (`Nidhox.Online`)."
  @spec hosting(map(), {number(), number()}) :: [map()]
  def hosting(%{host: nil, status: status}, window),
    do: [logo(window) | lines(["HOST", status || "starting.."], window)]

  def hosting(%{host: host, status: status}, window),
    do:
      [
        logo(window)
        | lines(
            ["HOST", "ADDRESS: #{host.address}", "CODE: #{host.code}", "waiting for player.."],
            window
          )
      ] ++ notice(status, window)

  @doc "The GUI items of serving the game over ssh, from the state's `online`."
  @spec ssh_hosting(map(), {number(), number()}) :: [map()]
  def ssh_hosting(%{ssh: nil, status: status}, window),
    do: [logo(window) | lines(["HOST OVER SSH", status || "starting.."], window)]

  def ssh_hosting(%{ssh: %{addresses: addresses, port: port}, status: status}, window),
    do:
      [
        logo(window)
        | lines(
            ["HOST OVER SSH"] ++
              Enum.map(addresses, &"ssh -p #{port} new@#{&1}") ++
              ["any password, then pick a name", "waiting for player.."],
            window
          )
      ] ++ notice(status, window)

  @doc """
  The GUI items of an entry being typed on a player's client (`Nidhox.Typing`): its label,
  how to type it again or go back, and `status` under them, `nil` for none.
  """
  @spec entry(
          {atom(), String.t(), charlist(), pos_integer(), String.t()},
          String.t() | nil,
          {number(), number()}
        ) ::
          [map()]
  def entry({_kind, label, _alphabet, _longest, _text}, status, window) do
    status_items =
      if status,
        do: Art.text("fMenu", status, {160, @status_y}, window, halign: :center),
        else: []

    [logo(window) | lines([label, "start to type, jump to go back"], window)] ++ status_items
  end

  @doc "The GUI items of the status line under ONLINE VERSUS's menu: `status`, nothing when `nil`."
  @spec notice(String.t() | nil, {number(), number()}) :: [map()]
  def notice(nil, _window), do: []

  def notice(status, window),
    do: Art.text("fMenu", status, {160, @notice_y}, window, halign: :center)

  defp lines(lines, window) do
    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, index} ->
      Art.text("fMenu", line, {160, @top + index * @spacing}, window, halign: :center)
    end)
  end

  defp logo(window), do: Art.centred("sNewTitle", 0, @logo, window)
end
