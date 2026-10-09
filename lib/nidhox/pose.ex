defmodule Nidhox.Pose do
  @moduledoc """
  How a fencer looks this step, in the copy's own sprites: the body's sprite and frame,
  and the sword's.

  | the fencer | body | sword |
  | --- | --- | --- |
  | down | `sManLieOnBack`, played once | — |
  | knocked down | `sManFallOverForward`, lying on its last frame, then `sManGetUp` | — |
  | sweeping the leg | `sManSweepTheLeg`, over the sweep | `sSwordSweepTheLeg` |
  | tearing out a heart | `sManStomping`, over it | `sSwordStomping` |
  | divekicking | `sManDiveKick` | `sSwordDiveKick` |
  | ducking, crawling | `sManCrawl`, still or crawling | `sSwordCrawl` |
  | disarmed | `sManDisarmedUpAndBackward`, over it | — |
  | catching a sword | `sManCatchFalling`, over it | `sSwordCatchFalling` |
  | rolling | `sManJumpRoll`, over the roll | `sSwordJumpRoll` |
  | sliding | `sManSlide` | `sSwordSlide` |
  | hanging from a ledge | `sManHangOnEdgeIdle` | `sSwordHangOnEdgeIdle` |
  | climbing onto a ledge | `sManEdgeJump`, over the climb | `sSwordEdgeJump` |
  | running up a wall | `sManRunUpWall`, over the run | `sSwordRunUpWall` |
  | the second punch | `sManNoWeaponAttackPunchFollowup`, over it | — |
  | the uppercut | `sManUppercutJump`, over it | — |
  | throwing on the ground | `sManThrowStanding`, over the throw | `sSwordThrowStanding` |
  | throwing in the air | `sManThrowMidAir`, over the throw | — |
  | thrusting | `sManSwordAttack<stance>`, over the thrust | `sSword` at the hand |
  | punching | `sManNoWeaponAttackPunch`, over the punch | — |
  | rising | `sManJumpForward` | `sSwordJumpForward` |
  | falling | `sManFall` | `sSwordFall` |
  | running | `sManRun` | `sSwordRun` |
  | walking on guard, armed | `sManSwordForward<stance>` towards the way it faces, `sManSwordBackward<stance>` away | `sSword` at the hand |
  | walking unarmed | `sManNoWeaponForward`, `sManNoWeaponBackward` | — |
  | standing, armed | `sManSwordStand<stance>` | `sSword` at the hand |
  | standing unarmed | `sManNoWeaponStand` | — |

  `<stance>` is `Hi`, `Med` or `Lo`. A fencer without its sword has no sword, whatever
  the table says. Looping poses advance a frame every `@run_rate`, `@walk_rate`,
  `@stand_rate` or `@fall_rate` steps of the fencer's age; a move plays its frames once
  across its own length.

  The hand is the frontmost opaque pixel of the body's frame, the one nearest its top
  when several are; `sSword` is drawn from there.
  """

  alias Nidhox.{Assets, Climb, Fencer}

  @type sprite :: {String.t(), non_neg_integer()}
  @type t :: %{body: sprite(), sword: {:paired, sprite()} | {:hand, {number(), number()}} | nil}

  @run_rate 1
  @walk_rate 5
  @stand_rate 6
  @fall_rate 3
  @dead_rate 4
  @kick_rate 3
  @crawl_rate 6
  @slide_rate 3
  @running 1.5
  @walking 0.2

  @doc "The pose of `fencer`."
  @spec of(Fencer.t()) :: t()
  def of(%Fencer{action: :dead, age: age}),
    do: %{body: once("sManLieOnBack", div(age, @dead_rate)), sword: nil}

  def of(%Fencer{action: :floored, timer: timer}) do
    falling = 3 * Assets.frame_count("sManFallOverForward")
    rising = 3 * Assets.frame_count("sManGetUp")

    cond do
      timer < falling ->
        %{body: {"sManFallOverForward", over("sManFallOverForward", timer, falling)}, sword: nil}

      timer >= Fencer.floored_steps() - rising ->
        %{
          body:
            {"sManGetUp", over("sManGetUp", timer - (Fencer.floored_steps() - rising), rising)},
          sword: nil
        }

      true ->
        %{body: once("sManFallOverForward", falling), sword: nil}
    end
  end

  def of(%Fencer{action: :disarmed, timer: timer}),
    do: %{
      body:
        {"sManDisarmedUpAndBackward",
         over("sManDisarmedUpAndBackward", timer, Fencer.move_steps().disarmed)},
      sword: nil
    }

  def of(%Fencer{action: :catch, timer: timer}) do
    frame = over("sManCatchFalling", timer, Fencer.move_steps().catch)
    %{body: {"sManCatchFalling", frame}, sword: {:paired, {"sSwordCatchFalling", frame}}}
  end

  def of(%Fencer{action: :roll} = fencer) do
    frame = over("sManJumpRoll", fencer.timer, Fencer.move_steps().roll)
    %{body: {"sManJumpRoll", frame}, sword: paired(fencer, "sSwordJumpRoll", frame)}
  end

  def of(%Fencer{action: :slide} = fencer) do
    body = looped("sManSlide", div(fencer.age, @slide_rate))
    %{body: body, sword: paired(fencer, "sSwordSlide", 0)}
  end

  def of(%Fencer{action: :hang} = fencer) do
    body = looped("sManHangOnEdgeIdle", div(fencer.age, @stand_rate))
    %{body: body, sword: paired(fencer, "sSwordHangOnEdgeIdle", elem(body, 1))}
  end

  def of(%Fencer{action: :climb} = fencer) do
    frame = over("sManEdgeJump", fencer.timer, Climb.climb_steps())
    %{body: {"sManEdgeJump", frame}, sword: paired(fencer, "sSwordEdgeJump", frame)}
  end

  def of(%Fencer{action: :wallrun} = fencer) do
    frame = over("sManRunUpWall", fencer.timer, Climb.run_steps())
    %{body: {"sManRunUpWall", frame}, sword: paired(fencer, "sSwordRunUpWall", frame)}
  end

  def of(%Fencer{action: :punch2} = fencer) do
    name = "sManNoWeaponAttackPunchFollowup"
    %{body: {name, over(name, fencer.timer, Fencer.punch_steps())}, sword: nil}
  end

  def of(%Fencer{action: :uppercut} = fencer) do
    name = "sManUppercutJump"
    %{body: {name, over(name, fencer.timer, Fencer.punch_steps())}, sword: nil}
  end

  def of(%Fencer{action: :sweep} = fencer) do
    frame = over("sManSweepTheLeg", fencer.timer, Fencer.sweep_steps())
    %{body: {"sManSweepTheLeg", frame}, sword: paired(fencer, "sSwordSweepTheLeg", frame)}
  end

  def of(%Fencer{action: :heart} = fencer) do
    frame = over("sManStomping", fencer.timer, Fencer.heart_steps())
    %{body: {"sManStomping", frame}, sword: paired(fencer, "sSwordStomping", frame)}
  end

  def of(%Fencer{action: :divekick} = fencer) do
    body = looped("sManDiveKick", div(fencer.age, @kick_rate))
    %{body: body, sword: paired(fencer, "sSwordDiveKick", elem(body, 1))}
  end

  def of(%Fencer{action: :duck, velocity: {vx, _vy}} = fencer) do
    body =
      if abs(vx) > @walking,
        do: looped("sManCrawl", div(fencer.age, @crawl_rate)),
        else: {"sManCrawl", 0}

    %{body: body, sword: paired(fencer, "sSwordCrawl", elem(body, 1))}
  end

  def of(%Fencer{action: :throw, grounded: true} = fencer) do
    frame = over("sManThrowStanding", fencer.timer, Fencer.throw_steps())
    %{body: {"sManThrowStanding", frame}, sword: paired(fencer, "sSwordThrowStanding", frame)}
  end

  def of(%Fencer{action: :throw} = fencer),
    do: %{
      body: {"sManThrowMidAir", over("sManThrowMidAir", fencer.timer, Fencer.throw_steps())},
      sword: nil
    }

  def of(%Fencer{action: :thrust} = fencer) do
    name = "sManSwordAttack" <> stance(fencer.stance)
    body = {name, over(name, fencer.timer, Fencer.thrust_steps())}
    %{body: body, sword: hand(fencer, body)}
  end

  def of(%Fencer{action: :punch} = fencer) do
    name = "sManNoWeaponAttackPunch"
    %{body: {name, over(name, fencer.timer, Fencer.punch_steps())}, sword: nil}
  end

  def of(%Fencer{grounded: false, velocity: {_vx, vy}} = fencer) when vy < 0,
    do: %{body: {"sManJumpForward", 0}, sword: paired(fencer, "sSwordJumpForward", 0)}

  def of(%Fencer{grounded: false} = fencer) do
    body = looped("sManFall", div(fencer.age, @fall_rate))
    %{body: body, sword: paired(fencer, "sSwordFall", elem(body, 1))}
  end

  def of(%Fencer{velocity: {vx, _vy}} = fencer) when abs(vx) > @running do
    body = looped("sManRun", div(fencer.age, @run_rate))
    %{body: body, sword: paired(fencer, "sSwordRun", elem(body, 1))}
  end

  def of(%Fencer{velocity: {vx, _vy}, armed: true} = fencer) when abs(vx) > @walking do
    way = if sign(vx) == fencer.facing, do: "Forward", else: "Backward"
    body = looped("sManSword" <> way <> stance(fencer.stance), div(fencer.age, @walk_rate))
    %{body: body, sword: hand(fencer, body)}
  end

  def of(%Fencer{velocity: {vx, _vy}} = fencer) when abs(vx) > @walking do
    way = if sign(vx) == fencer.facing, do: "Forward", else: "Backward"
    %{body: {"sManNoWeapon" <> way, 0}, sword: nil}
  end

  def of(%Fencer{armed: true} = fencer) do
    body = looped("sManSwordStand" <> stance(fencer.stance), div(fencer.age, @stand_rate))
    %{body: body, sword: hand(fencer, body)}
  end

  def of(%Fencer{} = fencer),
    do: %{body: looped("sManNoWeaponStand", div(fencer.age, @stand_rate)), sword: nil}

  @doc "Every body sprite a pose may use."
  @spec bodies() :: [String.t()]
  def bodies do
    stances =
      for way <- ~w(Stand Forward Backward Attack),
          stance <- ~w(Hi Med Lo),
          do: "sManSword#{way}#{stance}"

    stances ++
      ~w(sManLieOnBack sManThrowStanding sManThrowMidAir sManNoWeaponAttackPunch sManJumpForward
         sManFall sManRun sManNoWeaponForward sManNoWeaponBackward sManNoWeaponStand
         sManFallOverForward sManGetUp sManSweepTheLeg sManStomping sManDiveKick sManCrawl
         sManDisarmedUpAndBackward sManCatchFalling sManJumpRoll sManSlide sManHangOnEdgeIdle
         sManEdgeJump sManRunUpWall sManNoWeaponAttackPunchFollowup sManUppercutJump)
  end

  defp paired(%Fencer{armed: true}, name, frame), do: {:paired, {name, rem(frame, frames(name))}}
  defp paired(_fencer, _name, _frame), do: nil

  defp hand(%Fencer{armed: true}, body), do: {:hand, Assets.hand(body)}
  defp hand(_fencer, _body), do: nil

  defp looped(name, count), do: {name, rem(count, frames(name))}
  defp once(name, count), do: {name, min(count, frames(name) - 1)}

  defp over(name, timer, steps) do
    count = frames(name)
    min(div(timer * count, max(steps, 1)), count - 1)
  end

  defp frames(name), do: Assets.frame_count(name)

  defp stance(:high), do: "Hi"
  defp stance(:middle), do: "Med"
  defp stance(:low), do: "Lo"

  defp sign(value) when value < 0, do: -1
  defp sign(_value), do: 1
end
