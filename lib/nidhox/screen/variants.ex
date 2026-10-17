defmodule Nidhox.Screen.Variants do
  @moduledoc """
  VARIANTS (`VariantsMenu`), a `Nidhox.Screen.PopupList` window over TOURNAMENT or the
  pause menu: TIME LIMIT, the variant switches (`Nidhox.Rules`) and RESTORE DEFAULTS.
  Online it lists only the variants both players share: TIME LIMIT, DIVEKICKS,
  NO SWORDS, THROWS ONLY, LOW GRAVITY, SUDDEN DEATH ONLY, SPINE SWORDS,
  BOOMERANG SWORDS, TRAILS and RESTORE DEFAULTS.

  After its first 10 steps, up and down move round the list. On TIME LIMIT, left and
  right step it (`Nidhox.Rules.step_time_limit/2`) and select or start steps it
  forward; on a switch, select or start turns it over; on RESTORE DEFAULTS, they put
  every listed variant back as it starts. Each change is a `{:rules, rules}` event,
  with `{:lobby, text}` for the lobby's messages (`"/mode:name value"`, then the
  change in words). Back closes the window, except in the pause when TIME LIMIT or
  SUDDEN DEATH ONLY changed: then it asks RESTART THE MATCH TO APPLY?, where select
  closes it with `:restart_match` and back puts the rules back as they were when it
  opened (`{:rules, before}`).

  `step/3` reads `context.rules`; `items/3` reads `rules`, `language` and `devices`.
  """

  alias Nidhox.{Glyphs, Lang, Rules}
  alias Nidhox.Objects.Match
  alias Nidhox.Screen.{Gui, MainMenu, PopupList}

  @items [
    {:time_limit, "time_limit", "TIME LIMIT", true, true},
    {:divekicks, "divekicks", "DIVEKICKS", true, false},
    {:throws, "throws", "THROWS", false, false},
    {:noSwords, "no_swords", "NO SWORDS", true, false},
    {:throwsOnly, "throws_only", "THROWS ONLY", true, false},
    {:babyMode, "baby_mode", "BABY MODE", false, false},
    {:lowGravity, "low_gravity", "LOW GRAVITY", true, false},
    {:suddenDeathOnly, "sudden_death_only", "SUDDEN DEATH ONLY", true, true},
    {:skippyMode, "skippy_mode", "SKIPPY MODE", false, false},
    {:turboMode, "turbo_mode", "TURBO MODE", false, false},
    {:slowMode, "slow_mode", "SLOW MODE", false, false},
    {:spineSwords, "spine_swords", "SPINE SWORDS", true, false},
    {:boomerangSwords, "boomerang_swords", "BOOMERANG SWORDS", true, false},
    {:trails, "trails", "TRAILS", true, false},
    {:defaults, "restore_defaults", "RESTORE DEFAULTS", true, false}
  ]

  @width 300
  @ready_steps 10

  @enforce_keys [:items, :popup]
  defstruct [:items, :popup, :before, in_pause?: false, confirming: false, age: 0, prompt_side: 1]

  @type item :: {atom(), String.t(), String.t(), boolean(), boolean()}
  @type t :: %__MODULE__{
          items: [item()],
          popup: PopupList.t(),
          before: Rules.t() | nil,
          in_pause?: boolean(),
          confirming: boolean(),
          age: non_neg_integer(),
          prompt_side: 1 | 2
        }

  @doc """
  VARIANTS over `rules`. Options: `:online` (only the shared variants), `:in_pause` (a
  change to TIME LIMIT or SUDDEN DEATH ONLY asks to restart the match), `:prompt_side`.
  """
  @spec new(Rules.t(), keyword()) :: t()
  def new(%Rules{} = rules, opts \\ []) do
    items =
      if Keyword.get(opts, :online, false), do: Enum.filter(@items, &elem(&1, 3)), else: @items

    in_pause? = Keyword.get(opts, :in_pause, false)

    %__MODULE__{
      items: items,
      popup: PopupList.new(@width, length(items)),
      before: if(in_pause?, do: rules),
      in_pause?: in_pause?,
      prompt_side: Keyword.get(opts, :prompt_side, 1)
    }
  end

  @doc "The window after `players`' input: `{:open, window, events}` or `{:closed, events}`."
  @spec step(t(), map(), map()) :: {:open, t(), [term()]} | {:closed, [term()]}
  def step(window, players, context) do
    window = %{
      window
      | age: window.age + 1,
        prompt_side:
          if(window.in_pause?,
            do: window.prompt_side,
            else: MainMenu.prompt_side(players, window.prompt_side)
          )
    }

    cond do
      window.age < @ready_steps -> {:open, window, []}
      window.confirming -> confirming(window, players)
      true -> listed(window, players, context.rules)
    end
  end

  defp confirming(window, players) do
    cond do
      MainMenu.any_pressed?(players, 8) -> {:closed, [:restart_match]}
      MainMenu.any_pressed?(players, 9) -> {:closed, [{:rules, window.before}]}
      true -> {:open, window, []}
    end
  end

  defp listed(window, players, rules) do
    {popup, moved?} = PopupList.navigate(window.popup, players)
    window = %{window | popup: popup}
    moved = if moved?, do: [{:sound, :move}], else: []
    confirm? = MainMenu.any_pressed?(players, 8) or MainMenu.any_pressed?(players, 10)
    {name, _key, english, _net, _restart} = Enum.at(window.items, popup.selection)
    changes = changed(window, name, english, rules, players, confirm?)

    if MainMenu.any_pressed?(players, 9),
      do: back(window, rules_after(changes, rules), moved ++ changes),
      else: {:open, window, moved ++ changes}
  end

  defp changed(_window, :time_limit, english, rules, players, confirm?) do
    direction =
      if confirm?,
        do: 1,
        else: pressed(players, 1) - pressed(players, 0)

    if direction == 0 do
      []
    else
      limit = Rules.step_time_limit(rules.time_limit, direction)
      shown = if limit == 0, do: "-", else: Match.time(limit)

      [{:sound, :move}, {:rules, %{rules | time_limit: limit}}] ++
        lobby(:time_limit, limit, english <> ": " <> shown)
    end
  end

  defp changed(window, :defaults, _english, rules, _players, true) do
    entries = window.items |> Enum.map(&elem(&1, 0)) |> Enum.reject(&(&1 == :defaults))
    reset = Rules.reset(rules, entries)

    [{:sound, :choose}, {:rules, reset}] ++
      Enum.flat_map(entries, &lobby(&1, value(reset, &1), nil))
  end

  defp changed(_window, switch, english, rules, _players, true) do
    turned = Rules.choose(rules, switch)
    on? = Rules.on?(turned, switch)

    [{:sound, :choose}, {:rules, turned}] ++
      lobby(switch, value(turned, switch), if(on?, do: "+ ", else: "- ") <> english)
  end

  defp changed(_window, _name, _english, _rules, _players, false), do: []

  defp value(rules, :time_limit), do: rules.time_limit
  defp value(rules, switch), do: if(Rules.on?(rules, switch), do: 1, else: 0)

  defp lobby(name, value, nil), do: [{:lobby, "/mode:#{name} #{value}"}]

  defp lobby(name, value, message),
    do: [{:lobby, "/mode:#{name} #{value}"}, {:lobby, String.downcase(message)}]

  defp rules_after(events, rules) do
    Enum.reduce(events, rules, fn
      {:rules, changed}, _rules -> changed
      _other, rules -> rules
    end)
  end

  defp back(%{in_pause?: true} = window, rules, events) do
    if restart_needed?(window, rules),
      do: {:open, %{window | confirming: true, age: 0}, events},
      else: {:closed, events}
  end

  defp back(_window, _rules, events), do: {:closed, events}

  defp restart_needed?(window, rules) do
    window.items
    |> Enum.filter(&elem(&1, 4))
    |> Enum.any?(fn {name, _key, _english, _net, _restart} ->
      value(rules, name) != value(window.before, name)
    end)
  end

  defp pressed(players, button), do: if(MainMenu.any_pressed?(players, button), do: 1, else: 0)

  @doc "The window's drawing as GUI items."
  @spec items(t(), map(), Gui.window()) :: [map()]
  def items(window, context, size) do
    font = Lang.font(context.language)
    popup = window.popup
    device = context.devices[window.prompt_side]

    PopupList.draw_window(popup, text(context, "variants", "VARIANTS"), font, size) ++
      rows(window, context, font, size) ++
      PopupList.draw_scrollbar(popup, size) ++
      if(window.confirming,
        do: confirm(context, device, font, size),
        else:
          Gui.prompts(prompts(window, context, device), PopupList.prompt_at(popup), font, size)
      )
  end

  defp rows(window, context, font, size) do
    window.items
    |> Enum.with_index()
    |> Enum.flat_map(fn {{name, key, english, _net, _restart}, index} ->
      PopupList.draw_row(window.popup, index, text(context, key, english), font, size) ++
        value_items(window.popup, index, name, context, font, size)
    end)
  end

  defp value_items(popup, index, :time_limit, context, font, size) do
    shown =
      case context.rules.time_limit do
        0 -> text(context, "none", "NONE")
        limit -> Match.time(limit)
      end

    PopupList.draw_value(popup, index, shown, font, size)
  end

  defp value_items(_popup, _index, :defaults, _context, _font, _size), do: []

  defp value_items(popup, index, switch, context, font, size),
    do: PopupList.draw_tick(popup, index, Rules.on?(context.rules, switch), font, size)

  defp prompts(window, context, device) do
    case Enum.at(window.items, window.popup.selection) do
      {:time_limit, _key, _english, _net, _restart} ->
        [
          prompt(device, [0, 1], context, "prompt_adjust", "adjust"),
          prompt(device, [9], context, "prompt_back", "back")
        ]

      _other ->
        [
          prompt(device, [8], context, "prompt_select", "select"),
          prompt(device, [9], context, "prompt_back", "back")
        ]
    end
  end

  defp confirm(context, device, font, size) do
    Gui.confirm(
      font,
      text(context, "restart_prompt", "RESTART THE MATCH TO APPLY?"),
      Gui.glyph(Glyphs.icon(device, 9)) <>
        " " <> text(context, "discard_changes", "DISCARD CHANGES"),
      Gui.glyph(Glyphs.icon(device, 8)) <> " " <> text(context, "restart", "RESTART"),
      size
    )
  end

  defp prompt(device, buttons, context, key, english),
    do:
      Enum.map_join(buttons, &Gui.glyph(Glyphs.icon(device, &1))) <>
        " " <> text(context, key, english)

  defp text(context, key, english), do: Lang.text(context.language, "main menu", key, english)
end
