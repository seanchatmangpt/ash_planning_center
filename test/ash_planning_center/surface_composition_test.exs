defmodule AshPlanningCenter.SurfaceCompositionTest do
  use ExUnit.Case, async: true

  alias AshPlanningCenter.Surface

  test "AshSurface owns content-addressed OBSERVE projections" do
    observation =
      Surface.observation(
        "https://churchcenter.com/example",
        %{"title" => "Marketplace", "httpStatus" => 200},
        observed_at: ~U[2026-09-13 20:00:00Z]
      )

    assert %AshSurface.Observation{
             exact_subject: "https://churchcenter.com/example",
             authority_boundary: :OBSERVE,
             projection_purpose: "planning_center_accessibility_surface"
           } = observation

    assert AshSurface.Observation.to_map(observation)["authorityBoundary"] == "OBSERVE"
  end

  test "AshA2A derives machine capabilities from canonical public Ash reads" do
    capabilities = Surface.a2a_capabilities()
    ids = MapSet.new(capabilities, & &1.id)

    assert MapSet.subset?(
             MapSet.new([
               "AshPlanningCenter.People.Person.get",
               "AshPlanningCenter.People.Person.read"
             ]),
             ids
           )

    assert Enum.all?(capabilities, &(&1.action in [:get, :read]))
  end

  test "AshPPlan admits the nondeterministic observation policy without DO" do
    assert {:ok,
            %{
              policy: %{unobserved: :observe},
              validation: validation,
              authority_boundary: :OBSERVE
            }} = Surface.observation_policy()

    assert is_map(validation)
  end

  test "Playwright remains owned by ash_surface" do
    path = Surface.playwright_adapter_path()

    assert File.regular?(path)
    assert String.ends_with?(path, "ash_surface_playwright.mjs")
  end
end
