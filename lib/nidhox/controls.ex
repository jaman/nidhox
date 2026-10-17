defmodule Nidhox.Controls do
  @moduledoc """
  What a side can do, and the keys and controller buttons that do it.

  | action | side 1 | side 2 | controller |
  | --- | --- | --- | --- |
  | `:left`, `:right` | `A` `D` | `←` `→` | d-pad, left stick |
  | `:up`, `:down` | `W` `S` | `↑` `↓` | d-pad, left stick |
  | `:attack` | `F` | `M` | `X` |
  | `:jump` | `G` | `N` | `A` |
  | `:start` | `Enter` | `Enter` | `Start` |
  | `:pause` | `Esc` | | `B` |

  These are the game's own defaults (`InputForPlayer1`, `InputForPlayer2`). Side 1 is the terminal's own player and side 2 a second seat at the same keyboard
  (`seat_keys/1`); either's keys can be remapped in OPTIONS (`Nidhox.Options`);
  the first controller to report plays side 1 and the second side 2. On the menus
  (`Nidhox.Glyphs`), `:jump` and `:start` choose and `:pause` goes back. `:pause` pauses a match as
  `:start` does (the game's `keyboard_check_pressed(27)`), keyboard `Esc` being no one
  side's in the game.
  """

  @actions [:left, :right, :up, :down, :attack, :jump, :start, :pause]

  @doc "Every action, in the order the guide lists them."
  @spec actions() :: [atom()]
  def actions, do: @actions

  @doc "The keys side `side` plays with."
  @spec keys(1 | 2) :: %{atom() => [atom()]}
  def keys(1),
    do: %{
      left: [:a],
      right: [:d],
      up: [:w],
      down: [:s],
      attack: [:f],
      jump: [:g],
      start: [:enter],
      pause: [:escape]
    }

  def keys(2),
    do: %{
      left: [:left],
      right: [:right],
      up: [:up],
      down: [:down],
      attack: [:m],
      jump: [:n],
      start: [:enter],
      pause: []
    }

  @doc """
  The keys side 2's seat plays with, from a client's props: the keymap saved in the
  player's settings as the game option `:player_2`, else `keys(2)`.
  """
  @spec seat_keys(map()) :: %{atom() => [term()]}
  def seat_keys(%{settings: %{options: %{player_2: keys}}}) when is_map(keys), do: keys
  def seat_keys(_props), do: keys(2)

  @doc "The controller buttons and stick directions for each action."
  @spec pad() :: map()
  def pad do
    %{
      left: [:dpad_left, {:axis, :left_x, :neg}],
      right: [:dpad_right, {:axis, :left_x, :pos}],
      up: [:dpad_up, {:axis, :left_y, :neg}],
      down: [:dpad_down, {:axis, :left_y, :pos}],
      attack: [:x],
      jump: [:a],
      start: [:start],
      pause: [:b]
    }
  end
end
