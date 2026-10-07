defmodule Nidhox.Client do
  @moduledoc """
  NidhOX as a `Cauldron2D.Client.Game`: the keys, and the picture the terminal shows.

      mix nidhox

  The whole pane is the game's picture: exactly the room's view, at the largest scale
  that fits the pane, centred between black bars, with what the game draws on its GUI
  over it in window pixels. Keys and controller buttons are `Nidhox.Controls`'.
  """

  @behaviour Cauldron2D.Client.Game

  alias Cauldron2D.DrawList
  alias Nidhox.{Assets, Controls}

  @atlas :nidhox

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
  def local_seats(_props), do: [Controls.keys(2)]

  @impl true
  def padmap(_props), do: Controls.pad()

  @impl true
  def toggles, do: []

  @impl true
  def start, do: {:play, :nidhox}

  @impl true
  def look, do: %{projection: :picture, projections: [:picture]}

  @impl true
  def chat?, do: false

  @impl true
  def lobby?, do: false

  @impl true
  def client_keys do
    %{
      menu: :escape,
      back: nil,
      settings: nil,
      settings_menu: nil,
      title: nil,
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
  def worlds(props) do
    [
      %{
        id: :nidhox,
        name: "NidhOX",
        world:
          {Nidhox.Game,
           [hz: 60, game_opts: [room: Map.get(props, :room), area: Map.get(props, :area)]]},
        players: 0,
        humans: []
      }
    ]
  end

  @impl true
  def scene(frame) do
    %{
      focus: {0.0, 0.0},
      bounds: :unbounded,
      cell: fn _cell -> nil end,
      movers: [],
      picture: fn size, _aspect -> picture(frame, size) end
    }
  end

  @doc """
  The pane's picture of `frame` at `size` `{width, height}` pixels: the room's view
  scaled to fit, the GUI over it, centred between black bars.
  """
  @spec picture(map() | nil, {pos_integer(), pos_integer()}) :: FrenchCurve.Raster.t()
  def picture(
        %{items: items, gui: gui, view: {view_x, view_y, view_width, view_height}} = frame,
        {width, height} = size
      ) do
    pictures = Assets.get().pictures
    lookup = &lookup(pictures, &1)
    zoom = min(width / view_width, height / view_height)
    shown = {max(round(view_width * zoom), 1), max(round(view_height * zoom), 1)}

    room =
      DrawList.render(items, shown, lookup,
        view: {view_x, view_y},
        zoom: zoom,
        background: frame.background
      )

    room =
      case gui do
        [] ->
          room

        _ ->
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

  defp lookup(_pictures, {:text, words, colour, scale}),
    do: Linocut.Font.render(words, colour, scale: scale)

  defp lookup(pictures, key), do: Map.get(pictures, key)

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
  def listener(_frame), do: nil

  @impl true
  def sounds, do: fn _event -> nil end

  @impl true
  def music, do: []

  @impl true
  def cue(_frame, _screen), do: nil
end
