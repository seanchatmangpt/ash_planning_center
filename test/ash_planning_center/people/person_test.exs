defmodule AshPlanningCenter.People.PersonTest do
  use ExUnit.Case, async: false

  alias AshPlanningCenter.Domain
  alias AshPlanningCenter.People.Person

  setup do
    previous = Application.get_env(:ash_planning_center, :client)
    Application.put_env(:ash_planning_center, :client, AshPlanningCenter.TestClient)

    on_exit(fn ->
      if previous do
        Application.put_env(:ash_planning_center, :client, previous)
      else
        Application.delete_env(:ash_planning_center, :client)
      end
    end)

    :ok
  end

  test "generated resource carries the admitted OpenAPI Person surface" do
    names = Person |> Ash.Resource.Info.attributes() |> Enum.map(& &1.name)

    assert length(names) == 47
    assert :accounting_administrator in names
    assert :directory_shared_info in names
    assert :resource_permission_flags in names
    assert :search_name_or_email_or_phone_number in names
    assert :stripe_customer_identifier in names
    assert :remote_relationships in names
  end

  test "lists Planning Center people as Ash resource structs" do
    assert [
             %Person{id: "1", first_name: "Ada", last_name: "Lovelace"},
             %Person{id: "2", first_name: "Grace", last_name: "Hopper"},
             %Person{id: "3", first_name: "Katherine", last_name: "Johnson"}
           ] = Domain.list_people!()

    assert_receive {:planning_center_request, :get, "/people/v2/people", opts}
    assert opts[:params]["offset"] == 0
    assert opts[:params]["per_page"] == 25
  end

  test "gets one person by remote id" do
    assert %Person{id: "2", first_name: "Grace"} = Domain.get_person!("2")

    assert_receive {:planning_center_request, :get, "/people/v2/people/2", _opts}
  end

  test "retains upstream attributes and relationships that are not projected yet" do
    [person | _] = Domain.list_people!()

    assert person.remote_attributes["upstream_only_field"] == "preserved"
    assert person.remote_relationships["households"] == %{"data" => []}
  end

  test "returns nil for a missing get record" do
    assert Domain.get_person!("missing") == nil
  end
end
