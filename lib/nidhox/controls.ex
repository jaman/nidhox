defmodule Nidhox.Controls do
  @moduledoc """
  What a side can do, and the keys and controller buttons that do it.

  | action | side 1 | side 2 | controller |
  | --- | --- | --- | --- |
  | `:left`, `:right` | `A` `D` | `←` `→` | d-pad, left stick |
  | `:up`, `:down` | `W` `S` | `↑` `↓` | d-pad, left stick |
  | `:attack` | `F` | `.` | `X` |
  | `:jump` | `G` | `,` | `A` |
  | `:start` | `Enter` | | `Start` |

  Side 1 is the terminal's own player and side 2 a second seat at the same keyboard;
  the first controller to report plays side 1 and the second side 2. On the title and
  the menus, `:start` and `:attack` choose and `:jump` goes back.
  """

  @actions [:left, :right, :up, :down, :attack, :jump, :start]

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
      start: [:enter]
    }

  def keys(2),
    do: %{left: [:left], right: [:right], up: [:up], down: [:down], attack: [:.], jump: [:","]}

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
      start: [:start]
    }
  end
end
