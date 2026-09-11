defmodule AshPlanningCenter.People.Person.Read do
  @moduledoc false
  use Ash.Resource.ManualRead

  alias AshPlanningCenter.Client.Error
  alias AshPlanningCenter.People.Person

  @endpoint "/people/v2/people"
  @remote_page_size 100
  @max_remote_records 1_000

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

  defp scan(_query, _params, remote_offset, _wanted_offset, _limit, _acc, _context)
       when remote_offset >= @max_remote_records do
    scan_limit_error()
  end

  defp scan(query, params, remote_offset, wanted_offset, limit, acc, context) do
    wanted = wanted_offset + limit
    remaining_budget = @max_remote_records - remote_offset

    per_page =
      @remote_page_size
      |> min(max(wanted - length(acc), 1))
      |> min(remaining_budget)

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
      next_remote_offset = remote_offset + remote_count
      has_more? = more?(document, remote_count, per_page, remote_offset)

      cond do
        length(next_acc) >= wanted ->
          {:ok, take_window(next_acc, wanted_offset, limit)}

        remote_count == 0 ->
          {:ok, take_window(next_acc, wanted_offset, limit)}

        has_more? && next_remote_offset >= @max_remote_records ->
          scan_limit_error()

        has_more? ->
          scan(
            query,
            params,
            next_remote_offset,
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

  defp scan_limit_error do
    {:error,
     %Error{
       message:
         "Planning Center People read exceeded the 1000-record local scan boundary; use remote_params to narrow the server-side result set",
       reason: {:scan_limit_exceeded, @max_remote_records}
     }}
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
