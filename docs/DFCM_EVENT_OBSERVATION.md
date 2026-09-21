# DfCM event observation seam

This repository contributes one bounded surface to the ZOE whole-event simulation:

```text
Planning Center
  -> AshPlanningCenter.EventSnapshot
  -> zoe.event.observation.v1 (OBSERVE only)
  -> XaaS whole-event simulator
  -> SA2A candidate obligations
  -> Zoela projection
```

DfCM rule: preserve Planning Center as the remote source of record and preserve all
later routing possibilities. This package therefore normalizes operational facts but
does not select a worker, infer authority, dispatch a command, write Planning Center,
emit an execution receipt, or promote standing.

The snapshot carries registration/check-in/volunteer counts, roster completeness,
attendance-submission state, registration exceptions, and deterministic team counts.
Other sensors (security, facilities, first aid, parking, accessibility, etc.) can be
composed by XaaS without forcing those concepts into Planning Center.

The deterministic SHA-256 digest binds the exact observed snapshot. Reordering team
map keys cannot change the digest.

## Evidence ceiling

A green unit/CI court proves only the local observation contract. Live Planning Center
account behavior, SA2A dispatch, XaaS actuation, Zoela device execution, and real-world
event standing remain outside this repository's evidence ceiling.
