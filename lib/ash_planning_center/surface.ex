defmodule AshPlanningCenter.Surface do
  @moduledoc """
  Design-for-Complementary-Maximalism composition for Planning Center surfaces.

  Ash remains domain truth. `ash_surface` owns accessibility observation,
  `ash_a2a` owns machine capability projection, and `ash_pplan` owns formal
  planning admission. This module composes those owners without acquiring
  browser mutation, planner execution, or external DO authority.
  """

  alias AshPlanningCenter.Generated.Surface.Contract

  @observation_transitions %{
    unobserved: %{observe: [:observed, :refused]},
    observed: %{},
    refused: %{}
  }
  @observation_goals [:observed, :refused]
  @observation_policy %{unobserved: :observe}

  @spec metadata() :: map()
  def metadata, do: Contract.metadata()

  @spec probe(String.t() | atom(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, %{code: :unsupported_probe_kind, detail: String.t()}}
  def probe(kind, id, accessible_name, opts \\ []) do
    Contract.probe(kind, id, accessible_name, opts)
  end

  @doc "Constructs an AshSurface observation from already-observed facts; no browser is run here."
  @spec observation(String.t(), map(), keyword()) :: AshSurface.Observation.t()
  def observation(exact_subject, facts, opts \\ [])
      when is_binary(exact_subject) and is_map(facts) do
    opts =
      Keyword.put_new(opts, :projection_purpose, "planning_center_accessibility_surface")

    AshSurface.Observation.create(exact_subject, facts, opts)
  end

  @doc "Returns machine capabilities derived from canonical public Ash actions."
  @spec a2a_capabilities() :: [AshA2A.CapabilityIndex.skill()]
  def a2a_capabilities do
    AshA2A.Info.capability_index!(AshPlanningCenter.Domain)
  end

  @doc "Validates the observation-only nondeterministic policy through AshPPlan."
  @spec observation_policy() :: {:ok, map()} | {:error, term()}
  def observation_policy do
    with {:ok, domain} <- AshPPlan.fond_domain(@observation_transitions, @observation_goals),
         {:ok, validation} <-
           AshPPlan.validate_policy(domain, @observation_policy, :unobserved, :strong) do
      {:ok,
       %{
         domain: domain,
         policy: @observation_policy,
         validation: validation,
         authority_boundary: :OBSERVE
       }}
    end
  end

  @doc "Returns ash_surface's canonical Playwright accessibility observer path."
  @spec playwright_adapter_path() :: String.t()
  def playwright_adapter_path do
    Application.app_dir(:ash_surface, "priv/static/ash_surface_playwright.mjs")
  end
end
