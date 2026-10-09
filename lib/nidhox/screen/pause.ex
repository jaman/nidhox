defmodule Nidhox.Screen.Pause do
  @moduledoc """
  The pause over a bout: the copy's `sPaused` and its menu — "UNPAUSE GAME", "CHANGE
  LEVEL" in a versus bout, and "QUIT TO TITLE SCREEN".
  """

  alias Nidhox.Screen.{Art, Menu}

  @banner {160, 56}
  @menu_top {160, 92}

  @doc "The pause menu for a bout in `mode`."
  @spec menu(atom()) :: Menu.t()
  def menu(:versus),
    do:
      Menu.new([
        {"UNPAUSE GAME", :unpause},
        {"CHANGE LEVEL", :change_level},
        {"QUIT TO TITLE SCREEN", :title}
      ])

  def menu(_mode), do: Menu.new([{"UNPAUSE GAME", :unpause}, {"QUIT TO TITLE SCREEN", :title}])

  @doc "The pause's GUI items with `menu`."
  @spec items(Menu.t(), {number(), number()}) :: [map()]
  def items(%Menu{} = menu, window) do
    [
      Art.shade(window, {0, 0, 0}, 0.5),
      Art.centred("sPaused", 0, @banner, window)
      | Menu.items(menu, @menu_top, window)
    ]
  end
end
