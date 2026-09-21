defmodule AshPlanningCenter.EventSnapshotTest do
  use ExUnit.Case, async: true

  alias AshPlanningCenter.EventSnapshot

  test "normalizes an authority-free event observation contract" do
    assert {:ok, snapshot} =
             EventSnapshot.new(%{
               event_ref: "event:youth-001",
               event_name: "Youth Night",
               starts_at: "2026-09-22T19:00:00-07:00",
               roster: [
                 %{slot_ref: "slot:registration", person_ref: "person:tanner", role: "registration"}
               ],
               registrations: [
                 %{registration_ref: "reg:1", person_ref: "person:student-opaque", status: "registered"}
               ],
               check_ins: [
                 %{check_in_ref: "check:1", person_ref: "person:student-opaque", status: "present"},
                 %{check_in_ref: "check:2", person_ref: "person:student-opaque", status: "present"}
               ],
               source_refs: ["pco:event:youth-001"]
             })

    contract = EventSnapshot.to_contract(snapshot)

    assert contract.contract_version == "zoe-event-ops/v1"
    assert contract.provider == "planning_center"
    assert contract.authority_boundary == "OBSERVE"
    refute contract.do_authority
    assert contract.standing == "UNKNOWN"
    assert contract.evidence_ceiling == "CONTRACT_ONLY"
    assert contract.counts.roster == 1
    assert contract.counts.registrations == 1
    assert contract.counts.check_ins == 1
  end

  test "refuses participant PII instead of silently projecting it" do
    assert {:error,
            {:unsupported_participant_fields, :registrations, 0, ["first_name"]}} =
             EventSnapshot.new(%{
               event_ref: "event:youth-001",
               event_name: "Youth Night",
               starts_at: "2026-09-22T19:00:00-07:00",
               registrations: [
                 %{
                   registration_ref: "reg:1",
                   person_ref: "person:opaque",
                   first_name: "Minor"
                 }
               ]
             })
  end

  test "refuses missing opaque identities on participant records" do
    assert {:error, {:missing_participant_fields, :check_ins, 0, ["person_ref"]}} =
             EventSnapshot.new(%{
               event_ref: "event:youth-001",
               event_name: "Youth Night",
               starts_at: "2026-09-22T19:00:00-07:00",
               check_ins: [%{check_in_ref: "check:1"}]
             })
  end
end
