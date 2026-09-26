defmodule AshPlanningCenter.EventReaderTest do
  use ExUnit.Case, async: true

  alias AshPlanningCenter.Client.Response
  alias AshPlanningCenter.EventReader

  defmodule FakeClient do
    @behaviour AshPlanningCenter.Client

    @impl true
    def request(:get, path, opts) do
      send(self(), {:provider_read, :get, path, Keyword.get(opts, :params, %{})})

      body =
        case path do
          "/services/v2/service_types/st-youth/plans/plan-1/team_members" ->
            %{
              "data" => [
                %{
                  "id" => "pp-1",
                  "attributes" => %{
                    "team_position_name" => "Registration",
                    "status" => "C",
                    "notes" => "must never project"
                  },
                  "relationships" => %{"person" => %{"data" => %{"id" => "p-tanner"}}}
                }
              ],
              "meta" => %{"total_count" => 1}
            }

          "/registrations/v2/signups/signup-1/attendees" ->
            %{
              "data" => [
                %{
                  "id" => "att-1",
                  "attributes" => %{
                    "active" => true,
                    "name" => "Minor Name Must Be Dropped"
                  },
                  "relationships" => %{"person" => %{"data" => %{"id" => "p-student"}}}
                }
              ],
              "meta" => %{"total_count" => 1}
            }

          "/check-ins/v2/events/check-event-1/check_ins" ->
            %{
              "data" => [
                %{
                  "id" => "ci-1",
                  "attributes" => %{
                    "confirmed_at" => "2026-09-23T19:03:00-07:00",
                    "first_name" => "Must Be Dropped"
                  },
                  "relationships" => %{"person" => %{"data" => %{"id" => "p-student"}}}
                }
              ],
              "meta" => %{"total_count" => 1}
            }
        end

      {:ok, %Response{status: 200, body: body, headers: %{}}}
    end

    def request(method, path, _opts) do
      raise "unexpected provider method #{inspect(method)} for #{path}"
    end
  end

  test "reads only admitted GET collections and projects opaque event state" do
    assert {:ok, result} =
             EventReader.read(
               %{
                 event_ref: "event:youth-001",
                 event_name: "Youth Night",
                 starts_at: "2026-09-23T19:00:00-07:00",
                 sources: %{
                   services: %{service_type_id: "st-youth", plan_id: "plan-1"},
                   registrations: %{signup_id: "signup-1"},
                   check_ins: %{event_id: "check-event-1"}
                 }
               },
               client: FakeClient
             )

    assert_receive {:provider_read, :get,
                    "/services/v2/service_types/st-youth/plans/plan-1/team_members",
                    %{"offset" => 0, "per_page" => 100}}

    assert_receive {:provider_read, :get, "/registrations/v2/signups/signup-1/attendees",
                    %{"offset" => 0, "per_page" => 100}}

    assert_receive {:provider_read, :get, "/check-ins/v2/events/check-event-1/check_ins",
                    %{"offset" => 0, "per_page" => 100}}

    assert result.contract.authority_boundary == "OBSERVE"
    assert result.contract.do_authority == false
    assert result.contract.standing == "PARTIAL_ALIVE"
    assert result.contract.evidence_ceiling == "PROVIDER_READ_OBSERVED"
    assert result.contract.counts == %{roster: 1, registrations: 1, check_ins: 1}

    [roster] = result.contract.observations.roster

    assert roster == %{
             "slot_ref" => "plan-person:pp-1",
             "person_ref" => "person:p-tanner",
             "role" => "Registration",
             "status" => "C"
           }

    [registration] = result.contract.observations.registrations

    assert registration == %{
             "registration_ref" => "attendee:att-1",
             "person_ref" => "person:p-student",
             "status" => "active"
           }

    [check_in] = result.contract.observations.check_ins

    assert check_in == %{
             "check_in_ref" => "check-in:ci-1",
             "person_ref" => "person:p-student",
             "occurred_at" => "2026-09-23T19:03:00-07:00",
             "status" => "present"
           }

    assert result.receipt.kind == "PLANNING_CENTER_OBSERVATION"
    assert result.receipt.authority_boundary == "OBSERVE"
    assert result.receipt.do_authority == false
    assert result.receipt.transport_identity == inspect(FakeClient)
    assert result.receipt.implementation_origin == "HANDWRITTEN_IRREDUCIBLE_COMPOSITION"
    assert result.receipt.generator_capability == "UNSUPPORTED_NON_PEOPLE_PRODUCTS"

    assert result.receipt.generator_scope_ref ==
             "Mix.Tasks.AshPlanningCenter.Generate:People-only"

    assert length(result.receipt.source_refs) == 3

    refute inspect(result.contract) =~ "Minor Name"
    refute inspect(result.contract) =~ "Must Be Dropped"
    refute inspect(result.contract) =~ "notes"
  end

  test "refuses unsafe provider ids before transport" do
    assert {:error, {:unsafe_provider_id, :signup_id}} =
             EventReader.read(
               %{
                 event_ref: "event:youth-001",
                 event_name: "Youth Night",
                 starts_at: "2026-09-23T19:00:00-07:00",
                 sources: %{registrations: %{signup_id: "../admin"}}
               },
               client: FakeClient
             )

    refute_received {:provider_read, _, _, _}
  end

  test "refuses an empty provider-source set" do
    assert {:error, :no_admitted_provider_sources} =
             EventReader.read(%{
               event_ref: "event:youth-001",
               event_name: "Youth Night",
               starts_at: "2026-09-23T19:00:00-07:00",
               sources: %{}
             })
  end

  test "the public API exposes no write or dispatch operation" do
    exports = EventReader.__info__(:functions)
    refute {:request, 3} in exports
    refute {:write, 2} in exports
    refute {:dispatch, 2} in exports
  end
end
