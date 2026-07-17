# R1 — F3: gunshot/explosion stim pipeline + replaced-method vanilla diff

## Verdict (feasible / blocked / partial)
**FEASIBLE, both halves.** Half A: both target methods located exactly at the director's anchor and fully diffed line-by-line against the reference mod; every brief-claimed delta confirmed byte-for-byte, plus **one undocumented delta found** (a tightened instigator-null guard clause). Both are `@replaceMethod` candidates — logic is interleaved with early-returns the same way in the original mod, which itself chose `@replaceMethod` for both.
Half B: writing TweakDB is confirmed impossible (no writer API anywhere in `vanilla-scripts`), but it's **not needed** — every single Gunshot/SilencedGunshot/Explosion stim broadcast in the game (player, NPC, vehicle-mounted, grenade, melee-finisher) funnels through exactly two script-level chokepoints — `StimBroadcasterComponent.TriggerSingleBroadcast` and `.OnBroadcastEvent` — both of which take an explicit `radius : Float` argument that a `@wrapMethod` can override before forwarding. That reproduces the TweakXL radius bump for every stim source without touching TweakDB. `District.gunShotStimRange` is confirmed **enemy-aggro-relevant, not crime-only**: it reaches the player's primary Gunshot broadcast radius via a 4-hop script chain ending at `PlayerPuppet.GetGunshotRange()`. The mod's silenced-gunshot `radius = 8` is a confirmed **restatement** of the vanilla value (not a change) — verified against an independent vanilla TweakDB dump. Squad convergence (Q5) needs no new mechanism: `AISquadHelper.EnterAlerted`/`PullSquadSync` already propagate squad-wide with **no distance gate** (except NCPD's own 60 m cap), so widening broadcast radius + ignore-range alone is sufficient to deliver "enemies converge from farther."

---

## Findings

### F1 — `ShouldIgnoreCombatStim`: vanilla body (director anchor confirmed)
Two overloads, both in `sprint/vanilla-scripts/scripts/core/components/scriptComponents/reactionComponent.script`:
- **Shim** (5-arg, no `canDelay`/out-params): `reactionComponent.script:2583-2588` — just forwards to the 8-arg overload with `canDelay=false`.
- **Full logic** (8-arg): `reactionComponent.script:2590-2711`.

Only the 8-arg overload needs replacing; the shim is a pure passthrough untouched by the mod (mod only defines the 8-arg signature — `GunshotReactions.reds:2`).

Call sites into the 8-arg overload: `reactionComponent.script:2033` (own reaction pipeline) and `reactionComponent.script:2755` (`IsSquadMateInDanger`, cross-squadmate check).

Helpers the body depends on (all in the same file, all unmodified by the mod):
- `InGunshotCone(shooter, target)` — `reactionComponent.script:2578-2581` → `IsTargetInFrontOfSource(shooter, target, 15.0, true)`.
- `IsTargetInFrontOfSource` — `reactionComponent.script:5455-5487`. **Confirms the `15.0` in `InGunshotCone` is a front-angle in DEGREES, not a distance** (`frontAngle` param, compared via `AbsF(angleToTarget) < frontAngle`; `checkFullAngle=true` here). This matters for reading delta #3 below correctly: dropping the range-gate turns the illegal-action check into a pure direction check with **no distance cap at all**.
- `IsTargetPositionClose(pos, distance)` — `reactionComponent.script:5557-5562` (squared-distance compare; consumed by the `12.0`→`35.0` and `4.0` literals).
- `IsTargetVeryClose(target)` — `reactionComponent.script:5569-5572` = `IsTargetClose(3.0) || (IsTargetClose(6.0) && IsTargetInFront(60.0))`. **Not touched by the mod** (same call, no override).

### F2 — `ShouldIgnoreCombatStim`: confirmed diff vs `GunshotReactions.reds:1-126`
| # | Vanilla (line) | Mod (line) | Verdict |
|---|---|---|---|
| 1 | `inDangerRange = IsTargetPositionClose(sourcePos, 12.0);` (`:2642`) | `35.0; // was 12.0` (`:55`) | **Confirmed exactly**, brief accurate. |
| 2 | `if(stimType==Explosion && inDangerRange)` (`:2643`) | `&& inDangerRange` commented out (`:56`) | **Confirmed exactly** — Explosion never ignorable, brief accurate. |
| 3 | `if((IsIllegal(stimType) && inDangerRange) && InGunshotCone(...))` (`:2670`) | `inDangerRange &&` commented out (`:84`) | **Confirmed exactly** — illegal-action-in-cone loses its distance cap entirely (cone is angle-only per F1), brief accurate. |
| 4 | Gunshot check: `inDangerRange OR InGunshotCone` (`:2651-2669`) | identical structure (`:64-82`) | **Unchanged**, only inherits the widened range from #1. Brief doesn't claim a separate change here — consistent. |
| 5 | `IsTargetVeryClose`, security-zone, squadmate-in-combat loop (`:2678-2709`) | identical (`:92-124`) | **Unchanged.** |
| 6 | **NOT in brief:** guard `if(!source && !instigator) return false;` then `if(!source) source=instigator;` (`:2599-2606`) — permits "source defined, instigator undefined" to fall through and be evaluated. | `if(!IsDefined(instigator)) return false;` unconditionally (`:11-14`), regardless of `source` | **Real, undocumented delta.** The mod is stricter: any stim whose `instigator` is unset is now force-treated as "cannot be ignored" even if `source` (the actual player-check target) is defined and is the player. Vanilla would instead fall through to full evaluation in that case. Net effect is minor and in the same direction as the mod's overall intent (more reactive), but it's a real behavior change the brief's delta list omits. |
| 7 | cosmetic | mod caches `playerPuppet = source as PlayerPuppet` once instead of vanilla's repeated inline cast; mod uses `for squadMate in squadMates` vs vanilla's indexed `for(i=0;...)` loop | **No behavior change** — decompiled-vanilla-syntax vs modern-REDscript-syntax only (vanilla `.script` sources use legacy `function`/`var` decomp syntax throughout, not `func`/`let` — semantically identical, not directly paste-able). |

### F3 — `ShouldHelpTargetFromSameAttitudeGroup`: vanilla body (director anchor confirmed)
`reactionComponent.script:5784-5803`. Call sites (director's anchor exactly): `reactionComponent.script:918` and `:1723`.

### F4 — `ShouldHelpTargetFromSameAttitudeGroup`: confirmed diff vs `GunshotReactions.reds:129-164`
| # | Vanilla | Mod | Verdict |
|---|---|---|---|
| 1 | Single check: `if(ownerPuppet.GetAttitudeAgent().GetAttitudeGroup() != target.GetAttitudeAgent().GetAttitudeGroup()) return false;` (`:5789-5792`) | Adds an Affiliation branch: if both `ownerPuppet` and `targetPuppet=(targetOfTarget as ScriptedPuppet)` resolve, help proceeds unless **both** `Affiliation` (`TweakDBInterface.GetCharacterRecord(...).Affiliation()`) **and** `AttitudeGroup` differ (OR-widened vs vanilla's single AND-gate); else falls back to the vanilla attitude-group-only check (`:140-153`) | **Confirmed** — "same Affiliation OR same attitude group," brief accurate. `PlayerPuppet extends ScriptedPuppet` (`scripts/cyberpunk/player/player.script:435`), so this path also engages when `targetOfTarget` is the player. |
| 2 | `if(targetOfTarget && !targetOfTarget.IsPlayer()) return true;` (`:5793-5796`) — i.e. skip this shortcut when the ally's target IS the player, forcing fall-through to the police-only branch below | `!(targetOfTarget.IsPlayer())` commented out — `if(IsDefined(targetOfTarget)) return true;` (`:154-157`) | **Confirmed exactly** — this is the single line that makes ordinary (non-police) NPCs pile on to help a squad-/attitude-mate who is fighting the **player**, which vanilla explicitly exempts. This is the highest-impact line in the whole feature. |
| 3 | `preventionSys.IsChasingPlayer() && target.IsPrevention() && ownerPuppet.IsPrevention() && preventionSys.ShouldWorkSpotPoliceJoinChase(ownerPuppet)` (`:5797-5801`) | byte-identical (`:158-162`) | **Confirmed preserved exactly**, brief accurate. Side note: since delta #2 already returns `true` for almost every defined-`targetOfTarget` case, this fallback is now reached only when `targetOfTarget` is **undefined** — the logic is unchanged but it's reached less often. |

All APIs the mod's replacement calls are independently vanilla-verified (not just reference-mod usage) — see API inventory.

### F5 — Gunshot/Explosion stim broadcast infrastructure (shared plumbing)
`sprint/vanilla-scripts/scripts/core/components/stimBroadcasterComponent.script`. Two broadcast surfaces matter:
- `StimBroadcasterComponent.TriggerSingleBroadcast(contextOwner, gdStimType, optional radius, optional investigateData, optional propagationChange)` (`:239-260`, `public function`). If `contextOwner == GetOwner()` (broadcasting entity IS the component's own owner) it goes the **immediate** route: `StimBroadcasterComponentHelper.CreateStimEvent(...)` + `...ProcessSingleStimuliBroadcast(...)` inline (`:247-248`, both `public import static function` — native, opaque).
- Otherwise it queues a `BroadcastEvent{radius=...}` (`:252-258`) consumed by `protected event OnBroadcastEvent(evt)` (`:351-385`), whose `EBroadcasteingType.Single` case (`:358-361`) **re-implements the same two native calls independently** — this is a separate code path, not a call back into `TriggerSingleBroadcast`.
- Confirmed via repo-wide grep: `CreateStimEvent`/`ProcessSingleStimuliBroadcast` are called **only** from these two spots in the whole decompile — no other file reaches the native layer directly. **These two functions together are the complete funnel for every "Single" stim broadcast in the game.**

Which path a call site takes depends on whether `contextOwner == owner`:
- Weapon-fire from `weapon.script` passes `contextOwner = weapon` (the item) while the broadcaster was fetched via `weaponOwner.GetStimBroadcasterComponent()` — `weapon != weaponOwner`, so this **always takes the queued/`OnBroadcastEvent` path**.
- Player-fire from `weaponTransitions.script` and vehicle-mount fire from `vehicleComponent.script` fetch the broadcaster from the same entity they pass as `contextOwner` — these take the **immediate/`TriggerSingleBroadcast`-self path** (except the vehicle's own mounted-player sub-broadcast, which is cross-owner and queued — see F7).

### F6 — Player-fired Gunshot broadcast (THE primary enemy-aggro driver)
`sprint/vanilla-scripts/scripts/cyberpunk/player/psm/weaponTransitions.script`, class `ShootEvents extends WeaponEventsTransition`, function `OnEnter(stateContext, scriptInterface)` (`:2340-2470`). Per player shot:
- **Silenced weapon** (`CanSilentKill` stat > 0, `:2393-2404`): broadcasts `IllegalAction` (no radius → native fallback), `SilencedGunshot` (no radius → native fallback), `SilencedGunshot` again at **literal `10.0`** (`:2399`, `propagationChange=true`), and if the weapon is a sniper rifle, also `Gunshot` at literal `10.0` (`:2402`).
- **Normal weapon** (`:2408-2447`):
  - Interior (`IsEntityInInteriorArea`, native import `scripts/core/entity/gameEntity.script:5`): `Gunshot` at literal **`25.0`** (`:2425`); `visualStimDistance = 45.0`.
  - Exterior: `Gunshot` at **`GetPlayer(gameInstance).GetGunshotRange()`** (`:2430`, dynamic, district-driven — see F8); `visualStimDistance` further branches on Dogtown/combat state to `30.0`/`40.0`/else **`50.0`** (`:2431-2445`, **already vanilla, unmodified**).
  - Regardless of branch, a **second** `Gunshot` broadcast always fires at `visualStimDistance` with `propagationChange=true` (`:2447`).
- **Key observation:** in vanilla, exterior non-Dogtown player gunfire already broadcasts a second Gunshot stim at literal **50 m** (line 2444, unmodified vanilla source) — the mod's "Gunshot 30→50" framing is really about the **first**/district-driven broadcast (and the NPC-side fallback, F7), not this already-50 "visual" one. Untested from script alone whether `propagationChange=true` changes the stim's propagation model (e.g. audio→visual, meaning it might need line-of-sight) — that flag's exact native semantics are **UNVERIFIED** (opaque to `.script` decompile).

### F7 — NPC-fired Gunshot broadcast (record-default fallback path)
`sprint/vanilla-scripts/scripts/cyberpunk/items/weapon.script`, static function `Fire(...)` (`:1845` signature). Per shot:
- Silenced branch (`:2015-2023`, **not** gated by `IsPlayer()`): broadcasts `IllegalAction` and `SilencedGunshot`, **both with no radius argument** → falls through to the queued/`OnBroadcastEvent` path (contextOwner=weapon≠weaponOwner, F5) with `radius=0.0`.
- Normal branch, **gated `!(weaponOwner.IsPlayer())`** (`:2027-2030`): `broadcaster.TriggerSingleBroadcast(weapon, gamedataStimType.Gunshot);` — **no radius**, same queued/no-radius situation.
- The player-`IsPlayer()` guard on the plain-Gunshot branch cleanly separates NPC-fired gunshots (this file, radius unspecified) from player-fired gunshots (weaponTransitions.script, F6, radius always explicit) — **no double-broadcast of the plain Gunshot stim.** (The ungated silenced-branch broadcasts in this file, however, are NOT excluded for a player firing a silenced weapon; whether `ShootEvents.OnEnter`'s own silenced branch (F6) additionally fires on top of this per shot — i.e. a true double-broadcast for player-silenced-weapon shots — was not resolved; it does not change any hook-point conclusion below, since either way both call sites still resolve through F5's two chokepoints. Flagged as **UNVERIFIED**, non-blocking.)
- **This is the call site that actually consults the generic `stims.GunshotStimuli.radius` TweakDB record as its default** (radius=0 passed → native fallback), assuming the native `CreateStimEvent` treats radius=0 as "use the stim record's own radius" — a very strong, idiomatic inference (that's exactly what an `optional radius : Float` + a same-named TweakDB `Stim.radius` field is for) but the fallback mechanism itself lives in native code and is **UNVERIFIED** from script alone.

### F8 — `District.gunShotStimRange`: script-side readers exist, and they ARE enemy-aggro-relevant
Answers Q3 definitively. Chain (all in `vanilla-scripts`):
1. `District_Record.GunShotStimRange() : Float` — native TweakDB accessor, `scripts/core/data/tweakDBRecords.script:4249`.
2. `District.GetGunshotStimRange()` — `scripts/core/systems/prevention/districtManager.script:30-33`, reads `m_districtRecord.GunShotStimRange()`.
3. `DistrictManager.PushDistrict(...)` — `districtManager.script:182`: `playerNotification.gunshotRange = d.GetGunshotStimRange();` (queued as a `PlayerEnteredNewDistrictEvent` on district transition).
4. `PlayerPuppet.OnDistrictChanged(evt)` — `scripts/cyberpunk/player/player.script:6993-6997`: `m_gunshotRange = evt.gunshotRange;`.
5. `PlayerPuppet.GetGunshotRange() : Float` — `player.script:6999-7002`, plain public getter, returns `m_gunshotRange`.
6. Consumed at **`weaponTransitions.script:2430`** (F6, the player's primary exterior Gunshot radius) and **`vehicleComponent.script:1611`** (F9, mounted-player weapon fire).

This is a real, live, enemy-combat-relevant reader — **not** crime/prevention/crowd-only (districtManager.script's own package name is misleading; the value leaves the prevention subsystem and lands directly in the player's per-shot combat-stim radius). Vanilla schema default confirmed **30.f** (`schema.tweak`), Badlands override confirmed **45.f** (`districts.tweak`) — both exactly match the reference mod's "was" comments (see F10).

### F9 — Vehicle-mounted weapon fire (parallel confirmation of the F6 pattern)
`scripts/core/components/scriptComponents/vehicleComponent.script`, `protected event OnWeaponShootEvent(evt)` (`:1602-1613`):
```
broadcaster.TriggerSingleBroadcast( vehicle, gamedataStimType.Gunshot, 50.0, , true );   // :1608 — already-vanilla 50, "visual" (propagationChange=true), self-path (vehicle==owner)
if( m_mountedPlayer ) {
  broadcaster.TriggerSingleBroadcast( m_mountedPlayer, gamedataStimType.Gunshot, m_mountedPlayer.GetGunshotRange() );  // :1611 — queued/OnBroadcastEvent path (m_mountedPlayer != vehicle), district-driven
}
```
Same fixed-50-"visual" + dynamic-district-"primary" two-broadcast shape as F6, independently cross-validating that pattern.

### F10 — Vanilla stim-record radii, independently confirmed (resolves Q4)
Local `vanilla-scripts` has no TweakDB dump (scripts only), so this required web verification per the researcher method. `gh search code` located the actual vanilla file at `CDPR-Modding-Documentation/Cyberpunk-Tweaks:tweaks/base/gameplay/static_data/database/stimuli/stimpresets.tweak` (same relative path as the reference mod's replacement file) and fetched it directly:
```
GunshotStimuli : Stim { float radius = 30; ... }
SilencedGunshotStimuli : GunshotStimuli { float radius = 8; ... }
ExplosionStimuli : Stim { float radius = 25; ... }
```
- `GunshotStimuli.radius = 30` and `ExplosionStimuli.radius = 25` **exactly match** the reference mod's "was 30"/"was 25" comments — corroborates the mod author's own annotations.
- `SilencedGunshotStimuli.radius = 8` **exactly matches the mod's own value (8)** — **Q4 resolved: the mod's 8 m is a pure restatement, not a change.** (It's still force-restated in the mod's tweak file because `SilencedGunshotStimuli extends GunshotStimuli`, and the mod bumped the parent's radius 30→50; without restating, the child would incorrectly inherit 50.)
- Same GitHub code search independently confirmed `District` schema default `gunShotStimRange = 30.f` and Badlands override `45.f` (`CDPR-Modding-Documentation/Cyberpunk-Tweaks:tweaks/base/gameplay/static_data/database/fasttravel/{schema,districts}.tweak`) — matches F8 and the reference mod's own comments exactly.
- Also surfaced: a *different*, unrelated `DeviceExplosionStimuli.radius = 15` (stim type `StimTypes.DeviceExplosion`, separate from `StimTypes.Explosion`) — the reference mod does not touch it; out of scope, noted so the planner doesn't confuse it with `ExplosionStimuli`.
- A third-party CET mod found in the same search (`rfuzzo/cyberpunk-nexus-script-dump`, "FGR - AI Improvements") sets `SilencedGunshotStimuli.radius` to 15 with a comment claiming `--default 3`; this conflicts with the CDPR-Modding-Documentation dump's `8` and is a **different, less authoritative, third-party source** — the dump above (matching file path + matching two other "was" comments exactly) is trusted over it.

### F11 — Explosion stims: mostly NOT driven by the generic `ExplosionStimuli` record
Grep for `gamedataStimType.Explosion` broadcast call sites, repo-wide:
- `scripts/cyberpunk/items/combat_gadgets/fragGrenade.script:886-889`: `detonationStimRadius = m_tweakRecord.DetonationStimRadius();` (or `UnderwaterDetonationStimRadius()` at `:854`) → `TriggerStimuli(detonationStimRadius)` (`:1194-1209`) → `broadcaster.TriggerSingleBroadcast(this, m_tweakRecord.DetonationStimType().Type(), radius, investigateData)` (`:1206`). **Both the stim type and the radius come from the grenade/weapon's own `Attack_Record`/tweak record, not from `stims.ExplosionStimuli.radius`.**
- `scripts/cyberpunk/projectiles/rainMissileProjectile.script:322`: `broadCaster.TriggerSingleBroadcast(this, gamedataStimType.Explosion, aoeData.radius + 5.0, investigateData);` — AOE-derived, not record-derived.
- `scripts/cyberpunk/NPC/NPCPuppet.script:2881`: `broadcaster.TriggerSingleBroadcast(this, gamedataStimType.Explosion, 30.0, investigateData);` — inside a melee-finisher "savage sling throw" ragdoll-impact effect (not a real explosion), literal `30.0`.
- `scripts/cyberpunk/player/psm/locomotionTransitions.script:6218`: `broadcaster.TriggerSingleBroadcast(scriptInterface.executionOwner, gamedataStimType.Explosion);` — the player's Body-perk ground-slam attack; **no radius** → this is the one confirmed call site that would actually fall back to `stims.ExplosionStimuli.radius`.

Net: `stims.ExplosionStimuli.radius` (25→50 in the mod) is **not** the primary driver of grenade/explosive-device alert range (those use dedicated per-weapon `DetonationStimRadius` TweakDB fields, unaffected by the reference mod's tweak edit) — it mainly affects the ground-slam perk stim and whatever native fallback applies elsewhere. This does **not** break the Half-B hook strategy (F12) because the hook operates on the broadcast chokepoint itself, downstream of wherever the radius number came from.

### F12 — Squad alert propagation (Q5): distance-independent once triggered
`sprint/vanilla-scripts/scripts/core/ai/squads/aiSquadHelper.script`:
- `AISquadHelper.GetSquadmates(obj, out membersList, ...)` (`:15-28`) — roster fetch, already used by both replaced methods (F1, F3).
- `AISquadHelper.EnterAlerted(owner)` (`:415-444`) — loops `GetSquadmates(owner)`; for every squadmate currently `gamedataNPCHighLevelState.Relaxed`, calls `NPCPuppet.ChangeHighLevelState(puppet, gamedataNPCHighLevelState.Alerted)`. **No distance check anywhere in this function.** Entry point: `npcStateComponent.AlertPuppet(ownerPuppet)` — `scripts/cyberpunk/NPC/components/npcStateComponent.script:227-262`, called when an individual puppet's own state reaches `Alerted` and it isn't wired to a `SecuritySystemControllerPS` (`:247-259`).
- `AISquadHelper.PullSquadSync(puppet, squadType)` (`:332-371`) — loops squadmates and calls `PullSquadSyncOnSquadmate` (`:373-392`, syncs `TargetTrackingExtension.PullSquadSync`, i.e. shares the top hostile threat). **Gated by a 60 m distance cap only for police squads** (`isPuppetPolice` via `NPCManager.HasTag(..., 'InActivePoliceChase')`, `:357-363`); **no gate at all for non-police squads** (`:364-367`). Called from `npcStateComponent.script:680,695`, `NPCPuppet.script:2035`, `targetTrackingComponent.script:1229`, `tweakAISubActions.script:4351`, `aiStatusEffectTask.script:217` — i.e. broadly, whenever an NPC enters/updates combat.
- `AISquadHelper.SendStimFromSquadTargetToMember(member, actionName)` (`:136-164`) — routes a `Combat`-type stim directly via `SendDrirectStimuliToTarget` (bypasses radius entirely) from one squad member's target to another.
- `AISquadHelper.RemoveThreatFromSquad`/`GetThreatLocationFromSquad` (`:244-330`) — squad-wide threat/location sharing, also unconditional.

**Conclusion:** squad-wide convergence is already essentially unlimited-range in vanilla. The brief's "enemies converge from farther" outcome is a **natural consequence** of Half A + Half B (more individual NPCs personally receive and accept the stim from farther away — F1/F2/F5-F9), not something that itself needs a new distance-widening mechanism — each such NPC's own squad then gets synced with no further range gate.

---

## API inventory
| API / member | Signature (as used) | Evidence | Verified? |
|---|---|---|---|
| `ReactionManagerComponent.ShouldIgnoreCombatStim` (8-arg) | `(stimType, instigator: weak<ScriptedPuppet>, source: weak<ScriptedPuppet>, sourcePos: Vector4, canDelay: Bool, out canIgnoreOnlyDueToDelay: Bool, out canIgnorePlayerCombatStim: Bool, log: Bool) : Bool` | `reactionComponent.script:2590` | Verified (target method) |
| `ReactionManagerComponent.ShouldHelpTargetFromSameAttitudeGroup` | `(target: weak<GameObject>, targetOfTarget: weak<GameObject>) : Bool` (private) | `reactionComponent.script:5784` | Verified (target method) |
| `ReactionManagerComponent.InGunshotCone` (private static) | `(shooter: weak<GameObject>, target: weak<GameObject>) : Bool` | `reactionComponent.script:2578` | Verified |
| `IsTargetInFrontOfSource` (private static) | `(source, target, optional frontAngle: Float, optional checkFullAngle: Bool) : Bool` — angle in degrees | `reactionComponent.script:5455` | Verified |
| `StimBroadcasterComponent.TriggerSingleBroadcast` | `(contextOwner: weak<GameObject>, gdStimType: gamedataStimType, optional radius: Float, optional investigateData: stimInvestigateData, optional propagationChange: Bool)`, `public function` | `stimBroadcasterComponent.script:239` | Verified, wrap-feasible |
| `StimBroadcasterComponent.OnBroadcastEvent` | `protected event OnBroadcastEvent(evt: BroadcastEvent)` | `stimBroadcasterComponent.script:351` | Verified, wrap-feasible (event/cb wrap precedent: ScannerSuite.reds below) |
| `StimBroadcasterComponentHelper.CreateStimEvent` / `.ProcessSingleStimuliBroadcast` | `public import static function` | `stimBroadcasterComponent.script:860-861` | Verified to exist; **native, opaque** — NOT confirmed wrappable, avoid as a hook target |
| `PlayerPuppet.GetGunshotRange` | `public const function GetGunshotRange() : Float` (pure script, returns `m_gunshotRange`) | `player.script:6999` | Verified, wrap-feasible |
| `District.GetGunshotStimRange` | `public const function GetGunshotStimRange() : Float` → `m_districtRecord.GunShotStimRange()` | `districtManager.script:30` | Verified, wrap-feasible |
| `District_Record.GunShotStimRange` | `public import function GunShotStimRange() : Float` (native TweakDB read) | `tweakDBRecords.script:4249` | Verified (TweakDBInterface-family read, read-only per project rules) |
| `TweakDBInterface.GetCharacterRecord(id).Affiliation()` | `weak<Affiliation_Record>` | `NPCPuppet.script:800`, `fragGrenade.script:1764`, decl `tweakDBRecords.script:548` | Verified independently of the reference mod |
| `AttitudeAgent.GetAttitudeGroup()` | `public import function GetAttitudeGroup() : CName` | `attitudeAgent.script:21`; used `reactionComponent.script:5789` | Verified |
| `PreventionSystem.IsChasingPlayer` / `.ShouldWorkSpotPoliceJoinChase` | `const function ... : Bool` | `preventionSystem.script:252`, `:405` | Verified |
| `AISquadHelper.GetSquadmates` | `static function(obj, out membersList: array<weak<Entity>>, optional dontRemoveSelf) : Bool` | `aiSquadHelper.script:15` | Verified |
| `AISquadHelper.EnterAlerted` | `static function(owner: weak<ScriptedPuppet>)` | `aiSquadHelper.script:415` | Verified |
| `AISquadHelper.PullSquadSync` | `static function(puppet, squadType: AISquadType)` | `aiSquadHelper.script:332` | Verified |
| `IsEntityInInteriorArea` | `import function(entity: weak<Entity>) : Bool` | `gameEntity.script:5`; used `weaponTransitions.script:2423` | Verified |
| `NPCPuppet.IsInCombatWithTarget` | used unmodified in both replaced-method bodies | `reactionComponent.script:2629`/mod`:42` | Verified (pre-existing usage) |

---

## Precedents & inspiration
- `mods/enabled/r6-scripts/custom-scanner-suite/ScannerSuite.reds:611-659` — four `@wrapMethod(HUDManager) protected cb func On...Changed(...)` blocks, each caching `wrappedMethod(...)`'s result and doing pre/post work. **In-game-proven precedent that event/callback-style vanilla functions (the modern-REDscript equivalent of the decompiled `.script` files' `event` keyword) are wrappable**, directly supporting the `StimBroadcasterComponent.OnBroadcastEvent` hook option in F5/F12.
- `sprint/reference-aggro/r6/scripts/Enemy Aggro Improvements/GunshotReactions.reds` — the original mod, both `@replaceMethod`s fully diffed above (F2, F4). Confirms `@replaceMethod` was the original author's own choice for both, for the same reason our clean-room port would need it: distance-gates are removed from the *middle* of interleaved if-chains, not appended/prepended, so a wrap-then-postprocess can't cheaply reproduce it.
- `sprint/reference-aggro/r6/tweaks/.../stimpresets.tweak`, `districts.tweak`, `schema.tweak` — TweakXL-only (Windows/RED4ext ecosystem), **NOT AVAILABLE on macOS**, explicitly flagged per project rules. Their *intent* (raise Gunshot/Explosion/District radii) is portable via the script hooks in F5/F8/F12; their *mechanism* (direct TweakDB flat writes) is not.
- `CDPR-Modding-Documentation/Cyberpunk-Tweaks` (GitHub, found via `gh search code`) — a community-maintained vanilla TweakDB tweak-file dump, same directory layout as the game's own `r6/tweaks`. Used to independently confirm vanilla stim radii (F10) since `sprint/vanilla-scripts` contains only `.script` decompiles, no TweakDB dump.

## Dead ends
- Searching `vanilla-scripts` for any TweakDB **writer** API (`TweakDBInterface.Set*`, `.Update*`, flat-write patterns) — none exist; confirms the project's own stated constraint (TweakDB is read-only from REDscript here) rather than adding new information, but worth recording that this was checked, not assumed.
- Trying to resolve, from script alone, what the native `CreateStimEvent`/`ProcessSingleStimuliBroadcast` (`stimBroadcasterComponent.script:860-861`, both `import`) do internally with `radius=0.0` (i.e. whether they truly read the `Stim` TweakDB record's own `radius` field as a fallback, versus some other native default). This is architecturally the most likely explanation (an `optional radius:Float` sitting next to a same-shaped TweakDB `Stim.radius` field is the standard CDPR idiom seen elsewhere in this codebase) but is genuinely opaque past the `import` boundary. **Does not block the recommended hook strategy** (F5) since that hook overrides `radius` *before* it reaches the native call, regardless of what the native fallback does.
- Confirming whether `weapon.script:Fire`'s silenced-branch broadcasts (`:2019-2020`, ungated) and `weaponTransitions.script:ShootEvents.OnEnter`'s silenced branch (`:2397-2403`) both actually execute per player-fired silenced shot (possible double-broadcast) — would require tracing whether `ShootEvents.OnEnter` itself calls `WeaponObject`/`weapon.script:Fire`, which the static call graph in `.script` decompiles doesn't make obvious without deeper cross-referencing. Stopped after the finding was confirmed **not to matter** for hook-point selection (F5's chokepoints catch both call sites regardless).
- Web search for the exact vanilla `SilencedGunshotStimuli.radius` numeric value stalled twice on generic tool-documentation results (WebSearch on redmodding wiki / TweakXL repo, no numbers) before `gh search code` (a different method) found the actual dump on the third attempt — recorded here so a future researcher tries `gh search code "<TweakRecordName>"` first, not last, for this class of question.

## Open questions
None planner-blocking. Two informational (non-blocking) uncertainties carried forward from Dead ends above: (a) exact native semantics of `radius=0` in `CreateStimEvent`, (b) whether player-fired silenced shots double-broadcast `SilencedGunshot`/`IllegalAction`. Neither changes the hook-point recommendation in F5/F12.
