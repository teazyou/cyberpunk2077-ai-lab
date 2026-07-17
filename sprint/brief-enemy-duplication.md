# Brief — Feature: enemy-duplication (20% extra spawn)

## Goal
Every eligible enemy gets, exactly once, a 20% chance to spawn ONE extra enemy nearby.

## Decisions (user-confirmed, binding)
- Extra enemy identity: PREFERRED = same-faction random archetype; FALLBACK = exact clone of the source. Research decides feasibility; plan states the choice.
- Placement: near the source at a VALIDATED position (on ground/navmesh, not inside walls, not in the air). Prefer a smart placement/navigation query API; if no valid point is found → skip the spawn silently (no clone).
- Spawned enemy: hostile like the source (same faction/attitude toward player), joins the encounter naturally.
- Spawned enemy rolls F1 uprank (30%) but NEVER duplicates further (depth cap = 1 generation). Clones are marked (registry/tag) so sweeps treat them as already-processed-for-duplication.
- Eligibility: same shared filter as F1 — humans only; no quest/named, bosses, MaxTac, police, mechs/turrets/drones. Applies everywhere incl. quest encounters.
- Roll ONCE per source entity per session (in-memory seen-set).
- Rewards: clone yields NO XP and NO loot if achievable (kill-XP suppression, empty/cleared inventory, no dropped weapon, non-lootable corpse); else minimize best-effort — minimum bar: no lootable items. Plan documents exactly what is achievable.
- Persistence: prefer TRANSIENT spawns (not written into saves); despawn-on-reload acceptable. Clones must not linger/leak beyond normal NPC lifecycle.
- 20% = tunable const. Debug notify on each clone spawn (source, spawned record, position-validated). Default ON.

## Research questions (starting set — director may reshape)
1. Runtime NPC spawning from pure REDscript on 2.3: DynamicEntitySystem (`GetDynamicEntitySystem`, `DynamicEntitySpec` fields: recordID/appearance/position/persistState/…) — verify against vanilla sources; pure-.reds mod precedents?
2. Record selection: read source's CharacterRecord/Affiliation; feasible ways to pick same-faction alternatives (record enumeration? curated per-faction lists? community pools?). Fallback: reuse source record verbatim.
3. Position validation: NavigationSystem/navmesh nearest-point queries around a position; ground snap. Verified APIs only.
4. Attitude/hostility wiring post-spawn: does a spawned NPC inherit hostility from its record/faction? APIs to set attitude toward player/squad if needed.
5. Reward suppression: XP-on-kill path; NPC inventory clearing; loot/drop flags; corpse lootability.
6. Despawn/cleanup + persistState semantics of DynamicEntitySystem entities.
7. Risk: spawning during quest encounters — how encounters count kills (could an extra hostile break "kill all" triggers beyond what the named/quest exclusion already avoids?). Evidence, not speculation.

## Acceptance seeds (planner expands)
- Static: 20% const once per source; depth-1 recursion exact (clone rolls uprank only, never duplicates); identity preference honored + fallback documented; placement validated with skip-on-fail; exclusions exact; reward suppression per plan; transient persistence; compile clean; debug toggle; no per-entity OnGameAttached.
- Manual: ~2/10 enemies bring a friend; the friend fights immediately; no floating/wall-stuck clones; clone corpse gives no XP/loot; bosses/police never duplicate.
