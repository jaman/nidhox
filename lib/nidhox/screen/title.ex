defmodule Nidhox.Screen.Title do
  @moduledoc """
  The press that ends the logos (`Nidhox.Screen.Logos`) early: `:start`, `:attack` or
  `:jump` from either side.
  """

  @doc "Whether any player pressed something that ends the logos."
  @spec continue?(%{1 => map(), 2 => map()}) :: boolean()
  def continue?(players) do
    Enum.any?(Map.values(players), fn input ->
      Enum.any?([:start, :attack, :jump], &(&1 in input.pressed))
    end)
  end
end
