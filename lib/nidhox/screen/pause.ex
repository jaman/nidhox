defmodule Nidhox.Screen.Pause do
  @moduledoc """
  The pause over a bout (`PauseController`): a window of choices under the `sPaused`
  title, and the windows some choices open over it.

  `new/1` lists, from its options:

    * UNPAUSE GAME
    * CHANGE LEVEL — in a versus match or CPU BATTLE (`:flow` 4 or 62831853) with no
      player on another machine (`:remote?`)
    * VARIANTS — while the variants apply to the match (`:variants?`) and no player is
      on another machine, and in the online lobby (`:lobby?`)
    * CHANGE COLOR — in a versus match (`:flow` 4) and in the online lobby
    * INPUT DELAY — in the online lobby
    * OPTIONS — NidhOX's: the options of the chooser's own client
    * EXIT — LEAVE LOBBY in the online lobby and FORFEIT with a player on another
      machine

  `step/3` gives `{:open, pause, events}` or `{:closed, events}`. The pause takes no
  choice until select and start have been let go. Up and down move round the list;
  select or start chooses; back resumes; left and right step INPUT DELAY
  (`{:input_delay, step}`). UNPAUSE GAME and back keep the pause up 20 more steps without
  input, then close it with `:unpause`; CHANGE LEVEL closes it with `:change_level`;
  VARIANTS opens `Nidhox.Screen.Variants` and CHANGE COLOR `Nidhox.Screen.Colours`,
  whose events pass on; OPTIONS gives `{:options, side}`; EXIT asks BACK TO MAIN MENU?
  (LEAVE THE LOBBY?, FORFEIT THE MATCH?), whose select closes the pause with
  `{:exit, side}` and whose back returns to the list. The prompt side is the last side
  to press a menu button.

  `items/3` draws it, given `context` (`Nidhox.Screen.Context`).
  """

  alias Nidhox.{Glyphs, Lang}
  alias Nidhox.Screen.{Colours, Gui, MainMenu, Variants}

  @versus 4
  @cpu_battle 62_831_853
  @row 20
  @head 68
  @pad 12
  @width 320
  @resume_steps 20

  @enforce_keys [:items]
  defstruct [
    :items,
    current: 0,
    confirming: false,
    self_destruct: 0,
    can_trigger: false,
    window: nil,
    prompt_side: 1
  ]

  @type item :: {atom(), String.t(), String.t(), String.t()}
  @type t :: %__MODULE__{
          items: [item()],
          current: non_neg_integer(),
          confirming: boolean(),
          self_destruct: non_neg_integer(),
          can_trigger: boolean(),
          window: Variants.t() | Colours.t() | nil,
          prompt_side: 1 | 2
        }

  @doc "The pause for a match; options `:flow`, `:remote?`, `:variants?`, `:lobby?` and `:side`, the side that paused."
  @spec new(keyword()) :: t()
  def new(opts) do
    flow = Keyword.get(opts, :flow, @versus)
    remote? = Keyword.get(opts, :remote?, false)
    lobby? = Keyword.get(opts, :lobby?, false)
    variants? = Keyword.get(opts, :variants?, false)

    items =
      [{:unpause, "pause screen", "unpause_game", "UNPAUSE GAME"}] ++
        listed(flow in [@versus, @cpu_battle] and not remote?, :change_level) ++
        listed((variants? and not remote?) or lobby?, :variants) ++
        listed(flow == @versus or lobby?, :change_color) ++
        listed(lobby?, :input_delay) ++
        [{:options, "main menu", "options", "OPTIONS"}, exit_item(lobby?, remote?)]

    %__MODULE__{items: items, prompt_side: Keyword.get(opts, :side, 1)}
  end

  defp listed(false, _item), do: []

  defp listed(true, :change_level),
    do: [{:change_level, "pause screen", "change_level", "CHANGE LEVEL"}]

  defp listed(true, :variants), do: [{:variants, "main menu", "variants", "VARIANTS"}]

  defp listed(true, :change_color),
    do: [{:change_color, "pause screen", "change_color", "CHANGE COLOR"}]

  defp listed(true, :input_delay),
    do: [{:input_delay, "online match", "input_delay", "INPUT DELAY"}]

  defp exit_item(true, _remote?), do: {:exit, "online match", "leave_lobby", "LEAVE LOBBY"}
  defp exit_item(false, true), do: {:exit, "online match", "forfeit", "FORFEIT"}
  defp exit_item(false, false), do: {:exit, "pause screen", "exit", "EXIT"}

  @doc "The selected item's name."
  @spec selected(t()) :: atom()
  def selected(pause), do: pause.items |> Enum.at(pause.current) |> elem(0)

  @doc "The pause after a step of `players`' input; see the module documentation."
  @spec step(t(), map(), map()) :: {:open, t(), [term()]} | {:closed, [term()]}
  def step(%{window: %module{} = window} = pause, players, context) do
    case module.step(window, players, context) do
      {:open, window, events} -> {:open, %{pause | window: window}, events}
      {:closed, events} -> {:open, %{pause | window: nil}, events}
    end
  end

  def step(%{self_destruct: steps} = pause, _players, _context) when steps > 0 do
    if steps - 1 <= 0,
      do: {:closed, [:unpause]},
      else: {:open, %{pause | self_destruct: steps - 1}, []}
  end

  def step(%{can_trigger: false} = pause, players, _context) do
    held? = Enum.any?([8, 10], &held?(players, &1))
    {:open, %{pause | can_trigger: not held?}, []}
  end

  def step(%{confirming: true} = pause, players, _context) do
    pause = %{pause | prompt_side: MainMenu.prompt_side(players, pause.prompt_side)}

    cond do
      chooser(players) != nil -> {:closed, [{:exit, chooser(players)}]}
      MainMenu.any_pressed?(players, 9) -> {:open, %{pause | confirming: false}, []}
      true -> {:open, pause, []}
    end
  end

  def step(pause, players, context) do
    pause = %{pause | prompt_side: MainMenu.prompt_side(players, pause.prompt_side)}

    cond do
      chooser(players) != nil ->
        chosen(pause, selected(pause), chooser(players), context)

      selected(pause) == :input_delay and adjusted(players) != 0 ->
        {:open, pause, [{:input_delay, adjusted(players)}]}

      MainMenu.any_pressed?(players, 9) ->
        {:open, resuming(pause), []}

      MainMenu.any_pressed?(players, 2) ->
        {:open, moved(pause, -1), []}

      MainMenu.any_pressed?(players, 3) ->
        {:open, moved(pause, 1), []}

      true ->
        {:open, pause, []}
    end
  end

  defp chosen(pause, :unpause, _side, _context), do: {:open, resuming(pause), []}
  defp chosen(_pause, :change_level, _side, _context), do: {:closed, [:change_level]}

  defp chosen(pause, :variants, _side, context),
    do:
      {:open,
       %{
         pause
         | window:
             Variants.new(context.rules,
               online: context.remote?,
               in_pause: true,
               prompt_side: pause.prompt_side
             )
       }, []}

  defp chosen(pause, :change_color, _side, _context),
    do: {:open, %{pause | window: Colours.new(pause.prompt_side)}, []}

  defp chosen(pause, :input_delay, _side, _context), do: {:open, pause, [{:input_delay, 1}]}
  defp chosen(pause, :options, side, _context), do: {:open, pause, [{:options, side}]}
  defp chosen(pause, :exit, _side, _context), do: {:open, %{pause | confirming: true}, []}

  defp resuming(pause), do: %{pause | current: 0, self_destruct: @resume_steps}

  defp moved(pause, step),
    do: %{pause | current: Integer.mod(pause.current + step, length(pause.items))}

  defp chooser(players),
    do:
      Enum.find(
        [1, 2],
        &(MainMenu.pressed?(players, &1, 8) or MainMenu.pressed?(players, &1, 10))
      )

  defp adjusted(players),
    do: pressed(players, 1) - pressed(players, 0)

  defp pressed(players, button), do: if(MainMenu.any_pressed?(players, button), do: 1, else: 0)

  defp held?(players, button) do
    action = Glyphs.action(button)
    Enum.any?(Map.values(players), &(action in &1.held))
  end

  @doc "The pause's drawing as GUI items: the list, then its confirmation or open window."
  @spec items(t(), map(), Gui.window()) :: [map()]
  def items(pause, context, size) do
    font = Lang.font(context.language)
    height = @head + length(pause.items) * @row + @pad
    {left, top} = {320 - @width / 2, 200 - height / 2}
    list_top = top + @head

    MainMenu.dim(0.8, size) ++
      Gui.box("sprtextBgBox", {left, top, @width, height}, size) ++
      Gui.sprite("sPaused", 0, {320, top + @head / 2 - 1}, size, scale: {2, 2}) ++
      Gui.rectangle(
        {left + @pad, list_top - 3, left + @width - @pad, list_top - 3},
        Gui.grey(50),
        size
      ) ++
      rows(pause, left, list_top, context, font, size) ++
      over(pause, {left + @width - 6, top + height}, context, font, size)
  end

  defp rows(pause, left, list_top, context, font, size) do
    pause.items
    |> Enum.with_index()
    |> Enum.flat_map(fn {{name, section, key, english}, index} ->
      row_top = list_top + index * @row
      selected? = index == pause.current

      bar =
        if selected?,
          do:
            Gui.rectangle(
              {left + 4, row_top, left + @width - 4, row_top + @row - 1},
              Gui.grey(30),
              size
            ),
          else: []

      colour = if selected?, do: {255, 255, 255}, else: Gui.grey(150)
      text = String.downcase(Lang.text(context.language, section, key, english))
      bar ++ row_text(name, text, row_top + @row / 2, colour, context, font, size)
    end)
  end

  defp row_text(:input_delay, text, middle, colour, context, font, size) do
    label = text <> ": "
    value = "< #{context.input_delay.ms} ms >"
    left = 320 - (Gui.text_width(font, label) + Gui.text_width(font, value)) / 2

    Gui.text(font, label, {left, middle}, size, valign: :middle, colour: colour) ++
      Gui.text(font, value, {left + Gui.text_width(font, label), middle}, size,
        valign: :middle,
        colour: context.input_delay.colour
      )
  end

  defp row_text(_name, text, middle, colour, _context, font, size),
    do:
      Gui.text(font, text, {320, middle}, size, halign: :center, valign: :middle, colour: colour)

  defp over(%{window: %module{} = window}, _at, context, _font, size),
    do: module.items(window, context, size)

  defp over(%{confirming: true} = pause, _at, context, font, size) do
    device = context.devices[pause.prompt_side]

    Gui.confirm(
      font,
      confirm_text(pause, context),
      Gui.glyph(Glyphs.icon(device, 9)) <> " " <> text(context, "main menu", "no", "NO"),
      Gui.glyph(Glyphs.icon(device, 8)) <> " " <> text(context, "main menu", "yes", "YES"),
      size
    )
  end

  defp over(pause, at, context, font, size) do
    device = context.devices[pause.prompt_side]

    first =
      if selected(pause) == :input_delay,
        do:
          glyphs(device, [0, 1]) <> " " <> text(context, "main menu", "prompt_adjust", "adjust"),
        else: glyphs(device, [8]) <> " " <> text(context, "main menu", "prompt_select", "select")

    Gui.prompts(
      [first, glyphs(device, [9]) <> " " <> text(context, "main menu", "prompt_back", "back")],
      at,
      font,
      size
    )
  end

  defp confirm_text(pause, context) do
    case List.last(pause.items) do
      {:exit, _section, "leave_lobby", _english} ->
        text(context, "online match", "leave_lobby_prompt", "LEAVE THE LOBBY?")

      {:exit, _section, "forfeit", _english} ->
        text(context, "online match", "forfeit_prompt", "FORFEIT THE MATCH?")

      _exit ->
        text(context, "main menu", "leave_prompt", "BACK TO MAIN MENU?")
    end
  end

  defp glyphs(device, buttons), do: Enum.map_join(buttons, &Gui.glyph(Glyphs.icon(device, &1)))

  defp text(context, section, key, english),
    do: Lang.text(context.language, section, key, english)
end
