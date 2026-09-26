# AshPlanningCenter

Ash-native resources and actions over the Planning Center API.

`ash_planning_center` follows Ash's supported external-API pattern: a remote
Planning Center entity is presented as an `Ash.Resource`, and network access is
performed by manual Ash actions. Planning Center remains the remote system of
record; callers get the normal Ash resource/action interface.

## Architecture

```text
Planning Center JSON:API
          |
          v
AshPlanningCenter.Client
          |
          v
manual Ash.Resource actions
          |
          v
AshPlanningCenter.People.Person
          |
          v
AshPlanningCenter.Domain
```

The transport and JSON:API decoder are generic. Product-specific endpoint
semantics remain in their Ash resources/actions. This deliberately preserves a
future path to promote repeated remote query semantics into a data layer without
making that abstraction a prerequisite for the first working integration.

## Current boundary

| Surface | Standing |
| --- | --- |
| JSON:API document decoding | implemented; verified by fake-transport tests when CI passes |
| Personal Access Token/basic authentication | implemented; live account verification still required |
| OAuth bearer authentication | implemented; live account verification still required |
| People list/get | implemented; live account verification still required |
| Ash filtering over bounded People reads | implemented by bounded remote scanning |
| Ash sorting | `UNSUPPORTED` until a semantics-preserving translation exists |
| Planning Center writes | `UNSUPPORTED` in this release |
| Services/Registrations/Check-Ins ZOE event composite | bounded GET reader implemented; live account receipt still required |
| Other Planning Center products | extension points only |

`UNKNOWN` live-account behavior is not promoted to `ALIVE` by mocked transport
or compilation alone.

## Installation

```elixir
def deps do
  [
    {:ash_planning_center, github: "seanchatmangpt/ash_planning_center"}
  ]
end
```

## Authentication

Planning Center supports Personal Access Tokens for single-organization tools
and OAuth bearer tokens for third-party integrations. Configure one of the
following at runtime:

```elixir
config :ash_planning_center,
  auth: {:basic, System.fetch_env!("PCO_APPLICATION_ID"), System.fetch_env!("PCO_SECRET")}
```

or:

```elixir
config :ash_planning_center,
  auth: {:bearer, System.fetch_env!("PCO_ACCESS_TOKEN")}
```

The default base URL is `https://api.planningcenteronline.com` and can be
changed with `:base_url` for a controlled test service.

## People

```elixir
people = AshPlanningCenter.Domain.list_people!()
person = AshPlanningCenter.Domain.get_person!("123")
```

Reads default to 25 results and are capped at 100 results per Ash read. The
manual read scans bounded remote pages when an Ash filter must be evaluated
locally. Planning Center-native query parameters can be supplied through the
`:remote_params` action argument for endpoint semantics that are not yet
promoted into Ash query translation.

```elixir
query =
  AshPlanningCenter.People.Person
  |> Ash.Query.for_read(:read, %{
    remote_params: %{"where[status]" => "active"}
  })
  |> Ash.Query.limit(50)

Ash.read!(query, domain: AshPlanningCenter.Domain)
```

## DfCM extension rule

Expand in this order:

1. reuse the transport and decoder;
2. model the remote entity as an Ash resource;
3. add a manual action with an explicit bounded capability;
4. verify remote semantics with fixtures and then a real Planning Center
   account;
5. only after repeated semantics are observed, compose or extract a reusable
   data-layer/generator abstraction;
6. introduce writes only through an explicit authority, consequence, receipt,
   and replay boundary.

This keeps reversible read possibilities broad while preventing an observed
remote object from silently acquiring write authority.


## ZOE event observation seam

`AshPlanningCenter.EventSnapshot` is the DfCM boundary for event-operation
simulation. It normalizes already-observed Planning Center data into
`zoe-event-ops/v1` without adding provider calls or write authority.

The contract is intentionally `OBSERVE`-only, carries `do_authority: false`,
and uses only opaque participant references. Registration and check-in records
refuse unadmitted fields such as names, email addresses, phone numbers, or
other youth PII. XaaS may consume the normalized snapshot for simulation, but a
simulation result is not evidence that Planning Center was read live and is not
a Planning Center write receipt.

This preserves the existing extension law: live Services/Check-Ins/Registrations
endpoints remain `UNSUPPORTED` until their real provider semantics are added
and verified independently.


## ZOE live observation reader

`AshPlanningCenter.EventReader` closes the code-path gap between the existing
`zoe-event-ops/v1` normalization contract and Planning Center's read APIs.

It accepts explicit provider identities for any combination of:

- Services plan team members:
  `/services/v2/service_types/{service_type_id}/plans/{plan_id}/team_members`
- Registrations signup attendees:
  `/registrations/v2/signups/{signup_id}/attendees`
- Check-Ins event check-ins:
  `/check-ins/v2/events/{event_id}/check_ins`

The reader hardcodes GET, validates provider IDs before transport, caps pagination,
drops provider PII, and emits only opaque participant references and operational
status through `AshPlanningCenter.EventSnapshot`.

A successful read returns an OBSERVE-only receipt with `do_authority: false`.

Provider pages are admitted, not trusted: a record that is not a map, lacks an
opaque id, or carries an id (or person relationship id) outside
`[A-Za-z0-9_-]` is a typed `malformed_provider_record` refusal; an identical
re-delivery across pages is observed once (`duplicates_dropped` in the
receipt) while the same id with different content is refused as
`conflicting_duplicate_record`; a negative/non-integer `total_count`, or one
below the records already delivered, is refused instead of silently
truncating. Observations are ordered by their opaque ref and the receipt
carries `observation_digest` (sha256 over the deterministic term encoding), so
provider reordering replays to the same digest and any changed record does not.
`mix run bench/event_reader_bench.exs` records timing; the regression ceiling
lives in `test/ash_planning_center/event_reader_bench_test.exs`.
Repository tests use an injected client and therefore prove `PARTIAL_ALIVE`
transport semantics, not a live ZOE Planning Center observation.

For an operator-controlled live probe, configure the existing Planning Center
authentication and run:

```bash
mix ash_planning_center.zoe_probe \
  --event-ref event:youth-night \
  --event-name "Youth Night" \
  --starts-at 2026-09-23T19:00:00-07:00 \
  --service-type-id SERVICE_TYPE_ID \
  --plan-id PLAN_ID \
  --signup-id SIGNUP_ID \
  --check-in-event-id CHECK_IN_EVENT_ID \
  --out /tmp/zoe-event-observation.json
```

The task has no write option and does not accept or print credentials. A real
provider response from that exact probe is the missing evidence needed to move
the corresponding live observation subject beyond UNKNOWN/PARTIAL_ALIVE.
