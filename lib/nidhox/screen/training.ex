defmodule Nidhox.Screen.Training do
  @moduledoc """
  TRAINING (`TrainingMenu`), a window over the main menu: the computer opponent's
  personality from a list, then its difficulty from 0 to 1 in tenths.

  On the list, up and down move (without wrapping), select or start opens the difficulty
  window, back closes TRAINING. In the difficulty window, left and right change the
  difficulty, back returns to the list, select or start begins: `step/3` gives
  `{:begin, personality, difficulty}`, the personality a name of
  `Nidhox.Brain.Personality.training/0`. Both ignore input for their first 10 steps.
  """

  alias Nidhox.{Glyphs, Lang}
  alias Nidhox.Screen.{Gui, MainMenu}

  @items [
    {:no_divekicks, "no_divekicks", "NO DIVEKICKS"},
    {:no_throws, "no_throws", "NO THROWS"},
    {:divekicker, "divekicker", "DIVEKICKER"},
    {:run_n_lunge, "run_n_lunge", "RUN N LUNGE"},
    {:brawler, "brawler", "BRAWLER"},
    {:never_lunges, "never_lunges", "NEVER LUNGES"},
    {:parry_master, "parry_master", "PARRY MASTER"},
    {:random, "random", "RANDOM"}
  ]

  @row 20
  @head 30
  @pad 12
  @width 260
  @sub_width 220
  @ready_steps 10

  defstruct selection: 0, difficulty: 0.5, adjusting: false, age: 0

  @type t :: %__MODULE__{
          selection: non_neg_integer(),
          difficulty: float(),
          adjusting: boolean(),
          age: non_neg_integer()
        }

  @doc "TRAINING at personality `personality` and `difficulty`, as last chosen."
  @spec new(atom(), number()) :: t()
  def new(personality, difficulty) do
    selection = Enum.find_index(@items, &(elem(&1, 0) == personality)) || 0
    %__MODULE__{selection: selection, difficulty: round(difficulty * 10) / 10}
  end

  @doc """
  The window after `players`' input: `{:open, window, events}` or `{:closed, events}`,
  events `{:sound, :move | :choose}` and `{:begin, personality, difficulty}`.
  """
  @spec step(t(), map(), map()) :: {:open, t(), [term()]} | {:closed, [term()]}
  def step(window, players, _context) do
    window = %{window | age: window.age + 1}

    cond do
      window.age < @ready_steps -> {:open, window, []}
      window.adjusting -> difficulty(window, players)
      true -> personality(window, players)
    end
  end

  defp personality(window, players) do
    step = pressed(players, 3) - pressed(players, 2)
    selection = (window.selection + step) |> max(0) |> min(length(@items) - 1)
    moved = if selection != window.selection, do: [{:sound, :move}], else: []
    window = %{window | selection: selection}

    cond do
      MainMenu.any_pressed?(players, 9) -> {:closed, moved}
      chosen?(players) -> {:open, %{window | adjusting: true}, moved ++ [{:sound, :choose}]}
      true -> {:open, window, moved}
    end
  end

  defp difficulty(window, players) do
    level =
      (round(window.difficulty * 10) + pressed(players, 1) - pressed(players, 0))
      |> max(0)
      |> min(10)

    difficulty = level / 10
    moved = if difficulty != window.difficulty, do: [{:sound, :move}], else: []
    window = %{window | difficulty: difficulty}

    cond do
      MainMenu.any_pressed?(players, 9) ->
        {:open, %{window | adjusting: false}, moved ++ [{:sound, :choose}]}

      chosen?(players) ->
        {:closed, moved ++ [{:begin, elem(Enum.at(@items, window.selection), 0), difficulty}]}

      true ->
        {:open, window, moved}
    end
  end

  defp pressed(players, button), do: if(MainMenu.any_pressed?(players, button), do: 1, else: 0)

  defp chosen?(players),
    do: MainMenu.any_pressed?(players, 8) or MainMenu.any_pressed?(players, 10)

  @doc "The window's drawing as GUI items; `context` gives `language`, `devices` and `prompt_side`."
  @spec items(t(), map(), Gui.window()) :: [map()]
  def items(window, context, size) do
    font = Lang.font(context.language)
    height = @head + length(@items) * @row + @pad
    {x, y} = {320 - @width / 2, 200 - height / 2}
    list_top = y + @head
    device = context.devices[context.prompt_side]

    MainMenu.dim(0.8, size) ++
      Gui.box("sprtextBgBox", {x, y, @width, height}, size) ++
      Gui.text(font, text(context, "training", "TRAINING"), {320, y + @head / 2}, size,
        halign: :center,
        valign: :middle,
        colour: {255, 255, 0}
      ) ++
      Gui.rectangle({x + @pad, list_top - 3, x + @width - @pad, list_top - 3}, Gui.grey(50), size) ++
      rows(window, x, list_top, context, font, size) ++
      if(window.adjusting,
        do: adjusting(window, context, font, size),
        else:
          Gui.prompts(
            [
              prompt(device, [8], context, "prompt_select", "select"),
              prompt(device, [9], context, "prompt_back", "back")
            ],
            {x + @width - 6, y + height},
            font,
            size
          )
      )
  end

  defp rows(window, x, list_top, context, font, size) do
    @items
    |> Enum.with_index()
    |> Enum.flat_map(fn {{_name, key, english}, index} ->
      top = list_top + index * @row
      selected? = index == window.selection

      bar =
        if selected?,
          do: Gui.rectangle({x + 4, top, x + @width - 4, top + @row - 1}, Gui.grey(30), size),
          else: []

      bar ++
        Gui.text(font, text(context, key, english), {320, top + @row / 2}, size,
          halign: :center,
          valign: :middle,
          colour: if(selected?, do: {255, 255, 255}, else: Gui.grey(150))
        )
    end)
  end

  defp adjusting(window, context, font, size) do
    sub_height = @head + 44
    {x, y} = {320 - @sub_width / 2, 200 - sub_height / 2}
    slider_width = @sub_width - @pad * 4
    {_name, key, english} = Enum.at(@items, window.selection)
    device = context.devices[context.prompt_side]

    MainMenu.dim(0.6, size) ++
      Gui.box("sprtextBgBox", {x, y, @sub_width, sub_height}, size) ++
      Gui.text(font, text(context, key, english), {320, y + @head / 2}, size,
        halign: :center,
        valign: :middle,
        colour: {255, 255, 0}
      ) ++
      Gui.rectangle(
        {x + @pad, y + @head - 3, x + @sub_width - @pad, y + @head - 3},
        Gui.grey(50),
        size
      ) ++
      Gui.text(font, text(context, "difficulty", "DIFFICULTY"), {320, y + @head + 8}, size,
        halign: :center,
        valign: :middle,
        colour: Gui.grey(150)
      ) ++
      Gui.slider(
        {320 - slider_width / 2, y + @head + 22, slider_width, 8},
        window.difficulty,
        {255, 255, 255},
        size
      ) ++
      Gui.prompts(
        [
          prompt(device, [0, 1], context, "prompt_adjust", "adjust"),
          prompt(device, [8], context, "prompt_select", "select"),
          prompt(device, [9], context, "prompt_back", "back")
        ],
        {x + @sub_width - 6, y + sub_height},
        font,
        size
      )
  end

  defp prompt(device, buttons, context, key, english),
    do:
      Enum.map_join(buttons, &Gui.glyph(Glyphs.icon(device, &1))) <>
        " " <> text(context, key, english)

  defp text(context, key, english), do: Lang.text(context.language, "main menu", key, english)
end
