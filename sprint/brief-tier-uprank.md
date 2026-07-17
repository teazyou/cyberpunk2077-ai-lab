# Brief — Feature: tier-uprank (30% enemy rank upgrade)

## Goal
Every eligible enemy gets, exactly once, a 30% chance to be upgraded ONE rarity tier at (or shortly after) spawn.

## Decisions (user-confirmed, binding)
- Ladder: Trash → Weak → Normal → Rare → Officer → Elite. Elite is the ceiling.
- Never upgraded: already-max-tier (Elite), Boss, MaxTac.
- Eligibility (shared helper with duplication): HUMAN(OID) combat NPCs only. Excluded: quest/named/scripted-unique NPCs, bosses, MaxTac, police/prevention units, mechs/turrets/drones/robots, civilians/crowd.
- Trigger: game-thread periodic sweep (~0.5–1 s) around the player catching newly streamed NPCs (Scanner Suite pattern). NOT per-entity OnGameAttached (crash rule #2).
- Roll ONCE per entity per session (in-memory seen-set; re-stream while the session lives must not re-roll/stack). Save/reload may re-roll — accepted.
- Scope: everywhere incl. quest encounters (exclusions above still apply).
- F2 clones DO roll this 30% too (it is their only roll).
- Mechanism: literal rarity/record upgrade if runtime-feasible in pure REDscript; else stat-emulated tier (HP/damage/level ≈ next tier, multipliers justified from game data). Research decides; plan states chosen mechanism + fallback ladder.
- Rewards: natural — whatever the mechanism yields; no reward-tampering code for upranked enemies.
- 30% = tunable const. Single-tier bump only, never stacking.
- Debug: notify (HUD+log) on each uprank — who, old tier → new tier. Toggle const, default ON.

## Research questions (starting set — director may reshape)
1. Can an NPC's rarity / character record change at runtime in pure REDscript? (NPCPuppet APIs, level/rarity setters, record swap paths.) Vanilla evidence required.
2. Where does rarity manifest (health-bar tier icon, stats, XP, loot) and which changes propagate live post-spawn?
3. Stat-emulation fallback: which StatsSystem/StatPoolsSystem modifiers (Health, damage-related, Level, Armor…) reproduce a one-tier jump; per-tier deltas sourced from game data (TweakDB reads are OK — read-only).
4. Reading current rarity + boss/MaxTac flags (gamedataNPCRarity, IsBoss(), …).
5. Health StatPool behavior after a max-health buff (is a refill/re-sync needed?).

## Acceptance seeds (planner expands)
- Static: 30% const; single roll per entity per session; exact ladder + ceiling; each exclusion backed by a verified predicate; verified-API-only; compile clean; debug toggle; NO per-entity OnGameAttached; no reward tampering; clones processed exactly once.
- Manual: visible tier/power jump on ~3/10 street enemies; bosses/police/drones untouched; no repeat-uprank on walking away and back.
