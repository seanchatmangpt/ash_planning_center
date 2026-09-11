defmodule Mix.Tasks.AshPlanningCenter.Generate do
  @shortdoc "Regenerates Ash projections from the pinned Planning Center OpenAPI"
  @moduledoc """
  Fetches and validates the pinned Planning Center People OpenAPI description,
  uplifts the admitted schema to an ephemeral Turtle graph, then delegates all
  persistent projection and reconciliation to `ggen_igniter`.

      mix ash_planning_center.generate
      mix ash_planning_center.generate --input tmp/people-openapi.json

  `--input` is an offline/replay transport only; it is subjected to the same
  source version and server admission checks as a live fetch.
  """

  use Mix.Task

  @impl true
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [input: :string],
        aliases: []
      )

    if rest != [] or invalid != [] do
      Mix.raise("usage: mix ash_planning_center.generate [--input PATH]")
    end

    Mix.Task.run("app.start")

    project_root = File.cwd!()
    pack_dir = Path.join(project_root, "priv/ggen/planning-center-people")

    ontology_path =
      Path.join(
        System.tmp_dir!(),
        "ash_planning_center-people-#{AshPlanningCenter.OpenAPI.api_version()}.ttl"
      )

    document =
      case opts[:input] do
        nil -> AshPlanningCenter.OpenAPI.fetch!()
        path -> AshPlanningCenter.OpenAPI.load_file!(path)
      end

    receipt = AshPlanningCenter.OpenAPI.write_turtle!(document, ontology_path)

    Mix.shell().info(
      "Planning Center OpenAPI uplift: version=#{AshPlanningCenter.OpenAPI.api_version()} " <>
        "schema=#{AshPlanningCenter.OpenAPI.schema_key()} sha256=#{receipt.sha256}"
    )

    Mix.Task.reenable("ggen_igniter.sync")

    Mix.Task.run("ggen_igniter.sync", [
      "--pack-dir",
      pack_dir,
      "--ontology",
      ontology_path,
      "--for-each",
      "resources",
      "--template",
      Path.join(pack_dir, "templates/resource.ex.eex"),
      "--out",
      "lib/ash_planning_center/generated/people/<%= file_stem %>.ex",
      "--manifest-dir",
      project_root,
      "--verify-cwd",
      project_root,
      "--on-stale",
      "refuse"
    ])
  end
end
