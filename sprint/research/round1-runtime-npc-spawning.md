# R1 — pure-REDscript runtime NPC spawn paths (F2 feasibility)

## Verdict

**BLOCKED for a clean, brief-compliant implementation.** `DynamicEntitySystem`/`DynamicEntitySpec` is CONFIRMED Codeware-only (RED4ext C++ plugin — NOT AVAILABLE here), exactly as suspected. Two genuinely-native, script-callable spawn primitives do exist in vanilla 2.3 (`PreventionSpawnSystem.RequestUnitSpawn`, `CompanionSystem.SpawnSubcharacter[OnPosition]`), but both are dead ends for "spawn an arbitrary hostile NPC record near an arbitrary source, get a handle to it, tag/suppress/despawn it cleanly": `CompanionSystem` is hard-gated to a single TweakDB record type (`SubCharacter_Record`) that has exactly **one** real instance in the whole game (`Character.spiderbot_new`, Judy's Flathead), capped at 1 concurrent spawn; `PreventionSpawnSystem.RequestUnitSpawn` accepts a generic `TweakDBID`+`WorldTransform` but its async result is hardwired to a *private* `PreventionSystem` callback with no way for a third-party script to retrieve the spawned entity, and any entity it does produce is tracked by the native police/wanted subsystem and subject to unrelated `RequestDespawnAll` sweeps. No generic "spawn any character record at any position and get the object back" primitive exists in pure REDscript. Community precedent agrees: every NexusMods "spawn an enemy on demand" mod found requires Cyber Engine Tweaks, none is pure-.reds. A low-confidence, not-recommended workaround is documented below for completeness — the decisive fact for the planner is that the clean path does not exist and F2 needs to be redesigned or heavily scoped down around this constraint.

## Findings

1. **`GetDynamicEntitySystem`/`DynamicEntitySpec`: zero hits anywhere in vanilla scripts.** `grep -rn "GetDynamicEntitySystem\|DynamicEntitySpec" sprint/vanilla-scripts/` → no output at all. `sprint/vanilla-scripts/scripts/core/systems/gameInstance.script` declares every other system accessor (`GetCompanionSystem`, `GetPreventionSpawnSystem`, `GetDynamicSpawnSystem`, `GetEntitySpawnerEventsBroadcaster`, etc. — lines 17, 23, 34, 35) but never `GetDynamicEntitySystem`. Director pre-check CONFIRMED.

2. **Codeware is a RED4ext C++ plugin, not a base-game surface.** Web search on psiberx/cp2077-codeware: "Codeware is a C++ plugin built on top of the RED4ext framework"; installation requirements list "RED4ext 1.29.0+". `GameInstance.GetDynamicEntitySystem()` and `DynamicEntitySpec` are Codeware's own additions (confirmed via wiki.redmodding.org "Entity manipulation" page and Codeware's own `Entity.reds`/wiki, e.g. `CreateEntity(spec)`, `GetEntity(event.GetEntityID())`, `templatePath`/`position`/`orientation`/`tags` fields). Since RED4ext registers this class into the engine's RTTI at runtime and RED4ext is explicitly NOT AVAILABLE on macOS/Steam per `context-environment.md`, this system cannot be reached even by hand-declaring our own `import` bindings — the native vtable entry simply does not exist without the plugin loaded. **This confirms the mission's core suspicion outright.**

3. **`DynamicSpawnSystem` (distinct native class, NOT Codeware) exists but is query-only from script.** `sprint/vanilla-scripts/scripts/core/systems/dynamicSpawnSystem.script:12-16`:
   ```
   import class DynamicSpawnSystem extends IDynamicSpawnSystem
   {
       public import function GetNumberOfSpawnedUnits() : Int32;
       public import function IsEntityRegistered( id : EntityID ) : Bool;
       public import function IsInUnmountingRange( position : Vector3 ) : Bool;
   ```
   Only 3 methods are `public import` (script-callable). `SpawnRequestFinished`/`SpawnCallback` (lines 18, 42) are plain `protected function` — i.e. native code calls INTO these as event handlers; there is no exposed way to trigger a spawn FROM script. `GameInstance.GetDynamicSpawnSystem` accessor is real (`gameInstance.script:35`), but the system behind it offers nothing actionable for our use case.

4. **`PreventionSpawnSystem.RequestUnitSpawn` is the closest real match to the brief's imagined API — genuinely public, native, callable.** `sprint/vanilla-scripts/scripts/core/systems/preventionSpawnSystem.script:40`:
   ```
   public import function RequestUnitSpawn( recordID : TweakDBID, spawnTransform : WorldTransform ) : Uint32;
   ```
   Reached via `GameInstance.GetPreventionSpawnSystem(gameInstance)` (`gameInstance.script:34`, `public import static function`). Real usage in `preventionSystem.script:1813-1818` (private wrapper) and `preventionSystem.script:2819-2849` (`SpawnUnits`, builds a `WorldTransform` from a `Vector3` position + a look-at-player orientation, then calls `RequestUnitSpawn` per unit).

5. **But the spawn result is unreachable by a third-party caller — this is the fatal blocker.** `preventionSpawnSystem.script:81-92`:
   ```
   protected function SpawnRequestFinished( requestResult : SpawnRequestResult )
   {
       var system : PreventionSystem;
       ...
       system = ( ( PreventionSystem )( GameInstance.GetScriptableSystemsContainer( GetGameInstance() ).Get( 'PreventionSystem' ) ) );
       if( system ) { ... system.QueueRequest( request ); }
   }
   ```
   This callback is hardwired to the literal system name `'PreventionSystem'` — there is no `scriptable`/`functionName` callback parameter on `RequestUnitSpawn` itself (contrast `RequestAVSpawnPoints(scriptable, functionName, ...)` at line 58 and `FindPursuitPointsRangeAsync(..., scriptable, functionName)` at line 67, which DO take one). Then `preventionSystem.script:1875-1890`:
   ```
   private function OnPreventionUnitSpawnedRequest( request : PreventionUnitSpawnedRequest )
   {
       var ticketData : TicketData;
       if( !( m_agentRegistry.PopRequestTicket( request.requestResult.requestID, ticketData ) ) )
       {
           return;
       }
       ...
   }
   ```
   If the ticket wasn't created via `PreventionSystem`'s own *private* `RequestUnitSpawn` wrapper (`preventionSystem.script:1813-1818`, which calls `m_agentRegistry.CreateTicket(...)` right after — a private script-side registry a mod cannot reach), the lookup fails and the handler just returns. **A mod calling the native `RequestUnitSpawn` directly fires a spawn blind: no callback, no `spawnedObjects` array, no way to obtain the new entity's reference.** That kills tagging (depth-1 marker), attitude verification, debug-notify-with-record, and reward suppression — all of which need a live object handle.

6. **Entities spawned via `PreventionSpawnSystem` are tracked natively, independent of script tickets — lifecycle risk even if a handle were obtained.** `RequestDespawnAll(shouldUseAggressiveDespawn: Bool)` (`preventionSpawnSystem.script:64`) takes **no entity list** — its single call site (`preventionSystem.script:3215`) passes only a bool. Since there's nothing to enumerate, the native system must keep its own record of everything it spawned, separate from `PreventionSystem`'s script-side `m_agentRegistry`. That means an NPC spawned through this path is liable to be swept by native despawn-all logic tied to wanted/heat state changes that have nothing to do with our encounter — directly threatening the brief's "no floating/wall-stuck clones... fights immediately" and lifecycle-cleanliness expectations, in the opposite direction (unexpected disappearance, not leaking).

7. **`CompanionSystem.SpawnSubcharacter`/`SpawnSubcharacterOnPosition` are real, callable, and DO give a handle back — but are locked to one record.** `sprint/vanilla-scripts/scripts/core/systems/companionSystem.script` (full file, `importonly` — pure native binding, 12 lines):
   ```
   public import function SpawnSubcharacter( recordID : TweakDBID, offset : Float, offsetDir : Vector3 );
   public import function SpawnSubcharacterOnPosition( recordID : TweakDBID, pos : Vector3 );
   public import function DespawnSubcharacter( recordID : TweakDBID );
   public import function DespawnAll();
   public import function GetSpawnedEntities( out entities : array< weak< Entity > >, optional recordID : TweakDBID );
   ```
   `GetSpawnedEntities` is a genuine post-spawn handle-retrieval API (contrast finding 5) — this is a materially better shape of API. Real usage in `sprint/vanilla-scripts/scripts/cyberpunk/systems/subCharacterSystem.script:248-282`, which guards every spawn with `TweakDBInterface.GetSubCharacterRecord(request.subCharacterID)` and bails (`return`) if it's `NULL` (lines 254-258, 276-279). The only concrete `SubCharacter_Record` referenced anywhere in vanilla scripts is `T"Character.spiderbot_new"` (lines 28, 196, 267, 314).

8. **`gamedataSubCharacter` enum proves this is a single-purpose system, not a general spawner.** `sprint/vanilla-scripts/scripts/core/data/tweakDBEnums.script:3786-3791`:
   ```
   import enum gamedataSubCharacter
   {
       Flathead,
       Count,
       Invalid,
   }
   ```
   Exactly one real value. `SubCharacter_Record extends Character_Record` (`tweakDBRecords.script:8918-8930`) is a distinct TweakDB record *type* from the generic `Character_Record` used for NPC archetypes — since **TweakDB is read-only at runtime from REDscript** (per `context-environment.md`), no new `SubCharacter_Record` can ever be registered to wrap an arbitrary enemy archetype. Dead end for identity flexibility.

9. **`CompanionSystem` further caps at one live instance per `subCharType`.** `subCharacterSystem.script:36`: `if( !( SubCharacterExists( subCharType ) ) || m_isDespawningFlathead )` and `:260`: `if( SubCharacterExists( subCharType ) ) { return; }` — a second spawn request for the same type is a silent no-op unless the first is despawned first. Even setting aside finding 8, this could not support a 20%-per-source-roll feature firing repeatedly across a session.

10. **No other candidate system exposes a by-record spawn-request call.** Full-tree grep for `import.*function.*Spawn` across `sprint/vanilla-scripts/` turned up ~35 matches; every one not already covered above is off-topic for NPC spawning: UI widget/ink spawning (`widgetController.script`), VFX (`fxSystem.script`, `gameplayEffects.script`), projectile spawn (`projectileComponent.script`), player-only vehicle summon (`vehicleSystem.script:9-10`, explicitly "ActivePlayerVehicle"/"PlayerVehicle"), item drops (`lootManager.script:16-18`), and pure TweakDB config-record read accessors (`tweakDB.script`, `tweakDBRecords.script` — e.g. the `AIDirectorSchedule*Record` family at `tweakDB.script:93-98`, which describes the AI Director's population-spawning schedule data but has **no corresponding live `GetAIDirectorSystem`-style accessor anywhere in the tree** — script can read the config, never command a spawn).

11. **`CommunitySystem` and `EntitySpawnerEventsBroadcaster` control/observe, they don't create.** Full file, `sprint/vanilla-scripts/scripts/core/systems/communitySystem.script`:
    ```
    importonly final class CommunitySystem extends ICommunitySystem
    {
        public import function EnableDynamicCrowdNullArea(...) : Uint64;
        public import function DisableCrowdNullArea( areaId : Uint64 );
        public import function ChangeDensityModifier( modiefier : Float );
        public import function ResetDensityModifier();
    }
    importonly final class EntitySpawnerEventsBroadcaster extends IEntitySpawnerEventsBroadcaster
    {
        public import function RegisterSpawnerEventPSListener( spawnerOrCommunityId : EntityID, communityEntryName : CName, psListenerPersistentId : PersistentID, psListenerClassName : CName ) : Uint32;
        public import function UnregisterSpawnerEventPSListener( registerId : Uint32 );
    }
    ```
    `CommunitySystem` only tunes ambient-crowd density/exclusion zones. `EntitySpawnerEventsBroadcaster` only *listens* to spawn/despawn/death events on an EntityID that is already a community spawner — it cannot command a new spawn. Similarly, `questSystem.script:36-37` (`GetFixedEntityIdsFromSpawnerEntityID`, `GetGameObjectsFromSpawnerEntityID`) only resolve children of a spawner entity that is **already placed** in the level/quest data — useless for spawning near an arbitrary player-encountered enemy anywhere in the open world.

12. **Mission's "vehicleComponent.script has RequestSpawn hits" premise only partially holds.** No literal `RequestSpawn` string exists in `vehicleComponent.script`. What IS there (7 call sites) are read-only `GetPreventionSpawnSystem(...)` queries/registrations tied to **already-mounted** passengers: `RegisterEntityDeathCallback`/`UnregisterEntityDeathCallback` (lines 1729, 1786, 3635), `IsPreventionVehicleEnabled` (5033), `GetIntersectionInFrontOfPlayerPos`/`IsPlayerInDogTown` (6203, 6210). The actual occupant-spawning call (`RequestChaseVehicle(vehicleRecordID, passengersRecordIDs, strategy)`) lives in `preventionSpawnSystem.script:41`, not `vehicleComponent.script` — same family, same finding-5/6 blockers (async result routes only to `PreventionSpawnSystem`'s own handling; native-tracked despawn).

13. **"Netrunner proxies" and "workspot spawns" (mission Q2) yielded nothing on-topic.** Grepping `-i "proxy"` across the tree returns only UI `animationProxy`/widget-proxy noise, no NPC-spawn-adjacent hits. `workspotMapperComponent.script` and the wider "workspot" surface (per wiki.redmodding.org's own page title, "Play animations with workspots") is an **animation/interaction-slot mechanism for already-existing entities**, not an entity-creation mechanism. Closed per the no-rabbit-holes rule after one focused attempt each; flagged as an open question below only for completeness, not because it looked promising.

14. **A workaround is theoretically constructible but is NOT recommended.** Combine finding 4 (`RequestUnitSpawn`) with the proven local pattern in `mods/enabled/r6-scripts/custom-scanner-suite/ScannerSuite.reds` (`GameInstance.GetEntityList(game)` on a self-re-arming `DelaySystem` tick — `ScannerSuite.reds:1536`, `:1351`, `:1374` — the crash-safe, game-thread-only enumeration this codebase already trusts) and `GameObject.GetEntitiesAroundObject(optional range, optional searchFilter) : array<Entity>` (`sprint/vanilla-scripts/scripts/core/entity/gameObject.script:936`, a real script-level — not import — function) plus `GameInstance.FindEntityByID(gameInstance, entityID) : Entity` (native import, e.g. `aiComponent.script:376`, many other sites). Procedure: call `RequestUnitSpawn(recordID, spawnTransform)`, then on the next tick(s) enumerate nearby entities and heuristically match on `recordID` + proximity-to-`spawnTransform.position` + "not already in our seen-set" to guess which one is "ours." **Two unresolved problems make this unsound for a shipped feature, not just inelegant:** (a) false-positive risk — generic mook archetypes (the exact records F2 would duplicate) are frequently *already* present nearby in real encounters, so the heuristic could misidentify a genuine, pre-existing enemy as the clone and wrongly apply reward-suppression/depth-cap bookkeeping to it; (b) finding 6's native despawn-all entanglement still applies regardless of whether we can name the entity. Documented for completeness per the mission's "no rabbit holes... but be honest" instruction; not proposed as the path forward.

## API inventory

| API / member | Signature | Evidence (file:line) | Verified? |
|---|---|---|---|
| `GameInstance.GetDynamicEntitySystem` / `DynamicEntitySpec` | — | 0 hits in `sprint/vanilla-scripts/` (grep); Codeware wiki + GitHub README confirm RED4ext C++ plugin origin | **VERIFIED ABSENT** — Codeware/RED4ext-only, NOT AVAILABLE |
| `DynamicSpawnSystem.GetNumberOfSpawnedUnits/IsEntityRegistered/IsInUnmountingRange` | `()：Int32` / `(id:EntityID):Bool` / `(position:Vector3):Bool` | `dynamicSpawnSystem.script:14-16` | VERIFIED — query-only, no spawn-request import exists on this class |
| `GameInstance.GetDynamicSpawnSystem` | `static function(self:GameInstance):DynamicSpawnSystem` | `gameInstance.script:35` | VERIFIED accessor; system itself offers nothing actionable |
| `PreventionSpawnSystem.RequestUnitSpawn` | `(recordID:TweakDBID, spawnTransform:WorldTransform):Uint32` | `preventionSpawnSystem.script:40`; used `preventionSystem.script:1816`, `:2832` | VERIFIED callable; **no usable result path for a third-party caller** (finding 5) |
| `PreventionSpawnSystem.RequestDespawn` | `(entityID:EntityID)` | `preventionSpawnSystem.script:62` | VERIFIED |
| `PreventionSpawnSystem.RequestDespawnAll` | `(shouldUseAggressiveDespawn:Bool)` | `preventionSpawnSystem.script:64`; sole call site `preventionSystem.script:3215` | VERIFIED; native-tracked, independent of script tickets (finding 6) |
| `PreventionSpawnSystem.RequestChaseVehicle` | `(vehicleRecordID:TweakDBID, passengersRecordIDs:array<TweakDBID>, strategy:BaseStrategyRequest):Uint32` | `preventionSpawnSystem.script:41` | VERIFIED callable; same finding-5/6 blockers, vehicle-only |
| `PreventionSpawnSystem.RequestAVSpawnAtLocation` | `(recordID:TweakDBID, location:Vector3):Uint32` | `preventionSpawnSystem.script:59` | VERIFIED callable; same finding-5/6 blockers, AV/vehicle-only |
| `GameInstance.GetPreventionSpawnSystem` | `static function(self):PreventionSpawnSystem` | `gameInstance.script:34` | VERIFIED accessor |
| `PreventionSpawnSystem.SpawnRequestFinished` (native→script callback) | `protected function(requestResult:SpawnRequestResult)` | `preventionSpawnSystem.script:81-92` | VERIFIED — hardwired to literal system name `'PreventionSystem'`; no generic `scriptable`/`functionName` param unlike sibling APIs |
| `PreventionSystem.OnPreventionUnitSpawnedRequest` | `private function(request)` | `preventionSystem.script:1875-1890` | VERIFIED — silently `return`s if `m_agentRegistry.PopRequestTicket` fails (untracked ticket) |
| `CompanionSystem.SpawnSubcharacter` | `(recordID:TweakDBID, offset:Float, offsetDir:Vector3)` | `companionSystem.script:7` | VERIFIED callable; record-type-gated (findings 7-8) |
| `CompanionSystem.SpawnSubcharacterOnPosition` | `(recordID:TweakDBID, pos:Vector3)` | `companionSystem.script:8` | VERIFIED callable; record-type-gated |
| `CompanionSystem.DespawnSubcharacter` | `(recordID:TweakDBID)` | `companionSystem.script:9` | VERIFIED |
| `CompanionSystem.DespawnAll` | `()` | `companionSystem.script:10` | VERIFIED |
| `CompanionSystem.GetSpawnedEntities` | `(out entities:array<weak<Entity>>, optional recordID:TweakDBID)` | `companionSystem.script:11` | VERIFIED — genuine handle-retrieval (contrast `PreventionSpawnSystem`), but gated behind finding 8 |
| `GameInstance.GetCompanionSystem` | `static function(self):CompanionSystem` | `gameInstance.script:17` | VERIFIED accessor |
| `gamedataSubCharacter` (enum) | `Flathead, Count, Invalid` | `tweakDBEnums.script:3786-3791` | VERIFIED — exactly one real value in the entire game |
| `SubCharacter_Record` | `extends Character_Record`; `Type():gamedataSubCharacter` | `tweakDBRecords.script:8918-8930` | VERIFIED; `TweakDBInterface.GetSubCharacterRecord(id)` returns NULL for non-matching records (`subCharacterSystem.script:254-258`) |
| `CommunitySystem.EnableDynamicCrowdNullArea/DisableCrowdNullArea/ChangeDensityModifier/ResetDensityModifier` | various | `communitySystem.script` (full file) | VERIFIED — density/exclusion only, no by-record spawn |
| `EntitySpawnerEventsBroadcaster.RegisterSpawnerEventPSListener` | `(spawnerOrCommunityId:EntityID, communityEntryName:CName, psListenerPersistentId:PersistentID, psListenerClassName:CName):Uint32` | `communitySystem.script` | VERIFIED — listener registration on an EXISTING spawner, not a spawn request |
| `questSystem.GetGameObjectsFromSpawnerEntityID` / `GetFixedEntityIdsFromSpawnerEntityID` | `(entityID:EntityID, communityEntryNames:array<CName>, gameInstance, out ...)` | `questSystem.script:36-37` | VERIFIED — resolves children of a pre-authored spawner; can't create one at runtime |
| AI Director schedule/spawning-desc records | `GetAIDirectorSchedule*Record(path:TweakDBID)` family | `tweakDB.script:93-98` | VERIFIED — TweakDB config-read only; no live `GetAIDirectorSystem` accessor found anywhere |
| `GameObject.GetEntitiesAroundObject` | `(optional range:Float, optional searchFilter:TargetSearchFilter):array<Entity>` | `gameObject.script:936` | VERIFIED (script-level function, not import) |
| `GameInstance.GetEntityList` | `(gameInstance):array<ref<Entity>>` | Proven local pattern, `mods/enabled/.../ScannerSuite.reds:1536` (+ `:1351`,`:1374` for the `DelaySystem` tick that drives it) | VERIFIED via in-game-proven local mod |
| `GameInstance.FindEntityByID` | `static function(gameInstance, entityID):Entity` | e.g. `aiComponent.script:376`, `entityAttachementComponent.script:27`, many more | VERIFIED |

## Precedents & inspiration

- **psiberx/cp2077-codeware** (`GameInstance.GetDynamicEntitySystem()`, `DynamicEntitySpec{templatePath, position, orientation, tags}`, `CreateEntity(spec)`, `GetEntity(id)`) — proves what a *proper* general-purpose spawn API looks like (record/template + transform in, entity handle + lifecycle events out), and by being RED4ext-dependent, proves that shape of API is exactly what vanilla 2.3 is missing from pure script. Inspiration only — NOT AVAILABLE here.
- **NexusMods "Simple Enemy Spawner"** (mod 4674) — confirmed via fetched requirements table: `Cyber Engine Tweaks 1.19.5+`. Author's own words: "I've never played with the Cyber Engine Tweaks scripting language. This seemed like a good idea for a toy to play with the Cyberpunk's spawning mechanism." Direct evidence that even a hobbyist reaching for the simplest possible "spawn an enemy" mod needed CET, not REDscript.
- **NexusMods "Spawning enemy around you"** (mod 1423) — confirmed via fetched requirements table: `CyberEngineTweaks` (off-site requirement), install path literally `bin\x64\plugins\cyber_engine_tweaks\mods\npcspawn\init.lua`. Same conclusion.
- **NexusMods "Lightweight Crowd Duplicate Randomizer"** (mod 27433) — closest name match to "duplication," but a different mechanic entirely: it detects when the game's own ambient crowd system has spawned two NPCs with the same appearance and forces a **respawn-in-place** of the duplicate (not creation of a new hostile). Built on Redscript **with Codeware as a dependency** per search summary — even this narrower, softer task reached for Codeware rather than staying pure-.reds.
- **CDPR's own `subCharacterSystem.script`** — the single vanilla precedent of a script system successfully driving `CompanionSystem.SpawnSubcharacterOnPosition` end-to-end (spawn → equip → role-assign → UI flag → despawn), useful as a read/style reference for request-class plumbing (`ScriptableSystemRequest` subclasses, `QueueRequest` pattern) even though the underlying record constraint rules it out for F2.

## Dead ends

- **`DynamicEntitySystem`/`DynamicEntitySpec`** — Codeware/RED4ext-only; zero vanilla surface; confirmed via both grep and web (finding 1-2). Do not revisit without RED4ext, which is categorically unavailable on this platform.
- **`DynamicSpawnSystem`** — native and real, but 100% read-only from script (finding 3); no `RequestSpawn`-equivalent import exists on this class in vanilla 2.3.
- **`CompanionSystem.SpawnSubcharacter[OnPosition]`** — real, callable, even gives a handle back, but locked to `SubCharacter_Record` (one real record in the entire game, `Character.spiderbot_new`) and capped at one live instance per type; TweakDB read-only forecloses adding records (findings 7-9).
- **`CommunitySystem`** — crowd density/exclusion-zone controls only; no by-record spawn call (finding 11).
- **`EntitySpawnerEventsBroadcaster`** — event-listener registration on an existing spawner entity, not a spawn trigger (finding 11).
- **`questSystem` spawner-entity lookups** — resolve children of a pre-authored spawner node already placed in level data; cannot create a spawner at an arbitrary runtime position (finding 11).
- **AI Director schedule/spawning-desc TweakDB records** — config data only; no live system accessor (`GetAIDirectorSystem`-shaped) exists anywhere in the decompiled tree (finding 10).
- **"Netrunner proxies" / "workspot spawns"** — no on-topic vanilla evidence found after one focused grep pass each; workspots are confirmed (via wiki.redmodding.org page title) to be an animation mechanism for existing entities, not entity creation (finding 13).
- **`PreventionSpawnSystem.RequestUnitSpawn` as a clean primitive** — technically callable, but functionally unusable for F2 without accepting a heuristic, correctness-risky workaround: no result callback reaches third-party script code (finding 5), and entities it spawns are natively tracked and subject to `RequestDespawnAll` sweeps tied to unrelated wanted/heat state (finding 6). The `GetEntityList`-poll-and-guess workaround (finding 14) is documented but explicitly NOT recommended.

## Open questions

1. **Does native `RequestUnitSpawn` actually accept arbitrary (non-police-pool) `Character_Record` TweakDBIDs, or does it internally validate/reject them?** Unanswerable from decompiled REDscript (native C++ internals are invisible to us). Only resolvable by an in-game empirical test (compile a throwaway probe, launch, observe) — relevant only if the planner decides the finding-14 workaround is worth pursuing despite its documented risks.
2. **Does `RequestUnitSpawn` succeed when called outside an active police-chase/heat context** (i.e., with `PreventionSystem.m_systemEnabled`/`IsChasingPlayer()` false, which is the state the script-side call sites are always gated behind but which the native import itself may or may not require)? Same caveat as (1) — empirical-test-only, planner-relevant only if pursuing the not-recommended workaround.
3. **Not blocking this mission, flagging for the record:** same-faction random-archetype record *selection* (brief Q2 — record enumeration vs. curated pools) is an entirely separate research thread from spawning itself and was not investigated here; whoever picks that up should know the spawn-mechanism verdict above constrains what "selection" would even be for.
