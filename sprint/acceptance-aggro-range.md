# Acceptance — aggro-range (clean-room port of Nexus 19351)

Target file: `sprint/impl/custom-enemy-overhaul/EnemyOverhaul.AggroRange.reds`. Static items are verifiable by reading the file, running `sprint/bin/scc-serial.sh`, and grepping `sprint/vanilla-scripts` / `sprint/staging` / `sprint/reference-aggro` — never by launching the game. Manual items are user-run only.

## Static checklist (reviewer-verifiable against code/compile/greps ONLY — no game launch)

Compile & scope
- [x] S1 `sprint/bin/scc-serial.sh` exits 0 and prints "Output successfully saved" with `EnemyOverhaul.AggroRange.reds` present in `sprint/impl/custom-enemy-overhaul/`.
- [x] S2 File opens with `module EnemyOverhaul.AggroRange` (plus `import EnemyOverhaul.Common.*` only if a Common symbol is actually consumed).
- [x] S3 The implementation touched ONLY `EnemyOverhaul.AggroRange.reds` — no edits to `EnemyOverhaul.Common.reds`, other feature files, or any other repo file (verify via `git status`/diff scope).

USER CONFIG block
- [x] S4 A clearly-marked USER CONFIG block sits at the top and contains exactly these consts with exactly these defaults: `EnableAggroRange()=true`, `DangerRange()=35.0`, `VanillaDangerRange()=12.0`, `GunshotFallbackRadius()=50.0`, `ExplosionFallbackRadius()=50.0`, `DistrictGunshotRange()=50.0`, `DistrictGunshotRangeLow()=30.0`, `DistrictLowVanillaThreshold()=25.0`, `DebugNotify()=true`, `DebugThrottleSec()=5.0`.
- [x] S5 Hook inventory is EXACTLY: 2 × `@replaceMethod(ReactionManagerComponent)` (`ShouldIgnoreCombatStim` 8-arg, `ShouldHelpTargetFromSameAttitudeGroup`), 3 × `@wrapMethod` (`StimBroadcasterComponent.TriggerSingleBroadcast`, `StimBroadcasterComponent.OnBroadcastEvent`, `PlayerPuppet.GetGunshotRange`), 1 × `@addField(HUDManager)` (throttle Float), 1 × `@addMethod(HUDManager)` (notify funnel) — plus optional local `EOAR_` pure helpers/notify fallback; nothing else annotated.

Half A — `ShouldIgnoreCombatStim` (deltas D1–D4 + preserved vanilla logic)
- [x] S6 Replacement signature matches the vanilla 8-arg overload exactly (incl. both `out` Bool params and trailing `log: Bool`; `reactionComponent.script:2590`); the 5-arg shim (`:2583-2588`) is NOT redefined anywhere in the file.
- [x] S7 D1: the danger-range computation uses `DangerRange()` when enabled (35.0) and `VanillaDangerRange()` (12.0) on the toggle-off path; the literal `12.0` appears ONLY as the `VanillaDangerRange` default.
- [x] S8 D2: when enabled, the Explosion branch returns "not ignorable" WITHOUT requiring `inDangerRange`; toggle-off restores the vanilla conjunct.
- [x] S9 D3: when enabled, the illegal-action branch is `StimFilters.IsIllegal(...) && InGunshotCone(...)` with NO distance term (cone = 15-degree front-angle, direction-only); toggle-off restores `inDangerRange &&`.
- [x] S10 D4: when enabled, `!IsDefined(instigator)` → early `return false` regardless of `source`; toggle-off restores vanilla's `!source && !instigator` pair-guard; the `source = instigator` fallback assignment is preserved on both paths.
- [x] S11 Preserved vanilla-exact, in vanilla order: player-source gate; `StimFilters.CanBeIgnoredInCombat`; combat/grace block with `canDelay`→`canIgnoreOnlyDueToDelay` out-param semantics; `NPCPuppet.IsInCombatWithTarget` gate; `canIgnorePlayerCombatStim = true` set at the vanilla position; projectile check with literal `4.0` (NOT a config const); gunshot inDanger-OR-cone structure; `IsTargetVeryClose`; security-zone block; squadmate loop over `AISquadHelper.GetSquadmates`.

Half A — `ShouldHelpTargetFromSameAttitudeGroup` (deltas D5–D6 + police branch)
- [x] S12 Replacement signature matches the vanilla private method (`reactionComponent.script:5784`); annotation targets `ReactionManagerComponent`.
- [x] S13 D5: when enabled and both owner and `targetOfTarget as ScriptedPuppet` resolve, help is denied only if BOTH the affiliation records differ AND the attitude groups differ; otherwise (either unresolved, or toggle off) the vanilla attitude-group-only gate runs. The affiliation compare is owner-record vs `targetOfTarget`-record (LITERAL reference parity — a code comment marks it per plan D5), via `Equals`/`NotEquals` on the record handles or `GetID()` equality.
- [x] S14 D6: when enabled, `IsDefined(targetOfTarget)` alone yields `return true` (no `IsPlayer()` exemption); toggle-off restores `targetOfTarget && !targetOfTarget.IsPlayer()`.
- [x] S15 Police branch preserved semantics-equivalent: `IsChasingPlayer() && target.IsPrevention() && ownerPuppet.IsPrevention() && ShouldWorkSpotPoliceJoinChase(ownerPuppet)` → true, else false — unconditioned by the toggle.

Half B — chokepoint + district wraps
- [x] S16 `TriggerSingleBroadcast` wrap: forwards ALL five args to `wrappedMethod` exactly once on every path; injection happens ONLY when `EnableAggroRange()` AND `radius <= 0.0` AND stim type is exactly `gamedataStimType.Gunshot` (→ `GunshotFallbackRadius()`) or `gamedataStimType.Explosion` (→ `ExplosionFallbackRadius()`).
- [x] S17 `OnBroadcastEvent` wrap: `protected cb func`, returns `wrappedMethod(evt)`'s Bool, called exactly once on every path; adjusts `evt.radius` ONLY when `Equals(evt.broadcastType, EBroadcasteingType.Single)` plus the same enabled/type/`<= 0.0` gate as S16; no other event field is written.
- [x] S18 `SilencedGunshot` and `IllegalAction` are untouched: neither enum value appears in any radius-assignment path (grep the file — they may appear only in comments).
- [x] S19 No non-zero radius is ever modified at either chokepoint (no `MaxF`/uplift on explicit radii; the only radius writes are behind the `<= 0.0` gate).
- [x] S20 `GetGunshotRange` wrap: calls `wrappedMethod()` exactly once; disabled → returns the vanilla value unchanged; enabled → bucket map (`<= DistrictLowVanillaThreshold()` → `DistrictGunshotRangeLow()`, else `DistrictGunshotRange()`) wrapped in `MaxF(vanilla, bucket)`; no write to `m_gunshotRange`, no hook on `OnDistrictChanged`, `GetExplosionRange` untouched.

Forbidden patterns & purity
- [x] S21 No `continue` and no `break` keywords anywhere in the file.
- [x] S22 `OnGameAttached` appears NOWHERE in the file — no hook of any kind on it, on any class (this feature is stateless; absence is the requirement).
- [x] S23 No TweakDB writes (no `SetFlat`/`CreateRecord`/`TweakDBManager`); TweakDB access is `TweakDBInterface.Get*` reads only.
- [x] S24 No NEW stim emissions: `TriggerSingleBroadcast` appears only as the wrap declaration + its single forward; `SendStimDirectly`, `SendDrirectStimuliToTarget`, `AddActiveStimuli`, `SetSingleActiveStimuli` appear nowhere.
- [x] S25 No hook/reference to `StimBroadcasterComponentHelper.CreateStimEvent` / `ProcessSingleStimuliBroadcast` (native imports — off-limits as hook targets).
- [x] S26 Replace-collision grep over `sprint/staging/r6/scripts/` (all enabled mods): no OTHER `@replaceMethod` (or `@wrapMethod`) on `ShouldIgnoreCombatStim` / `ShouldHelpTargetFromSameAttitudeGroup` outside this mod's own file.
- [x] S27 No per-entity state: no `array<EntityID>` ledger, no `RandF`/`RandRange`, no `DelayCallback` loop — the file's only mutable state is the single HUDManager throttle Float.
- [x] S28 Verified-API-only spot-check: pick ≥3 engine APIs used in the file at random; each must be declared in `sprint/vanilla-scripts` at (approximately) the plan's cited file:line, or be an in-game-proven ScannerSuite call; zero APIs outside the plan/dossier inventories.
- [x] S29 Clean-room check vs `sprint/reference-aggro/r6/scripts/Enemy Aggro Improvements/GunshotReactions.reds`: local identifiers differ from the reference's (`playerPuppet`, `affiliation1`, `affiliation2`, `targetPuppet`, ...), no commented-out-vanilla-line style copied, comments original; vanilla-derived log strings are permitted.

Debug wiring
- [x] S30 Every notify site routes through one throttled funnel: gated by `DebugNotify()`, throttled by `DebugThrottleSec()` using `EngineTime.ToFloat(GameInstance.GetSimTime(...))`, emitting BOTH `AddLog` and `FTLog` (via Common `EO_Notify` or the local `EOAR_` fallback); the HUDManager resolve is `IsDefined`-guarded.
- [x] S31 Extended-range notify sites exist in all three widened branches of `ShouldIgnoreCombatStim` (gunshot / explosion / illegal) and fire only when `!IsTargetPositionClose(sourcePos, VanillaDangerRange())` (i.e. genuinely beyond vanilla); plus the D6 help-vs-player site, the D5 affiliation-leg site, and the chokepoint injection site(s).
- [x] S32 Toggle-off trace: with `EnableAggroRange()=false`, every delta demonstrably reverts on code inspection — danger range 12, explosion requires `inDangerRange`, illegal requires `inDangerRange`, vanilla instigator pair-guard, vanilla help gates incl. `!IsPlayer()` exemption, zero injection, district map pass-through.

## Manual in-game test plan (user-run; the reviewer NEVER ticks these)

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
