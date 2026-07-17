# Plan — aggro-range (clean-room REDscript port of Nexus 19351 "Enemy Aggro Improvements")

Owned file: `sprint/impl/custom-enemy-overhaul/EnemyOverhaul.AggroRange.reds`. Verdict: **FEASIBLE, both halves, no descope** — every hook shape compile-verified this sprint (P1/P4/P5/P6/P7), every API vanilla-verified (`sprint/vanilla-scripts` file:line below), director probe confirmed **no other enabled mod touches either replaced method**. Clean-room rule: the implementer writes from the VANILLA decompile + the delta list below; `sprint/reference-aggro/.../GunshotReactions.reds` is consulted for behavior questions only — no copied structure, names, or comments.

## Mechanism

**Half A — two `@replaceMethod(ReactionManagerComponent)`** (replace justified over wrap: every delta REMOVES a distance gate from the MIDDLE of an interleaved early-return chain — a wrap can only run before/after `wrappedMethod`, it cannot slice branches out of it; the original author faced the same constraint and also chose replace. P6/P7 probes compiled these exact replace shapes against full staging):

1. **`ShouldIgnoreCombatStim` 8-arg** (`reactionComponent.script:2590-2711`; the 5-arg shim `:2583-2588` forwards into it and is NOT redefined). Semantics: this method only ever evaluates PLAYER-sourced stims (`:2607-2610` returns false for non-player sources) and decides whether an NPC may IGNORE them; "return false" = must react. Behavior deltas (everything else stays vanilla-equivalent):
   - **D1 danger range 12→35 m**: `inDangerRange = this.IsTargetPositionClose(sourcePos, <danger>)` (`:2642`; helper `:5557-5562`, squared-distance) where `<danger>` = `DangerRange()` (35.0) when enabled, `VanillaDangerRange()` (12.0) when master toggle off.
   - **D2 Explosion never ignorable**: vanilla `if(stimType==Explosion && inDangerRange)` (`:2643`) loses the `inDangerRange` conjunct when enabled → `if Equals(stimType, gamedataStimType.Explosion) && (enabled || inDangerRange)`.
   - **D3 illegal-action range gate removed**: vanilla `if((IsIllegal && inDangerRange) && InGunshotCone(source, puppet))` (`:2670`) → drop `inDangerRange` when enabled. `InGunshotCone` (`:2578-2581`) = `IsTargetInFrontOfSource(shooter, target, 15.0, true)` (`:5455-5487`) — 15 is a front-angle in DEGREES, so after D3 this check is direction-only with NO distance cap. Reproduce as-is.
   - **D4 instigator-null guard (the reference's undocumented delta — parity requires it)**: vanilla `if(!source && !instigator) return false; if(!source) source = instigator;` (`:2599-2606`) → when enabled, `if !IsDefined(instigator) { return false; }` unconditionally, then the `source = instigator` fallback as vanilla; when disabled, vanilla's pair-guard. Net: stims with unset instigator are never ignorable even if `source` is the player.
   - **Preserved vanilla-exact** (structure and order): `CanBeIgnoredInCombat` filter (`:2611`, StimFilters class `:279`, fn `:391`); NPC/player-combat + `CombatGracePeriodPassed` block with the `canDelay`/`canIgnoreOnlyDueToDelay` out-param (`:2615-2627`; `CombatGracePeriodPassed` `:6235`; `PlayerPuppet.IsInCombat` `player.script:6469`); `NPCPuppet.IsInCombatWithTarget` gate (`:2629-2632`); `canIgnorePlayerCombatStim = true` assignment position (`:2633`); projectile 4.0 m check (`:2634-2641`, literal stays vanilla — original did not touch it); gunshot inDanger-OR-cone structure (`:2651-2669`, inherits D1 only); `IsTargetVeryClose` (`:2678`, helper `:5569-5572` — untouched); security-zone check (`:2686-2696`; `IsConnectedToSecuritySystem`/`IsTargetTresspassingMyZone` `gameObject.script:370,380`, overrides `scriptedPuppet.script:4364-4369`); squadmate loop (`:2697-2709`; `AISquadHelper.GetSquadmates` `aiSquadHelper.script:15-28`) — write as `for x in arr` with if-wrapper + early `return`, never `break`/`continue`.

2. **`ShouldHelpTargetFromSameAttitudeGroup`** (private, `:5784-5803`; call sites `:918`, `:1723` — there `target` = the ally candidate, `targetOfTarget` = that ally's combat target, frequently the player). Deltas:
   - **D5 affiliation OR attitude-group**: when enabled and BOTH `ownerPuppet` and `targetOfTarget as ScriptedPuppet` resolve: fetch each's `TweakDBInterface.GetCharacterRecord(GetRecordID()).Affiliation()` (`tweakDB.script:371`; `Character_Record.Affiliation()` `tweakDBRecords.script:~3476`; `GetRecordID` `puppet.script:13`); deny help ONLY if affiliations differ AND attitude groups differ (`GetAttitudeAgent().GetAttitudeGroup()`, `gameObject.script:586`, `attitudeAgent.script:21`; vanilla single gate `:5789-5792`). Either puppet unresolved (or toggle off) → vanilla attitude-group-only gate. **Literal-parity warning**: the reference compares the owner's affiliation against `targetOfTarget` — the ally's ENEMY — not against the ally. Almost certainly an author oversight (vs the player it is inert, since V's record affiliation never matches a gang's), but observable-behavior parity is the brief's binding rule → REPRODUCE IT LITERALLY (owner-record vs targetOfTarget-record). Flagged in Risks; implementer must NOT "fix" it silently.
   - **D6 player exemption removed (the load-bearing line)**: vanilla `if(targetOfTarget && !targetOfTarget.IsPlayer()) return true;` (`:5793-5796`) → when enabled, `if IsDefined(targetOfTarget) { return true; }` — NPCs now also help allies whose combat target IS the player.
   - **Preserved vanilla-exact**: police join-chase branch (`:5797-5801`): `preventionSys.IsChasingPlayer() && target.IsPrevention() && ownerPuppet.IsPrevention() && preventionSys.ShouldWorkSpotPoliceJoinChase(ownerPuppet)` (`GetPreventionSystem` `gameObject.script:3219`; `IsChasingPlayer` `preventionSystem.script:252`; `ShouldWorkSpotPoliceJoinChase` `:405`; `IsPrevention` `gameObject.script:1786`).
   - Affiliation equality implementation: primary = handle equality `Equals(affilA, affilB)` on the two `wref<Affiliation_Record>` (TweakDB records are per-ID singletons; the construct is compile-proven — the shipped reference mod uses `NotEquals` on the same types; both-null compares "equal", which IS reference behavior). Fallback rung if scc rejects ref-Equals: compare `affilA.GetID() == affilB.GetID()` (`TweakDBRecord.GetID` `tweakDBRecords.script:3`; TweakDBID `==` in-game-proven ScannerSuite.reds:1851; null-context native call returns default TDBID for both nulls → same corner behavior).

**Half B — TweakDB radii are unwritable (proven, index) → three wraps reproduce the tweak edits at their consumption points:**

| Original knob | Port hook | Behavior |
|---|---|---|
| `stims.GunshotStimuli.radius` 30→50 | `@wrapMethod(StimBroadcasterComponent) TriggerSingleBroadcast(...)` (`stimBroadcasterComponent.script:239-260`; P4-proven incl. opt-arg forwarding) | If enabled AND `radius <= 0.0` AND stim type is `Gunshot` → set radius `GunshotFallbackRadius()` (50.0) before forwarding. Covers the record-fallback callers: NPC gunfire `weapon.script:2029` (no radius, gated `!weaponOwner.IsPlayer()`) — the mod's main "was 30" driver. |
| `stims.ExplosionStimuli.radius` 25→50 | same wrap | Same gate for `Explosion` → `ExplosionFallbackRadius()` (50.0). Confirmed record-fallback caller: player ground-slam `locomotionTransitions.script:6218`. Grenades/missiles pass their OWN per-record radii (`fragGrenade.script:886-889`, `rainMissileProjectile.script:322`) — pass through UNTOUCHED (original's tweak never reached them either). |
| (belt-and-suspenders funnel closure) | `@wrapMethod(StimBroadcasterComponent) protected cb func OnBroadcastEvent(evt)` (`:351-385`; P5-proven; cb-wrap precedent ScannerSuite.reds:678+) | Same type/`<= 0.0` gate on `Equals(evt.broadcastType, EBroadcasteingType.Single)` (`enums.script:463`; event fields plain `var`, cross-class writes are vanilla precedent `:252-258`), mutate `evt.radius`, then `return wrappedMethod(evt)`. Idempotent by construction: every vanilla `EBroadcasteingType.Single` event is built INSIDE `TriggerSingleBroadcast` (`:252-258`; all five `new BroadcastEvent` sites live in this file), so a queued event already carries the injected radius and this wrap sees non-zero → no double-inject. It exists to catch any non-vanilla producer. |
| `District.gunShotStimRange` 30→50 (schema), Badlands 45→50, Dogtown 20→30 | `@wrapMethod(PlayerPuppet) GetGunshotRange()` (`player.script:6999-7002`; public const func — P1-proven wrap shape) | `let v = wrappedMethod();` if disabled → `v`. Else bucket-map: `v <= DistrictLowVanillaThreshold()` (25.0, classifies Dogtown's vanilla 20) → `DistrictGunshotRangeLow()` (30.0); else `DistrictGunshotRange()` (50.0). Return `MaxF(v, bucket)` (`scalar.script:50`) — never REDUCES a range another mod/patch already raised. Reproduces the reference table exactly: 20→30, 30→50, 45→50 (values read from `reference-aggro` districts.tweak/schema.tweak; vanilla defaults independently confirmed, dossier F8/F10). Consumers covered automatically: player exterior fire `weaponTransitions.script:2430`, mounted fire `vehicleComponent.script:1611`. |
| `SilencedGunshotStimuli.radius = 8` | **N/A — no code** | Confirmed pure RESTATEMENT of vanilla (dossier F10). The chokepoint gate must list ONLY Gunshot/Explosion so `SilencedGunshot` (and `IllegalAction`) radius-0 broadcasts keep their native record fallback. |
| Squad convergence | **N/A — no code** | `AISquadHelper.EnterAlerted` (`aiSquadHelper.script:415-444`) and `PullSquadSync` (`:332-371`) propagate squad-wide with no distance gate (60 m cap = police-only). Wider individual reception alone delivers "converge from farther" (dossier F12). |

**Deliberately untouched (parity — original changed none of these):** interior literal 25.0 (`weaponTransitions.script:2425`), "visual" second broadcast distances 30/40/45/50 (`:2426,2431-2445,2447`), silenced-sniper Gunshot 10.0 (`:2402`), NPC silenced 1.0 (`weapon.script:2020`), savage-sling Explosion 30.0 (`NPCPuppet.script:2881`), vehicle fixed 50 (`vehicleComponent.script:1608`), `explosiveDeviceStimRangeMultiplier`, `PlayerPuppet.GetExplosionRange`/`OnDistrictChanged` (`player.script:6993-7007`), `DeviceExplosionStimuli`.

**Fallback ladder** (rung triggers = specific `scc-serial.sh` failures; behavior identical on every rung):
1. Param reassignment (`radius = X` inside the TriggerSingleBroadcast wrap) rejected → copy to a local, forward the local (reference mod reassigns its `source` param, so rung 0 is expected to hold).
2. `evt.radius = X` field write rejected → build a fresh `BroadcastEvent`, copy all 10 fields (`stimBroadcasterComponent.script:14-26`) with adjusted radius, forward that.
3. `Equals(wref<record>, wref<record>)` rejected → `GetID() == GetID()` (above).
4. Const-context complaint on the notify call inside the `GetGunshotRange` wrap (const func → HUDManager method) → drop ONLY that notify site (debug sugar), keep the mapping; note it in implementer notes.
5. Wrap-signature mismatch (modifier drift `final`/`const`/`opt`) → re-grep the vanilla decl, mirror scc's expected-signature error verbatim. Never resolve a mismatch by switching to `@replaceMethod`.

## Architecture

All inside `EnemyOverhaul.AggroRange.reds`:

- `module EnemyOverhaul.AggroRange` + `import EnemyOverhaul.Common.*` (only if `EO_Notify` is actually consumed; drop when running on the local fallback).
- `public abstract class AggroRangeConfig` — USER CONFIG block, `public final static func` literals (ScannerSuiteConfig pattern, in-game-proven).
- `@replaceMethod(ReactionManagerComponent)` × 2 — the ONLY replaces in the whole mod (siblings are wrap/add-only). Rule 5 gives member access to the privates the bodies need: `GetOwnerPuppet` (`reactionComponent.script:4959`), `HasCombatTarget` (`:4964`), `CombatGracePeriodPassed` (`:6235`), `IsTargetPositionClose` (`:5557`), `IsTargetVeryClose` (`:5569`), `InGunshotCone` (`:2578`, private static → `ReactionManagerComponent.InGunshotCone(...)`), `LogInfo` (`:603`, keep vanilla's log calls).
- `@wrapMethod(StimBroadcasterComponent)` × 2 — `TriggerSingleBroadcast` (P4), `OnBroadcastEvent` (P5). Each calls `wrappedMethod` exactly once on every path; cb wrap returns the wrapped Bool.
- `@wrapMethod(PlayerPuppet) GetGunshotRange()` (P1 shape).
- Debug funnel: `@addField(HUDManager) let m_eoarLastNotify: Float;` + `@addMethod(HUDManager) public final func EOAR_Notify(game: GameInstance, msg: String) -> Void` — gates on `AggroRangeConfig.DebugNotify()`, throttles via `EngineTime.ToFloat(GameInstance.GetSimTime(game))` (`engineTime.script:5`, `gameInstance.script:7`; idiom ScannerSuite.reds:1804,1849) against `DebugThrottleSec()`, then emits via `EO_Notify(game, msg)`. HUDManager = session-stable host (`hud/hudManager.script:174`; `@addField(HUDManager)` proven ScannerSuite.reds:647,1385), reachable from every hook: `this.GetOwner().GetHudManager()` in components, `this.GetHudManager()` in PlayerPuppet (`gameObject.script:3183`), `IsDefined`-guarded (null → skip notify).
- No other classes, fields, loops, or state.

**Common APIs consumed** (if Common lacks it, implement same shape LOCALLY with `EOAR_` prefix and flag in implementer notes — never edit Common):
1. `EO_Notify(game: GameInstance, msg: String) -> Void` — `GameInstance.GetActivityLogSystem(game).AddLog(msg)` (`gameInstance.script:10`, `activityLogSystem.script:7`) + `FTLog(msg)` (`testStepLogicImport.script:29`; non-test precedent `worldMap.script:587`). Caller (the HUDManager funnel) handles gating + throttling.

That is the ENTIRE Common surface — this feature needs no eligibility filter, no seen-set, no RNG, no enumeration, no sweep loop.

## Lifecycle

Deliberately stateless — the template's arm→tick→roll pipeline does not apply, and the reviewer should verify its ABSENCE:
- **Arm:** none. Hooks are live from compile; config consts are read per call. NO `OnGameAttached` of any kind in this file — not even the player-puppet wrap (nothing to arm; the throttle `Float` @addField zero-inits).
- **Tick / detect-new / enumeration:** none. All five hooks execute inside vanilla's own game-thread call flow (AI reaction queries, entity event dispatch, player state machine).
- **Eligibility / roll-once / mark / session keying:** none. No per-entity decision is ever made; behavior is a pure function of (stim, distance, config). Re-stream/reload trivially consistent. The only mutable state is `m_eoarLastNotify` (debug throttle timestamp, session-transient, never saved).
- **Rule-3 note:** the `OnBroadcastEvent` wrap mutates ONLY the in-flight script event payload before forwarding — it does not call back into the dispatching system (no re-entrant engine mutation; vanilla's own handler body does strictly more inside the same callback).

## Constants — USER CONFIG block (top of file, clearly marked)

| Name | Default | Meaning |
|---|---|---|
| `EnableAggroRange()` | `true` | Master toggle. `false` → all five hooks behave vanilla: replaces run vanilla values/structure (D1–D6 revert), chokepoints inject nothing, district map returns `wrappedMethod()` unchanged. |
| `DangerRange()` | `35.0` | D1 — combat-stim danger radius, meters (vanilla 12). |
| `VanillaDangerRange()` | `12.0` | Vanilla baseline (`reactionComponent.script:2642`). Used by the toggle-off path and the "accepted only because widened" debug compare. Do not change. |
| `GunshotFallbackRadius()` | `50.0` | Injected radius for radius-0 `Gunshot` broadcasts (vanilla record 30). |
| `ExplosionFallbackRadius()` | `50.0` | Injected radius for radius-0 `Explosion` broadcasts (vanilla record 25). |
| `DistrictGunshotRange()` | `50.0` | Mapped player gunshot range for standard districts (vanilla 30, Badlands 45). |
| `DistrictGunshotRangeLow()` | `30.0` | Mapped range for low-noise districts (Dogtown, vanilla 20). |
| `DistrictLowVanillaThreshold()` | `25.0` | Classifier: vanilla ranges `<=` this are low-noise tier. Known vanilla values are exactly {20, 30, 45}. |
| `DebugNotify()` | `true` | Master debug toggle: HUD one-liner + FTLog per extended-range event, throttled. |
| `DebugThrottleSec()` | `5.0` | Min seconds between debug notifications (global, sim-time). |

## Exclusions — per-category disposition (this feature selects no entities)

Parity constraint: the original mod alters GLOBAL reaction logic for every NPC's ReactionManagerComponent — it excludes nobody, and a clean-room port must not invent exclusions. Per-category evidence that this is safe:

| Category | Disposition | Evidence |
|---|---|---|
| Quest/named | No gate (parity). Both methods only make NPCs MORE reactive to player-sourced stims (`ShouldIgnoreCombatStim` hard-returns false for non-player sources, `reactionComponent.script:2607-2610`); quest NPCs already react at 12 m — 35 m changes when, not whether. | brief: "everywhere incl. quest encounters" |
| Boss / MaxTac | No gate (parity). They don't lazily ignore combat stims in the first place; no reward/tier surface touched. | `scriptedPuppet.script:1640-1666` unused by design |
| Police | No special handling ADDED; vanilla's only police-specific branch (work-spot join-chase) preserved byte-equivalent. | `reactionComponent.script:5797-5801` |
| Mech/drone/robot | No gate (parity) — reaction preset data decides their stim handling, unchanged. | dossier F1/F12 |
| Civilian/crowd | No gate (parity). Crowd-panic side effects of wider stim radii ride along ONLY where the mechanism naturally carries them (chokepoint radius applies to all receivers) — brief explicitly orders this posture. | brief Decisions |
| F2 clones / F1 upranks | Invisible here — no entity identity is ever read; no clone-registry access. | — |

## What NOT to do

- NO TweakDB writes of any kind (the radii stay 30/25/8 in data; hooks change the runtime values) — `TweakDBInterface.Get*` reads only.
- NO hooks on `StimBroadcasterComponentHelper.CreateStimEvent` / `ProcessSingleStimuliBroadcast` (`stimBroadcasterComponent.script:860-861`) — native imports, not confirmed wrappable (dossier: avoid).
- Do NOT uplift NON-zero radii at the chokepoints (no `MaxF` there, no blanket 50): explicit radii (interior 25, sniper-silenced 10, grenades' DetonationStimRadius, visual 50, savage-sling 30) must pass through byte-identical — that is the parity line the original drew.
- Do NOT touch `SilencedGunshot` or `IllegalAction` radii (silenced 8 is vanilla restated; stealth balance must survive).
- Do NOT redefine the 5-arg `ShouldIgnoreCombatStim` shim, `IsTargetVeryClose`, `InGunshotCone`, or any helper — replace ONLY the two listed methods; everything else is wrap/add.
- Do NOT emit any NEW stim broadcast (no added `TriggerSingleBroadcast`/`SendStimDirectly`/`SendDrirectStimuliToTarget`/`AddActiveStimuli` calls) — this mod widens existing signals, it never creates signals.
- NO `continue`/`break` (if-wrappers + early return). NO `OnGameAttached` hook of ANY kind in this file (this feature needs none — absence is the safest compliance with rule 2). NO edits outside `EnemyOverhaul.AggroRange.reds` (Common gaps → local `EOAR_` fallback).
- Each wrap calls `wrappedMethod` EXACTLY once on every code path; cb wrap returns its Bool; no engine-state mutation beyond the event-payload radius field inside `OnBroadcastEvent` (rule 3).
- Clean-room: no verbatim copy of reference structure/identifiers/comments (`playerPuppet`/`affiliation1`/`affiliation2`/commented-out-vanilla-lines style). Vanilla-derived text (log strings like "can't be ignored - explosion nearby") is fine — its source is the decompile.
- Do NOT "fix" the reference's owner-vs-enemy affiliation compare (D5) — literal parity, flagged to user instead.
- NEVER run scc directly / compile the live game / launch the game — `sprint/bin/scc-serial.sh` only.

## Debug & manual-verification hooks

All sites route through the single throttled funnel (`EOAR_Notify` → `EO_Notify`), gated by `DebugNotify()`, throttled by `DebugThrottleSec()` (sim-time, menu-pause-proof):
1. **Extended-range acceptance** (in the replaced `ShouldIgnoreCombatStim`, only on return-false paths that fired SOLELY due to widening — i.e. `!this.IsTargetPositionClose(sourcePos, VanillaDangerRange())`): gunshot-nearby branch, explosion branch, illegal-cone branch. Msg: `"EO aggro: <branch> accepted beyond vanilla range"` + `FloatToStringPrec(Vector4.Distance(sourcePos, this.GetOwner().GetWorldPosition()), 1)` m (`vector.script:107,133`).
2. **Help-vs-player grant** (replaced help method): D6 path taken with `targetOfTarget.IsPlayer()` → `"EO aggro: ally joins vs player"`; D5 path where the affiliation leg (not the group leg) allowed help → `"EO aggro: affiliation-leg help"`.
3. **Radius injection** (TriggerSingleBroadcast wrap; the OnBroadcastEvent wrap stays silent — it almost never fires): `"EO aggro: Gunshot radius 0 -> 50"` / Explosion equivalent.
4. **District uplift** (GetGunshotRange wrap, only when mapped != vanilla): `"EO aggro: district gunshot range <v> -> <mapped>"` (fallback rung 4 may drop this site).

Manual verification leans on these lines: each M-scenario below states which line(s) must (not) appear.

## Risks — residual unknowns + how the implementer must surface them

1. **D5 literal-parity oddity (user-facing decision preserved, not resolved):** the affiliation leg compares owner vs the ally's ENEMY. Against the player it is inert; NPC-vs-NPC corners are weird but rare. Implementer ships the literal port + a one-line code comment `// literal reference parity — see plan D5`; reviewer flags it in the final report so the user can order the one-line "owner vs ally" variant later.
2. **Compile-shape rungs** (param reassign, evt-field write, ref-Equals, const-context notify): each has a behavior-identical fallback (Mechanism ladder); surface any rung actually taken in implementer notes.
3. **Native semantics inferred, not proven** (informational, index #8): `radius=0` = record-fallback is architectural inference — our injection happens BEFORE native so the port works regardless; `propagationChange=true` opaque — we never alter that flag; possible player-silenced double-broadcast — both paths hit the same chokepoints, and we skip silenced anyway.
4. **Balance/gameplay:** 35 m danger + explosion-always + ally-pile-on makes crowds noticeably deadlier and stealth-adjacent play harder — intended by the mod; all knobs are config consts; `EnableAggroRange=false` is the clean escape hatch. Surface via M-tests, not code.
5. **Mod interplay:** probe proved no replace collision and full-staging compile; other mods wrapping the same chokepoints chain by design (rule 6). If a future mod REPLACES either method, last-compiled wins — out of scope, note in report only if the reviewer's collision grep (S26) trips.
6. **Throttle host null early-session** (`GetHudManager()` before HUD init): guarded `IsDefined` → notify silently skipped; no functional impact.
