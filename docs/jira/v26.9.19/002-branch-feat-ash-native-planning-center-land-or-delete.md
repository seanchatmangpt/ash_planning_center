# ash_planning_center: land or delete remote branch `feat/ash-native-planning-center`

- Standing: OPEN
- Created: 2026-09-19 (v26.9.19 gh survey wave)
- Source: remote branch `feat/ash-native-planning-center` — not merged into `main`, no open PR
- Evidence: `git branch -r --no-merged origin/main` lists it; absent from `gh pr list` heads

## Work to complete
- Decide: open a PR (`gh pr create -R seanchatmangpt/ash_planning_center --head feat/ash-native-planning-center`) or delete (`git push origin --delete feat/ash-native-planning-center`).
- If superseded, delete; otherwise land through review.

## Acceptance
- After `git fetch --prune`, `git branch -r --no-merged origin/main` no longer lists `feat/ash-native-planning-center`.

## History
- 2026-09-19 | OPEN | survey found PR-less unmerged branch | feat/ash-native-planning-center | decision pending
