defmodule Nidhox.Glyphs do
  @moduledoc """
  The pictures of a side's keys and buttons that the game's prompts show (`inputIcon`,
  the Input library's `InputIconGet`): the key it binds on a keyboard, or the button on
  the controller it last played with.

      Nidhox.Glyphs.icon(%{device: :keyboard, keys: %{jump: [:g]}}, 8)
      #=> {:sprite, "keyboard_g"}

  A side's `device` is `%{device: :keyboard | {:pad, name}, keys: %{action => [key]}}`,
  what its client sends with its input (`Nidhox.Game`). A glyph is `{:sprite, name}`, one
  of the copy's sprites drawn inline (each one frame, its origin at its top left), or
  `{:text, text}`.

  The game's menu buttons are numbers: `0` left, `1` right, `2` up, `3` down, `4` jump,
  `5` attack, `8` select (the jump binding), `9` back and `10` start. `action/1` gives the
  side's action each one reads.

  A keyboard glyph is the game's sprite for the key (`keyboard_a`, `keyboard_enter`,
  `keyboard_arrow_up`, …), its text (`"page up"`, …) for keys it has words for, and
  `"unsupported"` for any other key. A side with no key for the action shows `"empty"`.

  A controller glyph follows the family its name says: Xbox, PlayStation 4, PlayStation 5,
  Switch Pro controller, the left and the right Joy-Con, and any other controller in
  words (`"face south"`, `"dpad left"`, …). The buttons are those of
  `Nidhox.Controls.pad/0`.
  """

  alias Nidhox.Controls

  @type glyph :: {:sprite, String.t()} | {:text, String.t()}
  @type device :: %{device: :keyboard | {:pad, String.t() | nil}, keys: map()}

  @actions %{
    0 => :left,
    1 => :right,
    2 => :up,
    3 => :down,
    4 => :jump,
    5 => :attack,
    8 => :jump,
    9 => :pause,
    10 => :start
  }

  @keyboard_sprites %{
    escape: "keyboard_escape",
    backspace: "keyboard_backspace",
    space: "keyboard_space",
    " ": "keyboard_space",
    enter: "keyboard_enter",
    up: "keyboard_arrow_up",
    down: "keyboard_arrow_down",
    left: "keyboard_arrow_left",
    right: "keyboard_arrow_right",
    tab: "key_tab",
    caps_lock: "keyboard_capslock",
    alt: "keyboard_alt",
    shift: "keyboard_shift",
    ctrl: "keyboard_ctrl",
    "`": "keyboard_tilde",
    "~": "keyboard_tilde",
    -: "keyboard_minus",
    +: "keyboard_plus",
    =: "keyboard_plus",
    ";": "keyboard_semicolon",
    "'": "keyboard_apostrophe",
    ",": "keyboard_comma",
    .: "keyboard_period",
    "[": "keyboard_bracket_open",
    "]": "keyboard_bracket_close",
    /: "keyboard_slash_forward",
    \\: "keyboard_slash_back",
    *: "keyboard_asterisk"
  }

  @keyboard_texts %{
    scroll_lock: "scroll lock",
    num_lock: "numlock",
    menu: "menu",
    print_screen: "print screen",
    pause_break: "pause break",
    delete: "delete",
    insert: "insert",
    home: "home",
    page_up: "page up",
    page_down: "page down",
    end: "end"
  }

  @buttons %{
    a: :face1,
    b: :face2,
    x: :face3,
    y: :face4,
    left_bumper: :shoulder_l,
    right_bumper: :shoulder_r,
    back: :select,
    start: :start,
    guide: :home,
    left_stick: :stick_l_click,
    right_stick: :stick_r_click,
    dpad_up: :dpad_up,
    dpad_down: :dpad_down,
    dpad_left: :dpad_left,
    dpad_right: :dpad_right
  }

  @axes %{
    {:left_x, :neg} => :stick_l_left,
    {:left_x, :pos} => :stick_l_right,
    {:left_y, :neg} => :stick_l_up,
    {:left_y, :pos} => :stick_l_down,
    {:right_x, :neg} => :stick_r_left,
    {:right_x, :pos} => :stick_r_right,
    {:right_y, :neg} => :stick_r_up,
    {:right_y, :pos} => :stick_r_down,
    {:left_trigger, :pos} => :trigger_l,
    {:right_trigger, :pos} => :trigger_r
  }

  @generic %{
    face1: "face south",
    face2: "face east",
    face3: "face west",
    face4: "face north",
    shoulder_l: "shoulder l",
    shoulder_r: "shoulder r",
    trigger_l: "trigger l",
    trigger_r: "trigger r",
    select: "select",
    start: "start",
    home: "home",
    dpad_left: "dpad left",
    dpad_right: "dpad right",
    dpad_up: "dpad up",
    dpad_down: "dpad down",
    stick_l_left: "thumbstick l left",
    stick_l_right: "thumbstick l right",
    stick_l_up: "thumbstick l up",
    stick_l_down: "thumbstick l down",
    stick_l_click: "thumbstick l click",
    stick_r_left: "thumbstick r left",
    stick_r_right: "thumbstick r right",
    stick_r_up: "thumbstick r up",
    stick_r_down: "thumbstick r down",
    stick_r_click: "thumbstick r click"
  }

  @dpad %{
    dpad_left: "generic_dpad_left",
    dpad_right: "generic_dpad_right",
    dpad_up: "generic_dpad_up",
    dpad_down: "generic_dpad_down"
  }

  @right_stick %{
    stick_r_left: "generic_stick_r_left",
    stick_r_right: "generic_stick_r_right",
    stick_r_up: "generic_stick_r_up",
    stick_r_down: "generic_stick_r_down",
    stick_r_click: "generic_stick_r_side"
  }

  @left_stick_l %{
    stick_l_left: "generic_stick_l_left",
    stick_l_right: "generic_stick_l_right",
    stick_l_up: "generic_stick_l_up",
    stick_l_down: "generic_stick_l_down",
    stick_l_click: "generic_stick_l_side"
  }

  @left_stick %{
    stick_l_left: "generic_stick_left",
    stick_l_right: "generic_stick_right",
    stick_l_up: "generic_stick_up",
    stick_l_down: "generic_stick_down",
    stick_l_click: "generic_stick_side"
  }

  @xbox %{
          face1: "xbox_button_color_a",
          face2: "xbox_button_color_b",
          face3: "xbox_button_color_x",
          face4: "xbox_button_color_y",
          shoulder_l: "xbox_lb",
          shoulder_r: "xbox_rb",
          trigger_l: "xbox_lt",
          trigger_r: "xbox_rt",
          select: "xbox_button_view",
          start: "xbox_button_menu"
        }
        |> Map.merge(@dpad)
        |> Map.merge(@left_stick_l)
        |> Map.merge(@right_stick)

  @playstation %{
    face1: "playstation_button_color_cross",
    face2: "playstation_button_color_circle",
    face3: "playstation_button_color_square",
    face4: "playstation_button_color_triangle",
    shoulder_l: "playstation_trigger_l1",
    shoulder_r: "playstation_trigger_r1",
    trigger_l: "playstation_trigger_l2",
    trigger_r: "playstation_trigger_r2",
    select: "playstation_button_create",
    start: "playstation_button_options"
  }

  @playstation_4 @playstation
                 |> Map.merge(@dpad)
                 |> Map.merge(@left_stick_l)
                 |> Map.merge(@right_stick)
  @playstation_5 @playstation
                 |> Map.merge(@dpad)
                 |> Map.merge(@left_stick)
                 |> Map.merge(@right_stick)

  @switch %{
            face1: "switch_button_b",
            face2: "switch_button_a",
            face3: "switch_button_y",
            face4: "switch_button_x",
            shoulder_l: "switch_button_l",
            shoulder_r: "switch_button_r",
            trigger_l: "switch_button_zl",
            trigger_r: "switch_button_zr",
            select: "switch_button_minus",
            start: "switch_button_plus",
            home: "switch_button_home"
          }
          |> Map.merge(@dpad)
          |> Map.merge(@left_stick_l)
          |> Map.merge(@right_stick)

  @joycon %{
    face1: "switch_buttons_down",
    face2: "switch_buttons_right",
    face3: "switch_buttons_left",
    face4: "switch_buttons_up",
    shoulder_l: "switch_button_sl",
    shoulder_r: "switch_button_sr"
  }

  @joycon_left @joycon
               |> Map.merge(@left_stick)
               |> Map.merge(%{start: "switch_button_minus", select: "switch_button_sync"})

  @joycon_right @joycon
                |> Map.merge(@left_stick)
                |> Map.merge(%{start: "switch_button_plus", select: "switch_button_home"})

  @tables %{
    xbox: @xbox,
    playstation_4: @playstation_4,
    playstation_5: @playstation_5,
    switch: @switch,
    joycon_left: @joycon_left,
    joycon_right: @joycon_right
  }

  @family_names [
    joycon_left: ["joy-con (l)", "joycon (l)", "joy-con l"],
    joycon_right: ["joy-con (r)", "joycon (r)", "joy-con r"],
    switch: ["pro controller", "switch"],
    playstation_5: ["dualsense", "ps5"],
    playstation_4: ["dualshock", "ps4", "sony"],
    xbox: ["xbox", "xinput", "x-box"],
    playstation_4: ["wireless controller"]
  ]

  @doc "The action of the side that menu button `button` reads, or `nil` for a button the game does not use."
  @spec action(non_neg_integer()) :: atom() | nil
  def action(button), do: Map.get(@actions, button)

  @doc "The glyph of menu button `button` for a side playing with `device`."
  @spec icon(device() | nil, non_neg_integer()) :: glyph()
  def icon(nil, button), do: icon(%{device: :keyboard, keys: %{}}, button)

  def icon(%{device: device} = side, button) do
    case action(button) do
      nil -> {:text, "empty"}
      action -> glyph(device, Map.get(side, :keys, %{}), action)
    end
  end

  @doc "The family a controller's name says it is: `:xbox`, `:playstation_4`, `:playstation_5`, `:switch`, `:joycon_left`, `:joycon_right` or `:generic`."
  @spec family(String.t() | nil) :: atom()
  def family(nil), do: :generic

  def family(name) do
    lower = String.downcase(name)

    Enum.find_value(@family_names, :generic, fn {family, parts} ->
      if Enum.any?(parts, &String.contains?(lower, &1)), do: family
    end)
  end

  defp glyph(:keyboard, keys, action) do
    case Map.get(keys, action, []) do
      [key | _rest] -> keyboard(key)
      [] -> {:text, "empty"}
    end
  end

  defp glyph({:pad, name}, _keys, action) do
    case Map.get(pad_controls(), action, []) do
      [control | _rest] -> pad(family(name), control)
      [] -> {:text, "empty"}
    end
  end

  defp pad_controls, do: Controls.pad()

  defp keyboard(key) when is_atom(key) do
    name = Atom.to_string(key)

    cond do
      Map.has_key?(@keyboard_sprites, key) -> {:sprite, @keyboard_sprites[key]}
      Map.has_key?(@keyboard_texts, key) -> {:text, @keyboard_texts[key]}
      name =~ ~r/^[a-z0-9]$/ -> {:sprite, "keyboard_" <> name}
      name =~ ~r/^f([1-9]|1[0-2])$/ -> {:sprite, "keyboard_" <> name}
      true -> {:text, "unsupported"}
    end
  end

  defp keyboard(_key), do: {:text, "unsupported"}

  defp pad(family, {:axis, axis, direction}),
    do: pad_glyph(family, Map.get(@axes, {axis, direction}))

  defp pad(family, button), do: pad_glyph(family, Map.get(@buttons, button))

  defp pad_glyph(_family, nil), do: {:text, "unsupported"}

  defp pad_glyph(:generic, button), do: {:text, Map.get(@generic, button, "unsupported")}
  defp pad_glyph(family, button), do: @tables |> Map.fetch!(family) |> Map.get(button) |> found()

  defp found(nil), do: {:text, "unsupported"}
  defp found(sprite), do: {:sprite, sprite}
end
