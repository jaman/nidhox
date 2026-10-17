defmodule Nidhox.Client do
  @moduledoc """
  NidhOX as a `Cauldron2D.Client.Game`: the keys, and the picture the terminal shows.

      mix nidhox

  The whole pane is the game's picture: exactly the room's view, at the largest scale
  that fits the pane, centred between black bars, with what the game draws on its GUI
  over it in window pixels, and the game's options (`Nidhox.Options`), or the typing of a
  host's address or join code (`Nidhox.Typing`, opened when the world asks with
  `{:menu, {:typing, entry}}`), over that while open. Keys and controller buttons are `Nidhox.Controls`'; of the client's own
  keys only `Ctrl+Q` and `Ctrl+C` (quit) remain, `q` and `p` doing nothing and `Esc`
  being the game's pause. A draw item's
  picture `{:part, key, {left, top, width, height}}` shows that part of picture `key`, and
  a tile layer's picture is drawn once a room and kept (`Nidhox.TileLayerCache`).

  The scene's `:native` is the room view's own size, so the client's picture options
  (`Cauldron2D.Drafter.Client.Picture`) can draw the room at that size times a whole
  number for the terminal to scale; the look's default is `native:2,png,swap`.

  The scene's `:gpu` draws the same picture on the graphics card (`Nidhox.Gpu`): in the
  pane when there is a card, in a window of its own with the picture option `window`, and
  in software with `software` or without a card.

  The game's music is the world's own sound events — the title's `MainMenuMusic`, the
  match's `LayeredMusic`, the tutorial's — so the client cues no music of its own.

  The world is this machine's NidhOX world, or with the mount prop `source:
  {:link, address, port}` (and `invited: true` when the player joins through an invite)
  a world of this machine's that follows the NidhOX world behind
  the `Cauldron2D.Link` listener at that address and port (ONLINE's joining,
  `Nidhox.Online`). The two worlds play with rollback (`Cauldron2D.World`'s
  `:rollback`): each machine runs the game on its own clock and draws it itself, and
  the two exchange only the players' joins, leaves and input.
  """

  @behaviour Cauldron2D.Client.Game

  @atlas :nidhox
  alias Cauldron2D.DrawList
  alias Nidhox.{Assets, Controls, Gpu, Options, Picture, Typing}
  alias Nidhox.Bout.Spiral

  @impl true
  def title, do: %{name: "NidhOX", tagline: "Nidhogg Open-source eXperience"}

  @impl true
  def atlas do
    unless Cauldron2D.Atlas.installed?(@atlas) do
      @atlas |> Cauldron2D.Atlas.new(tile: 16, void: {0, 0, 0}) |> Cauldron2D.Atlas.install()
    end

    @atlas
  end

  @impl true
  def actions, do: Controls.actions()

  @impl true
  def keymaps, do: [keyboard: Controls.keys(1)]

  @impl true
  def toggles, do: []

  @impl true
  def local_seats(props), do: [Controls.seat_keys(props)]

  @impl true
  def options,
    do: %{
      player_2: Controls.keys(2),
      flashing: true,
      persistent_blood: true,
      language:
        Nidhox.Lang.initial(Elixir.System.get_env("LC_ALL") || Elixir.System.get_env("LANG")),
      menu_seen: [],
      news_seen: [],
      hype: 0.75,
      colours: [1, 2]
    }

  @impl true
  def padmap(_props), do: Controls.pad()

  @impl true
  def start, do: {:play, :nidhox}

  @impl true
  def look,
    do: %{projection: :picture, projections: [:picture], picture: [{:native, 2}, :png, :swap]}

  @impl true
  def chat?, do: false

  @impl true
  def lobby?, do: false

  @impl true
  def client_keys do
    %{
      back: nil,
      title: nil,
      pause: nil,
      menu: nil,
      settings: nil,
      settings_menu: nil,
      talk: nil,
      watch: nil,
      team: nil,
      chat: nil,
      guide: nil,
      projection: nil,
      turn_left: nil,
      turn_right: nil,
      tilt_up: nil,
      tilt_down: nil,
      zoom_in: nil,
      zoom_out: nil,
      zoom_reset: nil
    }
  end

  @impl true
  def sounds, do: &Nidhox.Sounds.voice/1

  @impl true
  def recordings, do: &Nidhox.Sounds.recording/1

  @impl true
  def music, do: []

  @impl true
  def cue(_frame, _client_screen), do: nil

  @impl true
  def worlds(%{source: {:link, address, port}} = props),
    do: [
      %{
        id: world_id(),
        name: "NidhOX",
        world:
          {Nidhox.Game,
           [
             follow: {:link, address, port},
             rollback: true,
             join_props: Map.take(props, [:invited])
           ]}
      }
    ]

  def worlds(_props),
    do: [%{id: world_id(), name: "NidhOX", world: Cauldron2D.Worlds.world_name(world_id())}]

  @doc "The id NidhOX's world is registered under with `Cauldron2D.Worlds`."
  @spec world_id() :: atom()
  def world_id, do: :nidhox

  @impl true
  def scene(frame, %{menu: %Options{} = menu}) do
    scene(Map.put(frame, :overlay, Options.items(menu, frame.window)))
  end

  def scene(frame, %{menu: %Typing{} = typing}) do
    scene(Map.put(frame, :overlay, Typing.items(typing, frame.window)))
  end

  def scene(frame, _look), do: scene(frame)

  @impl true
  def open_menu(settings), do: Options.open(settings)

  @impl true
  def open_menu(_settings, {:typing, entry}), do: Typing.open(entry)

  @impl true
  def menu_event(%Typing{} = typing, event, settings), do: Typing.event(typing, event, settings)
  def menu_event(menu, event, settings), do: Options.event(menu, event, settings)

  @impl true
  def scene(frame) do
    %{
      focus: {0.0, 0.0},
      bounds: :unbounded,
      cell: fn _cell -> nil end,
      movers: [],
      native: native(frame),
      picture: fn size, _aspect -> picture(frame, size) end,
      gpu: fn target, cache, size, _aspect -> Gpu.draw(frame, target, cache, size) end
    }
  end

  defp native(%{spiral: {_left, _right}}), do: Spiral.screen_size()
  defp native(%{view: {_x, _y, width, height}}), do: {round(width), round(height)}
  defp native(_frame), do: nil

  @doc """
  The pane's picture of `frame` at `size` `{width, height}` pixels: the room's view
  scaled to fit, the room's GUI and then the overlay over it, centred between black bars.
  """
  @spec picture(map() | nil, {pos_integer(), pos_integer()}) :: FrenchCurve.Raster.t()
  def picture(
        %{items: items, view: {view_x, view_y, _view_width, _view_height}} = frame,
        size
      ) do
    lookup = &Picture.raster(Assets.get().pictures, Map.get(frame, :surfaces, %{}), &1)
    layout = Picture.layout(frame, size)

    room =
      items
      |> DrawList.render(layout.viewed, lookup,
        view: {view_x, view_y},
        zoom: layout.zoom,
        background: frame.background
      )
      |> warped(layout.shown, Map.get(frame, :spiral))

    room =
      case frame.gui ++ Map.get(frame, :overlay, []) do
        [] ->
          room

        gui ->
          DrawList.render(gui, layout.shown, lookup, zoom: layout.gui_zoom, background: room)
      end

    letterbox(room, layout.offset, size)
  end

  def picture(_frame, {width, height}),
    do: FrenchCurve.Raster.new(width, height, background: {0, 0, 0, 255})

  defp warped(room, _shown, nil), do: room
  defp warped(room, shown, amounts), do: Spiral.warp(room, shown, amounts)

  defp letterbox(room, offset, size) do
    Cauldron2D.Render.render(size, [{:raster, room, offset}], background: {0, 0, 0, 255})
  end

  @impl true
  def hud(_frame), do: []

  @impl true
  def ask(%{ask: ask}), do: ask
  def ask(_frame), do: nil

  @impl true
  def listener(%{view: {x, y, width, height}}), do: {(x + width / 2) / 16, (y + height / 2) / 16}
  def listener(_frame), do: nil

  @impl true
  def audio, do: [earshot: 20, voices: 24, master: :sfx]
end
