defmodule Mix.Tasks.AshPlanningCenter.GenerateSurface do
  @shortdoc "Manufactures the Planning Center accessibility surface contract"
  @moduledoc """
  Projects the canonical Planning Center UI ontology into a small runtime
  accessibility-probe contract. The ontology remains source; generated Elixir
  is a projection and must not be edited by hand.
  """

  use Mix.Task

  @impl true
  def run(args) do
    if args != [] do
      Mix.raise("usage: mix ash_planning_center.generate_surface")
    end

    Mix.Task.run("app.start")

    project_root = File.cwd!()
    pack_dir = Path.join(project_root, "priv/ggen/planning-center-surface")
    ontology_path = Path.join(pack_dir, "ontology.ttl")

    Mix.Task.reenable("ggen_igniter.sync")

    Mix.Task.run("ggen_igniter.sync", [
      "--pack-dir",
      pack_dir,
      "--ontology",
      ontology_path,
      "--for-each",
      "surface_contracts",
      "--template",
      Path.join(pack_dir, "templates/surface_contract.ex.eex"),
      "--out",
      "lib/ash_planning_center/generated/surface/<%= file_stem %>.ex",
      "--manifest-dir",
      project_root,
      "--verify-cwd",
      project_root,
      "--on-stale",
      "refuse"
    ])
  end
end
