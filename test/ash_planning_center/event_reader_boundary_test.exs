defmodule AshPlanningCenter.EventReaderBoundaryTest do
  use ExUnit.Case, async: true

  alias AshPlanningCenter.Client.Response
  alias AshPlanningCenter.EventReader

  defmodule PagingClient do
    @behaviour AshPlanningCenter.Client

    @impl true
    def request(:get, "/registrations/v2/signups/signup-1/attendees", opts) do
      offset = opts |> Keyword.fetch!(:params) |> Map.fetch!("offset")

      data =
        for index <- 1..100 do
          %{
            "id" => "att-#{offset + index}",
            "attributes" => %{"active" => true}
          }
        end

      {:ok,
       %Response{
         status: 200,
         body: %{"data" => data, "meta" => %{"total_count" => 1_000}},
         headers: %{}
       }}
    end
  end

  defmodule ErrorClient do
    @behaviour AshPlanningCenter.Client

    @impl true
    def request(:get, _path, _opts), do: {:error, :transport_down}
  end

  defmodule MalformedClient do
    @behaviour AshPlanningCenter.Client

    @impl true
    def request(:get, _path, _opts) do
      {:ok, %Response{status: 200, body: %{"meta" => %{}}, headers: %{}}}
    end
  end

  defmodule FallbackClient do
    @behaviour AshPlanningCenter.Client

    @impl true
    def request(:get, "/registrations/v2/signups/signup-1/attendees", _opts) do
      {:ok,
       %Response{
         status: 200,
         body: %{
           "data" => [
             %{
               "id" => "att-no-person",
               "attributes" => %{"waitlisted" => true}
             }
           ],
           "meta" => %{"total_count" => 1}
         },
         headers: %{}
       }}
    end
  end

  @attrs %{
    event_ref: "event:youth-001",
    event_name: "Youth Night",
    starts_at: "2026-09-23T19:00:00-07:00",
    sources: %{registrations: %{signup_id: "signup-1"}}
  }

  test "pagination is bounded and refuses rather than silently truncating" do
    assert {:error, {:provider_page_bound_exceeded, 2}} =
             EventReader.read(@attrs, client: PagingClient, max_pages: 2)
  end

  test "provider transport failure is typed and does not become an empty observation" do
    assert {:error,
            {:provider_read_failed, "/registrations/v2/signups/signup-1/attendees",
             :transport_down}} =
             EventReader.read(@attrs, client: ErrorClient)
  end

  test "malformed provider success shape is refused" do
    assert {:error,
            {:unexpected_provider_response, "/registrations/v2/signups/signup-1/attendees", 200,
             {:map, ["meta"]}}} =
             EventReader.read(@attrs, client: MalformedClient)
  end

  test "missing person relationship falls back only to an opaque attendee identity" do
    assert {:ok, result} = EventReader.read(@attrs, client: FallbackClient)

    assert result.contract.observations.registrations == [
             %{
               "registration_ref" => "attendee:att-no-person",
               "person_ref" => "registration-attendee:att-no-person",
               "status" => "waitlisted"
             }
           ]
  end

  test "max_pages must remain inside the admitted execution bound" do
    assert {:error, {:invalid_max_pages, 0}} =
             EventReader.read(@attrs, client: FallbackClient, max_pages: 0)

    assert {:error, {:invalid_max_pages, 101}} =
             EventReader.read(@attrs, client: FallbackClient, max_pages: 101)
  end
end
