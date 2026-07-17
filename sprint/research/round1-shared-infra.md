# R1 — Cross-cutting: sweep loop, entity keying, eligibility predicates, RNG, HUD notify (shared-infra)

## Verdict
Feasible, fully. All 5 areas have vanilla-grep-verified APIs AND an in-game-proven ScannerSuite.reds pattern to structurally mirror (not copy — clean file, `EnemyOverhaul.Common.reds`). Decisive fact: the crash-safe shape is **`DelaySystem.DelayCallback` self-re-arming loop, armed once from `PlayerPuppet.OnGameAttached`, enumerating via `GameObject.GetEntitiesAroundObject`/`GetNPCsAroundObject` (`TargetingSet.Complete` — 360°, camera-independent) filtered by `TSF_EnemyNPC()`** — cheaper than `GameInstance.GetEntityList` (ScannerSuite's own comments call GetEntityList "expensive" 3×) and, unlike ScannerSuite's tag sweep (`TargetingSet.Frustum`, camera-bound), Complete matches the briefs' "sweep around the player" requirement natively. One real gap: no clean vanilla predicate for "quest/named/scripted-unique NPC" exists beyond Boss/MaxTac rarity — flagged as the one open risk shared by all three briefs.

## Findings

### 1. Sweep loop — DelaySystem self-re-arming callback (verbatim pattern)
`DelayCallback` is a native base class; `DelaySystem.DelayCallback(cb, interval, isAffectedByTimeDilation)` schedules one shot:
```
import class DelayCallback extends IScriptable { public virtual function Call(); }          // sprint/vanilla-scripts/scripts/core/gameplay/delaySystem.script:41-44
public import function DelayCallback( delayCallback : DelayCallback, timeToDelay : Float, optional isAffectedByTimeDilation : Bool ) : DelayID;   // delaySystem.script:59
public import function DelayCallbackNextFrame( delayCallback : DelayCallback );             // delaySystem.script:63
public import function CancelCallback( delayID : DelayID );                                 // delaySystem.script:67
public import static function GetDelaySystem( self : GameInstance ) : DelaySystem;          // gameInstance.script:21
```
ScannerSuite.reds implements this pattern **twice**, verbatim, and both are directly reusable as Common.reds's template:
- Tag sweep: `STSweepTickCallback extends DelayCallback` (ScannerSuite.reds:1303-1311) + `ST_ArmSweep()` (1334-1354) + `ST_SweepTick()` (1356-1411, self-re-arms before doing any work — "FAULT-PROOF RE-ARM" comment at 1368).
- Loot loop: `APSLootLoopCallback extends DelayCallback` (1788-1796) + `APS_StartLootLoop()`/`APS_ArmLootTick()` (1806-1826) + `APS_LootLoopTick()` (1828-1882, identical fault-proof-rearm-first ordering, comment at 1845-1850).
Both are armed **exactly once** from `@wrapMethod(PlayerPuppet) protected cb func OnGameAttached() -> Bool` (ScannerSuite.reds:1949-1970), guarded by a `Bool` double-arm field (`m_stSweepArmed` / `m_apsLoopArmed`) so a replacer re-attach never runs two loops. Vanilla decl: `protected event OnGameAttached()` on `PlayerPuppet` at `sprint/vanilla-scripts/scripts/cyberpunk/player/player.script:1161` — **this is the game-thread-safe player-object hook**, distinct from the per-entity streaming hook `GameObject.OnGameAttached()` at `gameObject.script:490` that crashed the worker thread (context-environment.md rule #2; ScannerSuite.reds:201-206 documents the exact crash and fix).
Gotchas baked into both loops, worth carrying into Common.reds: skip-but-stay-alive during replacer/braindance (`this.IsReplacer()` — `gameObject.script:1731`, override `player.script:582`; `HUDManager.IsBraindanceActive()` — `hudManager.script:615`), and the re-arm-before-work ordering (a fault in enumeration/classification this tick must never kill the loop for the session).

### 2. Enumeration APIs — three verified options, ranked
**(a) `GameObject.GetEntitiesAroundObject` / `GetNPCsAroundObject` — recommended for the sweep.**
```
public function GetEntitiesAroundObject( optional range : Float, optional searchFilter : TargetSearchFilter ) : array< Entity >   // gameObject.script:936-965
public function GetNPCsAroundObject( optional range : Float ) : array< NPCPuppet >                                               // gameObject.script:967-987
```
Body of (a): builds a `TargetSearchQuery` with `testedSet = TargetingSet.Complete` (NOT Frustum — 360°, camera-independent), `maxDistance = range`, `filterObjectByDistance = range > 0.0`, `ignoreInstigator = true`, then calls `GameInstance.GetTargetingSystem(GetGame()).GetTargetParts(this, searchQuery, targetParts)` and dedupes into the return array. `GetNPCsAroundObject` is a thin wrapper calling (a) with `TSF_NPC()` and casting to `NPCPuppet`. Live vanilla caller precedent: `entities = player.GetEntitiesAroundObject( 20.0, filter )` — `sprint/vanilla-scripts/scripts/cyberpunk/UI/fullscreen/settings/settingsMain.script:755`. Callable directly as `player.GetEntitiesAroundObject(range, TSF_EnemyNPC())` — no manual query-struct plumbing needed.
**(b) `GameInstance.GetEntityList` — the raw-world-list fallback.**
```
public import static function GetEntityList( self : GameInstance ) : array< Entity >;   // sprint/vanilla-scripts/scripts/core/systems/gameInstance.script:106
```
Returns **every** streamed entity of every type (items, effects, vehicles, devices, NPCs) — no native filtering; caller must cast+distance-check each element. ScannerSuite's own comments call this "the **expensive** 360 GetEntityList pass" three times (config comment line 451; APS_LootLoopTick doc line 1783; inline comment line 1864) and deliberately throttle it to a slower cadence than the TargetingSystem-based channel. Independent vanilla-authored precedent for the identical iterate-and-cast idiom: `PlayerDevelopmentSystem.ScaleNPCsToPlayerLevel` (`sprint/vanilla-scripts/scripts/cyberpunk/systems/playerDevelopmentSystem.script:3041-3074`) — walks `GameInstance.GetEntityList(...)`, casts `entityList[i] as GameObject` then `as NPCPuppet`, and reads `NPCManager.HasTag(npc.GetRecordID(), 'MaxTac_Prevention')` (see Finding 5). ScannerSuite.reds cites this exact function as its own iterate+cast precedent at line 1892-1894.
**(c) `TargetingSystem.GetTargetParts` raw — for a custom filter/query Common.reds doesn't get from (a).**
```
public import function GetTargetParts( instigator : weak< GameObject >, query : TargetSearchQuery, out parts : array< TS_TargetPartInfo > ) : Bool;   // sprint/vanilla-scripts/scripts/core/systems/targetingSystem.script:84
public import static function GetComponent( self : TS_TargetPartInfo ) : weak< TargetingComponent >;   // targetingSystem.script:9
```
`TargetSearchQuery` fields: `testedSet: TargetingSet`, `searchFilter: TargetSearchFilter`, `includeSecondaryTargets/ignoreInstigator: Bool`, `maxDistance: Float`, `filterObjectByDistance: Bool`, `queryTarget: EntityID` (`targetingSearchFilter.script:53-64`). `TargetingSet` enum = `{Visible, ClearlyVisible, Frustum, Complete, None}` (`:40-47`). This is exactly what ScannerSuite's own `ST_RunSweepOnce` builds by hand (ScannerSuite.reds:1438-1446), but with `TargetingSet.Frustum` — appropriate for ITS camera/tag use case, wrong shape for an all-around player sweep. Use (a) instead unless a bespoke filter is needed.

**Filter-mask verdict:** ScannerSuite's own comment at line 1440 says composite `TSFMV` masks (`TSF_And`/`TSF_All` combos like `TSF_EnemyNPC()`) "stay unverified" and deliberately uses only the trivial `TSF_Not(TSFMV.Obj_Player)` filter, pushing all classification into script. **This research upgrades that caution**: `TSF_EnemyNPC()`/`TSQ_EnemyNPC()`/`TSF_NPC()`/`TSQ_NPC()` (`targetingSearchFilter.script:72-111`) are used live in vanilla's own **combat-critical** targeting paths — melee target acquisition (`defaultTransition.script:298,355`, `meleeTransitions.script:1271,3423`), weapon transitions (`weaponTransitions.script:1627`), damage system's closest-enemy-to-crosshair resolution (`damageSystem.script:3337,3340`), projectile homing (`monoDisc.script:61`, `projectileHelper.script:32,75`), and 3 gameplay effectors. `TSF_EnemyNPC()` body: `TSF_And( TSF_All( (TSFMV.Obj_Puppet | TSFMV.Att_Hostile) | TSFMV.St_Alive ), TSF_Not( TSFMV.Obj_Player ) )` (`targetingSearchFilter.script:79-84`) — puppet + hostile-toward-instigator + alive, excl. player. Safe to use as the native pre-filter. **Still only a pre-filter**, not full eligibility — Boss/MaxTac/police/mech/crowd/quest exclusions must still run script-side per-candidate (Finding 3), exactly mirroring how ScannerSuite itself does zero category classification at the query level.

### 3. Entity keying — EntityID semantics
```
importonly struct EntityID {
  public import static function IsDefined( id : EntityID ) : Bool;
  public import static function IsDynamic( id : EntityID ) : Bool;
  public import static function IsStatic( id : EntityID ) : Bool;
  public import static function GetHash( id : EntityID ) : Uint32;
  public import static function ToDebugString/ToDebugStringDecimal( id : EntityID ) : String;
}
import operator==/!=/<( a : EntityID, b : EntityID ) : Bool;
```
— `sprint/vanilla-scripts/scripts/core/entity/entityID.script:1-19`. `GetEntityID() -> EntityID` on `Entity` (`entity.script:5`). The `==` operator is what makes `ArrayContains(array<EntityID>, id)` work for a seen-set. No map/dict/set type in REDscript — every seen-set in this codebase is `array<EntityID>` + `ArrayContains`/`ArrayPush`/`ArrayErase`/`ArraySize` (ScannerSuite.reds:687-727 for tags, 1617-1639 for loot). **Persistence semantics (operational, not from a spec — ScannerSuite's own hard-won findings)**: an entity keeps the SAME `EntityID` across re-streaming within a session ("world devices keep their EntityID across streaming", ScannerSuite.reds:826) — good, this is exactly the "re-stream must not re-roll" guarantee all three briefs need. BUT the engine **recycles** a despawned entity's ID onto a later-spawned entity ("EntityIDs are recycled by the engine after an entity despawns... an unbounded ledger eventually false-flags a FRESH corpse that inherited a retired ID", ScannerSuite.reds:1629-1634) — the proven mitigation is a FIFO-capped array (cap 4096 in both ScannerSuite ledgers) so old entries age out. Common.reds's seen-set(s) should copy this FIFO-cap shape exactly.

### 4. Eligibility predicates — one verified predicate per brief category
All on `ScriptedPuppet` (base of `NPCPuppet`) unless noted; `GameObject`/`Puppet` base members noted separately.

- **Human/humanoid combat NPC**: `GetNPCType() -> gamedataNPCType` = `GetRecord().CharacterType().Type()` (`scriptedPuppet.script:1419-1422`). `IsHuman()` = `NPCType==Human` (`:1434-1437`); `IsHumanoid()` = `Human||Android` (`:1444-1449`). Enum `gamedataNPCType = {Android,Any,Cerberus,Chimera,Device,Drone,Human,Mech,Spiderbot,Count,Invalid}` (`tweakDBEnums.script:3371-3384`). Best single vanilla-authored combo predicate: `TargetIsHumanTrashToElite(target) = target.GetNPCType()==gamedataNPCType.Human && target.GetNPCRarity()!=gamedataNPCRarity.Boss` (`sprint/vanilla-scripts/scripts/cyberpunk/NPC/NPCPuppet.script:3065-3068`) — vanilla's OWN "human, any tier below boss" gate (used to decide Gorilla Arms/Mantis Blades one-punch marks).
- **Boss**: `IsBoss() = GetNPCRarity()==gamedataNPCRarity.Boss`; static overload `ScriptedPuppet.IsBoss(obj: weak<GameObject>)` guards with `obj.IsPuppet()` first (`scriptedPuppet.script:1640-1652`; `IsPuppet()` at `gameObject.script:1716`).
- **MaxTac**: PRIMARY = `IsMaxTac() = GetNPCRarity()==gamedataNPCRarity.MaxTac`, static overload same shape (`scriptedPuppet.script:1654-1666`). `gamedataNPCRarity = {Boss,Elite,MaxTac,Normal,Officer,Rare,Trash,Weak,Count,Invalid}` (`tweakDBEnums.script:3396-3408`) — **MaxTac is a rarity value, not a faction**: `gamedataAffiliation` enum (`NPCPuppet.script:2843-2883`, 30+ members incl. `NCPD`) has **no MaxTac entry** — rules out affiliation-based detection. Vanilla pairs `IsBoss() || GetNPCRarity()==gamedataNPCRarity.MaxTac` at 10+ call sites (NPCPuppet.script:448,840,2655; hitReactionComponent.script:331,2375,2492,2874; scriptedPuppet.script:1582,1629,4857; npcStateComponent.script:242) — treat Boss+MaxTac as a single combined exclusion, exactly as vanilla always does. SECONDARY/narrower tag signal: `NPCManager.HasTag(npc.GetRecordID(), 'MaxTac_Prevention')` (`playerDevelopmentSystem.script:3063`, var name `isPreventionMT`) — flags Prevention-registered MaxTac squads specifically; use rarity check as the authoritative one.
- **Police / prevention units**: `IsCharacterPolice()` (instance, backed by `m_isPolice`) + static `ScriptedPuppet.IsCharacterPolice(obj: GameObject)` (`scriptedPuppet.script:1780-1794`). `IsPrevention()` override is a literal alias: `return IsCharacterPolice();` (`:1976-1979`). Field populated by `RefreshCachedReactionPresetData()` reading `AIActionHelper.GetReactionPresetGroup(this) == "Police"` (`scriptedPuppet.script:1721-1725`, `AIActionHelper` decl in `sprint/vanilla-scripts/scripts/core/ai/actions/aiActionHelper.script`).
- **Mech/turret/drone/robot exclusion**: two-layer, both free side-effects of the class/type checks above. (1) Turrets/cameras/sensors are **structurally a different class tree** — `GameObject.IsSensor()/IsTurret()/IsDevice()` default `false`, overridden `true` only on the Device subtree (`gameObject.script:1766-1779`); `SensorDevice extends ExplosiveDevice` (`sprint/vanilla-scripts/scripts/cyberpunk/devices/core/sensorDevice.script:155`), `SurveillanceCamera extends SensorDevice` (`surveillanceCamera.script:33`), `GlitchedTurret extends Device` (`glitchedTurret.script:1`) — a cast to `ScriptedPuppet`/`NPCPuppet` already excludes all of these, no explicit check needed. (2) Puppet-typed mechanicals (drones, mechs, spiderbots, androids) are excluded by the `GetNPCType()==Human` check already in the humanoid predicate above; `IsMechanical()` is available as a single combined check = `NPCType in {Android,Drone,Mech}` OR `AIActionHelper.CheckAbility(this, Ability.IsMechanical)` (`scriptedPuppet.script:1456-1461`) if a belt-and-suspenders redundant check is wanted.
- **Civilian/crowd detection**: `IsCrowd() = GetRecord().IsCrowd() || (GetCrowdMemberComponent() ? GetCrowdMemberComponent().IsInCrowd() : false)` (`scriptedPuppet.script:1815-1818`); TweakDB-level `Character_Record.IsCrowd() -> Bool` (`sprint/vanilla-scripts/scripts/core/data/tweakDBRecords.script:3549`). `IsCivilian()`/`IsCharacterCivilian()` both return the same `m_isCivilian` field (`scriptedPuppet.script:1728-1731`, `:1775-1778`), populated the same way as police (`GetReactionPresetGroup(this)=="Civilian"`). Combined vanilla idiom worth reusing wholesale: `IsEnemy() = IsHostile() || (IsNeutral() && !IsCharacterCivilian() && !IsCrowd())` (`scriptedPuppet.script:2003-2006`) — necessary-not-sufficient (still needs Boss/MaxTac/police/mech layered on) but a good first-pass "is this a viable combat target at all" gate.
- **Quest/named/scripted-unique NPC — the one soft spot, see Open Questions**: `GameObject.IsQuest()` reads `m_markAsQuest` (`sprint/vanilla-scripts/scripts/core/entity/gameObject.script:2699-2702`) but `ScriptedPuppet` **overrides** it: `return super.IsQuest() || m_hasQuestItems;` (`scriptedPuppet.script:3773-3776`) — true for ANY puppet merely carrying a quest item right now, not "is a unique/scripted NPC." This is the exact same trap ScannerSuite's own author already hit and documented for devices (`ShardCaseContainerPS sets default m_markAsQuest = true, so EVERY shard case reports IsQuest()==true`, ScannerSuite.reds:148-153) — do not reuse `IsQuest()` naively for puppets either. Best available TweakDB-level signal instead: `Character_Record.Quest() -> weak<NPCQuestAffiliation_Record>` / `.QuestHandle()` (`tweakDBRecords.script:3472-3473`), `.Type() -> gamedataNPCQuestAffiliation` (`tweakDBRecords.script:6215-6220`), enum `{General,MainQuest,MinorActivity,MinorQuest,SideQuest,StreetStory,Count,Invalid}` (`tweakDBEnums.script:4171-4181`) — a curated per-record quest-affiliation field, read via `TweakDBInterface.GetCharacterRecord(recordID).Quest().Type() != gamedataNPCQuestAffiliation.General`. Coverage unverified (see Open Questions).

### 5. Attitude/hostility API (bonus — feeds duplication brief's "hostile like the source" wiring)
```
public const function GetAttitudeTowards( target : GameObject ) : EAIAttitude              // gameObject.script:632-648 (+ static overload :613-630)
public const function IsHostile() : Bool / IsNeutral() : Bool                               // gameObject.script:679-687
public static function IsFriendlyTowardsPlayer( obj : weak<GameObject> ) : Bool             // gameObject.script:655-670
public static function ChangeAttitudeToHostile( owner, target : weak<GameObject> )          // gameObject.script:689-707 (ChangeAttitudeToNeutral sibling :709-727)
```
`ChangeAttitudeToHostile` is a ready-made, vanilla-verified way to force a freshly-spawned clone's `AttitudeAgent` hostile toward a target if it doesn't inherit the right attitude from its record/faction automatically.

### 6. RNG
```
import function RandRange( min : Int32, max : Int32 ) : Int32;                              // sprint/vanilla-scripts/scripts/core/math/rand.script:1
import function RandDifferent( lastValue : Int32, range : Int32 ) : Int32;                  // rand.script:2
import function RandF() : Float;                                                            // rand.script:3
import function RandRangeF( min : Float, max : Float ) : Float;                             // rand.script:4
import function RandNoiseF( seed : Int32, max : Float, optional min : Float ) : Float;       // rand.script:5
import function RandPerlinNoiseF( seed : Int32, offset : Float ) : Float;                   // rand.script:6
```
Global `import function`s, no receiver object — call directly (`RandF()`, `RandRange(0, n)`). Live vanilla probability-roll idiom, exactly our 30%/20% shape: `if( RandF() < 0.89999998 )` (`sprint/vanilla-scripts/scripts/cyberpunk/NPC/NPCPuppet.script:893`) → our rolls are `RandF() < 0.30` / `RandF() < 0.20`. Index-roll idiom: `RandRange( 0, list.Size() + 1 )` (`NPCPuppet.script:3160,3168`). Weighted-roll idiom: `RandRangeF( 0.0, totalWeight )` (`sprint/vanilla-scripts/scripts/cyberpunk/managers/bountyManager.script:64,150`). No seed/determinism control exposed to REDscript (no `Seed`/`SetSeed` import anywhere in `rand.script`) — this is the same global engine RNG stream vanilla loot/AI rolls use; each call advances shared state, not deterministic/replayable from script. Not a blocker (single-player, no replay requirement in any brief).

### 7. HUD one-liner debug notify + FTLog
**Recommended (in-game-proven): `ActivityLogSystem.AddLog`.**
```
public import static function GetActivityLogSystem( self : GameInstance ) : ActivityLogSystem;   // sprint/vanilla-scripts/scripts/core/systems/gameInstance.script:10
public import function AddLog( logEntry : String );                                               // sprint/vanilla-scripts/scripts/core/systems/activityLogSystem.script:7
public import function AddLogFromParts( textpart1 : String, optional ...4 more );                  // activityLogSystem.script:8
```
This is the **exact call ScannerSuite uses** for every one of its DebugProbe lines, battle-tested across the mod's whole iteration history (7 call sites, e.g. `GameInstance.GetActivityLogSystem(game).AddLog("ST sweep: parts=" + ToString(ArraySize(parts)) + ...)` — ScannerSuite.reds:1492-1499; also 655-656, 1598, 1751, 1935, 2009-2010, 2419). Produces a HUD activity-log line (the scrolling on-screen notification feed) — genuinely a "one-liner," matching the ask exactly.
**FTLog — verified signature, log-sink uncertain.**
```
import function FTLog( const value : ref< String > );          // sprint/vanilla-scripts/scripts/tests/testStepLogicImport.script:29
import function FTLogWarning( const value : ref< String > );   // :30
import function FTLogError( const value : ref< String > );     // :31
```
Declared in a `scripts/tests/` file (name = "Functional Test Log"), which initially reads test-harness-only — **but it is NOT test-gated**: confirmed called unconditionally in live gameplay UI code, `FTLog( "OnSetZoomLevelEvent:" + IntToString(eventData.m_value) )` inside `WorldMapMenuGameController.OnSetZoomLevelEvent`, no test-mode check anywhere near it (`sprint/vanilla-scripts/scripts/cyberpunk/UI/fullscreen/map/worldMap.script:585-589`). Signature confirmed real and callable outside tests. What's NOT provable from static source: which sink it writes to (log file vs. console vs. anything player-visible) — treat as context-environment.md's debug convention literally intends: a **log-file companion** alongside the HUD `AddLog` line, not a second on-screen surface. `context-environment.md`'s own debug-conventions line ("Debug notify = HUD one-liner + `FTLog(...)`") matches this exactly — pair the two, don't pick one.
**Secondary/heavier alternative — `SimpleScreenMessage` (not recommended as primary):**
```
importonly final struct SimpleScreenMessage { import var isShown : Bool; duration : Float; message : String; isInstant : Bool; type : SimpleMessageType; }   // sprint/vanilla-scripts/scripts/core/ui/uiStructs.script:61-68
```
Dispatch precedent: build the struct, then `GameInstance.GetBlackboardSystem(gi).Get(GetAllBlackboardDefs().UI_Notifications).SetVariant(GetAllBlackboardDefs().UI_Notifications.WarningMessage, msg, true)` (`sprint/vanilla-scripts/scripts/core/systems/craftingSystem.script:57-61`). This is vanilla's full-screen warning-toast mechanism (bigger/more intrusive than a log line) — more moving parts (`GetAllBlackboardDefs()` reachability from an arbitrary module untraced), lower recommendation than `AddLog` for a routine per-uprank/per-clone debug ping.

## API inventory
| API / member | Signature | Evidence (file:line) | Verified? |
|---|---|---|---|
| `DelayCallback` (base class) | `class DelayCallback extends IScriptable { function Call(); }` | delaySystem.script:41-44 | Yes |
| `DelaySystem.DelayCallback` | `(cb: DelayCallback, delay: Float, optional dilation: Bool) -> DelayID` | delaySystem.script:59 | Yes |
| `DelaySystem.DelayCallbackNextFrame` | `(cb: DelayCallback) -> Void` | delaySystem.script:63 | Yes |
| `DelaySystem.CancelCallback` | `(id: DelayID) -> Void` | delaySystem.script:67 | Yes |
| `GameInstance.GetDelaySystem` | `(self: GameInstance) -> DelaySystem` | gameInstance.script:21 | Yes |
| ScannerSuite sweep-loop pattern | `STSweepTickCallback` + `ST_ArmSweep`/`ST_SweepTick` | ScannerSuite.reds:1303-1411 | In-game-proven |
| ScannerSuite loot-loop pattern | `APSLootLoopCallback` + `APS_StartLootLoop`/`APS_LootLoopTick` | ScannerSuite.reds:1788-1882 | In-game-proven |
| `PlayerPuppet.OnGameAttached` (safe arm point) | `protected event OnGameAttached()` | player.script:1161 | Yes |
| `GameObject.OnGameAttached` (UNSAFE, per-entity) | `protected event OnGameAttached()` | gameObject.script:490 | Yes (do not hook) |
| `GameObject.GetEntitiesAroundObject` | `(optional range: Float, optional filter: TargetSearchFilter) -> array<Entity>` | gameObject.script:936-965 | Yes |
| `GameObject.GetNPCsAroundObject` | `(optional range: Float) -> array<NPCPuppet>` | gameObject.script:967-987 | Yes |
| Usage precedent (a) | `player.GetEntitiesAroundObject(20.0, filter)` | settingsMain.script:755 | Yes |
| `GameInstance.GetEntityList` | `(self: GameInstance) -> array<Entity>` | gameInstance.script:106 | Yes |
| Usage precedent (b), vanilla | `PlayerDevelopmentSystem.ScaleNPCsToPlayerLevel` | playerDevelopmentSystem.script:3041-3074 | Yes |
| Usage precedent (b), mod | F2 auto-loot / entity-list tag pass | ScannerSuite.reds:1536, 1900 | In-game-proven |
| `TargetingSystem.GetTargetParts` | `(instigator, query: TargetSearchQuery, out parts: array<TS_TargetPartInfo>) -> Bool` | targetingSystem.script:84 | Yes |
| `TS_TargetPartInfo.GetComponent` | `(self) -> weak<TargetingComponent>` | targetingSystem.script:9 | Yes |
| `TargetSearchQuery` struct | fields: testedSet/searchFilter/includeSecondaryTargets/ignoreInstigator/maxDistance/filterObjectByDistance/queryTarget | targetingSearchFilter.script:53-64 | Yes |
| `TargetingSet` enum | `{Visible, ClearlyVisible, Frustum, Complete, None}` | targetingSearchFilter.script:40-47 | Yes |
| `TSF_All/Not/And/Or/Any` | `(mask: TSFMV[, ...]) -> TargetSearchFilter` | targetingSearchFilter.script:66-70 | Yes |
| `TSFMV` enum | Obj_Player/Puppet/Sensor/Device/Other, Att_Friendly/Hostile/Neutral, St_Alive/Dead/... | targetingSearchFilter.script:13-35 | Yes |
| `TSF_NPC()` / `TSF_EnemyNPC()` | `() -> TargetSearchFilter` | targetingSearchFilter.script:72-84 | Yes — declared AND live in vanilla melee/damage/projectile targeting (defaultTransition.script:298,355; meleeTransitions.script:1271,3423; weaponTransitions.script:1627; damageSystem.script:3337,3340; monoDisc.script:61; projectileHelper.script:32,75) |
| `GameInstance.GetTargetingSystem` | `(self) -> TargetingSystem` | gameInstance.script:49 | Yes |
| `GameObject.IsReplacer` | `() -> Bool` (override on PlayerPuppet) | gameObject.script:1731 / player.script:582 | Yes |
| `HUDManager.IsBraindanceActive` | `() -> Bool` | hudManager.script:615 | Yes |
| `EntityID` struct | `IsDefined/IsDynamic/IsStatic/GetHash(->Uint32)/ToDebugString` + `==`,`!=`,`<` | entityID.script:1-19 | Yes |
| `Entity.GetEntityID` | `() -> EntityID` | entity.script:5 | Yes |
| Seen-set pattern | `array<EntityID>` + `ArrayContains/Push/Erase/Size`, FIFO cap 4096 | ScannerSuite.reds:687-727, 1617-1639 | In-game-proven |
| EntityID persistence notes | stable across re-stream; recycled after despawn | ScannerSuite.reds:826, 1629-1634 | In-game-proven (operational) |
| `ScriptedPuppet.GetNPCType` | `() -> gamedataNPCType` | scriptedPuppet.script:1419-1422 | Yes |
| `gamedataNPCType` enum | Android/Any/Cerberus/Chimera/Device/Drone/Human/Mech/Spiderbot/Count/Invalid | tweakDBEnums.script:3371-3384 | Yes |
| `IsHuman()` / `IsHumanoid()` | `() -> Bool` | scriptedPuppet.script:1434-1449 | Yes |
| `IsMechanical()` | `() -> Bool` (Android\|Drone\|Mech or Ability.IsMechanical) | scriptedPuppet.script:1456-1461 | Yes |
| `TargetIsHumanTrashToElite` | `Human && rarity!=Boss` (vanilla combo predicate) | NPCPuppet.script:3065-3068 | Yes |
| `Puppet.GetNPCRarity` | `() -> gamedataNPCRarity` (native, base class) | puppet.script:95 | Yes |
| `gamedataNPCRarity` enum | Boss/Elite/MaxTac/Normal/Officer/Rare/Trash/Weak/Count/Invalid | tweakDBEnums.script:3396-3408 | Yes |
| `IsBoss()` (+static) | `()/  (obj: weak<GameObject>) -> Bool` | scriptedPuppet.script:1640-1652 | Yes |
| `IsMaxTac()` (+static) | `()/  (obj: weak<GameObject>) -> Bool` | scriptedPuppet.script:1654-1666 | Yes |
| `gamedataAffiliation` enum (no MaxTac member) | 30+ factions incl. NCPD | NPCPuppet.script:2843-2883 | Yes (confirms rarity, not affiliation) |
| `NPCManager.HasTag` | `(recordID: TweakDBID, tag: CName) -> Bool` | npcManager.script:142-151 | Yes |
| `'MaxTac_Prevention'` tag usage | `NPCManager.HasTag(npc.GetRecordID(), 'MaxTac_Prevention')` | playerDevelopmentSystem.script:3063 | Yes |
| `IsCharacterPolice()` (+static) | `()/  (obj: GameObject) -> Bool` | scriptedPuppet.script:1780-1794 | Yes |
| `IsPrevention()` | `() -> Bool` = `IsCharacterPolice()` | scriptedPuppet.script:1976-1979 | Yes |
| `IsCivilian()` / `IsCharacterCivilian()` | `() -> Bool`, both = `m_isCivilian` | scriptedPuppet.script:1728-1731, 1775-1778 | Yes |
| `IsCrowd()` | `() -> Bool` | scriptedPuppet.script:1815-1818 | Yes |
| `Character_Record.IsCrowd` | `() -> Bool` (TweakDB) | tweakDBRecords.script:3549 | Yes |
| `IsEnemy()` combo | `IsHostile() \|\| (IsNeutral() && !IsCharacterCivilian() && !IsCrowd())` | scriptedPuppet.script:2003-2006 | Yes |
| `GameObject.IsSensor/IsTurret/IsDevice` | `() -> Bool`, default false, true on Device tree | gameObject.script:1766-1779 | Yes |
| Device-tree class hierarchy | `SensorDevice extends ExplosiveDevice`; `SurveillanceCamera extends SensorDevice`; `GlitchedTurret extends Device` | sensorDevice.script:155; surveillanceCamera.script:33; glitchedTurret.script:1 | Yes |
| `GameObject.IsQuest()` | `() -> Bool` = `m_markAsQuest` | gameObject.script:2699-2702 | Yes |
| `ScriptedPuppet.IsQuest()` override | `super.IsQuest() \|\| m_hasQuestItems` (FOOTGUN — item-carry, not uniqueness) | scriptedPuppet.script:3773-3776 | Yes (unreliable for our purpose) |
| `Character_Record.Quest()`/`.QuestHandle()` | `() -> weak<NPCQuestAffiliation_Record>` | tweakDBRecords.script:3472-3473 | Yes |
| `NPCQuestAffiliation_Record.Type()` | `() -> gamedataNPCQuestAffiliation` | tweakDBRecords.script:6215-6220 | Yes |
| `gamedataNPCQuestAffiliation` enum | General/MainQuest/MinorActivity/MinorQuest/SideQuest/StreetStory/Count/Invalid | tweakDBEnums.script:4171-4181 | Yes |
| 'Unique'/'Named' tag or flag | — | (searched, not found) | Dead end |
| `GameObject.GetAttitudeTowards` (+static) | `(target: GameObject) -> EAIAttitude` | gameObject.script:613-648 | Yes |
| `IsHostile()` / `IsNeutral()` | `() -> Bool` | gameObject.script:679-687 | Yes |
| `IsFriendlyTowardsPlayer` | `(obj: weak<GameObject>) -> Bool` static | gameObject.script:655-670 | Yes |
| `ChangeAttitudeToHostile`/`ToNeutral` | `(owner, target: weak<GameObject>) -> Void` static | gameObject.script:689-727 | Yes |
| `RandRange` | `(min: Int32, max: Int32) -> Int32` | rand.script:1 | Yes |
| `RandDifferent` | `(lastValue: Int32, range: Int32) -> Int32` | rand.script:2 | Yes |
| `RandF` | `() -> Float` | rand.script:3 | Yes |
| `RandRangeF` | `(min: Float, max: Float) -> Float` | rand.script:4 | Yes |
| `RandNoiseF` / `RandPerlinNoiseF` | `(seed, max[, min]) -> Float` / `(seed, offset) -> Float` | rand.script:5-6 | Yes |
| `RandF() < p` probability idiom | live vanilla call | NPCPuppet.script:893 | Yes |
| `RandRange(0, n)` index idiom | live vanilla call | NPCPuppet.script:3160,3168 | Yes |
| `RandRangeF(0.0, totalWeight)` weighted idiom | live vanilla call | bountyManager.script:64,150 | Yes |
| `GameInstance.GetActivityLogSystem` | `(self) -> ActivityLogSystem` | gameInstance.script:10 | Yes |
| `ActivityLogSystem.AddLog` | `(logEntry: String) -> Void` | activityLogSystem.script:7 | Yes — 7 in-game-proven call sites in ScannerSuite.reds (e.g. 1492-1499) |
| `ActivityLogSystem.AddLogFromParts` | `(text1, optional text2..5: String) -> Void` | activityLogSystem.script:8 | Yes |
| `FTLog` / `FTLogWarning` / `FTLogError` | `(const value: ref<String>) -> Void` | testStepLogicImport.script:29-31 | Yes (declared); confirmed non-test call site: worldMap.script:587 |
| `SimpleScreenMessage` struct | isShown/duration/message/isInstant/type | uiStructs.script:61-68 | Yes |
| `UI_Notifications` blackboard dispatch | `GetBlackboardSystem(gi).Get(...).SetVariant(...)` | craftingSystem.script:57-61 | Yes (heavier, secondary option) |

## Precedents & inspiration
- **ScannerSuite.reds** (`mods/enabled/r6-scripts/custom-scanner-suite/ScannerSuite.reds`) is the load-bearing precedent for this whole round: proves the DelayCallback self-re-arming shape works crash-free in production across months of iteration (see its own changelog header), proves the EntityID-array seen-set + FIFO-cap shape, and is the literal source of the `ActivityLogSystem.AddLog` HUD debug-notify call. Common.reds should structurally mirror its sweep-loop skeleton (own naming/module, clean-room, per project convention) but can call the exact same vanilla APIs.
- **`PlayerDevelopmentSystem.ScaleNPCsToPlayerLevel`** (`playerDevelopmentSystem.script:3041-3074`) is an independent, vanilla-authored (not a mod) precedent for walking `GameInstance.GetEntityList`, casting to `NPCPuppet`, and reading a MaxTac signal (`NPCManager.HasTag(..., 'MaxTac_Prevention')`) plus `ContentAssignmentHandle()` — i.e. vanilla itself does an "iterate all NPCs, treat MaxTac specially" sweep, which is reassuring precedent that our brief's shape (sweep, classify, treat MaxTac as untouchable) is an idiom the engine's own systems already use.
- **`sprint/reference-aggro/`** — checked for overlap (grepped for RandRange/RandF/IsBoss/IsCrowd/IsHuman/GetEntitiesAroundObject/GetEntityList/AddLog/DelayCallback across all its files): zero hits. It's two `@replaceMethod(ReactionManagerComponent)` methods plus TweakXL `.tweak` files — no shared-infra surface. Not useful precedent for this round; a later feature-specific round (aggro-range) should mine it for `ShouldIgnoreCombatStim`/`ShouldHelpTargetFromSameAttitudeGroup`/stim-broadcast specifics, out of scope here.
- **Vanilla combat-targeting call sites** (melee transitions, damage system, projectile homing — listed in Finding 2) are precedent that composite `TSFMV` masks (`TSF_EnemyNPC()` etc.) are safe and load-bearing in real-time combat-critical code, which should give the planner confidence to use them despite ScannerSuite's own more conservative choice.

## Dead ends
- **`GameObject.IsQuest()` / `ScriptedPuppet.IsQuest()` as a "unique/named NPC" detector** — does NOT work. It's overridden on `ScriptedPuppet` to also fire for any puppet merely carrying a quest item (`m_hasQuestItems`), the exact same false-positive trap ScannerSuite's own author already documented and rejected for `ShardCaseContainerPS` (device side). Do not reuse naively for puppets.
- **`gamedataAffiliation`-based MaxTac detection** — the enum (30+ factions) has no `MaxTac` member at all. MaxTac is exclusively a `gamedataNPCRarity` value (+ a narrower `'MaxTac_Prevention'` NPCManager tag). Affiliation checks are the wrong tool here.
- **A dedicated 'Unique'/'Named' tag or record flag** — searched exhaustively: every literal tag string passed to `NPCManager.HasTag`/`HasVisualTag` repo-wide (no 'Unique'/'Named'/'Quest' hits beyond what's documented above), and `UINameplate_Record`/`gamedataUINameplateDisplayType` (`{AfterScan,Always,Default,Never,...}` — this is nameplate display **timing**, not a uniqueness marker). No such flag exists in the decompiled 2.3 source. See Open Questions for the fallback plan.
- **`reference-aggro`** — confirmed no shared-infra overlap (see Precedents); do not spend further time mining it for this round's questions.

## Open questions
1. **No clean "quest/named/scripted-unique NPC" predicate exists.** Best available: `TweakDBInterface.GetCharacterRecord(recordID).Quest().Type() != gamedataNPCQuestAffiliation.General`. Its false-negative rate (a hand-placed unique NPC whose `Quest` field was left at `General`) is unverified — can't be proven from static source, only from in-game testing. Planner must pick a risk posture: (a) use the TweakDB Quest-affiliation check as best-effort and document the residual gap (matches this codebase's existing tolerance for "known, accepted" caveats elsewhere, e.g. the stuck-quest-flag note in ScannerSuite.reds); (b) layer a soft heuristic (uniques are essentially never `Trash`/`Weak` rarity, essentially never `IsCrowd()`); or (c) rely solely on the already-hard Boss/MaxTac/police/mech exclusions and accept that a Rare/Officer-tier quest-adjacent mook may occasionally get upranked/duplicated — all three briefs already scope "everywhere incl. quest encounters," so this may be within the accepted tolerance. This blocks nothing structurally, but the planner should state the chosen posture explicitly in the plan.
2. **Streaming-order timing between `GameInstance.GetEntityList` and `TargetingComponent`-based queries** (does a just-streamed-in NPC appear in both at the same tick, or could `GetEntitiesAroundObject` lag `GetEntityList` by a frame or more while the TargetingComponent attaches?) is not provable from static decompiled source. Low practical risk given 0.5-1s sweep cadence and once-per-session seen-set semantics (a miss this tick is simply caught next tick, never permanently lost) — flagging only so the planner knows `GameInstance.GetEntityList` remains available as a same-cadence backstop channel if live testing ever shows `GetEntitiesAroundObject` missing freshly-spawned NPCs, exactly the two-channel redundancy shape ScannerSuite already uses for loot (frustum + entity-list).
3. **`SimpleScreenMessage`/`UI_Notifications` blackboard path** (`GetAllBlackboardDefs()` reachability from an arbitrary module, `SimpleMessageType` enum values) is not fully traced. Not blocking — `ActivityLogSystem.AddLog` is already sufficient and in-game-proven — only relevant if planner later wants a more intrusive on-screen popup than a log line.
