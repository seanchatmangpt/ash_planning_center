defmodule AshPlanningCenter.Client do
  @moduledoc """
  Transport boundary for Planning Center.

  A client can be replaced globally with `config :ash_planning_center, :client`
  or per Ash query by setting `:planning_center_client` in the query context.
  The latter keeps tests and higher-order compositions deterministic without
  mutating global configuration.
  """

  alias AshPlanningCenter.Client.{Error, Response}

  @type method :: :get | :post | :put | :patch | :delete
  @callback request(method(), String.t(), keyword()) ::
              {:ok, Response.t()} | {:error, Error.t()}

  @spec request(method(), String.t(), keyword()) ::
          {:ok, Response.t()} | {:error, Error.t()}
  def request(method, path, opts \\ []) do
    context = Keyword.get(opts, :context, %{}) || %{}
    client = context_client(context) || Application.get_env(:ash_planning_center, :client, Req)

    client.request(method, path, Keyword.delete(opts, :context))
  end

  defp context_client(context) when is_map(context), do: Map.get(context, :planning_center_client)
  defp context_client(_), do: nil
end

defmodule AshPlanningCenter.Client.Response do
  @moduledoc false

  @enforce_keys [:status, :body]
  defstruct [:status, :body, headers: %{}]

  @type t :: %__MODULE__{
          status: non_neg_integer(),
          body: term(),
          headers: term()
        }
end

defmodule AshPlanningCenter.Client.Error do
  @moduledoc false

  defexception [:message, :status, :body, :reason]

  @type t :: %__MODULE__{
          message: String.t(),
          status: non_neg_integer() | nil,
          body: term(),
          reason: term()
        }
end

defmodule AshPlanningCenter.Client.Req do
  @moduledoc false
  @behaviour AshPlanningCenter.Client

  alias AshPlanningCenter.Client.{Error, Response}

  @default_base_url "https://api.planningcenteronline.com"

  @impl true
  def request(method, path, opts) do
    with {:ok, auth_header} <- auth_header() do
      request_opts =
        [
          method: method,
          url: url(path),
          params: Keyword.get(opts, :params, %{}),
          headers:
            [
              {"accept", "application/json"},
              auth_header
            ] ++ Keyword.get(opts, :headers, [])
        ]
        |> maybe_put_json(Keyword.get(opts, :body))

      case Req.request(request_opts) do
        {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
          {:ok,
           %Response{
             status: response.status,
             body: response.body,
             headers: response.headers
           }}

        {:ok, %Req.Response{} = response} ->
          {:error,
           %Error{
             message: "Planning Center returned HTTP #{response.status}",
             status: response.status,
             body: response.body,
             reason: :http_error
           }}

        {:error, reason} ->
          {:error,
           %Error{
             message: "Planning Center request failed",
             reason: reason
           }}
      end
    end
  end

  defp auth_header do
    case Application.get_env(:ash_planning_center, :auth) do
      {:basic, application_id, secret}
      when is_binary(application_id) and is_binary(secret) ->
        encoded = Base.encode64(application_id <> ":" <> secret)
        {:ok, {"authorization", "Basic " <> encoded}}

      {:bearer, token} when is_binary(token) ->
        {:ok, {"authorization", "Bearer " <> token}}

      nil ->
        {:error,
         %Error{
           message: "Planning Center authentication is not configured",
           reason: :missing_auth
         }}

      other ->
        {:error,
         %Error{
           message: "Planning Center authentication configuration is invalid",
           reason: {:invalid_auth, auth_shape(other)}
         }}
    end
  end

  defp auth_shape({kind, _, _}), do: {kind, :redacted, :redacted}
  defp auth_shape({kind, _}), do: {kind, :redacted}
  defp auth_shape(other), do: other

  defp url(path) do
    base_url =
      Application.get_env(:ash_planning_center, :base_url, @default_base_url)
      |> String.trim_trailing("/")

    base_url <> "/" <> String.trim_leading(path, "/")
  end

  defp maybe_put_json(opts, nil), do: opts
  defp maybe_put_json(opts, body), do: Keyword.put(opts, :json, body)
end
