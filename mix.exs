defmodule Nidhox.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/jaman/nidhox"

  def project do
    [
      app: :nidhox,
      version: @version,
      elixir: "~> 1.18",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      description:
        "NidhOX: a two-player fencing game played from your own copy of the game's files, on Cauldron.",
      source_url: @source_url,
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {Nidhox.Application, []}]
  end

  defp package do
    [
      licenses: ["GPL-2.0-or-later"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs .formatter.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v" <> @version,
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  defp deps do
    [
      family(:cauldron_2d, "~> 0.3.0", "../cauldron/cauldron_2d", override: true),
      family(:cauldron_2d_gamemaker, "~> 0.3.0", "../cauldron/cauldron_2d_gamemaker", []),
      family(:cauldron_2d_drafter, "~> 0.3.0", "../cauldron/cauldron_2d_drafter", []),
      family(:cauldron_gpu, "~> 0.3.0", "../cauldron/cauldron_gpu", []),
      family(:linocut, "~> 0.3.0", "../cauldron/linocut", override: true),
      family(:drafter, "~> 0.5.6", "../drafter", override: true),
      family(:french_curve, "~> 0.2.1", "../french_curve", override: true),
      family(:tuning_fork, "~> 0.1.13", "../tuning_fork/tuning_fork", override: true),
      family(:tuning_fork_speaker, "~> 0.1.13", "../tuning_fork/tuning_fork_speaker", []),
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp family(app, requirement, path, opts) do
    if System.get_env("PLUMB_HEX") == nil and File.dir?(path),
      do: {app, [path: path] ++ opts},
      else: {app, requirement, Keyword.delete(opts, :override)}
  end
end
