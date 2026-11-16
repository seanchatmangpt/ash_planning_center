# TODO-FIX-AND-FINISH (ash_planning_center)

Standing: UNVERIFIED

Source: `ash_surface/docs/jira/v26.11.11/PROJECT-REVIEWS.md` R7, re-read where marked confirmed.

## Fix

- MED `priv/ggen/planning-center-people/templates/resource.ex.eex:7-9` interpolates
  `row["name"]`/`row["ash_type"]` into Elixir source unvalidated (confirmed). Check: hostile
  name in fixture is refused by a court.
- MED `lib/ash_planning_center/open_api.ex:37-68` output-path interpolation UNVERIFIED (not read).
- MED `json_api.ex:64` `struct(resource, projected)` no type casting (confirmed). Check: typed
  decode test.
- MED `people/person.ex:22` silent default `limit || 25` truncation (confirmed); filter/limit
  untested UNVERIFIED. Check: limit/offset court passes.
- LOW `generated/people/person.ex:13-15` all attributes `public?: true` (confirmed).
- LOW `client.ex:139` `auth_shape(other)` passthrough echo (confirmed); lossy type map
  `open_api.ex:93,137-142` UNVERIFIED.

## Finish

- Validate identifiers in codegen before render. Check: `mix test` codegen refusal case.
- Pin CI toolchain (UNVERIFIED; workflow not read). Check: workflow pins versions.

## Commit hygiene

- `mix.lock` and `docs/` untracked (confirmed `??`; `git ls-files mix.lock` empty). Check:
  both tracked after commit.

## Decide

- Keep generated resources public by default, or add a sensitive-field list?

## Reuse

- `json_api.ex:43-71` name-based projection; `open_api.ex:90-142` type table (UNVERIFIED lines).

## See Also

- `ash_surface/docs/jira/v26.11.11/PROJECT-REVIEWS.md` R7
