defmodule Nidhox.MixProject do
  use Mix.Project

  def project do
    [
      app: :nidhox,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      description:
        "NidhOX: a two-player fencing game played from your own copy of the game's files, on Cauldron.",
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {Nidhox.Application, []}]
  end

  defp deps do
    [
      {:cauldron_2d, path: "../cauldron/cauldron_2d", override: true},
      {:cauldron_2d_gamemaker, path: "../cauldron/cauldron_2d_gamemaker"},
      {:cauldron_2d_drafter, path: "../cauldron/cauldron_2d_drafter"},
      {:linocut, path: "../cauldron/linocut", override: true},
      {:drafter, path: "../drafter", override: true},
      {:french_curve, path: "../french_curve", override: true},
      {:tuning_fork, path: "../tuning_fork/tuning_fork", override: true},
      {:tuning_fork_speaker, path: "../tuning_fork/tuning_fork_speaker"},
      {:gamepad, path: "../gamepad"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
