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
