# Role: Common-Module Consolidator (fable-max)

Merge the three feature plans' `common_needs` + the plan files into ONE shared-infrastructure design for `EnemyOverhaul.Common.reds`.

Deliverables: `sprint/plan-common.md` + `sprint/acceptance-common.md` (same formats as prompt-planner.md), defining the Common module EXACTLY — every public API signature feature files will import.

Design constraints:
- Module imports must be ACYCLIC: Common imports NOTHING from feature modules. Preferred shape: Common exposes utilities (shared eligibility predicates, once-per-session seen-sets/registry incl. clone-marking, RNG roll helper, debug notify, entity-enumeration helper) and each feature file arms its OWN loop via its own `PlayerPuppet.OnGameAttached` @wrapMethod (multiple wraps chain fine — ScannerSuite precedent). A single Common-owned loop with registration is acceptable ONLY if a verified pattern supports it. Pick the simplest verified design.
- Sweep pattern: DelaySystem self-re-arming callback, game-thread, ~0.5–0.75 s cadence; enumeration via the APIs verified in search_index (GetEntitiesAroundObject / GetEntityList / TargetingSystem parts).
- Session-unique entity keying exactly per search_index.
- Keep Common MINIMAL: only what ≥2 features need or what enforces safety (seen-sets, eligibility, notify).
- Verified-API-only; all global rules from context-environment.md apply.
- `acceptance-common.md`: static checklist incl. compile-clean, public API surface matches plan-common exactly, forbidden patterns absent. The manual section may be near-empty (Common alone has no visible behavior) — say so.
