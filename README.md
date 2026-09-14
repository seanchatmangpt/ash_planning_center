# AshPlanningCenter

Ash-native, observation-first Planning Center integration.

`ash_planning_center` presents remote Planning Center entities as canonical Ash resources and composes the ecosystem's existing machine-facing frameworks instead of recreating their responsibilities locally.

## DfCM composition

```text
Planning Center JSON:API                 Planning Center / Church Center UI
          |                                           |
          v                                           v
AshPlanningCenter.Client                    ash_surface Playwright observer
          |                                           |
          v                                           v
canonical Ash.Resource/actions  <---- AshSurface.Observation
          |
          +---- ash_a2a: public Ash action -> machine capability projection
          |
          +---- ash_pplan: FOND/HDDL admission and policy validation
          |
          `---- AshPlanningCenter.Surface: OBSERVE-only composition
```

Ownership is explicit:

- **Ash** is domain/action truth.
- **ash_surface** owns WAI-ARIA/Playwright observation and observation receipts.
- **ash_a2a** derives machine capabilities from canonical public Ash actions.
- **ash_pplan** validates the nondeterministic observation policy; it does not receive DO authority here.
- **ggen_igniter** manufactures the surface projection from the canonical RDF/SPARQL/template pack.

AshStateMachine, AshOban, Reactor, AshR2RML, and AshAI remain explicit exclusions for this specialization: there is no persistent local lifecycle, background activation, multi-step execution graph, relational RDF subject, or semantic unknown requiring an LLM at the current OBSERVE boundary. An exclusion is a topology fact, not a rejection of those frameworks globally.

## Authority boundary

The public network boundary admits GET only. Planning Center writes, browser click/fill/submit, and planner execution are outside this package's current authority.

```text
OBSERVE -> receipt
SELECT/CONSTRUCT/DO -> outside ash_planning_center v26.9.13
```

`UNKNOWN` live-account or live-browser behavior is never promoted to `ALIVE` by compilation, fixtures, or generated contracts.

## Surface contract

The canonical source is `priv/ggen/planning-center-surface/ontology.ttl`. `mix ash_planning_center.generate_surface` projects it through SPARQL and ggen into `lib/ash_planning_center/generated/surface/contract.ex`.

```elixir
{:ok, probe} =
  AshPlanningCenter.Surface.probe(
    :link,
    "marketplace-registration",
    "Register",
    denotes: "planning-center:event:marketplace"
  )

probe["role"]
#=> "link"
```

Unknown kinds such as CSS selectors or XPath are typed refusals, not guessed locators.

The actual Playwright adapter remains owned by `ash_surface`:

```elixir
AshPlanningCenter.Surface.playwright_adapter_path()
```

That path lookup does not launch a browser. Live Planning Center/browser execution is a separate verification tier.

## Machine capabilities

`AshPlanningCenter.Domain` uses `AshA2A`. The capability index is therefore derived from the domain's canonical public Ash actions rather than maintained as a second action registry.

```elixir
AshPlanningCenter.Surface.a2a_capabilities()
```

The current resource exposes reads only, so the projected machine capability set is also read-only.

## Formal observation policy

The observation attempt is admitted as a bounded FOND transition:

```text
unobserved --observe--> observed | refused
```

Both terminal outcomes are safe goals. `AshPlanningCenter.Surface.observation_policy/0` asks `ash_pplan` to validate that policy as strong; it executes no browser, Planning Center request, Reactor graph, queue, or external action.

## Authentication

Planning Center supports Personal Access Tokens and OAuth bearer tokens.

```elixir
config :ash_planning_center,
  auth: {:basic, System.fetch_env!("PCO_APPLICATION_ID"), System.fetch_env!("PCO_SECRET")}
```

or:

```elixir
config :ash_planning_center,
  auth: {:bearer, System.fetch_env!("PCO_ACCESS_TOKEN")}
```

The default base URL is `https://api.planningcenteronline.com`; controlled tests can override `:base_url`.

## People

```elixir
people = AshPlanningCenter.Domain.list_people!()
person = AshPlanningCenter.Domain.get_person!("123")
```

Reads default to 25 results and are capped at 100 per Ash read. Bounded remote scanning stops at 1,000 remote records and refuses unsupported Ash sorting rather than approximating it.

## Verification

Repository qualification is exact-head and repository-native:

```bash
mix deps.get
mix ash_planning_center.generate_surface
git diff --exit-code -- lib/ash_planning_center/generated/surface/contract.ex
mix ash_planning_center.generate
git diff --exit-code -- lib/ash_planning_center/generated/people/person.ex
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix hex.build
```

The complementary framework pins point at exact repository commits so this PR qualifies the repository-native composition actually inspected. Package construction is evidence only; publication remains a separate authority and compatibility decision.
