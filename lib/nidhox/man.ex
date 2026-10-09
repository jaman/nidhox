defmodule Nidhox.Man do
  @moduledoc """
  The game's fencer: `Man`, a `PhysicsObject`, and its `YellowPlayer` (player 1) and
  `OrangePlayer` (player 2). The fencer itself is invisible; its body is its
  `FleshCollisionMask` (`flesh`, `Nidhox.Man.Flesh`) and its weapon its `HeldWeapon`
  (`weapon`, `Nidhox.Objects.HeldWeapon`). The match runs it each frame as user event 2.

    * create: the physics variables; a body made where it stands, its `mother`; no
      weapon; on the ground; stance middle (3), facing right, entering the screen (23)
      with 180 steps to do it in; its collapse picked by `System.frame`
      (`collapseAnimation`, 208–210); `forceOutTimer` 120; the rest of its counters and
      flags 0. Yellow: player 1, its weapon a hidden `YellowHeldWeapon`, the match's
      `yellowInstance`. Orange: player 2 facing left, an `OrangeHeldWeapon`, the match's
      `orangeInstance`
    * user events 0 and 1: run into a wall, onto a floor or a ceiling
      (`Nidhox.Man.Physics.collide_x/2`, `collide_y/2`)
    * user event 2, its update: whether it crouched (`lastCrouched`); crouching (9, 58,
      10, 11) and not hurt it takes the low mask (270), else the full one (269); entering
      the screen too long (`timeEnteringScreen`) it runs (52); the physics begin step;
      `stairYModifier` 0; its next state (`Nidhox.Man.Enter`), its state's behaviour
      (`Nidhox.Man.Behave`) and friction (`Nidhox.Man.Friction`); the physics end step;
      its body brought to where it is; its weapon placed (`Nidhox.Man.Weapon.x_pos/2`,
      `y_pos/2`), set bouncing (`random_range(0, 1)`) when its height changed, facing its
      way, and — shown, off stairs — pushing it back 2 pixels when its blade's end is in
      a wall. Warping in (79) nothing more; otherwise, not collapsing, a `Smoosher` above
      its head pushes it down a pixel at a time while there is room below its feet and
      crushes it (66) when there is none, a `SpikeSmoosher` the same; every 120 steps
      (`forceOutTimer`) one stuck in a wall is put out of it (`force_out`) and falls
      (18); with the AI about, whether it stands on or in a log (`onLog`, `inLog`); in
      level 22 a cloud underfoot is `touched`
    * end step: with trails on, a fading copy of its body (`Trail`); every tenth
      `System.metaFrame` it is lifted out of any `Block` it is in
    * draw: while a blade it is stabbed on touches (`swordCollision`), the blade going in
      (`sSwordOverlay`) drawn where the blade is, its frame the depth (held to 0–16)
    * destroy: its body and weapon go with it; the match forgets it
  """

  alias Cauldron2D.GameMaker.{Collide, Draw, Instance, World}
  alias Nidhox.Bout.Variants
  alias Nidhox.Gml
  alias Nidhox.Man.{Behave, Enter, Friction, Physics, Push, Query, State, Weapon}
  alias Nidhox.Objects.System

  @noone -4
  @low_mask 270
  @full_mask 269
  @crouching [9, 58, 10, 11]
  @collapses [208, 209, 210, 369]
  @overlay 155
  @force_out_every 120

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_Man_Create_0", &start/3},
      {"gml_Object_YellowPlayer_Create_0", &player(&1, &2, &3, 1)},
      {"gml_Object_OrangePlayer_Create_0", &player(&1, &2, &3, 2)},
      {"gml_Object_Man_Other_10", fn world, self, _other -> Physics.collide_x(world, self) end},
      {"gml_Object_Man_Other_11", fn world, self, _other -> Physics.collide_y(world, self) end},
      {"gml_Object_Man_Other_12", &update/3},
      {"gml_Object_Man_Step_2", &end_step/3},
      {"gml_Object_Man_Draw_0", &draw/3},
      {"gml_Object_Man_Destroy_0", &finish/3},
      {"gml_Object_YellowPlayer_Destroy_0", &forget(&1, &2, &3, :yellowInstance)},
      {"gml_Object_OrangePlayer_Destroy_0", &forget(&1, &2, &3, :orangeInstance)}
    ]
  end

  defp start(world, self, _other) do
    world = World.inherited(world, self, "Man", :create, 0)
    %Instance{x: x, y: y} = World.fetch(world, self)
    {world, flesh} = World.create(world, World.object_index(world, "FleshCollisionMask"), {x, y})
    collapse = Enum.at(@collapses, cycle(Gml.round(System.get(world, :frame)), 0, 3))

    world
    |> Gml.put(flesh, %{mother: self})
    |> Gml.put(self, %{
      playerIndex: -1,
      flesh: flesh,
      weapon: @noone,
      onGround: 1,
      pOnGround: 0,
      inBetweenHeight: 0,
      runButtonHeldCounter: 0,
      lastStepFrame: -1,
      collapseAnimation: collapse,
      timeEnteringScreen: 180,
      swordCollision: 0,
      swordX: 0,
      swordY: 0,
      prevSwordY: 0,
      swordXScale: 1,
      frame: 0,
      state: 23,
      nextState: -1,
      stance: 3,
      facingXScale: 1,
      buttonHeldCounter: 0,
      knockDowns: 0,
      hitFlag: 0,
      stabCounter: 0,
      fallOverHits: 2,
      turnAroundFlag: 0,
      turnAroundTimer: 0,
      stairYModifier: 0,
      forceOutTimer: @force_out_every,
      lastCrouched: 0,
      stateCounter: 0
    })
    |> logs(self)
  end

  defp player(world, self, _other, index) do
    weapon_object = if index == 1, do: "YellowHeldWeapon", else: "OrangeHeldWeapon"
    slot = if index == 1, do: :yellowInstance, else: :orangeInstance
    world = World.inherited(world, self, World.object(world, World.fetch(world, self).object).name, :create, 0)
    world = Gml.put(world, self, %{playerIndex: index})
    world = if index == 2, do: Gml.put(world, self, %{facingXScale: -1}), else: world
    world = with_match(world, &Gml.put(&1, &2, %{slot => self}))
    %Instance{x: x, y: y} = World.fetch(world, self)
    {world, weapon} = World.create(world, World.object_index(world, weapon_object), {x, y})

    world
    |> Gml.put(self, %{weapon: weapon})
    |> Gml.put(weapon, %{mother: self})
    |> World.update(weapon, &%{&1 | visible: false})
  end

  defp update(world, self, _other) do
    world =
      world
      |> State.put(self, %{lastCrouched: if(Query.ducking?(world, self), do: 1, else: 0)})
      |> mask(self)
      |> entering_timer(self)
      |> Physics.begin_step(self)
      |> State.put(self, %{stairYModifier: 0})
      |> Enter.process(self)

    world = Behave.run(world, self, State.get(world, self, :state))

    if World.fetch(world, self) do
      world
      |> Friction.apply(self)
      |> Physics.end_step(self)
      |> while_here(self, &after_moving/2)
    else
      world
    end
  end

  defp after_moving(world, self) do
    world = world |> carry_body(self) |> place_weapon(self)

    if State.get(world, self, :state) == 79 do
      world
    else
      world
      |> crush(self)
      |> force_out(self)
      |> logs(self)
      |> touch_cloud(self)
    end
  end

  defp while_here(world, self, fun), do: if(World.fetch(world, self), do: fun.(world, self), else: world)

  defp mask(world, self) do
    crouching =
      State.get(world, self, :state) in @crouching and
        not (Query.collapsing?(world, self) or Query.stabbed?(world, self))

    case World.fetch(world, self) do
      _ when crouching -> World.update(world, self, &%{&1 | mask_index: @low_mask})
      %Instance{mask_index: @low_mask} -> stand_up(world, self)
      _ -> world
    end
  end

  defp stand_up(world, self) do
    world = World.update(world, self, &%{&1 | mask_index: @full_mask})

    Enum.reduce_while(1..30, world, fn _try, world ->
      %Instance{x: x, y: y} = World.fetch(world, self)

      if meeting?(world, self, {x, y}, "Block"),
        do: {:cont, World.update(world, self, &%{&1 | y: Float.floor(&1.y * 1.0)})},
        else: {:halt, world}
    end)
  end

  defp entering_timer(world, self) do
    if State.get(world, self, :state) == 23 do
      left = State.get(world, self, :timeEnteringScreen) - 1
      world = State.put(world, self, %{timeEnteringScreen: left})
      if Gml.truthy?(left), do: world, else: State.go(world, self, 52)
    else
      world
    end
  end

  defp carry_body(world, self) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    case State.get(world, self, :flesh) do
      @noone -> world
      flesh -> World.update(world, flesh, &%{&1 | x: x, y: y})
    end
  end

  defp place_weapon(world, self) do
    weapon = State.get(world, self, :weapon)

    case World.fetch(world, weapon) do
      nil -> world
      %Instance{y: before} -> hold(world, self, weapon, before)
    end
  end

  defp hold(world, self, weapon, before) do
    world = World.update(world, weapon, &%{&1 | x: Weapon.x_pos(world, self)})
    {y, world} = Weapon.y_pos(world, self)
    world = World.update(world, weapon, &%{&1 | y: y})

    world =
      if Gml.eq?(y, before) do
        world
      else
        {bounce, world} = Gml.random_range(world, 0, 1)
        Gml.put(world, weapon, %{bounce: bounce})
      end

    facing = State.get(world, self, :facingXScale)
    world = World.update(world, weapon, &%{&1 | image_xscale: facing})
    blade_in_wall(world, self, weapon, facing)
  end

  defp blade_in_wall(world, self, weapon, facing) do
    %Instance{x: x, y: y, visible: visible} = blade = World.fetch(world, weapon)

    if visible and not on_stairs?(world, self) and
         Physics.block_at?(world, {x + sprite_width(world, blade) * 0.9, y}),
       do: world |> Push.force_shift(self, -facing * 2) |> elem(1),
       else: world
  end

  defp crush(world, self) do
    if Query.collapsing?(world, self) do
      world
    else
      height = sprite_height(world, @full_mask)
      height = if Query.crouched?(world, self), do: height * 0.5, else: height

      world
      |> smoosher(self, height, "Smoosher", height)
      |> smoosher(self, height, "SpikeSmoosher", sprite_height(world, @full_mask))
    end
  end

  defp smoosher(world, self, height, name, tries) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    case at_point(world, {x, y - height}, name) do
      nil -> world
      smoosher -> squash(world, self, height, smoosher, 0, tries)
    end
  end

  defp squash(world, _self, _height, _smoosher, count, tries) when count >= tries, do: world

  defp squash(world, self, height, smoosher, count, tries) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    if Collide.at_point(world, {x, y - height}, {:id, smoosher}) != nil do
      world =
        if room_below?(world, self, smoosher),
          do: world |> World.update(self, &%{&1 | y: &1.y + 1}) |> pressed_down(self, smoosher),
          else: State.go(world, self, 66)

      squash(world, self, height, smoosher, count + 1, tries)
    else
      world
    end
  end

  defp pressed_down(world, self, smoosher) do
    if World.object(world, World.fetch(world, smoosher).object).name == "Smoosher",
      do: State.put(world, self, %{vspd: 0, onGround: 0}),
      else: State.put(world, self, %{vspd: 0})
  end

  defp room_below?(world, self, smoosher) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    if World.object(world, World.fetch(world, smoosher).object).name == "Smoosher" do
      left = bbox_side(world, :left)
      right = bbox_side(world, :right)
      not Physics.block_at?(world, {x + left, y + 2}) and not Physics.block_at?(world, {x + right, y + 2})
    else
      not Physics.block_at?(world, {x, y + 2})
    end
  end

  defp force_out(world, self) do
    timer = State.get(world, self, :forceOutTimer) - 1

    if timer < 0 do
      world = State.put(world, self, %{forceOutTimer: 1})
      %Instance{x: x, y: y} = World.fetch(world, self)

      if State.get(world, self, :state) != 23 and meeting?(world, self, {x, y}, "Block"),
        do: world |> Physics.force_out(self) |> State.go(self, 18),
        else: world
    else
      State.put(world, self, %{forceOutTimer: timer})
    end
  end

  defp logs(world, self) do
    if exists?(world, "Brain") do
      %Instance{x: x, y: y} = World.fetch(world, self)

      State.put(world, self, %{
        onLog: if(at_point(world, {x, y - 8}, "TopOfLog"), do: 1, else: 0),
        inLog: if(at_point(world, {x, y - 8}, "InsideLog"), do: 1, else: 0)
      })
    else
      world
    end
  end

  defp touch_cloud(world, self) do
    if State.get(world, self, :state) != 23 and System.get(world, :level) == 22 do
      %Instance{x: x, y: y} = World.fetch(world, self)

      case at_point(world, {x - 2, y + 1}, "NewCloudBlock") || at_point(world, {x + 2, y + 1}, "NewCloudBlock") do
        nil -> world
        cloud -> Gml.put(world, cloud, %{touched: 1})
      end
    else
      world
    end
  end

  defp end_step(world, self, _other) do
    world
    |> trail(self)
    |> lift_when_stuck(self)
  end

  defp trail(world, self) do
    if Variants.active?(world) and Gml.truthy?(System.get(world, :trails)) do
      %Instance{x: x, y: y} = World.fetch(world, self)
      body = World.fetch(world, State.get(world, self, :flesh))
      {world, trail} = World.create(world, World.object_index(world, "Trail"), {x, y})

      World.update(world, trail, fn trail ->
        %{
          trail
          | sprite_index: body.sprite_index,
            image_index: body.image_index,
            image_speed: 0.0,
            image_blend: body.image_blend,
            image_xscale: body.image_xscale
        }
      end)
    else
      world
    end
  end

  defp lift_when_stuck(world, self) do
    if rem(trunc(System.get(world, :metaFrame)), 10) == 0 and exists?(world, "Block"),
      do: lift(world, self),
      else: world
  end

  defp lift(world, self) do
    %Instance{x: x, y: y} = World.fetch(world, self)

    if meeting?(world, self, {x, y}, "Block"),
      do: world |> World.update(self, &%{&1 | y: Float.floor(&1.y * 1.0) - 1}) |> lift(self),
      else: world
  end

  defp draw(world, self, _other) do
    if not Query.collapsing?(world, self) and not Query.stabbed?(world, self) and
         Gml.truthy?(State.get(world, self, :swordCollision)) do
      %Instance{x: x} = World.fetch(world, self)
      depth = Gml.clamp(abs(State.get(world, self, :swordX) - x) - 4, 0, 16)

      Draw.sprite(world, @overlay, Gml.round(depth), {State.get(world, self, :swordX), State.get(world, self, :swordY)},
        scale: {State.get(world, self, :swordXScale), 1},
        angle: 0,
        blend: {255, 255, 255},
        alpha: 1
      )
    else
      world
    end
  end

  defp finish(world, self, _other) do
    [State.get(world, self, :flesh), State.get(world, self, :weapon)]
    |> Enum.reduce(world, fn id, world -> if World.fetch(world, id), do: World.destroy(world, id), else: world end)
  end

  defp forget(world, self, _other, slot) do
    world
    |> with_match(&Gml.put(&1, &2, %{slot => @noone}))
    |> World.inherited(self, World.object(world, World.fetch(world, self).object).name, :destroy, 0)
  end

  defp with_match(world, fun) do
    with object when is_integer(object) <- World.object_index(world, "Match"),
         [match | _] <- World.instances_of(world, object) do
      fun.(world, match)
    else
      _none -> world
    end
  end

  defp on_stairs?(world, self), do: State.get(world, self, :state) in [30, 31]

  defp exists?(world, name) do
    case World.object_index(world, name) do
      nil -> false
      object -> World.instances_of(world, object) != []
    end
  end

  defp at_point(world, point, name) do
    case World.object_index(world, name) do
      nil -> nil
      object -> Collide.at_point(world, point, object)
    end
  end

  defp meeting?(world, self, position, name) do
    case World.object_index(world, name) do
      nil -> false
      object -> Collide.meeting?(world, self, position, object)
    end
  end

  defp sprite_height(world, sprite) do
    case World.sprite(world, sprite) do
      nil -> 0
      definition -> elem(definition.size, 1)
    end
  end

  defp bbox_side(world, side) do
    case World.sprite(world, @full_mask) do
      nil ->
        0

      definition ->
        {left, _top, right, _bottom} = definition.box
        {origin_x, _origin_y} = definition.origin
        if side == :left, do: left - origin_x, else: right - origin_x
    end
  end

  defp sprite_width(world, %Instance{sprite_index: sprite, image_xscale: xscale}) do
    case World.sprite(world, sprite) do
      nil -> 0
      definition -> elem(definition.size, 0) * xscale
    end
  end

  defp cycle(value, low, high) do
    range = high - low
    offset = :math.fmod((value - low) * 1.0, range * 1.0)
    trunc(if(offset < 0, do: offset + range, else: offset) + low)
  end
end
