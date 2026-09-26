defmodule AshPlanningCenter.EventReader do
  @moduledoc """
  Bounded, read-only Planning Center observation composition for ZOE event operations.

  The repository generator is intentionally pinned to the People OpenAPI only.
  Services, Registrations, and Check-Ins are therefore explicit handwritten
  residue with generator capability marked UNSUPPORTED until those product
  schemas are admitted into the ontology/ggen path.

  The reader may call only the admitted GET collections needed to construct an
  AshPlanningCenter.EventSnapshot. It discards provider PII and projects opaque
  identities/status only. It never exposes a write method, routes an incident,
  or acquires consequence authority.
  """

  alias AshPlanningCenter.{Client, EventSnapshot}

  @per_page 100
  @default_max_pages 10
  @id_pattern ~r/\A[A-Za-z0-9_-]+\z/

  @spec read(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def read(attrs, opts \\ [])

  def read(attrs, opts) when is_map(attrs) do
    sources = value(attrs, :sources, %{})
    client = Keyword.get(opts, :client)
    max_pages = Keyword.get(opts, :max_pages, @default_max_pages)

    with :ok <- validate_sources(sources),
         :ok <- validate_max_pages(max_pages),
         :ok <- validate_client(client),
         {:ok, roster, service_receipts} <- read_services(sources, client, max_pages),
         {:ok, registrations, registration_receipts} <-
           read_registrations(sources, client, max_pages),
         {:ok, check_ins, check_in_receipts} <- read_check_ins(sources, client, max_pages),
         source_receipts <- service_receipts ++ registration_receipts ++ check_in_receipts,
         roster <- Enum.sort_by(roster, & &1["slot_ref"]),
         registrations <- Enum.sort_by(registrations, & &1["registration_ref"]),
         check_ins <- Enum.sort_by(check_ins, & &1["check_in_ref"]),
         {:ok, snapshot} <-
           EventSnapshot.new(%{
             event_ref: value(attrs, :event_ref, nil),
             event_name: value(attrs, :event_name, nil),
             starts_at: value(attrs, :starts_at, nil),
             roster: roster,
             registrations: registrations,
             check_ins: check_ins,
             source_refs: Enum.map(source_receipts, & &1.source_ref)
           }) do
      contract =
        snapshot
        |> EventSnapshot.to_contract()
        |> Map.put(:standing, "PARTIAL_ALIVE")
        |> Map.put(:evidence_ceiling, "PROVIDER_READ_OBSERVED")

      {:ok,
       %{
         snapshot: snapshot,
         contract: contract,
         receipt: %{
           kind: "PLANNING_CENTER_OBSERVATION",
           provider: "planning_center",
           authority_boundary: "OBSERVE",
           do_authority: false,
           standing: "PARTIAL_ALIVE",
           transport_identity: transport_identity(client),
           implementation_origin: "HANDWRITTEN_IRREDUCIBLE_COMPOSITION",
           generator_capability: "UNSUPPORTED_NON_PEOPLE_PRODUCTS",
           generator_scope_ref: "Mix.Tasks.AshPlanningCenter.Generate:People-only",
           source_refs: Enum.map(source_receipts, & &1.source_ref),
           pages: length(source_receipts),
           duplicates_dropped: Enum.reduce(source_receipts, 0, &(&1.duplicates + &2)),
           observation_digest: observation_digest(contract.observations),
           records: %{
             roster: length(roster),
             registrations: length(registrations),
             check_ins: length(check_ins)
           }
         }
       }}
    end
  end

  def read(_attrs, _opts), do: {:error, {:invalid_event_reader, :expected_map}}

  @spec read!(map(), keyword()) :: map()
  def read!(attrs, opts \\ []) do
    case read(attrs, opts) do
      {:ok, result} ->
        result

      {:error, reason} ->
        raise ArgumentError, "Planning Center event read refused: #{inspect(reason)}"
    end
  end

  defp read_services(sources, client, max_pages) do
    case source(sources, :services) do
      nil ->
        {:ok, [], []}

      config ->
        with {:ok, service_type_id} <- provider_id(config, :service_type_id),
             {:ok, plan_id} <- provider_id(config, :plan_id),
             path <-
               "/services/v2/service_types/#{service_type_id}/plans/#{plan_id}/team_members",
             {:ok, data, receipts} <- fetch_collection(path, client, max_pages),
             {:ok, normalized} <- normalize_all(data, path, &normalize_team_member/1) do
          {:ok, normalized, receipts}
        end
    end
  end

  defp read_registrations(sources, client, max_pages) do
    case source(sources, :registrations) do
      nil ->
        {:ok, [], []}

      config ->
        with {:ok, signup_id} <- provider_id(config, :signup_id),
             path <- "/registrations/v2/signups/#{signup_id}/attendees",
             {:ok, data, receipts} <- fetch_collection(path, client, max_pages),
             {:ok, normalized} <- normalize_all(data, path, &normalize_attendee/1) do
          {:ok, normalized, receipts}
        end
    end
  end

  defp read_check_ins(sources, client, max_pages) do
    case source(sources, :check_ins) do
      nil ->
        {:ok, [], []}

      config ->
        with {:ok, event_id} <- provider_id(config, :event_id),
             path <- "/check-ins/v2/events/#{event_id}/check_ins",
             {:ok, data, receipts} <- fetch_collection(path, client, max_pages),
             {:ok, normalized} <- normalize_all(data, path, &normalize_check_in/1) do
          {:ok, normalized, receipts}
        end
    end
  end

  defp fetch_collection(path, client, max_pages) do
    do_fetch_collection(path, client, max_pages, 0, {[], %{}}, [])
  end

  defp do_fetch_collection(_path, _client, max_pages, offset, _acc, _receipts)
       when div(offset, @per_page) >= max_pages do
    {:error, {:provider_page_bound_exceeded, max_pages}}
  end

  defp do_fetch_collection(path, client, max_pages, offset, acc, receipts) do
    params = %{"per_page" => @per_page, "offset" => offset}
    opts = [params: params] |> maybe_put_context(client)

    case Client.request(:get, path, opts) do
      {:ok, %Client.Response{status: status, body: %{"data" => data} = body}}
      when status in 200..299 and is_list(data) ->
        total = get_in(body, ["meta", "total_count"])

        with :ok <- validate_total(path, total),
             {:ok, {ordered, seen} = acc, duplicates} <- admit_page(path, data, offset, acc),
             unique = map_size(seen),
             :ok <- validate_count(path, total, unique) do
          receipt = %{
            source_ref: "pco:" <> path <> "?offset=#{offset}&per_page=#{@per_page}",
            status: status,
            count: length(data),
            duplicates: duplicates
          }

          all_receipts = receipts ++ [receipt]

          cond do
            data == [] ->
              {:ok, Enum.reverse(ordered), all_receipts}

            is_integer(total) and unique >= total ->
              {:ok, Enum.reverse(ordered), all_receipts}

            length(data) < @per_page ->
              {:ok, Enum.reverse(ordered), all_receipts}

            true ->
              do_fetch_collection(
                path,
                client,
                max_pages,
                offset + @per_page,
                acc,
                all_receipts
              )
          end
        end

      {:ok, %Client.Response{status: status, body: body}} ->
        {:error, {:unexpected_provider_response, path, status, response_shape(body)}}

      {:error, error} ->
        {:error, {:provider_read_failed, path, error}}
    end
  end

  # Admits one provider page: every resource must be a map carrying an opaque
  # id; an identical re-delivery (offset drift under concurrent inserts) is
  # observed once, while the same id with different content is refused because
  # the provider no longer describes one state.
  defp admit_page(path, data, offset, acc) do
    data
    |> Enum.with_index(offset)
    |> Enum.reduce_while({:ok, acc, 0}, fn {resource, index}, {:ok, {ordered, seen}, dups} ->
      with {:ok, id} <- admitted_resource_id(resource) do
        case Map.fetch(seen, id) do
          :error ->
            {:cont, {:ok, {[resource | ordered], Map.put(seen, id, resource)}, dups}}

          {:ok, ^resource} ->
            {:cont, {:ok, {ordered, seen}, dups + 1}}

          {:ok, _different} ->
            {:halt, {:error, {:conflicting_duplicate_record, path, id}}}
        end
      else
        {:error, reason} ->
          {:halt, {:error, {:malformed_provider_record, path, index, reason}}}
      end
    end)
  end

  defp admitted_resource_id(%{"id" => id}) when is_binary(id) and id != "" do
    if Regex.match?(@id_pattern, id), do: {:ok, id}, else: {:error, :unsafe_opaque_id}
  end

  defp admitted_resource_id(resource) when is_map(resource), do: {:error, :missing_opaque_id}
  defp admitted_resource_id(_resource), do: {:error, :expected_resource_map}

  defp validate_total(_path, nil), do: :ok
  defp validate_total(_path, total) when is_integer(total) and total >= 0, do: :ok
  defp validate_total(path, total), do: {:error, {:invalid_provider_total, path, total}}

  defp validate_count(path, total, unique) when is_integer(total) and unique > total,
    do: {:error, {:provider_count_inconsistent, path, total, unique}}

  defp validate_count(_path, _total, _unique), do: :ok

  defp normalize_all(data, path, fun) do
    data
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {resource, index}, {:ok, acc} ->
      case fun.(resource) do
        {:ok, normalized} ->
          {:cont, {:ok, [normalized | acc]}}

        {:error, reason} ->
          {:halt, {:error, {:malformed_provider_record, path, index, reason}}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp normalize_team_member(resource) do
    id = resource["id"]
    attrs = attributes(resource)

    with {:ok, person_ref} <- opaque_person_ref(resource, "plan-person", id) do
      {:ok,
       %{
         "slot_ref" => "plan-person:" <> id,
         "person_ref" => person_ref,
         "role" => non_blank(attrs["team_position_name"]) || "team-member",
         "status" => non_blank(attrs["status"]) || "unknown"
       }}
    end
  end

  defp normalize_attendee(resource) do
    id = resource["id"]
    attrs = attributes(resource)

    status =
      cond do
        attrs["canceled"] == true -> "canceled"
        attrs["waitlisted"] == true -> "waitlisted"
        attrs["active"] == true -> "active"
        true -> "unknown"
      end

    with {:ok, person_ref} <- opaque_person_ref(resource, "registration-attendee", id) do
      {:ok,
       %{
         "registration_ref" => "attendee:" <> id,
         "person_ref" => person_ref,
         "status" => status
       }}
    end
  end

  defp normalize_check_in(resource) do
    id = resource["id"]
    attrs = attributes(resource)

    with {:ok, person_ref} <- opaque_person_ref(resource, "check-in", id) do
      {:ok,
       %{
         "check_in_ref" => "check-in:" <> id,
         "person_ref" => person_ref,
         "occurred_at" => non_blank(attrs["confirmed_at"]) || non_blank(attrs["created_at"]),
         "status" => if(non_blank(attrs["checked_out_at"]), do: "checked_out", else: "present")
       }
       |> drop_nil("occurred_at")}
    end
  end

  defp opaque_person_ref(resource, fallback_kind, fallback_id) do
    case get_in(resource, ["relationships", "person", "data", "id"]) do
      id when is_binary(id) and id != "" ->
        if Regex.match?(@id_pattern, id),
          do: {:ok, "person:" <> id},
          else: {:error, :unsafe_person_id}

      _ ->
        {:ok, "#{fallback_kind}:#{fallback_id}"}
    end
  rescue
    # get_in/2 over a non-map relationship payload (e.g. a list) is a
    # malformed provider shape, not a crash.
    _ in [FunctionClauseError, ArgumentError, BadMapError] ->
      {:error, :malformed_person_relationship}
  end

  defp attributes(%{"attributes" => attrs}) when is_map(attrs), do: attrs
  defp attributes(_), do: %{}

  defp observation_digest(observations) do
    "sha256:" <>
      (:crypto.hash(:sha256, :erlang.term_to_binary(observations, [:deterministic]))
       |> Base.encode16(case: :lower))
  end

  defp source(sources, key) when is_map(sources),
    do: Map.get(sources, key, Map.get(sources, Atom.to_string(key)))

  defp source(_sources, _key), do: nil

  defp validate_sources(sources) when is_map(sources) do
    keys = [:services, :registrations, :check_ins]

    case Enum.find(keys, fun_invalid_source(sources)) do
      nil ->
        if Enum.any?(keys, &is_map(source(sources, &1))) do
          :ok
        else
          {:error, :no_admitted_provider_sources}
        end

      key ->
        {:error, {:invalid_provider_source, key}}
    end
  end

  defp validate_sources(_), do: {:error, :invalid_provider_sources}

  defp fun_invalid_source(sources) do
    fn key ->
      config = source(sources, key)
      not (is_nil(config) or is_map(config))
    end
  end

  defp validate_client(nil), do: :ok

  defp validate_client(client) when is_atom(client) do
    if Code.ensure_loaded?(client) and function_exported?(client, :request, 3),
      do: :ok,
      else: {:error, {:invalid_client, client}}
  end

  defp validate_client(client), do: {:error, {:invalid_client, client}}

  defp validate_max_pages(value) when is_integer(value) and value in 1..100, do: :ok
  defp validate_max_pages(value), do: {:error, {:invalid_max_pages, value}}

  defp provider_id(config, key) do
    case value(config, key, nil) do
      id when is_binary(id) ->
        id = String.trim(id)

        cond do
          id == "" -> {:error, {:missing_provider_id, key}}
          Regex.match?(@id_pattern, id) -> {:ok, id}
          true -> {:error, {:unsafe_provider_id, key}}
        end

      _ ->
        {:error, {:missing_provider_id, key}}
    end
  end

  defp maybe_put_context(opts, nil), do: opts

  defp maybe_put_context(opts, client) when is_atom(client),
    do: Keyword.put(opts, :context, %{planning_center_client: client})

  defp transport_identity(nil), do: "configured-client"
  defp transport_identity(client) when is_atom(client), do: inspect(client)

  defp response_shape(value) when is_map(value), do: {:map, Map.keys(value) |> Enum.sort()}
  defp response_shape(value) when is_list(value), do: {:list, length(value)}
  defp response_shape(value), do: {:other, type_of(value)}

  defp type_of(value) when is_binary(value), do: :binary
  defp type_of(value) when is_integer(value), do: :integer
  defp type_of(value) when is_atom(value), do: :atom
  defp type_of(_), do: :term

  defp drop_nil(map, key), do: if(is_nil(Map.get(map, key)), do: Map.delete(map, key), else: map)

  defp non_blank(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp non_blank(_), do: nil

  defp value(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
