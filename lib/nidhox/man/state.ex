defmodule Nidhox.Man.State do
  @moduledoc """
  What a fencer's states read and do, in the words their code uses:

    * `down?/3` and `pressed?/3`: the fencer's player's button held now, or just pressed
      (`checkPlayerIndexButtonDown`, `checkPlayerIndexButtonPressed`); buttons as
      `Nidhox.Bout.Input` numbers them
    * `combo?/2`: the throw combination (`checkPlayerIndexCombo(player, 0)`)
    * `go/3`: the state to take next step (`set_nextState`)
    * `stand/2`: fencing (29) with a sword, the unarmed stance (78) without
    * `pose/3`: the body's sprite (`setFleshSprite`); `animate/4`: the body's frame moved
      on (`frameSpeedLoop`), with whether it went past the last frame
    * `on_ground?/2`, `armed?/2` (a weapon that is not fists), `type/2`
      (`get_weapon_type`), `hspd/2`, `get/3`, `put/3`
    * `sound/3`: a sound where the fencer stands
  """

  alias Cauldron2D.GameMaker.World
  alias Nidhox.Bout.Input
  alias Nidhox.Gml
  alias Nidhox.Man.{Actions, Flesh, Physics}

  @fencing 29
  @unarmed 78

  @doc "Whether fencer `self`'s player holds `button`."
  @spec down?(World.t(), non_neg_integer(), non_neg_integer()) :: boolean()
  def down?(world, self, button), do: Input.down?(world, self, player(world, self), button)

  @doc "Whether fencer `self`'s player just pressed `button`."
  @spec pressed?(World.t(), non_neg_integer(), non_neg_integer()) :: boolean()
  def pressed?(world, self, button), do: Input.pressed?(world, self, player(world, self), button)

  @doc "Whether fencer `self`'s player made the throw combination."
  @spec combo?(World.t(), non_neg_integer()) :: boolean()
  def combo?(world, self), do: Actions.combo?(world, self, player(world, self))

  @doc "The world with fencer `self` to take `state` next step."
  @spec go(World.t(), non_neg_integer(), integer()) :: World.t()
  def go(world, self, state), do: Physics.next_state(world, self, state)

  @doc "The world with fencer `self` to take its standing state next step."
  @spec stand(World.t(), non_neg_integer()) :: World.t()
  def stand(world, self),
    do: go(world, self, if(armed?(world, self), do: @fencing, else: @unarmed))

  @doc "The world with fencer `self`'s body in sprite `sprite`."
  @spec pose(World.t(), non_neg_integer(), integer()) :: World.t()
  def pose(world, self, sprite), do: Flesh.set_sprite(world, self, sprite)

  @doc "`{went_past, world}` with fencer `self`'s frame moved on by `speed`."
  @spec animate(World.t(), non_neg_integer(), number(), boolean()) :: {boolean(), World.t()}
  def animate(world, self, speed, loop), do: Flesh.frame_speed_loop(world, self, speed, loop)

  @doc "Whether fencer `self` stands on something."
  @spec on_ground?(World.t(), non_neg_integer()) :: boolean()
  def on_ground?(world, self), do: Gml.truthy?(Gml.var(world, self, :onGround))

  @doc "Fencer `self`'s weapon type: 1 fists, 2 sword."
  @spec type(World.t(), non_neg_integer()) :: number()
  def type(world, self), do: Physics.weapon_type(world, self)

  @doc "Whether fencer `self` holds something other than its fists."
  @spec armed?(World.t(), non_neg_integer()) :: boolean()
  def armed?(world, self), do: type(world, self) != 1

  @doc "Fencer `self`'s horizontal speed."
  @spec hspd(World.t(), non_neg_integer()) :: number()
  def hspd(world, self), do: Gml.var(world, self, :hspd)

  @doc "Fencer `self`'s variable `name`."
  @spec get(World.t(), non_neg_integer(), atom()) :: term()
  def get(world, self, name), do: Gml.var(world, self, name)

  @doc "The world with fencer `self`'s variables in `values` set."
  @spec put(World.t(), non_neg_integer(), map()) :: World.t()
  def put(world, self, values), do: Gml.put(world, self, values)

  @doc "The world with sound `sound` played where fencer `self` stands."
  @spec sound(World.t(), non_neg_integer(), non_neg_integer()) :: World.t()
  def sound(world, self, sound), do: Actions.play(world, self, sound)

  defp player(world, self), do: Gml.var(world, self, :playerIndex)
end
