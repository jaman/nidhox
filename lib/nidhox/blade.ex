defmodule Nidhox.Blade do
  @moduledoc """
  Swords and bodies as the copy draws them, for telling what touches what.

  A fencer's blade is the `sSword` it holds out from its hand (`Nidhox.Pose`): level, at
  the hand's height, from the hand forward by the sword sprite's length; `root` is where
  the fencer stands, the arm's start. A fencer whose
  pose holds no blade out — unarmed, down, running, in the air, throwing — has none.

  A body is the copy's `sManMask` about where the fencer stands — or, ducking or knocked
  down, the bounds of its pose's frame — `{left, top, right, bottom}` in room pixels.

  Two blades cross when they face each other at the same height (within
  `@same_height` pixels) and each tip has passed the other's.
  """

  alias Nidhox.{Assets, Fencer, Pose}

  @type t :: %{root: number(), from: number(), to: number(), y: number(), facing: 1 | -1}
  @type box :: {number(), number(), number(), number()}

  @same_height 3
  @sword "sSword"
  @mask "sManMask"
  @lunges ~w(sManSwordAttackHi sManSwordAttackMed sManSwordAttackLo)

  @doc "The blade `fencer` holds out this step, or `nil`."
  @spec of(Fencer.t()) :: t() | nil
  def of(%Fencer{action: :dead}), do: nil

  def of(%Fencer{position: {x, y}, facing: facing} = fencer) do
    case Pose.of(fencer) do
      %{sword: {:hand, {dx, dy}}} ->
        from = x + facing * dx
        %{root: x, from: from, to: from + facing * length(), y: y + dy, facing: facing}

      _none ->
        nil
    end
  end

  @doc "The body of `fencer`, or `nil` when it is down."
  @spec body(Fencer.t()) :: box() | nil
  def body(%Fencer{action: :dead}), do: nil

  def body(%Fencer{action: action, position: {x, y}, facing: facing} = fencer)
      when action in [:duck, :floored] do
    {left, top, right, bottom} = Assets.bounds(Pose.of(fencer).body)
    {near, far} = Enum.min_max([x + facing * left, x + facing * right])
    {near, y + top, far, y + bottom}
  end

  def body(%Fencer{position: {x, y}}) do
    {_index, %{size: {width, height}, origin: {origin_x, origin_y}}} = Assets.sprite!(@mask)
    {x - origin_x, y - origin_y, x - origin_x + width, y - origin_y + height}
  end

  @doc "Whether `blade` — the arm from the fencer's `root` and the sword to its tip — crosses `body`."
  @spec hits?(t() | nil, box() | nil) :: boolean()
  def hits?(nil, _body), do: false
  def hits?(_blade, nil), do: false

  def hits?(%{y: y, root: root, to: to}, {left, top, right, bottom}) do
    {near, far} = Enum.min_max([root, to])
    y >= top and y <= bottom and far >= left and near <= right
  end

  @doc "How far the tips of blades `a` and `b` have passed each other, in pixels along x; `0` when they do not cross."
  @spec crossing(t() | nil, t() | nil) :: number()
  def crossing(nil, _other), do: 0
  def crossing(_blade, nil), do: 0

  def crossing(%{facing: facing} = a, %{facing: other} = b) when facing == -other do
    if abs(a.y - b.y) <= @same_height,
      do: max(0, (a.to - b.to) * facing),
      else: 0
  end

  def crossing(_a, _b), do: 0

  @doc "Whether the point `{x, y}` lies on `blade`, within `@same_height` pixels of it."
  @spec touches?(t() | nil, {number(), number()}) :: boolean()
  def touches?(nil, _point), do: false

  def touches?(%{y: y} = blade, {px, py}) do
    {near, far} = span(blade)
    abs(py - y) <= @same_height and px >= near and px <= far
  end

  @doc "How far above its feet a fencer in high guard holds its hand: where a throw leaves from."
  @spec high() :: number()
  def high, do: -elem(Assets.hand({"sManSwordStandHi", 0}), 1)

  @doc "The tip of `blade`."
  @spec tip(t()) :: {number(), number()}
  def tip(%{to: to, y: y}), do: {to, y}

  @doc "How far in front of its feet a fencer's lunge reaches: the furthest hand of the copy's lunges, and the sword."
  @spec reach() :: number()
  def reach do
    hands =
      for name <- @lunges,
          frame <- 0..(Assets.frame_count(name) - 1),
          do: elem(Assets.hand({name, frame}), 0)

    Enum.max(hands) + length()
  end

  defp length, do: @sword |> Assets.sprite!() |> elem(1) |> Map.fetch!(:size) |> elem(0)

  defp span(%{from: from, to: to}), do: {min(from, to), max(from, to)}
end
