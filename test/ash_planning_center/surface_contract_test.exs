defmodule AshPlanningCenter.SurfaceContractTest do
  use ExUnit.Case, async: true

  alias AshPlanningCenter.Generated.Surface.Contract

  test "ontology-manufactured contract preserves surface/planner authority ceilings" do
    assert Contract.metadata() == %{
             "specVersion" => "26.9.13",
             "surfaceRuntime" => "ash_surface",
             "observer" => "playwright_accessibility",
             "plannerBoundary" => "ash_a2a",
             "planningFormalism" => "hddl_fond",
             "authorityBoundary" => "OBSERVE"
           }
  end

  test "Planning Center link probes compile to accessibility semantics, not selectors" do
    probe =
      Contract.probe(:link, "marketplace-registration", "Register",
        denotes: "planning-center:event:marketplace",
        capability_id: "PlanningCenter.Event.observe_registration"
      )

    assert probe["role"] == "link"
    assert probe["name"] == "Register"
    assert probe["roleSpec"] == "https://www.w3.org/TR/wai-aria/#link"
    assert probe["authorityBoundary"] == "OBSERVE"
    assert probe["surfaceRuntime"] == "ash_surface"
    assert probe["observer"] == "playwright_accessibility"
    assert probe["plannerBoundary"] == "ash_a2a"
    refute Map.has_key?(probe, "selector")
    refute Map.has_key?(probe, "xpath")
  end

  test "unknown probe kinds are refused instead of guessed" do
    assert_raise KeyError, fn ->
      Contract.probe(:css_selector, "brittle", "#app > div:nth-child(7)")
    end
  end
end
