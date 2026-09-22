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
  def read(attrs, opts \\ []) when is_map(attrs) do
    sources = value(attrs, :sources, %{})
    client = Keyword.get(opts, :client)
    max_pages = Keyword.get(opts, :max_pages, @default_max_pages)

    with :ok <- validate_sources(sources),
         :ok <- validate_max_pages(max_pages),
         {:ok, roster, service_receipts} <- read_services(sources, client, max_pages),
         {:ok, registrations, registration_receipts} <-
           read_registrations(sources, client, max_pages),
         {:ok, check_ins, check_in_receipts} <- read_check_ins(sources, client, max_pages),
         source_receipts <- service_receipts ++ registration_receipts ++ check_in_receipts,
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
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, "Planning Center event read refused: #{inspect(reason)}"
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
             {:ok, data, receipts} <- fetch_collection(path, client, max_pages) do
          {:ok, Enum.map(data, &normalize_team_member/1), receipts}
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
             {:ok, data, receipts} <- fetch_collection(path, client, max_pages) do
          {:ok, Enum.map(data, &normalize_attendee/1), receipts}
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
             {:ok, data, receipts} <- fetch_collection(path, client, max_pages) do
          {:ok, Enum.map(data, &normalize_check_in/1), receipts}
        end
    end
  end

  defp fetch_collection(path, client, max_pages) do
    do_fetch_collection(path, client, max_pages, 0, [], [])
  end

  defp do_fetch_collection(_path, _client, max_pages, offset, _records, _receipts)
       when div(offset, @per_page) >= max_pages do
    {:error, {:provider_page_bound_exceeded, max_pages}}
  end

  defp do_fetch_collection(path, client, max_pages, offset, records, receipts) do
    params = %{"per_page" => @per_page, "offset" => offset}
    opts = [params: params] |> maybe_put_context(client)

    case Client.request(:get, path, opts) do
      {:ok, %Client.Response{status: status, body: %{"data" => data} = body}}
      when status in 200..299 and is_list(data) ->
        receipt = %{
          source_ref: "pco:" <> path <> "?offset=#{offset}&per_page=#{@per_page}",
          status: status,
          count: length(data)
        }

        all_records = records ++ data
        all_receipts = receipts ++ [receipt]
        total = get_in(body, ["meta", "total_count"])

        cond do
          data == [] ->
            {:ok, all_records, all_receipts}

          is_integer(total) and length(all_records) >= total ->
            {:ok, all_records, all_receipts}

          length(data) < @per_page ->
            {:ok, all_records, all_receipts}

          true ->
            do_fetch_collection(
              path,
              client,
              max_pages,
              offset + @per_page,
              all_records,
              all_receipts
            )
        end

      {:ok, %Client.Response{status: status, body: body}} ->
        {:error, {:unexpected_provider_response, path, status, response_shape(body)}}

      {:error, error} ->
        {:error, {:provider_read_failed, path, error}}
    end
  end

  defp normalize_team_member(resource) do
    id = resource_id(resource)
    attrs = attributes(resource)

    %{
      "slot_ref" => "plan-person:" <> id,
      "person_ref" => opaque_person_ref(resource, "plan-person", id),
      "role" => non_blank(attrs["team_position_name"]) || "team-member",
      "status" => non_blank(attrs["status"]) || "unknown"
    }
  end

  defp normalize_attendee(resource) do
    id = resource_id(resource)
    attrs = attributes(resource)

    status =
      cond do
        attrs["canceled"] == true -> "canceled"
        attrs["waitlisted"] == true -> "waitlisted"
        attrs["active"] == true -> "active"
        true -> "unknown"
      end

    %{
      "registration_ref" => "attendee:" <> id,
      "person_ref" => opaque_person_ref(resource, "registration-attendee", id),
      "status" => status
    }
  end

  defp normalize_check_in(resource) do
    id = resource_id(resource)
    attrs = attributes(resource)

    %{
      "check_in_ref" => "check-in:" <> id,
      "person_ref" => opaque_person_ref(resource, "check-in", id),
      "occurred_at" => non_blank(attrs["confirmed_at"]) || non_blank(attrs["created_at"]),
      "status" => if(non_blank(attrs["checked_out_at"]), do: "checked_out", else: "present")
    }
    |> drop_nil("occurred_at")
  end

  defp opaque_person_ref(resource, fallback_kind, fallback_id) do
    case get_in(resource, ["relationships", "person", "data", "id"]) do
      id when is_binary(id) and id != "" -> "person:" <> id
      _ -> "#{fallback_kind}:#{fallback_id}"
    end
  end

  defp resource_id(%{"id" => id}) when is_binary(id) and id != "", do: id
  defp resource_id(_), do: raise(ArgumentError, "provider resource missing opaque id")

  defp attributes(%{"attributes" => attrs}) when is_map(attrs), do: attrs
  defp attributes(_), do: %{}

  defp source(sources, key) when is_map(sources),
    do: Map.get(sources, key, Map.get(sources, Atom.to_string(key)))

  defp source(_sources, _key), do: nil

  defp validate_sources(sources) when is_map(sources) do
    if Enum.any?([:services, :registrations, :check_ins], &is_map(source(sources, &1))) do
      :ok
    else
      {:error, :no_admitted_provider_sources}
    end
  end

  defp validate_sources(_), do: {:error, :invalid_provider_sources}

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
