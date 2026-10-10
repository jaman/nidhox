defmodule Nidhox.Screen do
  @moduledoc """
  What each screen of `Nidhox.Flow` draws over its room, as GUI items for a window
  `{width, height}`: the screen's own pictures and text. A bout draws itself through
  its objects; over it only the pause menu and the replay's skip line are added.
  """

  alias Nidhox.Screen.{Art, Credits, Ladder, Levels, Logos, Online, Pause, Results, Title}

  @skip {160, 186}

  @doc "The room items and the GUI items of `state`'s screen."
  @spec layer(map(), {number(), number()}) :: {[map()], [map()]}
  def layer(%{screen: :logos} = state, window), do: {[], Logos.items(state.timer, window)}

  def layer(%{screen: screen} = state, window) when screen in [:title, :join],
    do: {[], Title.items(state.steps, state.menu, window)}

  def layer(%{screen: :levels} = state, _window),
    do: {Levels.items(state.levels, state.world), []}

  def layer(%{screen: :credits} = state, window),
    do: {[], Credits.items(state.credits, state.timer, window)}

  def layer(%{screen: :hosting} = state, window), do: {[], Online.hosting(state.online, window)}

  def layer(%{screen: screen} = state, window) when screen in [:address, :code],
    do: {[], Online.entry(state.entry, state.online.status, window)}

  def layer(%{screen: :tournament_intro} = state, window),
    do: {[], Ladder.intro(state.tournament.bracket.count, window)}

  def layer(%{screen: :ladder} = state, window),
    do: {[], Ladder.items(state.tournament.bracket, window)}

  def layer(%{screen: :champion} = state, window),
    do: {[], Ladder.champion(state.tournament.bracket.champion, window)}

  def layer(%{screen: screen}, _window)
      when screen in [:bout, :demo, :tutorial, :challenge, :arcade, :arcade_complete],
      do: {[], []}

  def layer(%{screen: :paused} = state, window), do: {[], Pause.items(state.menu, window)}

  def layer(%{screen: :replay}, window),
    do: {[], Art.text("fMenu", "SKIP THIS", @skip, window, halign: :center)}

  def layer(%{screen: :results} = state, window),
    do:
      {[], Results.items(state.world, state.winner, state.stats, state.menu || :continue, window)}
end
