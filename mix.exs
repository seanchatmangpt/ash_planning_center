defmodule AshPlanningCenter.MixProject do
  use Mix.Project

  @version "26.9.10"
  @source_url "https://github.com/seanchatmangpt/ash_planning_center"

  def project do
    [
      app: :ash_planning_center,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Ash-native resources and actions over the Planning Center API",
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:ash, "~> 3.33"},
      {:req, "~> 0.7.4"}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE)
    ]
  end
end
