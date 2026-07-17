# Brief — Feature: aggro-range (clean-room REDscript port of Nexus mod 19351 "Enemy Aggro Improvements")

## Goal
Reproduce the ORIGINAL mod's observable behavior in PURE REDscript (macOS-safe). Clean-room rewrite: own code/structure/naming, same behavior. Original's values as tunable constants.

## Original mod dissection (reference files: sprint/reference-aggro/)
Half A — REDscript, 2 `@replaceMethod(ReactionManagerComponent)` [portable as-is, but we REWRITE clean-room]:
1. `ShouldIgnoreCombatStim`: danger range 12 → 35 m; Explosion stims NEVER ignorable (range gate removed); illegal-action stims not ignorable when in gunshot cone (range gate removed); rest ≈ vanilla logic.
2. `ShouldHelpTargetFromSameAttitudeGroup`: help allies of same Affiliation OR same attitude group; vanilla's `!targetOfTarget.IsPlayer()` gate removed → NPCs help allies against the PLAYER too; prevention join-chase behavior preserved.

Half B — TweakXL `.tweak` [NOT portable → needs a runtime REDscript equivalent or documented N/A]:
3. `stims.GunshotStimuli.radius` 30 → 50; `ExplosionStimuli.radius` 25 → 50; `SilencedGunshotStimuli` radius 8 (fear 10).
4. `District.gunShotStimRange` 30 → 50 (schema default + all districts).

## Decisions (user-confirmed, binding)
- Clean-room: fresh implementation in our style; reference consulted for behavior only, no copy-paste.
- Values: the original's (35 m danger range, 50 m gunshot/explosion radii, …), each a named const in the USER CONFIG block.
- Target = ENEMY combat-reaction parity. Crowd-panic side effects of stim radii: port only if the mechanism naturally carries them; do not chase separately.
- Research must determine for Half B: where gunshot/explosion stim RADIUS is set or consumed script-side (weapon-fire broadcast call sites, StimBroadcasterComponent, senses/receiver path), and which of knobs 3/4 actually drives ENEMY aggro vs crowd/NCPD-only effects. Port the driver(s); document the rest as N/A with reasons.
- Prefer @wrapMethod; @replaceMethod only where interleaved logic forces it (justify in plan).
- Debug: throttled log (HUD optional if cheap) when an extended-range reaction fires (stim accepted beyond vanilla range). Toggle const, default ON.

## Research questions (starting set — director may reshape)
1. Vanilla sources of both replaced methods (cite file:line) — diff vs the original mod to isolate the exact behavior deltas.
2. Gunshot stim lifecycle in scripts: who broadcasts (weapon fire events → SendStimuli/Broadcast* call sites), where the radius value originates (record read? literal param?), receiver path (ReactionManagerComponent / senses). Script-side hook points that could scale 30→50 / 25→50.
3. `District.gunShotStimRange`: any script-side readers? Does it affect enemy NPC senses at all, or only crime/prevention?
4. Silenced gunshots: vanilla radius/behavior; is the original's 8 m a change or a restatement?
5. Squad alert propagation: when one NPC aggros, how squadmates/allies join (AISquadHelper, squad signals) — the port must deliver "enemies converge from farther".
6. Pure-.reds aggro/detection mods as precedent.

## Acceptance seeds (planner expands)
- Static: behavior deltas 1–4 each mapped to a code mechanism OR documented N/A with evidence; values = original's, as consts; verified-API-only; wrap-over-replace justified where replace is used; compile clean; clean-room (no verbatim copies from reference); debug throttle + toggle.
- Manual: gunfire draws enemies from ~50 m (vs ~30 vanilla); attacking one enemy makes same-group allies pile on; explosions always alert nearby enemies.
