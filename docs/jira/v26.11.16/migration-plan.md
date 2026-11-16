# ash_planning_center migration plan v26.11.16

Standing: UNVERIFIED

## Identity
- Path: /Users/sac/ash_planning_center
- Remote: https://github.com/seanchatmangpt/ash_planning_center.git (origin)
- Branch: main@f555e86 — last commit 2026-10-07 — 3 commits — 0 MB (tiny)
- Languages/build: Elixir (mix.exs, .formatter.exs), GitHub workflows
- Nested repos: none

## Observed state
- Dirty 0; untracked 6: docs/ (docs/jira/v26.9.19, v26.11.12) and mix.lock
- ahead 0 / behind 0 origin/main; stash 0
- Unpushed local branches 2: feat/v26.9.21-zoe-live-observation (8ea7cc5),
  v26.9.13/accessibility-surface (8123d9b) — neither has an upstream
- Build dirs: none (_build/deps absent)

## What it is
Ash-native resources and manual actions wrapping the Planning Center JSON:API (People
list/get, PAT and OAuth auth). Planning Center stays the system of record.

## Classification
ACTIVE (census agrees).

## Migration risk
- 2 local-only branches with real commits (event-reader hardening, accessibility surface)
- Untracked mix.lock and docs/jira/ history
- No .env / secrets observed
Rate: MEDIUM

## Recommended action
COMMIT-PUSH
1. `cd /Users/sac/ash_planning_center && git add docs mix.lock &&
   git commit -m "chore(v26.11.16): track mix.lock and jira docs"`
2. `git push origin main`
3. `git push -u origin feat/v26.9.21-zoe-live-observation`
4. `git push -u origin v26.9.13/accessibility-surface`
5. Nothing to clean; directory is tiny. Re-clone on the new machine.

## First commands on the new machine
`mix deps.get && mix compile --warnings-as-errors && mix test` (stated, not run).

## See Also
- ../v26.11.12/
- /Users/sac/docs/jira/v26.11.16/README.md
