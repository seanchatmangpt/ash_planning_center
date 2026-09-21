defmodule AshPlanningCenter.EventSnapshotTest do
  use ExUnit.Case, async: true

  alias AshPlanningCenter.EventSnapshot

  test "projects a deterministic OBSERVE-only event snapshot" do
    attrs = %{
      event_id: "youth-2026-09-20",
      starts_at: "2026-09-20T18:00:00-07:00",
      registrations: 120,
      check_ins: 84,
      volunteers: 18,
      roster_complete?: true,
      attendance_submitted?: false,
      registration_exceptions: 3,
      teams: %{registration: 3, administration: 2, welcome: 8, security: 2}
    }

    assert {:ok, snapshot} = EventSnapshot.new(attrs)
    observation = EventSnapshot.to_observation(snapshot)

    assert observation["schema"] == "zoe.event.observation.v1"
    assert observation["authority"] == "OBSERVE"
    assert observation["source"] == "planning_center"
    assert observation["event_id"] == "youth-2026-09-20"
    assert observation["registration_exceptions"] == 3

    assert Enum.map(observation["teams"], & &1["team"]) ==
             ["administration", "registration", "security", "welcome"]

    assert observation["digest"] == EventSnapshot.digest(snapshot)
    assert observation == EventSnapshot.to_observation(snapshot)
    refute Map.has_key?(observation, "dispatch")
    refute Map.has_key?(observation, "receipt")
  end

  test "refuses malformed operational counts" do
    assert {:error, {:invalid, :registrations}} =
             EventSnapshot.new(%{
               event_id: "event",
               starts_at: "2026-09-20T18:00:00-07:00",
               registrations: -1,
               check_ins: 0,
               volunteers: 0,
               roster_complete?: false,
               attendance_submitted?: false,
               registration_exceptions: 0,
               teams: %{}
             })
  end
end
