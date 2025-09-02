defmodule MiniJobs.MixProject do
  use Mix.Project

  def project do
    [
      app: :mini_jobs,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {MiniJobs.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug_cowboy, "~> 2.0"},
      {:plug, "~> 1.14"},
      {:jason, "~> 1.4"},
      # {:uuid, "~> 1.8"}, # Temporarily disabled
      {:telemetry, "~> 1.2"}
    ]
  end
end
