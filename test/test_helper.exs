ExUnit.start()

defmodule AshPlanningCenter.TestClient do
  @behaviour AshPlanningCenter.Client

  alias AshPlanningCenter.Client.{Error, Response}

  @people [
    %{
      "type" => "Person",
      "id" => "1",
      "attributes" => %{
        "first_name" => "Ada",
        "last_name" => "Lovelace",
        "status" => "active",
        "upstream_only_field" => "preserved"
      },
      "relationships" => %{"households" => %{"data" => []}}
    },
    %{
      "type" => "Person",
      "id" => "2",
      "attributes" => %{
        "first_name" => "Grace",
        "last_name" => "Hopper",
        "status" => "active"
      }
    },
    %{
      "type" => "Person",
      "id" => "3",
      "attributes" => %{
        "first_name" => "Katherine",
        "last_name" => "Johnson",
        "status" => "inactive"
      }
    }
  ]

  @impl true
  def request(:get, "/people/v2/people", opts) do
    send(self(), {:planning_center_request, :get, "/people/v2/people", opts})

    params = Keyword.get(opts, :params, %{})
    offset = int_param(params, "offset", 0)
    per_page = int_param(params, "per_page", 25)
    data = Enum.slice(@people, offset, per_page)

    next_link =
      if offset + length(data) < length(@people) do
        "https://example.test/people?offset=#{offset + length(data)}"
      end

    {:ok,
     %Response{
       status: 200,
       headers: %{},
       body: %{
         "data" => data,
         "meta" => %{"total_count" => length(@people)},
         "links" => %{"next" => next_link}
       }
     }}
  end

  def request(:get, <<"/people/v2/people/", id::binary>>, opts) do
    send(self(), {:planning_center_request, :get, "/people/v2/people/" <> id, opts})

    case Enum.find(@people, &(&1["id"] == id)) do
      nil ->
        {:error,
         %Error{
           message: "not found",
           status: 404,
           reason: :http_error
         }}

      person ->
        {:ok,
         %Response{
           status: 200,
           headers: %{},
           body: %{"data" => person}
         }}
    end
  end

  defp int_param(params, key, default) do
    case Map.get(params, key, default) do
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
    end
  end
end
