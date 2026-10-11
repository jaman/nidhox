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

  The game's music is the world's own sound events — the title's `MainMenuMusic`, the
  match's `LayeredMusic`, the tutorial's — so the client cues no music of its own.

  The world is this machine's NidhOX world, or with the mount prop `source:
  {:node, node}` the NidhOX world of that connected node (ONLINE VERSUS's joining,
  `Nidhox.Online`).
  """

  @behaviour Cauldron2D.Client.Game

  @atlas :nidhox
  alias Cauldron2D.DrawList
  alias Cauldron2D.GameMaker.{Shapes, TileLayers}
  alias Nidhox.{Assets, Controls, Options, TileLayerCache, Typing}

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
  def options, do: %{player_2: Controls.keys(2), flashing: true, persistent_blood: true}

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
  def worlds(%{source: {:node, node}}),
    do: [%{id: world_id(), name: "NidhOX", world: Cauldron2D.Worlds.world_name(world_id(), node)}]

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
      picture: fn size, _aspect -> picture(frame, size) end
    }
  end

  defp native(%{view: {_x, _y, width, height}}), do: {round(width), round(height)}
  defp native(_frame), do: nil

  @doc """
  The pane's picture of `frame` at `size` `{width, height}` pixels: the room's view
  scaled to fit, the room's GUI and then the overlay over it, centred between black bars.
  """
  @spec picture(map() | nil, {pos_integer(), pos_integer()}) :: FrenchCurve.Raster.t()
  def picture(
        %{items: items, view: {view_x, view_y, view_width, view_height}} = frame,
        {width, height} = size
      ) do
    pictures = Assets.get().pictures
    surfaces = Map.get(frame, :surfaces, %{})
    lookup = &lookup(pictures, surfaces, &1)
    zoom = min(width / view_width, height / view_height)
    shown = {max(round(view_width * zoom), 1), max(round(view_height * zoom), 1)}

    room =
      DrawList.render(items, shown, lookup,
        view: {view_x, view_y},
        zoom: zoom,
        background: frame.background
      )

    room =
      case frame.gui ++ Map.get(frame, :overlay, []) do
        [] ->
          room

        gui ->
          {window_width, window_height} = frame.window
          {shown_width, shown_height} = shown

          DrawList.render(gui, shown, lookup,
            zoom: min(shown_width / window_width, shown_height / window_height),
            background: room
          )
      end

    letterbox(room, shown, size)
  end

  def picture(_frame, {width, height}),
    do: FrenchCurve.Raster.new(width, height, background: {0, 0, 0, 255})

  defp lookup(_pictures, surfaces, {:surface, id}), do: Map.get(surfaces, id)

  defp lookup(_pictures, surfaces, {:surface_part, id, {left, top, width, height}}) do
    case Map.get(surfaces, id) do
      nil -> nil
      raster -> FrenchCurve.Raster.crop(raster, {left, top}, {width, height})
    end
  end

  defp lookup(_pictures, _surfaces, {:ellipse, _size, _fill} = shape), do: Shapes.raster(shape)

  defp lookup(pictures, _surfaces, {:tile_layer, _room, _layer, _blend} = key) do
    TileLayerCache.fetch(key, fn ->
      TileLayers.raster(Assets.get().data, key, &Map.get(pictures, &1))
    end)
  end

  defp lookup(pictures, surfaces, {:part, key, {left, top, width, height}}) do
    case lookup(pictures, surfaces, key) do
      nil -> nil
      raster -> FrenchCurve.Raster.crop(raster, {left, top}, {width, height})
    end
  end

  defp lookup(pictures, _surfaces, key), do: Map.get(pictures, key)

  defp letterbox(room, {shown_width, shown_height}, {width, height} = size) do
    Cauldron2D.Render.render(
      size,
      [{:raster, room, {div(width - shown_width, 2), div(height - shown_height, 2)}}],
      background: {0, 0, 0, 255}
    )
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
