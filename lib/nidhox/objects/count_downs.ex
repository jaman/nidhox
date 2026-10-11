defmodule Nidhox.Objects.CountDowns do
  @moduledoc """
  The tournament's two countdowns, as the game runs them.

    * `CountDownToStart`, in `rPreMatch` before every tournament match:
        * create: `timer` 540; `System.flow` 4890734, the warm-up's, in which the match
          keeps nobody leading and its clock full (`Nidhox.Bout.Frame`); a `Match`
          made, so the players can fight while they wait
        * step: `timer` counts down; below 0 the warm-up's match is gone, `System.flow`
          is 3 and the tournament's match starts (`Nidhox.Objects.Match.start_match/1`)
        * draw: "players find your controller" at (160, 40) and "starting match in N..."
          at (160, 100), `N` being `round(timer / 60)`, white in `fMenu`, centred
    * `CountDownToQuit`, in `rShowChampion`:
        * create: `timer` 600
        * step: `timer` counts down; once it is below 0, or on `inputdog` 10, the
          `Tournament` is gone and the main menu (`rMainMenu`) gone to
  """

  alias Cauldron2D.GameMaker.{Data, Draw, World}
  alias Nidhox.Gml
  alias Nidhox.Objects.{Arcade, Match}

  @start_steps 540
  @quit_steps 600
  @warm_up_flow 4_890_734
  @tournament_flow 3
  @font "fMenu"
  @find_at {160, 40}
  @starting_at {160, 100}
  @steps_a_second 60

  @doc "The compiled names this module answers for, with their functions."
  @spec handlers() :: [{String.t(), Cauldron2D.GameMaker.Code.handler()}]
  def handlers do
    [
      {"gml_Object_CountDownToStart_Create_0", &start_create/3},
      {"gml_Object_CountDownToStart_Step_0", &start_step/3},
      {"gml_Object_CountDownToStart_Draw_0", &start_draw/3},
      {"gml_Object_CountDownToQuit_Create_0",
       fn world, self, _other -> Gml.put(world, self, %{timer: @quit_steps}) end},
      {"gml_Object_CountDownToQuit_Step_0", &quit_step/3}
    ]
  end

  defp start_create(world, self, _other) do
    world = world |> Gml.put(self, %{timer: @start_steps}) |> put_flow(@warm_up_flow)
    {_match, world} = Match.create(world)
    world
  end

  defp start_step(world, self, _other) do
    timer = Gml.var(world, self, :timer) - 1
    world = Gml.put(world, self, %{timer: timer})

    if timer < 0 do
      world
      |> kill_all("Match")
      |> put_flow(@tournament_flow)
      |> Match.start_match()
    else
      world
    end
  end

  defp start_draw(world, self, _other) do
    seconds = (Gml.var(world, self, :timer) / @steps_a_second) |> Float.round() |> trunc()

    world
    |> Draw.text(@font, "players find your controller", @find_at,
      halign: :center,
      valign: :middle
    )
    |> Draw.text(@font, "starting match in #{seconds}...", @starting_at,
      halign: :center,
      valign: :middle
    )
  end

  defp quit_step(world, self, _other) do
    timer = Gml.var(world, self, :timer) - 1
    world = Gml.put(world, self, %{timer: timer})

    if timer >= 0 and not Arcade.pressed?(world, 10) do
      world
    else
      world
      |> kill_all("Tournament")
      |> World.goto(Data.index(world.data, :rooms, "rMainMenu"))
    end
  end

  defp put_flow(world, flow) do
    case Gml.first(world, "System") do
      nil -> world
      system -> Gml.put(world, system, %{flow: flow})
    end
  end

  defp kill_all(world, name),
    do: world |> Gml.all(name) |> Enum.reduce(world, &World.destroy(&2, &1))
end
