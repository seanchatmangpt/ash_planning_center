defmodule AshPlanningCenter.MixProject do
  use Mix.Project

  @version "26.9.13"
  @source_url "https://github.com/seanchatmangpt/ash_planning_center"
  @ash_surface_ref "7d5492795d9b9a0956f51545ed1ad1932768b77e"
  @ash_a2a_ref "faa86055591cdf2bda867a4c033b8b6f18b79780"
  @ash_pplan_ref "d35f6298e8bd4683c36018180afac1b17dfeaa97"
  @ggen_igniter_ref "6b9baecf6d40d4357702526524e8a4a13c1c1c8d"

  def project do
    [
      app: :ash_planning_center,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: "Ash-native resources and actions over the Planning Center API",
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp aliases do
    [
      generate: [
        "ash_planning_center.generate",
        "ash_planning_center.generate_surface"
      ]
    ]
  end

  defp deps do
    [
      {:ash, "~> 3.33"},
      {:ash_surface, github: "seanchatmangpt/ash_surface", ref: @ash_surface_ref},
      {:ash_a2a, github: "seanchatmangpt/ash_a2a", ref: @ash_a2a_ref},
      {:ash_pplan, github: "seanchatmangpt/ash_pplan", ref: @ash_pplan_ref},
      {:req, "~> 0.7.4"},
      {:jason, "~> 1.4"},
      {:ggen_igniter,
       github: "seanchatmangpt/ggen_igniter", ref: @ggen_igniter_ref, override: true}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv mix.exs README.md LICENSE)
    ]
  end
end
