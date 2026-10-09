defmodule Nidhox.Screen do
  @moduledoc """
  What each screen of `Nidhox.Flow` draws over its room: the fencers and swords of a
  bout as room items (`Nidhox.Look`), and the screen's own pictures and text as GUI
  items for a window `{width, height}`.
  """

  alias Nidhox.{Look, Tutorial}
  alias Nidhox.Screen.{Art, Credits, Ladder, Levels, Logos, Online, Pause, Results, Title}

  @skip {160, 186}
  @lesson {160, 18}
  @lesson_wrap 280

  @doc "The room items and the GUI items of `state`'s screen."
  @spec layer(map(), {number(), number()}) :: {[map()], [map()]}
  def layer(%{screen: :logos} = state, window), do: {[], Logos.items(state.timer, window)}

  def layer(%{screen: screen} = state, window) when screen in [:title, :multi, :online, :join],
    do: {[], Title.items(state.steps, state.menu, window)}

  def layer(%{screen: :levels} = state, window), do: {[], Levels.items(state.levels, window)}

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

  def layer(%{screen: :en_garde} = state, _window), do: {Look.items(state.match), []}

  def layer(%{screen: :bout} = state, window),
    do: {Look.items(state.match), Look.banner(state.match, window)}

  def layer(%{screen: :paused} = state, window),
    do: {Look.items(state.match), Pause.items(state.menu, window)}

  def layer(%{screen: :results} = state, window),
    do: {[], Results.items(state.match.winner, state.stats, state.menu, window)}

  def layer(%{screen: :tutorial} = state, window) do
    line =
      case Tutorial.line(state.tutorial) do
        nil -> []
        words -> Art.text("fMenu", words, @lesson, window, halign: :center, wrap: @lesson_wrap)
      end

    {Look.items(state.match), Look.banner(state.match, window) ++ line}
  end

  def layer(%{screen: :replay} = state, window) do
    skip = Art.text("fMenu", "SKIP THIS", @skip, window, halign: :center)
    {Look.items(state.match), Look.banner(state.match, window) ++ skip}
  end
end
