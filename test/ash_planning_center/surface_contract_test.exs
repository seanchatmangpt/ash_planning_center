defmodule AshPlanningCenter.SurfaceContractTest do
  use ExUnit.Case, async: true

  alias AshPlanningCenter.Generated.Surface.Contract

  test "ontology-manufactured contract preserves complementary ownership and OBSERVE ceiling" do
    assert %{
             "specVersion" => "26.9.13",
             "surfaceRuntime" => "ash_surface",
             "observer" => "playwright_accessibility",
             "plannerBoundary" => "ash_a2a",
             "planningFormalism" => "hddl_fond",
             "authorityBoundary" => "OBSERVE",
             "frameworks" => frameworks,
             "exclusions" => exclusions
           } = Contract.metadata()

    assert frameworks == %{
             "ash" => %{"role" => "domain_action_truth", "authorityBoundary" => "OBSERVE"},
             "ash_a2a" => %{
               "role" => "machine_capability_projection",
               "authorityBoundary" => "OBSERVE"
             },
             "ash_pplan" => %{
               "role" => "fond_hddl_admission",
               "authorityBoundary" => "OBSERVE"
             },
             "ash_surface" => %{
               "role" => "accessibility_observation_runtime",
               "authorityBoundary" => "OBSERVE"
             }
           }

    assert Map.keys(exclusions) |> Enum.sort() ==
             ~w(ash_ai ash_oban ash_r2rml ash_state_machine reactor)
  end

  test "Planning Center link probes compile to accessibility semantics, not selectors" do
    assert {:ok, probe} =
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

  test "selector and XPath probe kinds are typed refusals instead of guessed locators" do
    for kind <- [:css_selector, :xpath] do
      assert {:error, %{code: :unsupported_probe_kind, detail: detail}} =
               Contract.probe(kind, "brittle", "non-semantic locator")

      assert detail == Atom.to_string(kind)
    end
  end
end
