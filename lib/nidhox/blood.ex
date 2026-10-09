defmodule Nidhox.Blood do
  @moduledoc """
  Blood, in the colour of the fencer it comes from (`Nidhox.Look.colour/1`), as
  particles of the copy's sprites.

  A kill (`{:killed, killer, victim}` among a step's events) sprays `sBloodEffect` from
  the victim's chest, `@chest` pixels above its feet, the way the killer faces, playing
  its frames over `@spray_life` steps; and throws `@drops` drops, `@drop_size` pixels square, from there, each at
  a speed and angle drawn from the step and its number, falling under `@gravity` for
  `@drop_life` steps, as particles of kind `:blood_drop` (`Nidhox.Objects.Stains`).
  """

  alias Cauldron2D.GameMaker.Particles
  alias Cauldron2D.GameMaker.World
  alias Nidhox.{Assets, Look, Match}

  @chest 15
  @spray_life 24
  @drops 10
  @drop_life 40
  @drop_size 2
  @gravity 0.2
  @depth -102

  @doc "`world` with the blood of every kill among `match`'s events this step."
  @spec spill(World.t(), Match.t()) :: World.t()
  def spill(%World{} = world, %Match{events: events, fencers: fencers, frame: frame}) do
    for {:killed, killer, victim} <- events, reduce: world do
      world ->
        spray(world, fencers[killer].facing, fencers[victim].position, Look.colour(victim), frame)
    end
  end

  defp spray(world, facing, {x, y}, colour, frame) do
    {spray, %{frames: frames}} = Assets.sprite!("sBloodEffect")
    chest = {x, y - @chest}

    world =
      Particles.create(world, %{
        sprite: spray,
        position: chest,
        life: @spray_life,
        frame_speed: length(frames) / @spray_life,
        scale: {facing, 1},
        blend: colour,
        depth: @depth
      })

    for number <- 1..@drops, reduce: world do
      world ->
        speed = 1.0 + :erlang.phash2({frame, number, :speed}, 30) / 10
        rise = -(:erlang.phash2({frame, number, :rise}, 30) / 10)

        Particles.create(world, %{
          picture: :pixel,
          scale: {@drop_size, @drop_size},
          kind: :blood_drop,
          position: chest,
          velocity: {facing * speed, rise},
          gravity: {0.0, @gravity},
          life: @drop_life,
          blend: colour,
          depth: @depth
        })
    end
  end
end
