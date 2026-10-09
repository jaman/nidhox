defmodule Nidhox.Screen.Online do
  @moduledoc """
  ONLINE VERSUS's screens under the title's logo, as GUI items for a window
  `{width, height}`:

    * `hosting/2` — HOST, this machine's address and the join code to tell the player
      joining, and "waiting for player.." until they join (or why hosting failed)
    * `entry/3` — an address or a join code being typed (`Nidhox.Screen.Entry`), with
      the joining's status under it
  """

  alias Nidhox.Screen.{Art, Entry}

  @logo {160, 52}
  @top 100
  @spacing 14
  @entry_top 100
  @status_y 150

  @doc "The hosting screen's GUI items for `online` (`Nidhox.Online`)."
  @spec hosting(map(), {number(), number()}) :: [map()]
  def hosting(%{host: nil, status: status}, window),
    do: [logo(window) | lines(["HOST", status || "starting.."], window)]

  def hosting(%{host: host}, window),
    do: [
      logo(window)
      | lines(
          ["HOST", "ADDRESS: #{host.address}", "CODE: #{host.code}", "waiting for player.."],
          window
        )
    ]

  @doc "An entry's GUI items with `status` under it, `nil` for none."
  @spec entry(Entry.t(), String.t() | nil, {number(), number()}) :: [map()]
  def entry(%Entry{} = entry, status, window) do
    status_items =
      if status,
        do: Art.text("fMenu", status, {160, @status_y}, window, halign: :center),
        else: []

    [logo(window) | Entry.items(entry, {160, @entry_top}, window)] ++ status_items
  end

  defp lines(lines, window) do
    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, index} ->
      Art.text("fMenu", line, {160, @top + index * @spacing}, window, halign: :center)
    end)
  end

  defp logo(window), do: Art.centred("sNewTitle", 0, @logo, window)
end
