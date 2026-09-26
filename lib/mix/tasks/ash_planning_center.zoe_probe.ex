defmodule Mix.Tasks.AshPlanningCenter.ZoeProbe do
  use Mix.Task

  @shortdoc "Observe a bounded ZOE event snapshot from Planning Center"

  @moduledoc """
  Executes the read-only Planning Center event observation seam.

  Credentials are read only through the library's existing runtime
  configuration. The task never accepts or prints secrets and has no write
  operation.
  """

  @switches [
    event_ref: :string,
    event_name: :string,
    starts_at: :string,
    service_type_id: :string,
    plan_id: :string,
    signup_id: :string,
    check_in_event_id: :string,
    out: :string,
    max_pages: :integer
  ]

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, rest, invalid} = OptionParser.parse(args, strict: @switches)

    if rest != [] or invalid != [] do
      Mix.raise("unsupported arguments: #{inspect(rest ++ invalid)}")
    end

    sources =
      %{}
      |> maybe_services(opts)
      |> maybe_source(:registrations, opts[:signup_id], fn id -> %{signup_id: id} end)
      |> maybe_source(:check_ins, opts[:check_in_event_id], fn id -> %{event_id: id} end)

    result =
      AshPlanningCenter.EventReader.read!(
        %{
          event_ref: required!(opts, :event_ref),
          event_name: required!(opts, :event_name),
          starts_at: required!(opts, :starts_at),
          sources: sources
        },
        max_pages: opts[:max_pages] || 10
      )

    receipt =
      result.receipt
      |> Map.put(:producer_sha, producer_sha!())
      |> Map.put(:contract_version, result.contract.contract_version)

    payload = %{contract: result.contract, receipt: receipt}
    json = Jason.encode!(payload, pretty: true)

    case opts[:out] do
      nil ->
        Mix.shell().info(json)

      path ->
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, json <> "\n")
        Mix.shell().info("wrote #{path}")
    end
  end

  defp maybe_services(sources, opts) do
    case {opts[:service_type_id], opts[:plan_id]} do
      {nil, nil} ->
        sources

      {service_type_id, plan_id}
      when is_binary(service_type_id) and is_binary(plan_id) ->
        Map.put(sources, :services, %{
          service_type_id: service_type_id,
          plan_id: plan_id
        })

      _ ->
        Mix.raise("--service-type-id and --plan-id must be supplied together")
    end
  end

  defp maybe_source(sources, _key, nil, _fun), do: sources
  defp maybe_source(sources, key, id, fun), do: Map.put(sources, key, fun.(id))

  defp producer_sha! do
    env_sha = System.get_env("ASH_PLANNING_CENTER_PRODUCER_SHA")

    cond do
      is_binary(env_sha) and Regex.match?(~r/\A[0-9a-f]{40}\z/, env_sha) ->
        env_sha

      is_binary(env_sha) ->
        Mix.raise("ASH_PLANNING_CENTER_PRODUCER_SHA must be an exact 40-hex SHA")

      true ->
        case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
          {sha, 0} ->
            sha = String.trim(sha)

            if Regex.match?(~r/\A[0-9a-f]{40}\z/, sha) do
              sha
            else
              Mix.raise("git rev-parse HEAD did not return an exact SHA")
            end

          {output, _} ->
            Mix.raise(
              "producer SHA unavailable; run from a git checkout or set " <>
                "ASH_PLANNING_CENTER_PRODUCER_SHA: #{String.trim(output)}"
            )
        end
    end
  end

  defp required!(opts, key) do
    case opts[key] do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        flag = key |> Atom.to_string() |> String.replace("_", "-")
        Mix.raise("--#{flag} is required")
    end
  end
end
