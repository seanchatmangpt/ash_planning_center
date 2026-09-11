defmodule AshPlanningCenter.People.Person do
  @moduledoc "Planning Center People person projected as an Ash resource."

  use Ash.Resource,
    domain: AshPlanningCenter.Domain

  attributes do
    attribute(:id, :string, primary_key?: true, allow_nil?: false, public?: true)
    attribute(:first_name, :string, public?: true)
    attribute(:middle_name, :string, public?: true)
    attribute(:last_name, :string, public?: true)
    attribute(:nickname, :string, public?: true)
    attribute(:status, :string, public?: true)
    attribute(:avatar, :string, public?: true)
    attribute(:child, :boolean, public?: true)
    attribute(:gender, :string, public?: true)
    attribute(:membership, :string, public?: true)
    attribute(:birthdate, :string, public?: true)
    attribute(:anniversary, :string, public?: true)
    attribute(:created_at, :string, public?: true)
    attribute(:updated_at, :string, public?: true)

    attribute(:remote_type, :string, public?: true)
    attribute(:remote_attributes, :map, public?: true, default: %{})
    attribute(:relationships, :map, public?: true, default: %{})
    attribute(:links, :map, public?: true, default: %{})
    attribute(:meta, :map, public?: true, default: %{})
  end

  actions do
    read :read do
      primary?(true)

      argument :remote_params, :map do
        default(%{})
      end

      prepare(fn query, _context ->
        cond do
          query.limit && query.limit > 100 ->
            Ash.Query.add_error(query, "People reads are bounded to at most 100 results")

          query.limit ->
            query

          true ->
            Ash.Query.limit(query, 25)
        end
      end)

      manual(AshPlanningCenter.People.Person.Read)
    end

    read :get do
      get?(true)
      argument(:id, :string, allow_nil?: false)
      manual(AshPlanningCenter.People.Person.Get)
    end
  end
end

defmodule AshPlanningCenter.People.Person.Read do
  @moduledoc false
  use Ash.Resource.ManualRead

  alias AshPlanningCenter.Client.Error
  alias AshPlanningCenter.People.Person

  @endpoint "/people/v2/people"
  @remote_page_size 100

  @impl true
  def read(query, _data_layer_query, _opts, _context) do
    if query.sort not in [nil, []] do
      {:error,
       %Error{
         message:
           "Ash sorting is not admitted for Planning Center People reads; use a verified remote order parameter instead",
         reason: :unsupported_sort
       }}
    else
      limit = query.limit || 25
      offset = query.offset || 0

      if limit == 0 do
        {:ok, []}
      else
        local_query =
          query
          |> Ash.Query.unset(:limit)
          |> Ash.Query.unset(:offset)

        remote_params = Map.get(query.arguments, :remote_params, %{}) || %{}

        scan(
          local_query,
          normalize_params(remote_params),
          0,
          offset,
          limit,
          [],
          query.context || %{}
        )
      end
    end
  end

  defp scan(query, params, remote_offset, wanted_offset, limit, acc, context) do
    wanted = wanted_offset + limit
    per_page = min(@remote_page_size, max(wanted - length(acc), 1))

    request_params =
      params
      |> Map.put("per_page", per_page)
      |> Map.put("offset", remote_offset)

    with {:ok, response} <-
           AshPlanningCenter.request(:get, @endpoint,
             params: request_params,
             context: context
           ),
         {:ok, records, document} <- AshPlanningCenter.JSONAPI.decode_many(response.body, Person),
         {:ok, matching} <- Ash.Query.apply_to(query, records) do
      next_acc = acc ++ matching
      remote_count = length(records)

      cond do
        length(next_acc) >= wanted ->
          {:ok, take_window(next_acc, wanted_offset, limit)}

        remote_count == 0 ->
          {:ok, take_window(next_acc, wanted_offset, limit)}

        more?(document, remote_count, per_page, remote_offset) ->
          scan(
            query,
            params,
            remote_offset + remote_count,
            wanted_offset,
            limit,
            next_acc,
            context
          )

        true ->
          {:ok, take_window(next_acc, wanted_offset, limit)}
      end
    end
  end

  defp more?(document, remote_count, per_page, remote_offset) do
    next_link = Map.get(document.links, "next")
    total_count = Map.get(document.meta, "total_count")

    cond do
      is_binary(next_link) and next_link != "" -> true
      is_integer(total_count) -> remote_offset + remote_count < total_count
      true -> remote_count == per_page
    end
  end

  defp take_window(records, offset, limit) do
    records
    |> Enum.drop(offset)
    |> Enum.take(limit)
  end

  defp normalize_params(params) when is_map(params) do
    Map.new(params, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} when is_binary(key) -> {key, value}
      {key, value} -> {to_string(key), value}
    end)
  end
end

defmodule AshPlanningCenter.People.Person.Get do
  @moduledoc false
  use Ash.Resource.ManualRead

  alias AshPlanningCenter.Client.Error
  alias AshPlanningCenter.People.Person

  @endpoint "/people/v2/people"

  @impl true
  def read(query, _data_layer_query, _opts, _context) do
    id = Map.fetch!(query.arguments, :id)
    path = @endpoint <> "/" <> URI.encode_www_form(id)

    case AshPlanningCenter.request(:get, path, context: query.context || %{}) do
      {:ok, response} ->
        with {:ok, person, _document} <-
               AshPlanningCenter.JSONAPI.decode_one(response.body, Person) do
          {:ok, [person]}
        end

      {:error, %Error{status: 404}} ->
        {:ok, []}

      {:error, error} ->
        {:error, error}
    end
  end
end
