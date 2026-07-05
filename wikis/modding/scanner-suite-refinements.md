# Scanner Suite Refinements — Feasibility Research (2026-07-06)

Scope: two refinements to the locally-authored **Custom Scanner Suite**
(`mods/enabled/r6-scripts/custom-scanner-suite/ScannerSuite.reds`), pure REDscript only, game v2.3x macOS Steam.

- **Refinement 1 (final spec after four revisions):** auto-tag is no longer hover-based. While scan mode is ON, continuously tag **everything currently in the player's camera view (frustum — in front, not behind), IGNORING obstruction/LOS** (tag through walls), for FIVE whitelisted categories only: (1) safe-to-attack enemies (no crime / no NCPD heat), (2) collectables, (3) quest-related elements, (4) un-breached network Access Points, (5) security cameras & turrets. Manual middle-click stays 100% vanilla; once-per-entity semantics kept.
- **Refinement 2 (final spec):** auto-pickup unchanged — hover trigger, 12 m range (the 10 m interim change was reverted; current `AutoPickupMaxDistance() = 12.0` stays). Only open question was the LOS gate: **verdict below = KEEP.** (Original "vanilla loot-prompt parity gate" research kept as a superseded note.)

Evidence tiers: **VERIFIED** = read directly in the local decompiled 2.x vanilla sources
(`scratchpad/vanilla-scripts/`, adamsmasher/CDPR-Modding-Documentation dump — same dump the existing plans cite). **SPECULATED** = inferred, not directly confirmed in source.

Verdict up front: **Refinement 1 feasible in pure REDscript** — new periodic sweep (DelaySystem loop + `TargetingSystem.GetTargetParts` with the frustum-only target set) feeding the existing `AutoTagTryOnce` path through a five-category whitelist; one coverage caveat on loot containers (1.4). **Refinement 2 is a no-op confirmation** plus the recommendation to keep its LOS gate.

---

## Refinement 1 — visible-sweep auto-tag with category whitelist

### 1.1 What vanilla tagging already gives us (VERIFIED)

`core/systems/focusModeTagging.swift`:

- `FocusModeTaggingSystem.CanTag() -> Bool` (public final const, line 187): only checks player stat `gamedataStatType.HasCybereye > 0` and absence of `GameplayRestriction.NoScanning`. **No target-category filtering at all** — the whitelist cannot be delegated to `CanTag`.
- `FocusModeTaggingSystem.TagObject(target)` (private, line 98): re-checks `this.CanTag() && target.CanBeTagged()` then tags. Callable from `@addMethod` class scope — the suite's existing `AutoTagTryOnce` already does this.
- Manual path `OnActionWithOwner` (TagButton) is untouched by the mod — manual middle-click can still tag/untag anything vanilla allows.

`GameObject.CanBeTagged()` base (`core/entity/gameObject.swift:1547`) **returns `true` unconditionally** — devices, vehicles, containers, dropped items are all vanilla-taggable. No override exists anywhere under `cyberpunk/devices/` (grepped; none). So middle-click DOES tag cameras, turrets, vehicles, crates, access points, quest props.

`ScriptedPuppet.CanBeTagged()` override (`cyberpunk/puppet/scriptedPuppet.swift:1677`) — the only category filter vanilla has, puppets only (VERIFIED, full body):

```swift
public const func CanBeTagged() -> Bool {
  if this.IsCrowd() || this.IsCharacterCivilian() { return false; };
  if !this.IsActive() && !this.IsContainer() { return false; };   // dead+lootless
  if GameObject.IsFriendlyTowardsPlayer(this) { return false; };
  if this.IsCerberus() { return false; };
  return true;
}
```

**Answer to "does vanilla tag civilians": NO** — crowd and civilian-preset puppets are already un-taggable (`TagObject` no-ops on them). That part of the whitelist is free. **Police, gangers, vendor-puppets, devices, vehicles, containers are NOT excluded by vanilla** — the whitelist must handle those itself.

### 1.2 The "attack without crime" predicate (VERIFIED)

The authoritative crime gate is `PreventionSystem.ShouldPreventionSystemReactToAttack` (`core/systems/preventionSystem.swift:2975`) — the ONLY entry point that turns player damage into crime score / wanted stars (`OnPreventionDamage` -> `CalculateCrimeScoreForNPC`). Its target-classification core:

```swift
if NPCManager.HasTag(puppetTarget.GetRecordID(), n"DoNotTriggerPrevention") { return false; };
if puppetTarget.IsCrowd() || puppetTarget.IsVendor() || puppetTarget.IsCharacterCivilian()
   || puppetTarget.IsPrevention() || NPCManager.HasTag(puppetTarget.GetRecordID(), n"TriggerPrevention") {
  return true;   // crime
};
// vehicles: IsPrevention() || HasPassengers() -> crime
return false;    // everything else (incl. ALL devices): NOT a crime
```

So **"safe-to-attack" == not (crowd | vendor | civilian | police | TriggerPrevention-tagged)**, with `DoNotTriggerPrevention` as an absolute exemption, and **devices never generate crime** (gate handles only puppets + vehicles — VERIFIED). Attacking an **already-hostile cop is still a crime by this gate** (heat rises further); user spec whitelists hostile police anyway — correct gameplay-wise, you're already wanted.

Supporting predicates, all VERIFIED in `cyberpunk/puppet/scriptedPuppet.swift`:

| Predicate | Line | Body / meaning |
|---|---|---|
| `IsCharacterCivilian() -> Bool` (public final const) | 1394 | cached `m_isCivilian` = reaction-preset group `"Civilian"` (`RefreshCachedReactionPresetData`, 1351) |
| `IsCharacterPolice()` / `IsPrevention()` | 1398/1553 | cached group `"Police"`; `IsPrevention()` returns `IsCharacterPolice()` |
| `IsCharacterGanger()` | 1410 | cached group `"Ganger"` |
| `IsCrowd()` | 1425 | record `IsCrowd()` or crowd-member component |
| `IsVendor()` | 1336 | character record has valid `VendorID()` |
| `IsCharacterCyberpsycho()` | 1390 | cached record tag `Cyberpsycho` (false if crowd) |
| `IsBoss()` / `IsMaxTac()` | 1299/1310 | NPCRarity Boss / MaxTac |
| `IsEnemy()` | 1574 | `IsHostile() \|\| IsNeutral() && !IsCharacterCivilian() && !IsCrowd()` |
| `IsAggressive()` | 1578 | FistFight SE, aggressive reaction preset, reaction-system registration, or hostile-to-player attitude |
| `IsActive()` / `IsDead()` / `IsIncapacitated()` | 1537/1557 | liveness |

`core/entity/gameObject.swift`: `GameObject.GetAttitudeTowards(a, b) -> EAIAttitude` (static, 451), `IsHostile()` = `HasAttitude(AIA_Hostile)` vs local player (499), `IsNeutral()` (503), `IsFriendlyTowardsPlayer(obj)` (481). `cyberpunk/managers/npcManager.swift:119`: `NPCManager.HasTag(recordID: TweakDBID, tag: CName) -> Bool` (public static — reads `Character_Record.Tags()`).

**Local precedent check** — `fighting-gangs-allowed-reasonable-police/FightingGangsAllowed.reds`: wraps `ReactionManagerComponent.ProcessReactionOutput` (police ignore player stims) and replaces `AIActionHelper.TryChangingAttitudeToHostile` using `IsPrevention()`/`IsAggressive()`. Its classification atoms are sound and re-verified, but it models *NPC reaction* to the player, not *crime attribution*. For the whitelist, mirroring `ShouldPreventionSystemReactToAttack` directly is strictly more faithful — that function IS the crime system. Reuse the atoms, not the structure.

### 1.3 Whitelist predicate chain (recommended, exact signatures verified)

```reds
// Categories 4+5 + enemy-device handling — non-puppet branch
// Category 1 — safe-to-attack enemy (puppet branch)
func ST_IsWhitelisted(target: ref<GameObject>) -> Bool {
  let p: ref<ScriptedPuppet> = target as ScriptedPuppet;
  if !IsDefined(p) {
    // CATEGORY 4 — network access points, un-breached only (default; see below)
    if target.IsAccessPoint() {                       // GameObject base false (gameObject.swift:1867);
                                                      // AccessPoint override true (accessPoint.swift:119)
      let ap: ref<AccessPoint> = target as AccessPoint;
      return IsDefined(ap) && !ap.GetDevicePS().IsBreached();   // both public const — verified below
    };
    // CATEGORY 5 — security cameras & turrets, skip destroyed/broken (default; see below)
    if target.IsSensor() {                            // GameObject base false; SensorDevice override true
                                                      // (sensorDevice.swift:412) — covers SurveillanceCamera
                                                      // and SecurityTurret (verified subclasses)
      let dev: ref<Device> = target as Device;
      return IsDefined(dev) && !dev.GetDevicePS().IsBroken();
    };
    return false;                                     // all other devices/vehicles: not whitelisted
    // (categories 2/3 for non-puppets checked by the caller before this — see below)
  };
  // CATEGORY 1 — puppets
  if !p.CanBeTagged() { return false; };           // vanilla gate: crowd/civ/friendly/Cerberus/dead-lootless
  if p.IsHostile() { return true; };               // already hostile — incl. police in combat, aggroed cyberpsychos, bosses
  if p.IsCharacterCyberpsycho() { return true; };  // NCPD scanner targets: meant to be fought
  if NPCManager.HasTag(p.GetRecordID(), n"DoNotTriggerPrevention") { return true; };  // crime-exempt by record
  if p.IsPrevention() || p.IsVendor() || p.IsCharacterCivilian() || p.IsCrowd()
      || NPCManager.HasTag(p.GetRecordID(), n"TriggerPrevention") { return false; };  // crime -> never auto-tag
  return p.IsEnemy();                              // hostile OR neutral-non-civilian (gangers idling in territory)
}

// CATEGORY 2 — collectables (same classification auto-pickup already uses — reuse is straightforward)
// puppet: (IsDead() || IsIncapacitated()) && IsContainer()   [corpse with loot]
// non-puppet: IsContainer() || IsShardContainer() || IsItem()  — IsItem() is protected final const,
// so this predicate must live in an @addMethod(GameObject) like the existing APS_TryAutoPickup (precedent in-file).
// Exclude IsPlayerStash().

// CATEGORY 3 — quest-related
// target.IsQuest() || target.GetAvailableClueIndex() >= 0
```

**Category 3 basis (VERIFIED):** the scanner's own QUEST highlight is driven by `GameObject.GetDefaultHighlight()` (`gameObject.swift` ~1560): `if this.IsQuest() -> EFocusForcedHighlightType.QUEST`. `IsQuest()` = `m_markAsQuest` (quest-system controlled via `SetAsQuestImportantEvent`); puppet override adds `m_hasQuestItems` (scriptedPuppet.swift:3000). So `IsQuest()` matches exactly what the player sees as gold/quest in scan mode. `GetAvailableClueIndex() -> Int32` (public final const, gameObject.swift:2133, −1 when no clue) adds focus-clue props not yet marked. Quest *mappins* (MappinSystem) not needed — SPECULATED they'd only add map-level markers; skipped.

**Category 4 basis (VERIFIED):** `AccessPoint extends InteractiveMasterDevice` (`cyberpunk/devices/masters/accessPoint.swift:21`); overrides `IsAccessPoint() -> true` (line 119); `GameObject.IsAccessPoint()` base returns false (gameObject.swift:1867) — clean, callable on any enumerated GameObject. `AccessPoint.GetDevicePS() -> ref<AccessPointControllerPS>` is **public const** (accessPoint.swift:73). `AccessPointControllerPS.IsBreached() -> Bool` is **public const quest** (`accessPointController.swift:294`): `return this.m_isBreached || this.WasHackingMinigameSucceeded();` — `m_isBreached` is persistent (line 138), so already-breached APs stay excluded across saves.
Recommended default: **only dedicated `AccessPoint` entities, un-breached (`!IsBreached()`)**. Alternative considered: any device with a network backdoor / datamine-capable computers — `GameObject.IsConnectedToBackdoorDevice()` (public const, gameObject.swift:1912) and `Computer extends Terminal` (computer.swift:53) exist, so widening is technically easy, but every camera/screen on a breached-able network would light up — noise, and the physical AP is where the materials/eddies breach actually happens. Note: `lootContainerAccessPoint.swift` defines AP-in-loot-crate variants; they ride the same `IsAccessPoint()` override chain (SPECULATED for that subclass, not read line-by-line).

**Category 5 basis (VERIFIED):** `SurveillanceCamera extends SensorDevice` (`cyberpunk/devices/cameras/surveillanceCamera.swift:2`), `SecurityTurret extends SensorDevice` (`cyberpunk/devices/securityTurret/securityTurret.swift:2`); `SensorDevice.IsSensor() -> true` override (sensorDevice.swift:412) vs GameObject base false — so `target.IsSensor()` identifies exactly the camera/turret family from an enumerated entity. State predicates on `ScriptableDeviceComponentPS` (`cyberpunk/devices/core/scriptableDeviceBasePS.swift`), all public: `IsBroken()` (final const, line 5770), `IsON()` (1374), `IsDisabled()` (1390), `IsUnpowered()` (1405); reachable via `Device.GetDevicePS()` (public const, deviceBase.swift:803, and `SensorDevice.GetDevicePS() -> ref<SensorDeviceControllerPS>`, sensorDevice.swift:472).
Recommended default (per spec): **skip broken/destroyed (`IsBroken()`), tag everything else** — including friendly-hacked, disabled and unpowered ones (they can be re-enabled by enemies/netrunners; knowing where they are stays valuable). Alternatives: also skip `IsDisabled()`/`IsUnpowered()` (quieter HUD), or tag only hostile ones (`target.IsHostile()` — attitude API works on devices via their attitude agents, VERIFIED `GameObject.GetAttitudeTowards`); the earlier hostile-only device rule from the pre-update draft is superseded by this category.

Decision table (edge cases):

| Target | Chain result | Why |
|---|---|---|
| Gang member hostile in combat | TAG | `IsHostile()` |
| Gang member neutral in own territory | TAG | `IsEnemy()` (neutral, non-civ) and prevention gate returns "no crime" for them (VERIFIED) |
| Civilian / crowd | NO TAG (free) | vanilla `CanBeTagged()` already false |
| Police calm | NO TAG | `IsPrevention()` -> crime branch |
| Police already hostile | TAG | `IsHostile()` short-circuits before police check |
| Vendor | NO TAG | `IsVendor()` in crime branch (attacking = crime, VERIFIED) |
| Cyberpsycho (pre-aggro neutral) | TAG | explicit `IsCharacterCyberpsycho()` |
| Boss / MaxTac in fight | TAG | `IsHostile()` (rarity irrelevant to whitelist) |
| Drone / mech / android | TAG when hostile/enemy | they ARE `ScriptedPuppet` (`GetNPCType()` Drone/Mech — VERIFIED, scriptedPuppet.swift:1332), same puppet chain |
| Security camera / turret, working | TAG (cat 5) | `IsSensor() && !IsBroken()` — any attitude/state except broken |
| Security camera / turret, destroyed | NO TAG | `IsBroken()` |
| Access point, un-breached | TAG (cat 4) | `IsAccessPoint() && !IsBreached()` |
| Access point, already breached | NO TAG | persistent `m_isBreached` / minigame-succeeded |
| Computer with datamine option | NO TAG (default) | not `IsAccessPoint()`; widening alternative documented above |
| Friendly companion (Jackie etc.) | NO TAG (free) | vanilla `IsFriendlyTowardsPlayer` in `CanBeTagged` |
| Cerberus | NO TAG (free) | vanilla `CanBeTagged` |
| Vehicle | NO TAG | no category (attacking occupied/police vehicles = crime, VERIFIED) |
| Non-sensor, non-AP device (door, screen, vending) non-quest | NO TAG | excluded — part of what vanilla WOULD tag that we now skip |
| Quest prop / quest NPC / clue | TAG (cat 3) | `IsQuest()` / clue index |
| Corpse with loot / crate / shard / dropped item | TAG (cat 2) | collectables classification |

### 1.4 Enumerating "everything in view" (the sweep) — frustum-gated, obstruction IGNORED

**Only pure-REDscript entity enumerator: `TargetingSystem.GetTargetParts`** (VERIFIED, orphans.swift:22383):

```swift
public final native func GetTargetParts(instigator: wref<GameObject>, query: TargetSearchQuery,
                                        out parts: [TS_TargetPartInfo]) -> Bool;
```

`TargetSearchQuery` fields (VERIFIED, orphans.swift:28817): `testedSet: TargetingSet`, `searchFilter: TargetSearchFilter`, `includeSecondaryTargets`, `ignoreInstigator`, `maxDistance: Float`, `filterObjectByDistance: Bool`, `queryTarget`. `TargetingSet` enum (VERIFIED names, orphans.swift:3194): `Visible=0, ClearlyVisible=1, Frustum=2, Complete=3, None=4`.

**LOS-ignore mapping (per final spec):**
- **Use `testedSet = TargetingSet.Frustum`** — camera-frustum membership without occlusion testing (semantics from enum name + set ordering: SPECULATED; vanilla scripts use `Complete` for AoE effectors and `ClearlyVisible` for melee selection — meleeTransitions.swift:2636 — never `Frustum` directly).
- The flags/sets that WOULD have enforced LOS (documented, deliberately NOT used for auto-tag): `TargetingSet.Visible` / `TargetingSet.ClearlyVisible` (occlusion-tested sets) and the per-candidate native `TargetingSystem.IsVisibleTarget(instigator, target)` (orphans.swift:22453). `IsVisibleTarget` stays in use ONLY by auto-pickup (Refinement 2).
- "In front, not behind" backstop, in case `Frustum` proves broader than expected at runtime: `GetCrosshairData(instigator, out pos, out fwd)` (VERIFIED native) + dot-product `Vector4.Dot(fwd, targetPos − camPos) > 0` (or a tighter cosine for actual FOV). Cheap, pure-script, keeps correctness independent of set semantics.
- **Range cap recommendation:** "everything in frustum through walls" needs a hard radius — recommend config default **50 m** (`filterObjectByDistance = true`). Rationale: matches the useful scanner engagement envelope (nameplate/quickhack HUD search uses `SNameplateRangesData.GetMaxDisplayRange()` for the same purpose — hudManager.swift:627 — reusing that value at runtime is a good dynamic alternative); beyond ~50 m tags are unreadable clutter and every extra meter cubes the through-wall entity count. Policy value, SPECULATED as tuning; make it a config literal.

Filter helpers (VERIFIED, targetingSearchFilter.swift + orphans natives): `TSF_NPC()`, `TSF_EnemyNPC()`, `TSF_And/TSF_Not/TSF_Any/TSF_All`, `TSFMV` flags (`Obj_Puppet`, `Obj_Sensor`, `Obj_Device`, `Obj_Other`, `Att_Hostile`, `St_Dead`, ...). Vanilla's composite masks (`IntEnum<TSFMV>(2050)`, `2114`) are verified literals but their bit decoding is SPECULATED — **recommendation: query broadly (`TSF_Not(TSFMV.Obj_Player)`, or two passes: `TSF_NPC()` + `TSF_Any(TSFMV.Obj_Device)`/`TSF_Any(TSFMV.Obj_Sensor)`) and do ALL category filtering script-side with the 1.3 chain**, so mask semantics can't bite. Note `TSFMV.Att_*` / `St_*` flags exist but attitude/state filtering is deliberately done script-side.

Vanilla precedent for exactly this pattern (VERIFIED): `highlightEffector.swift:64` — builds query (`testedSet`, `searchFilter`, `maxDistance`, `filterObjectByDistance=true`), calls `GetTargetParts`, iterates `TS_TargetPartInfo.GetComponent(parts[i]).GetEntity() as GameObject`. Also `GameObject.GetEntitiesAroundObject(range, filter)` (gameObject.swift:687) is a ready-made public wrapper with dedupe — but hardcodes `TargetingSet.Complete`, so write our own query for frustum semantics (borrow its dedupe loop).

**Coverage caveat (the one real gap):** `GetTargetParts` enumerates entities with `TargetingComponent`s. Puppets, sensors, devices have them (vanilla queries prove it — incl. `TSF_Any(TSFMV.Obj_Device)` in highlightEffector). Plain loot crates (`gameLootContainerBase`), shard cases, and dropped `ItemObject`s **likely do NOT** — nothing in the decompile ever retrieves them via targeting queries; the scanner acquires them via `ScanningComponent`/lookat instead. SPECULATED-LIKELY: the sweep will see categories 1, 4, 5, most of 3, and corpses (puppets), but **miss standalone containers/dropped items**. `SpatialQueriesSystem` is no help (raycast/overlap only, no entity enumeration — VERIFIED orphans.swift:27631). Mitigation is free: **keep the existing hover auto-tag path as the collectables channel** (crosshair-acquired loot is auto-tagged/auto-picked exactly as today). Add a one-session debug probe (log class names returned by a broad sweep) to settle container coverage empirically; if containers DO appear, fold them into the sweep and retire the hover tag path.

Alternatives considered: mod 26670 "Auto Tag Enemies" (REDscript) tags NPCs *that turn hostile/alerted* — event-driven, no visibility sweep; precedent for "tag on aggro" but doesn't satisfy "everything in view". CNML 16040 (gold precedent, source read): global `GameObject.OnGameAttached` registry + self-re-arming `DelayCallback` batches — proves pure-REDscript periodic-tick machinery at scale.

### 1.5 Driving the sweep (tick while scanner is ON)

Recommended driver (all parts VERIFIED):

1. **Start/stop:** the suite already wraps `HUDManager.OnScannerUIVisibleChanged(visible)`. On `visible==true` start the loop; the loop self-terminates when scanner closes (check `HUDManager.GetActiveMode(game) == ActiveMode.FOCUS` — static, hudManager.swift:1247 — each tick and simply don't re-arm).
2. **Loop:** `DelayCallback` subclass with `Call()` -> run sweep -> re-arm via `GameInstance.GetDelaySystem(game).DelayCallback(cb, delay, false)` (VERIFIED signature orphans.swift:11818; `CancelCallback(delayID)` available; `CNML.reds:643` is the working in-repo precedent).
3. **Cadence:** 0.25–0.5 s. One `GetTargetParts` per tick is the same class of call vanilla effectors fire per activation; at 2–4 Hz with the 50 m cap the cost is negligible. Per-candidate work is a handful of cached-bool predicate reads.
4. **Once-per-entity:** reuse `m_autoTagSeen` ledger exactly as today — mark seen when the auto-tag fires, so a manual untag is never re-tagged; non-whitelisted entities are never marked (they "spend nothing") and get re-filtered each tick (cheap; optionally add a per-scan-session negative cache if profiling ever demands it).
5. `OnScannedObjectChanged` hover wrap stays: for tagging it now serves the collectables channel (1.4 caveat); auto-pickup dispatch unchanged.

### 1.6 Quest-clue safety (VERIFIED)

`ResolveFocusClues(tag, target)` (focusModeTagging.swift:138) does one thing: if the target has an available focus clue with valid `clueGroupID`, it queues `TagLinkedCluekRequest` — i.e. it **propagates TAG state across a linked clue group**. Quest "scan the clue" beats are completed by the ScanningComponent inspection pipeline (`WasInspected`, `conclusionQuestState`, `SetIsScanned_Event` — scanningComponent.swift 241–352, 775+), which runs when the player scans, **independent of tagging**. Vanilla itself only calls `ResolveFocusClues` on a manual TagButton press — most playthroughs never tag most clues and quests progress fine. Therefore: **skipping clue resolution for non-whitelisted targets is safe for quest progression**; keep calling it (with `tag=true`) inside the auto-tag attempt for whitelisted targets, as `AutoTagTryOnce` already does.

Hover-based auto-tag (previous design) stays documented in `plan-auto-tag-on-scan.md` as the fallback if the sweep proves infeasible/too heavy; the 1.3 whitelist chain drops into the existing hover wrap unchanged.

---

## Refinement 2 — auto-pickup: confirmed as-is + LOS verdict

Final spec after revisions: hover trigger unchanged, range unchanged at **12 m** (`AutoPickupMaxDistance() = 12.0` already in the file — the interim 10 m request was reverted). **Functional code change: none.**

**LOS gate verdict: KEEP `IsVisibleTarget`.** Reasoning: the scanner cursor resolves targets through walls and floors; a bare 12 m sphere without occlusion would vacuum loot from adjacent rooms, behind locked doors, and one floor down — immersion-breaking and occasionally sequence-breaking (loot gated behind a locked route). `IsVisibleTarget` is a single native occlusion check (VERIFIED, orphans.swift:22453), already implemented, already treated as a transient refusal (walk around the wall, re-hover, retries). Zero cost to keep, real failure mode if dropped. Note the deliberate asymmetry: auto-TAG ignores LOS by spec (information through walls = the scanner fantasy); auto-PICKUP keeps LOS (physically moving items through walls is not).

All other safety filters unchanged: alive-puppet transient refusal, locked-container transient refusal, player-stash final skip, quest/`IsQuest`/iconic/HMG/nameless filters, once-per-entity attempt ledger, transient-vs-final semantics, open-animation + loot sound.

**Considered & superseded (kept for the record):** a vanilla-parity gate ("fire only when the manual loot prompt would show") was viable. `LootData` struct VERIFIED (orphans.swift:41346): `isActive: Bool`, `ownerId: EntityID`, `itemIDs: [ItemID]`, `isLocked: Bool`, `choices`, `title`, `currentIndex`, `isListOpen` — published to `UIInteractions.LootData` (blackboardDefinitions.swift:811) and already routed into the wrapped `HUDManager.OnLootDataChanged`. The gate would have been `data.isActive && data.ownerId == scannedEntityID`. Interdependency it carried: with Loot-While-Scanning toggled OFF, vanilla pushes `UIGameContext.Scanning` and interaction visualizers are suppressed, so LootData very likely stops updating during scan (SPECULATED, would have needed the probe) — a TweakDB numeric-range fallback would have been required. The final spec removes the whole dependency chain; interaction-record TweakDB ranges were not dug further.

---

## Impact on current ScannerSuite.reds

File: `/Users/teazyou/dev/tmp-claude/cyberpunk/mods/enabled/r6-scripts/custom-scanner-suite/ScannerSuite.reds` (389 lines today).

| Change | Where | Est. LOC |
|---|---|---|
| Auto-pickup | — | 0 (12 m + LOS confirmed as-is) |
| Config: sweep radius (50.0) + cadence (0.35) + per-category toggles (optional) + sweep debug probe | USER CONFIG block | +18 |
| Whitelist predicates: puppet chain + AP + sensor branches (`ST_IsWhitelisted*`), collectables check needs `@addMethod(GameObject)` for protected `IsItem()` (precedent: `APS_TryAutoPickup`), quest check | new section | +55 |
| Sweep: `DelayCallback` subclass + running-flag field + sweep body (`GetTargetParts` frustum query -> dedupe -> whitelist -> `AutoTagTryOnce`) + start hook inside existing `OnScannerUIVisibleChanged` wrap | new; 3-line addition to existing wrap | +60 |
| `AutoTagTryOnce` / `m_autoTagSeen` | unchanged (reused by sweep) | 0 |
| Shared hover wrap `OnScannedObjectChanged` | auto-tag branch narrows to collectables channel (or stays as-is harmlessly — sweep + hover share the seen-ledger, double-fire impossible) | ~5 (edit) |
| Header comment rewrite | top block | ~15 (edit) |

Net: roughly **+135 new / ~20 edited LOC**; auto-pickup feature body untouched.

## Risks & unknowns

1. **Container/dropped-item sweep coverage** — SPECULATED-LIKELY that `GetTargetParts` won't return plain loot containers (no TargetingComponent). Design already absorbs it (hover channel kept); settle with the debug probe. MEDIUM.
2. **`TargetingSet.Frustum` exact semantics** — names VERIFIED, behavior not exercised by vanilla scripts, and it is now load-bearing (no `IsVisibleTarget` backstop for tag, by spec). Mitigations: camera-forward dot test guarantees "in front"; debug probe confirms through-wall + behind-player behavior on first run. If `Frustum` returns nothing usable, fall back to `Complete` + dot-product angle gate (same effect, slightly wider). MEDIUM-LOW.
3. **TSFMV composite-mask decoding** (2050/2114) unverified — mitigated by filtering script-side only. LOW.
4. **`IsCharacterCyberpsycho` pre-aggro crime status** — a civilian-preset cyberpsycho shot first could still raise heat despite the (desirable) tag. Tagging itself never causes crime; worst case = tag on a technically-crime target. Drop the clause if purism wins. LOW.
5. **Through-wall tagging is by design** but reveals silhouettes of enemies the player "hasn't seen" — intended scanner fantasy per spec; note it flattens stealth recon difficulty. ACCEPTED BY SPEC.
6. **Perf** — 2–4 Hz native query + cached-bool predicates; CNML ran far heavier loops acceptably. LOW.
7. **Tag spam on dense scenes** (gang hideout + cameras + APs in one scanner open) — intended per spec; per-category config toggles are the dial; tagged-object HUD pins persist ~vanilla tag duration. COSMETIC.
8. **Quest-clue skip** — analyzed safe (1.6); residual risk only if some quest scripted a beat on *tag* rather than *scan* (none found in decompile). LOW.
9. **`lootContainerAccessPoint` subclass** assumed to inherit `IsAccessPoint()==true` — not read line-by-line. Trivial to confirm during implementation. LOW.

## Sources

- Local decompiled 2.x vanilla scripts (adamsmasher / CDPR-Modding-Documentation dump, scratchpad `vanilla-scripts/`): `core/systems/focusModeTagging.swift`, `core/systems/preventionSystem.swift` (crime gate 899–962, 2947–3045), `core/entity/gameObject.swift` (CanBeTagged 1547, attitude 451–505, GetDefaultHighlight ~1560, GetEntitiesAroundObject 687, IsAccessPoint 1867, IsConnectedToBackdoorDevice 1912, clues 2125–2140), `cyberpunk/puppet/scriptedPuppet.swift` (predicate table, CanBeTagged 1677, IsQuest 3000), `cyberpunk/managers/npcManager.swift` (HasTag 119), `cyberpunk/devices/masters/accessPoint.swift` (21/73/119) + `accessPointController.swift` (138/294), `cyberpunk/devices/cameras/surveillanceCamera.swift:2`, `cyberpunk/devices/securityTurret/securityTurret.swift:2`, `cyberpunk/devices/core/sensorDevice.swift` (23/412/472), `cyberpunk/devices/core/deviceBase.swift` (82/803), `cyberpunk/devices/core/scriptableDeviceBasePS.swift` (1374/1390/1405/5770), `cyberpunk/devices/masters/computer.swift:53`, `core/gameplay/targetingSearchFilter.swift`, `core/gameplay/effectors/custom/highlightEffector.swift`, `core/systems/hud/hudManager.swift` (GetTargetParts 630, GetActiveMode 1247), `core/components/scanningComponent.swift`, `orphans.swift` (TargetingSystem 22381+, TargetSearchQuery 28817, TSFMV/TargetingSet 3171+, LootData 41346, DelaySystem 11814, SpatialQueriesSystem 27631), `core/blackboard/blackboardDefinitions.swift:811`.
- Installed mod source: `mods/enabled/r6-scripts/fighting-gangs-allowed-reasonable-police/FightingGangsAllowed.reds` (classification precedent).
- Mod precedents (scratchpad): `CNML.reds` (16040, DelayCallback loop + loot filters), `mod-26670.md` (Auto Tag Enemies — tags on hostility events, no visibility sweep).
- Prior dossiers: `wikis/modding/plan-auto-tag-on-scan.md`, `plan-auto-pickup-on-scan.md`, `scan-mode-*.md` (hover fallback design lives there).
