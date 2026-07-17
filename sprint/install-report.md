# Install Report — custom-enemy-overhaul

Deployed: 2026-07-17. Role: Installer (opus-max). Single source of truth for mod ops: `mod-manager.md`.

## Outcome
- installed: **true**
- registry_updated: **true** (entry added to `mod-manager.md`)
- compile_clean: **true** (scc-serial exit 0 + "Output successfully saved")

## Preconditions verified (both passed → proceeded)
1. **All four `sprint/acceptance-*.md` static checklists fully `[x]`.** Verified by grep: every unchecked box (`- [ ]`) in all four files lives ONLY under the "Manual in-game test plan" section (user-run, reviewer never ticks). Every item under each "Static checklist" header is `[x]`.
   - acceptance-common.md: static S1–S25 all `[x]`; only M1 unchecked (manual).
   - acceptance-tier-uprank.md: static S1–S38 all `[x]`; only M1–M12 unchecked (manual).
   - acceptance-enemy-duplication.md: static S1–S43 all `[x]`; only M1–M12 unchecked (manual).
   - acceptance-aggro-range.md: static S1–S32 all `[x]`; only M1–M10 unchecked (manual).
2. **Staging baseline refreshed from the live game, then compile clean.**
   - `rsync -a --delete --exclude 'custom-enemy-overhaul' "<GAME>/r6/scripts/" sprint/staging/r6/scripts/` → rc 0 (our mod dir preserved in staging; all other enabled mods re-baselined from the live game).
   - `sprint/bin/scc-serial.sh` → exit 0.

## Files placed
Canonical source stays in `sprint/impl/custom-enemy-overhaul/`. Deployment copies were placed through the `r6-scripts` portal (symlink `mods/enabled/r6-scripts` → `<GAME>/r6/scripts`), so they are live in-game:

| Deployed path (portal) | Resolves to (live game) | Bytes |
|---|---|---|
| `mods/enabled/r6-scripts/custom-enemy-overhaul/EnemyOverhaul.Common.reds` | `<GAME>/r6/scripts/custom-enemy-overhaul/EnemyOverhaul.Common.reds` | 12854 |
| `mods/enabled/r6-scripts/custom-enemy-overhaul/EnemyOverhaul.TierUprank.reds` | `…/custom-enemy-overhaul/EnemyOverhaul.TierUprank.reds` | 18316 |
| `mods/enabled/r6-scripts/custom-enemy-overhaul/EnemyOverhaul.Duplication.reds` | `…/custom-enemy-overhaul/EnemyOverhaul.Duplication.reds` | 33656 |
| `mods/enabled/r6-scripts/custom-enemy-overhaul/EnemyOverhaul.AggroRange.reds` | `…/custom-enemy-overhaul/EnemyOverhaul.AggroRange.reds` | 19065 |

`<GAME>` = `/Users/teazyou/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077`.
All four verified byte-identical (`diff -q`) between `sprint/impl/` and the portal copies. No `.archive`, `.xml`, or `.ini` shipped (pure REDscript mod). Slug `custom-enemy-overhaul`, module namespace `EnemyOverhaul`.

## Registry entry added
`mod-manager.md` gained one entry, `### Gameplay: Custom Enemy Overhaul`, placed immediately after `### Gameplay: Custom Scanner Suite` (kept in the custom-local cluster). Mirrors the custom-scanner-suite precedent: `COMPAT: ✅ REDscript only (locally authored …)`, `STATE: ENABLED`, `URL: — (custom local mod, not from Nexus)`, `TOTAL DLS: —`, `FILES:` the four portal paths, plus a NOTE recording AI-built via sprint 2026-07-17, source `sprint/impl/custom-enemy-overhaul`, features (30% tier-uprank / 20% enemy duplication / aggro-range clean-room port of Nexus 19351), the OnGameAttached wrap-chain + F3 @replaceMethod collision surface, crash-safety posture, and the pending manual tests. No other mod's files or entries were touched.

## Compile evidence
Command: `sprint/bin/scc-serial.sh` (the only sanctioned compile gate — global lock, refreshes `staging/r6/scripts/custom-enemy-overhaul` from `sprint/impl`, compiles the FULL staging set = live game scripts + all enabled mods; never touches the live game dir or `GAME/r6/cache`).

Result:
```
[INFO] Compiling files in …/sprint/staging/r6/scripts:
… (48 mod/script files incl.)
custom-enemy-overhaul/EnemyOverhaul.Common.reds
custom-enemy-overhaul/EnemyOverhaul.TierUprank.reds
custom-enemy-overhaul/EnemyOverhaul.AggroRange.reds
custom-enemy-overhaul/EnemyOverhaul.Duplication.reds
…
[INFO] Compilation complete
[INFO] Output successfully saved to …/sprint/staging/r6/cache/final.redscripts
[scc-serial] exit=0
```
All four custom-enemy-overhaul files compiled. Exit 0 + "Output successfully saved" = clean.

**Warnings (5) are all PRE-EXISTING and belong to OTHER mods — none from custom-enemy-overhaul:**
- `simple-untrack-quest/untrackQuestByRightClick.reds:1` + `better-fast-travel-map-redscript/BetterFastTravelMap.reds:60` — two `@replaceMethod(WorldMapMenuGameController)` on the same method (known benign vault conflict, last-compiled wins).
- `disassemble-loot/dalc_base.reds:113` — redundant `PlayerPuppet`→`GameObject` cast.
- `drink-at-the-counter/DrinkAtTheCounter.reds:7,27` — `Equals` on unrelated types (future-deprecation warning).

These predate this install and are unrelated to the new mod.

## Not done (per role constraints)
Did NOT launch the game, run raw scc against the GAME dir, touch `GAME/r6/cache`, or modify any other mod's files/entry. Next launch: `script/launch_modded.sh` recompiles automatically at startup (Steam must be running), producing the in-game cache from the now-deployed scripts.

---

# MANUAL TEST PLAN (user-run next launch)

Launch with `script/launch_modded.sh` (recompiles at startup). All three features default `Enable*=true` and `DebugNotify=true`. Debug notify = HUD activity-log one-liner + `FTLog`. Toggles/tunables live in the USER CONFIG block at the top of each feature `.reds` (edit literal + relaunch). These are copied verbatim from the three feature acceptance files; the reviewer never ticks them — they are yours to run.

> **Common (`EnemyOverhaul.Common.reds`) is passive by design** — no hooks, loops, or notifies of its own. Its single manual check (acceptance-common M1: inertness) is only meaningful with Common as the SOLE EnemyOverhaul file installed, which is not this deployment. Common's correctness is instead exercised through the three feature plans below (no re-roll on re-stream = uprank ledger; no XP / no loot = clone registry incl. const path; exclusion silence = eligibility composite; every debug line = `EO_Notify`).

## F1 — Tier Uprank (`EnemyOverhaul.TierUprank.reds`)

- [ ] M1 **Path probe.** Load any save with `DebugNotify=true`. Within seconds of spawn, the log/HUD shows the 5 ladder-probe lines with rarityValues 2.0 / 3.0 / 4.0 / 4.5 / 5.0. Any `MISSING` line = web-sourced path wrong → report the exact path string (feature keeps running in rung-b PowerLevel-only mode).
- [ ] M2 **~30% hit rate.** Enter a street/gang area with ~10 low-tier hostiles (e.g. a Watson gang hangout). Expect roughly 3 uprank notifies (binomial spread 1–6 of 10 is normal), each naming the NPC, old→new tier, and an hp before→after jump.
- [ ] M3 **Felt power jump, not badge.** Fight one notified enemy and one non-notified same-pack enemy: the upranked one shows a larger health pool and survives noticeably longer. Its nameplate badge does NOT change — that is EXPECTED (badge reads the frozen rarity); a missing badge change is not a failure. Note: Rare→Officer upranks read weaker than other rungs (Officer inherits Rare's stat block; the PowerLevel/Level bump carries that rung).
- [ ] M4 **No re-roll on re-stream.** After notifies fire, walk ~100 m away (out of `SweepRange`) and return to the same group: NO second notify for the same NPCs, and no further hp growth (no stacking).
- [ ] M5 **Exclusions silent — police/MaxTac.** Provoke a wanted level: police and MaxTac units produce ZERO uprank notifies.
- [ ] M6 **Exclusions silent — non-humans & civilians.** Around drones/mechs/turrets/robots and civilian crowds: ZERO uprank notifies.
- [ ] M7 **Exclusions silent — boss.** In any boss encounter: ZERO uprank notify for the boss (generic human adds in the arena MAY uprank — allowed).
- [ ] M8 **Quest encounters.** During a quest firefight: generic quest mooks may uprank (in-scope by design). If a clearly named/unique non-boss NPC ever gets a notify, log who — accepted residual of the best-effort quest filter, report for posture review, not a defect.
- [ ] M9 **Save/reload.** Reload a save where upranks had fired: buffs are gone and fresh rolls may occur (accepted per brief). Verify no double-height hp (no stacking of an old buff under a new one) on any single enemy.
- [ ] M10 **F2 clones (only if duplication is active).** Spawned clones occasionally receive their own single uprank notify — exactly one roll each, never more.
- [ ] M11 **Tuning knob.** If upranked enemies do NOT feel tougher vs your own damage (ScalePlayerDamage compensation), raise `PowerLevelBump` to 3.0–4.0, recompile via `sprint/bin/scc-serial.sh`, retest M3. Do not add bare Health multipliers.
- [ ] M12 **Toggle check (optional).** With `DebugNotify=false`: no HUD/log lines while fights still show the M3 power jump. With `EnableTierUprank=false`: no upranks and no loop activity at all.

## F2 — Enemy Duplication (`EnemyOverhaul.Duplication.reds`)

Run with defaults (`DuplicationEnabled=true`, `DebugNotify=true`). **M1 is the GATE for Posture B: if it fails, flip `DuplicationEnabled` default to `false` (plan Rung 2), re-verify S6, and skip M2–M12.**

- [ ] M1 **Spawn probe (GATE).** Approach a street gang group (e.g. Maelstrom/Valentinos, no police heat active). Expect on ~1 in 5 eligible enemies: HUD lines `roll OK` → `req #<id>` → `harvest #<id> n=1 success=true` → `wired clone=<id>`, and a visible extra enemy appearing near the source. FAIL SIGNATURE = `req #` lines with NO matching `harvest` line (native rejected arbitrary records / no-heat context) → Posture A per plan Rung 2.
- [ ] M2 **Rate & once-only.** Across ≥20 distinct eligible enemies, roughly 2/10 bring a friend (accept ~1–4/10); leaving and re-approaching the same living NPC never produces a second roll or second clone.
- [ ] M3 **Fights immediately.** Each clone enters combat within a few seconds of appearing, targets the player/allies like its source, no idle statue-standing.
- [ ] M4 **Placement sanity.** No clone floats in the air, clips inside walls, or spawns out of reach; in navmesh-hostile spots (ledges, cramped geometry) `placement FAIL — skip` lines appear and no clone spawns.
- [ ] M5 **Identity (verbatim default).** Clones visually/behaviorally match the source archetype family (same faction look/weapons class), consistent with `UseFactionPools=false`.
- [ ] M6 **No XP.** Killing a clone yields no XP/skill-proficiency ticks and no bounty payout (compare against killing its source: source pays normally).
- [ ] M7 **No loot.** A clone's corpse shows no loot highlight/mappin/prompt and drops no weapon into the world; source corpses loot normally.
- [ ] M8 **Exclusions hold.** Bosses, MaxTac, police (NCPD scanner hustles with officers present), mechs/drones/turrets, and civilians NEVER duplicate — no `req #` lines fire for them.
- [ ] M9 **Transient persistence.** Save mid-encounter with a live clone, reload — clone despawning on reload is ACCEPTABLE; there must be no save corruption, no permanently lingering duplicate, and no re-spawn stacking after repeated save/reload cycles.
- [ ] M10 **Heat-sweep lifecycle (observation).** With a live clone present, gain then lose police heat (or let a chase end). Note whether clones vanish on heat-state changes (`RequestDespawnAll` native sweep). Acceptable for transient clones — document per plan Rung 3; report frequency.
- [ ] M11 **Quest encounter safety.** Complete one "neutralize all enemies"-style objective (gig/NCPD hustle) with duplication active and a clone spawned inside it — the objective must still complete after all enemies incl. the clone die. If a kill-counter wedges, flip `DuplicationEnabled=false` and report (plan Risk 3).
- [ ] M12 **Depth cap & F1 interplay.** Observed clones NEVER spawn their own friend (no `roll OK`/`req` lines keyed to a clone id); occasionally a clone gets F1's uprank notify (its allowed single uprank roll) — confirming clones are F1-eligible but duplication-immune.

## F3 — Aggro Range (`EnemyOverhaul.AggroRange.reds`)

- [ ] M1 **Gunfire draws enemies from ~50 m (the headline).** Exterior, any standard district (e.g. Watson street): find a gang cluster, back off to ~40–45 m (scanner distance readout or count ~55 paces), fire an UNSILENCED gun into the air. Enemies alert/investigate/converge, and with `DebugNotify=true` a `district gunshot range 30 -> 50` (per shot, throttled) and/or `gunshot accepted beyond vanilla range` line appears. Vanilla would ignore at >30 m.
- [ ] M2 **Same-group pile-on vs player.** Attack ONE member at the edge of a spread-out gang group: nearby same-gang NPCs (including ones not directly stimulated) join against you, with `ally joins vs player` debug lines. Vanilla frequently leaves distant group-mates passive.
- [ ] M3 **Explosions always alert.** In combat with enemies ~20–30 m away, detonate an explosion near yourself (or use the ground-slam perk if owned): enemies react — `explosion accepted beyond vanilla range` (and for ground-slam an `Explosion radius 0 -> 50` injection line). No explosion within earshot is ever shrugged off.
- [ ] M4 **NPC gunfire carries 50 m.** Trigger an NPC-vs-NPC or NPC-vs-you firefight, retreat to ~40–50 m: other enemy NPCs around the shooters still alert (record-fallback path: `Gunshot radius 0 -> 50` injection lines while NPCs shoot).
- [ ] M5 **Dogtown stays quieter (30 m, not 50).** In Dogtown, repeat M1 from ~40 m: NO reaction from unalerted enemies to the shot's primary stim; from ~25 m they react. Debug shows `district gunshot range 20 -> 30`.
- [ ] M6 **Silenced stealth intact.** With a silenced weapon, shoot from 15–20 m of unalerted enemies (no kill, miss into a wall): no squad-wide aggro beyond vanilla behavior, and NO injection/extended-range debug line mentioning SilencedGunshot — silenced radius stays vanilla 8 m.
- [ ] M7 **Danger-range widening (35 m).** While IN combat, have a distant second group ~20–30 m from your gunfire line of retreat: they stop ignoring the fight (vanilla ignores combat stims beyond 12 m when unengaged) — `accepted beyond vanilla range` lines cite distances between 12 and 35 m.
- [ ] M8 **Parity spot-checks (unchanged behaviors).** Interior gunfire still only draws ~25 m; thrown grenades alert at their normal per-grenade radius (no bigger than vanilla); police behavior unchanged outside chases.
- [ ] M9 **Throttle + toggles.** Sustained autofire produces at most ~1 debug line per `DebugThrottleSec` (5 s), not per shot. `DebugNotify=false` → zero lines, behavior unchanged. `EnableAggroRange=false` + recompile → vanilla ranges return (M1 shot at 40 m ignored), zero injection lines.
- [ ] M10 **D5 oddity watch (report-only).** If during NPC-vs-NPC fights you see nonsensical helping (an NPC aiding the victim of its own faction-mate), note the factions involved — that is the literal-parity affiliation leg (plan D5/Risk 1) surfacing; report for the "owner vs ally" one-line variant decision, not a defect.
