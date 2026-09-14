defmodule AshPlanningCenter.SurfaceContractTest do
  use ExUnit.Case, async: true

  alias AshPlanningCenter.Generated.Surface.Contract
  alias AshPlanningCenter.Surface

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
