# Plan — enemy-duplication (20% extra spawn)

Owned file: `sprint/impl/custom-enemy-overhaul/EnemyOverhaul.Duplication.reds` (module `EnemyOverhaul.Duplication`; imports `EnemyOverhaul.Common.*`).
Verdict: **FEASIBLE-EXPERIMENTAL — Posture B** (per `search_index.md` F2 guidance + `research/round1-runtime-npc-spawning.md`). All downstream wiring (identity, placement, hostility, reward suppression, depth cap) is 100% vanilla-verified and every hook shape is compile-proven (director probes P1/P2/P3). The single residual unknown is game-launch-empirical: whether native `RequestUnitSpawn` spawns arbitrary non-police records outside a heat context. That unknown is front-loaded into probe gate **M1**; the bail-out (Posture A) is one config flip.

## Mechanism

**Chosen path: Posture B — PreventionSpawnSystem spawn + private-wrap harvest.**

1. **Spawn call**: `GameInstance.GetPreventionSpawnSystem(gi).RequestUnitSpawn(recordID, spawnTransform) : Uint32` (`preventionSpawnSystem.script:40`) — the ONLY script-callable by-record spawn primitive on this platform (exhaustive sweep, spawning dossier F10; `DynamicEntitySystem` = Codeware/RED4ext = absent; `CompanionSystem` = single-record dead end; `DynamicSpawnSystem` = query-only). Store the returned `requestID` in a pending ledger.
2. **Handle recovery** (the piece the dossier called fatal, solved by the P2-proven private wrap): native queues a `PreventionUnitSpawnedRequest` for EVERY spawn result unconditionally (`preventionSpawnSystem.script:81-92` → `system.QueueRequest(request)`), and vanilla's private handler `PreventionSystem.OnPreventionUnitSpawnedRequest` no-ops on unknown tickets (`PopRequestTicket` fails → `return`, `preventionSystem.script:1875-1890`). `@wrapMethod(PreventionSystem)` on that private handler: always pass through to `wrappedMethod(request)`, and when `request.requestResult.requestID` matches our ledger, harvest `request.requestResult.spawnedObjects : array<weak<GameObject>>` + `success : Bool` (`preventionSpawnSystem.script:20-27`) — EXACT handles, zero heuristics. Our tickets are invisible to police bookkeeping; police tickets are untouched by us.
3. **Transform recipe** (verbatim vanilla, `preventionSystem.script:2819-2848` `SpawnUnits`): `WorldTransform.SetPosition(t, spawnPos)` (`worldTransform.script:5`) + `WorldTransform.SetOrientationFromDir(t, Vector4.Normalize2D(playerPos - spawnPos))` (`worldTransform.script:8`, `vector.script:54`) — clone spawns facing the player.
4. **Identity — plan's stated choice**: v1 DEFAULT = **verbatim clone** of the source (`source.GetRecordID()`, `puppet.script:13`) — `UseFactionPools = false`. The brief's PREFERRED same-faction pool IS implemented (curated 8-faction `array<TweakDBID>` table from `research/round1-spawn-wiring.md` Finding 9, third-party-sourced, 2 IDs cross-validated) but ships default-off, each pick null-checked via `TweakDBInterface.GetCharacterRecord(pick)` (`tweakDB.script:371`) with automatic fallback to the verbatim record. Rationale: the wiring dossier itself recommends verbatim for v1, and the M1 probe must not conflate pool-data staleness with spawn-primitive failure. Flip `UseFactionPools = true` = the documented fast-follow after M1 passes. Faction key: `TweakDBInterface.GetCharacterRecord(id).Affiliation().Type()` (`tweakDBRecords.script:3476,2570`); pool pick via `RandRange(0, size)` (`rand.script:1`; idiom `NPCPuppet.script:3160`); factions without a pool → verbatim.
5. **Placement — validated or silent skip** (brief rule): query center = source position with random XY jitter (`center.X += RandRangeF(-PlacementJitter, PlacementJitter)`, same for Y; struct-field mutation idiom = vanilla `origin.Z -=` in `navigationSystem.script:66-86`; `RandRangeF` `rand.script:4`). Primary: `GameInstance.GetNavigationSystem(gi).FindPointInSphereOnlyHumanNavmesh(center, PlacementRadius, NavGenAgentSize.Human, false)` (`navigationSystem.script:57`; enum `:17-20`, `Human` is its only member; `heightDetail=false` is the ONLY vanilla-precedented value — sole call site `:73`) → require `result.status == worldNavigationRequestStatus.OK` (`:9-15`, result struct `:33-36`). Fallback attempt: `GetNearestNavmeshPointBelowOnlyHumanNavmesh(center, 1.0, 5)` (`:66-86`; vanilla params `deviceBase.script:3244`) → fail = `Vector4.IsZero(point)`. Both fail → **skip silently** (debug-notify only); the roll stays spent, no re-roll.

**Fallback ladder (rung → trigger):**
- **Rung 0 (primary)**: full Posture B pipeline, verbatim identity, `DuplicationEnabled = true`.
- **Rung 1 — compile regression** on any of the five hook shapes (all probe-proven: P1 `AwardsExperience` const wrap, P2 `DropHeldItems`/private wraps, P3 `OnIncapacitated`): implementer re-runs `sprint/bin/scc-serial.sh`, reports the exact failing shape; for reward-suppression wraps degrade per the dossier ladder (`research/round1-reward-suppression.md` Ranked ladder — minimum bar `RemoveAllItems` + `EvaluateLootQualityByTask`, zero wraps). A failure of the `OnPreventionUnitSpawnedRequest` wrap itself has NO workaround (poll-and-guess is forbidden, see What NOT to do) → Rung 2.
- **Rung 2 — Posture A (descope)**: trigger = M1 probe shows request-sent notifies but zero harvest notifies (native rejects arbitrary records and/or no-heat context), or Rung 1's no-workaround case. Action: set `DuplicationEnabled` default `false` (feature fully dormant, pure passthrough), keep the code as the brief's "implemented-but-dormant" option, report the platform blocker to the user. No code deletion.
- **Rung 3 — lifecycle degradation accepted**: trigger = M1 passes but M10 shows heat-state changes despawn live clones (`RequestDespawnAll`, native-tracked, `preventionSpawnSystem.script:64` / `preventionSystem.script:3215`). Action: keep the feature (clones are transient by design), document the caveat in the mod header + report. No re-spawn compensation.

## Architecture

Everything below lives in `EnemyOverhaul.Duplication.reds`. Nobody edits Common or other feature files.

**State home = `PreventionSystem`** (`class PreventionSystem extends ScriptableSystem`, `preventionSystem.script:1`). Why: the harvest wrap is a member of `PreventionSystem` (rule 5 — member access to our own `@addField` state, zero cross-class shims), and the class is resolvable from anywhere via `GameInstance.GetScriptableSystemsContainer(gi).Get(n"PreventionSystem") as PreventionSystem` — vanilla's own idiom (`preventionSpawnSystem.script:81-92`). `GetGameInstance()` is available inside it (vanilla uses it, e.g. `preventionSystem.script:207`).

Classes:
- `EODuplicationConfig` — `public abstract class`, `final static func` per const (ScannerSuite config pattern, `ScannerSuiteConfig` at `ScannerSuite.reds:241`).
- `EODupPendingReq` — plain class: `requestId: Uint32`, `sourceId: EntityID`, `sourceRecord: TweakDBID`, `spawnRecord: TweakDBID`, `ageTicks: Int32`.
- `EODupWiringTask` — plain class: `clone: wref<GameObject>`, `cloneId: EntityID`, `sourceId: EntityID`.
- `EODupSweepCallback extends DelayCallback` — holds `system: wref<PreventionSystem>`; `Call()` → `EODup_SweepTick()` (shape: `STSweepTickCallback`, `ScannerSuite.reds:1370`; `DelayCallback` base `delaySystem.script:41-44`).
- `EODupWiringCallback extends DelayCallback` — `Call()` → `EODup_ProcessWiringQueue()`.
- `EODupCorpseStripCallback extends DelayCallback` — holds `puppet: wref<ScriptedPuppet>`; `Call()` → deferred corpse strip.

`@addField(PreventionSystem)` (all session-transient): `m_eodupArmed: Bool`, `m_eodupRollSeen: array<EntityID>`, `m_eodupPending: array<ref<EODupPendingReq>>`, `m_eodupWiringQueue: array<ref<EODupWiringTask>>`, `m_eodupWiringScheduled: Bool`.

Hooks (5, all `@wrapMethod`, rule 6):
1. `@wrapMethod(PlayerPuppet) protected cb func OnGameAttached()` (`player.script:1161`; chains with F1/ScannerSuite wraps — `ScannerSuite.reds:2018-2019` precedent, each wrap calls `wrappedMethod` exactly once) → if `DuplicationEnabled()`: resolve PreventionSystem via container, call `EODup_Arm()`.
2. `@wrapMethod(PreventionSystem) private func OnPreventionUnitSpawnedRequest(request: ref<PreventionUnitSpawnedRequest>)` (`preventionSystem.script:1875-1890`; request class `:5274-5277` field `requestResult: SpawnRequestResult`) — harvest; P2-proven private-wrap shape.
3. `@wrapMethod(ScriptedPuppet) public const func AwardsExperience() -> Bool` (`scriptedPuppet.script:1835-1838`; P1-proven const-wrap) → clone ⇒ `false`. Const context: only `this.GetGame()` (`gameObject.script:226`, `const final`) + `this.GetEntityID()` (`entity.script:5`, `const`) + Common's registry lookup — all const-safe.
4. `@wrapMethod(NPCPuppet) protected override func OnIncapacitated()` (`NPCPuppet.script:3935-3987`; P3-proven) → `wrappedMethod()` FIRST (vanilla `ProcessLoot()` + bookkeeping run), then clone ⇒ schedule `EODupCorpseStripCallback` via `DelayCallbackNextFrame` (`delaySystem.script:63`).
5. `@wrapMethod(ScriptedPuppet) private func DropHeldItems() -> Bool` (`scriptedPuppet.script:3092-3119`; this exact method was the P2 probe target) → clone ⇒ return `false` WITHOUT calling `wrappedMethod()` (no world-dropped weapon); else pass through.

`@addMethod(PreventionSystem)`: `EODup_Arm()`, `EODup_SweepTick()`, `EODup_ProcessCandidate(player, npc) -> Bool` (returns "spawn request sent"), `EODup_PickSpawnRecord(source) -> TweakDBID`, `EODup_FindSpawnPoint(sourcePos: Vector4, out point: Vector4) -> Bool`, `EODup_ProcessWiringQueue()`, `EODup_Notify(msg: String)`.

**Common APIs consumed** (proposed names below, aligned with plan-tier-uprank; final names per `plan-common.md` — if the consolidated names/shapes differ, adapt call sites; if a utility is missing entirely, implement the same shape locally in this file with `EODup_`-prefixed names, do not edit Common):
- `EO_IsEligibleCombatHuman(puppet: ref<NPCPuppet>) -> Bool` — shared eligibility predicate (composite, see Exclusions) — MUST NOT itself exclude marked clones (clones need their F1 roll).
- `EO_MarkClone(id: EntityID) -> Void` + `EO_IsClone(id: EntityID) -> Bool` — clone registry by `EntityID`, reachable given only `GameInstance` (or fully static script state), pure script state (synchronously callable inside wraps, const-context-safe — `EO_IsClone` is called from inside a wrapped `public const func`), FIFO cap 4096.
- `EO_SeenContains(seen: script_ref<array<EntityID>>, id: EntityID) -> Bool` + `EO_SeenTryAdd(seen: script_ref<array<EntityID>>, id: EntityID, cap: Int32) -> Bool` — FIFO seen-set helpers (contains / try-add with cap eviction).
- `EO_Notify(game: GameInstance, msg: String) -> Void` — AddLog + FTLog pair, caller-gated (caller checks its own `DebugNotify()`).
- Optional: RNG roll helper; NPC enumeration helper; `EO_SweepGateOK` replacer/braindance gate (trivial to inline locally if absent).

## Lifecycle

**Arm**: OnGameAttached wrap (game thread, once per load) → `EODup_Arm()`: if `m_eodupArmed` return (double-arm guard — replacer re-attach fires OnGameAttached again); schedule `EODupSweepCallback` at `FirstTickDelay`; set `m_eodupArmed = true`.

**Tick** (`EODup_SweepTick()`, cadence `SweepInterval`):
1. `!DuplicationEnabled()` → `m_eodupArmed = false`; return (permanent stop — only non-re-arming path; dead in practice, config static).
2. **Re-arm FIRST** (fault-proof ordering, "FAULT-PROOF RE-ARM" `ScannerSuite.reds:1435` precedent) — schedule successor tick before any work.
3. Resolve player (`GameInstance.GetPlayerSystem(gi).GetLocalPlayerMainGameObject()` — `gameInstance.script:32`, `playerSystem.script:13`, cast `PlayerPuppet`). `!IsDefined || player.IsReplacer()` (`gameObject.script:1731`/`player.script:582`) `|| hud.IsBraindanceActive()` (`hudManager.script:615` via `player.GetHudManager()`, ScannerSuite-proven) → skip-but-stay-alive.
4. Age pending ledger: `ageTicks += 1`; entries `> PendingTTLTicks` removed (notify drop). Backstop-drain `m_eodupWiringQueue` if nonempty (primary drain is next-frame).
5. **Detect-new**: `player.GetNPCsAroundObject(SweepRange())` (`gameObject.script:967-987`; `TargetingSet.Complete` 360°, `TSF_NPC` — includes not-yet-hostile gang NPCs; NEVER `TSF_EnemyNPC`, it pre-filters to currently-hostile).
6. Per candidate — if-wrapper chain, no `continue`, budget-gated (`budgetLeft` local starts at `MaxSpawnRequestsPerTick`; candidates are only PROCESSED while `budgetLeft > 0`, so an un-processed candidate spends nothing and is retried next tick):
   - **clone gate**: registry contains `GetEntityID()` → skip (depth cap = 1, permanent).
   - **seen gate**: `m_eodupRollSeen` contains id → skip.
   - **eligibility**: Common composite predicate fails → skip WITHOUT marking seen (an NPC can become eligible later, e.g. `IsActive`/hostility flips; roll happens once it qualifies).
   - **roll-once**: add id to `m_eodupRollSeen` (FIFO cap 4096 — **spend-on-roll**: placement/spawn failure never refunds), then `RandF() < DuplicateChance()` (`rand.script:3`; idiom `NPCPuppet.script:893`). Fail → done with this entity forever.
   - **apply**: `EODup_FindSpawnPoint` (Mechanism §5) fail → notify + silent skip. Else `EODup_PickSpawnRecord` (Mechanism §4) → build WorldTransform (Mechanism §3) → `RequestUnitSpawn(record, t)` → push `EODupPendingReq{requestId, sourceId, sourceRecord, spawnRecord, 0}` → notify request-sent → `budgetLeft -= 1`.
7. **Harvest** (wrap 2, on PreventionSystem request processing): call `wrappedMethod(request)` unconditionally FIRST (vanilla no-ops our tickets; police tickets require it). Then scan `m_eodupPending` for `request.requestResult.requestID`: on match — remove ledger entry; if `!requestResult.success` or `spawnedObjects` empty → notify failure, done. Else per spawned object: **mark clone in Common registry synchronously** (pure script-array state — this is NOT engine mutation; marking here closes the race where a sweep tick sees the clone before wiring) + push `EODupWiringTask`; notify `harvest #id n=<size>`; if `!m_eodupWiringScheduled` → `DelayCallbackNextFrame(EODupWiringCallback)` + set flag. **No engine-state mutation inside this wrap** (rule 3).
8. **Wire** (`EODup_ProcessWiringQueue()`, next frame, game thread): per task (clear queue + reset `m_eodupWiringScheduled` first): resolve clone (`wref` still defined, else `GameInstance.FindEntityByID(gi, cloneId)` — `aiComponent.script:376` precedent) → cast `ScriptedPuppet`; null → notify anomaly, skip. Then:
   - `clone.DisableKillReward(true)` (`gameObject.script:1682`; telemetry bonus, vanilla precedent `disposalDevice.script:302-313`).
   - Attitude: `source = FindEntityByID(gi, sourceId) as ScriptedPuppet`; if defined → `clone.GetAttitudeAgent().SetAttitudeGroup(source.GetAttitudeAgent().GetAttitudeGroup())` (`gameObject.script:586`, `attitudeAgent.script:21,23`; idiom `aiRole.script:315,327`). ALWAYS: `clone.GetAttitudeAgent().SetAttitudeTowards(playerAgent, EAIAttitude.AIA_Hostile)` (`attitudeAgent.script:25`; enum `:1-6`). Spawned NPCs do NOT inherit hostility — vanilla proof `dynamicSpawnSystem.script:42-56`.
   - Combat join: `AIInjectCombatThreatCommand` with `targetPuppetRef = CreateEntityReference("#player", emptyNames)` (`questSystem.script:38`; usage `dynamicSpawnSystem.script:36`), `duration = CloneThreatDuration()`, sent via `AIComponent.SendCommand(clone, cmd)` (`aiCommand.script:469-476`, `aiComponent.script:72`; recipe verbatim `dynamicSpawnSystem.script:18-40`; human-gated internally = matches eligibility).
   - If `CloneUseCombatStimFallback()`: `StimBroadcasterComponent.SendStimDirectly(player, gamedataStimType.CombatHit, clone)` (`stimBroadcasterComponent.script:225`; enum `tweakDBEnums.script:2938`).
   - Notify wired (source record, spawn record, `EntityID.ToDebugString`).
9. **Mark / death-time suppression**: clone kill or takedown → wrap 4 fires → next-frame `EODupCorpseStripCallback`: `GameInstance.GetTransactionSystem(gi).RemoveAllItems(clone)` (`transactionSystem.script:49`) + `ScriptedPuppet.EvaluateLootQualityByTask(clone)` (`scriptedPuppet.script:440-446`) → `m_lootQuality = Invalid` → corpse exits `EGameplayRole.Loot` (`scriptedPuppet.script:4687-4697, 4516-4530`). Wraps 3/5 cover XP (`rpgManager.script:2116` gate; also kills bounty `bountyManager.script:230` + status-effect rewards `executorGivePlayerReward.script:19`) and the world-dropped weapon. **Never strip inventory at spawn** — it would disarm the clone.
10. **F1 interplay**: F2 writes nothing to F1 state. The clone is a fresh eligible entity → F1's own sweep gives it its single uprank roll (30%) naturally. Registry gate (step 6) is what makes it never-duplicate. Exact once-per-session keying: rolls keyed by source `EntityID` in `m_eodupRollSeen`; clones keyed by spawned `EntityID` in the Common registry; both FIFO-capped 4096 (EntityID recycling mitigation, `ScannerSuite.reds:1696-1699`; `entityID.script:1-19`).

## Constants — USER CONFIG block (top of file)

| Const (static func) | Default | Meaning |
|---|---|---|
| `DuplicationEnabled()` | `true` | Master toggle. `false` = Posture A: nothing arms, all wraps pure passthrough. |
| `DuplicateChance()` | `0.20` | Once-per-source probability of spawning one extra enemy. |
| `UseFactionPools()` | `false` | `false` = verbatim clone of source record (v1 default). `true` = PREFERRED same-faction curated pool, per-pick null-check, auto-fallback to verbatim. |
| `SweepInterval()` | `0.5` | Seconds between sweep ticks (index-sanctioned 0.5–1.0; ScannerSuite-proven 0.5). |
| `FirstTickDelay()` | `1.0` | Delay of first tick after player attach. |
| `SweepRange()` | `50.0` | Enumeration radius (m) around player. |
| `MaxSpawnRequestsPerTick()` | `1` | Spawn-request budget per tick; unprocessed candidates retried next tick (burst guard). |
| `PlacementJitter()` | `3.0` | Max random XY offset (m) of the navmesh query center from the source. |
| `PlacementRadius()` | `3.0` | Navmesh point-in-sphere search radius (m). |
| `PendingTTLTicks()` | `60` | Sweep ticks before an unharvested spawn request is dropped from the ledger (~30 s). |
| `CloneThreatDuration()` | `120.0` | `AIInjectCombatThreatCommand.duration` (vanilla's own value, `dynamicSpawnSystem.script:37`). |
| `CloneUseCombatStimFallback()` | `false` | Also fire `SendStimDirectly(CombatHit)` at wiring (secondary hostility channel). |
| `LedgerCap()` | `4096` | FIFO cap for roll-seen set (and requested of Common's clone registry). |
| `DebugNotify()` | `true` | HUD `AddLog` + `FTLog` on every roll/skip/request/harvest/wire/strip event. |

## Exclusions — one VERIFIED predicate per category

Shared filter (same as F1) consumed from Common; F2 adds the clone gate. Evidence per predicate:

| Category | Predicate (exclude unless stated) | Evidence |
|---|---|---|
| Humanoid combat NPC (INCLUDE gate) | cast to `ref<NPCPuppet>` succeeds AND `GetNPCType() == gamedataNPCType.Human` AND `IsActive()` AND `IsEnemy()` | `scriptedPuppet.script:1419-1437` (type), `:1955` (IsActive, const), `:2003-2006` (IsEnemy = hostile OR neutral∧¬civ∧¬crowd); vanilla combo `NPCPuppet.script:3065-3068` |
| Boss / MaxTac (paired, always) | `IsBoss() \|\| IsMaxTac()` | `scriptedPuppet.script:1640-1666`; vanilla pairs them 10+ sites |
| Police / prevention | `IsCharacterPolice()` | `scriptedPuppet.script:1780-1794`; `IsPrevention()` alias `:1976-1979` |
| Mech / drone / robot / android | excluded by the `Human` type check; belt-and-suspenders `!IsMechanical()` | `scriptedPuppet.script:1456-1461`; devices (turrets/cameras) already excluded by the NPCPuppet cast — `gameObject.script:1766-1779`, `sensorDevice.script:155`, `surveillanceCamera.script:33` |
| Civilian / crowd | `!IsCharacterCivilian() && !IsCrowd()` | `scriptedPuppet.script:1775-1778, 1815-1818` |
| Quest / named / unique (best-effort — no clean predicate exists) | `TweakDBInterface.GetCharacterRecord(GetRecordID()).Quest().Type() != gamedataNPCQuestAffiliation.General`; null record → ineligible; null `Quest()` → treat as General (eligible) | `tweakDBRecords.script:3472, 6215-6220`; enum `tweakDBEnums.script:4171-4181`. `IsQuest()` is a FOOTGUN (fires on quest-item carriers, `scriptedPuppet.script:3773-3776`) — must NOT appear. **Posture (index Unresolved #2)**: accept the residual — brief scopes "everywhere incl. quest encounters"; Boss/MaxTac/police exclusions are the hard guardrail |
| Clone (F2-specific, NOT in shared filter) | Common registry `IsClone(id)` → skip before seen/roll | depth cap = 1 by construction; registry marked at harvest, synchronously |

## What NOT to do

- NO per-entity `GameObject.OnGameAttached` hooks (rule 2; worker-thread heap corruption; `gameObject.script:490`). Arm ONLY from `PlayerPuppet.OnGameAttached`.
- NO `continue`/`break` (rule 1) — if-wrapper + boolean budget flag.
- NO TweakDB writes (impossible + forbidden); record reads null-checked.
- NO poll-and-guess clone acquisition (`GetEntityList`/proximity matching, spawning-dossier Finding 14) — false positives would mark REAL enemies as clones and strip their rewards. RequestID ticket match is the only acquisition path; if it cannot work, the feature descopes (Rung 2), never degrades to guessing.
- NEVER skip `wrappedMethod(request)` in the `OnPreventionUnitSpawnedRequest` wrap — police bookkeeping must always run.
- NEVER call `RequestDespawn`/`RequestDespawnAll` (native police-tracked set; `preventionSpawnSystem.script:62-64`).
- NO engine-state mutation inside the harvest wrap or inside `OnIncapacitated` before `wrappedMethod()` (rule 3) — script-array pushes + `DelayCallbackNextFrame` scheduling only.
- NEVER `RemoveAllItems` at spawn/wiring time — disarms the clone; death-time only.
- NO `CompanionSystem`/`DynamicSpawnSystem`/`DynamicEntitySystem`/CET/Codeware spawn attempts (proven dead ends / absent).
- NO `AddSavedModifier` anywhere (save persistence; violates transient-clone decision).
- NO `TSF_EnemyNPC()` as the sweep filter (misses not-yet-hostile gangs) — `GetNPCsAroundObject` (TSF_NPC) only.
- NO edits outside `EnemyOverhaul.Duplication.reds`; Common consumed read-only; no game launch; compile only via `sprint/bin/scc-serial.sh`; never touch `GAME/r6/cache`.

## Debug & manual-verification hooks

- `EODup_Notify(msg)`: gated by `DebugNotify()`; pairs `GameInstance.GetActivityLogSystem(gi).AddLog("EO-Dup: " + msg)` (`activityLogSystem.script:7`; ScannerSuite-proven HUD one-liner) + `FTLog(...)` (`testStepLogicImport.script:29`; live non-test site `worldMap.script:587`). String helpers: `TDBID.ToStringDEBUG` (`tweakDBID.script:9`), `EntityID.ToDebugString` (`entityID.script:6`).
- Notify sites (each one M1-load-bearing): roll success (`roll OK src=<id>`); placement fail (`placement FAIL — skip`); request sent (`req #<id> rec=<record> pos OK`); harvest (`harvest #<id> n=<count> success=<bool>`); harvest failure; wiring applied (`wired clone=<id> group=<name>`); corpse strip (`strip clone=<id>`); pending TTL drop (`req #<id> TTL — dropped`).
- **Probe semantics**: with defaults, "req" lines WITHOUT matching "harvest" lines = native rejected the spawn (unknowns i/ii negative) → Rung 2. "harvest n=1" + visible fighting clone = Posture B validated.

## Risks — residual unknowns + how the implementer surfaces them

1. **Native `RequestUnitSpawn` acceptance** (arbitrary records / outside heat context / engine-internal validation) — unknowable statically. Surfaced by the req/harvest notify pair; gated by M1; bail = Rung 2 config flip. Implementer ships the code compile-clean regardless.
2. **`RequestDespawnAll` heat-sweeps may cull live clones** (native-tracked, unrelated heat transitions). Surfaced by M10 observation; acceptable for transient clones (Rung 3 documents).
3. **Quest "kill-all" encounter counters** with an extra hostile (index Unresolved #7 — no evidence either way). Surfaced by M11; mitigation = exclusions + instant Posture A flip if broken.
4. **Harvest payload anomalies** (`success=true` with empty `spawnedObjects`, non-puppet objects, >1 object): wiring null-checks every element, notifies anomalies, never assumes size 1.
5. **`RemoveAllItems` → `OnInventoryEmptyEvent` synchronicity unknown** (index Unresolved #6): always paired with `EvaluateLootQualityByTask`, always next-frame-deferred.
6. **Save persistence of prevention-spawned units unproven**: M9 checks reload behavior; despawn-on-reload is acceptable per brief. Static guarantee: no persistence API is used by us.
7. **Faction-pool ID staleness** (third-party source): default-off + per-pick null-check + verbatim fallback; M-phase flip is user-driven.
8. **requestID collisions/reuse**: ledger only matches OUR stored IDs and removes on harvest; TTL ages out never-harvested entries.
9. **Common surface drift**: if `plan-common.md` ships different names/shapes than requested, implementer adapts call sites; if a utility is missing entirely, implement it locally in this file (env rule) and note it in the PR/commit message.
10. Any vanilla API in this plan failing the implementer's own grep against `sprint/vanilla-scripts` → STOP, re-verify against the dossiers, document the discrepancy; never substitute a guessed API.

## Addendum 2026-07-17: +10% HP on dup-processed enemies

**Feature (user spec)**: every enemy the duplication feature PROCESSES gets one extra multiplicative +10% max-HP buff, exactly once per entity per session, regardless of the 20% roll outcome. "Processed" = rolled sources (cloned or not) AND spawned clones.

**Apply points** (both in `EnemyOverhaul.Duplication.reds`, nothing else touched):
1. **Sources** — `EODup_ProcessCandidate`, immediately after the `m_eodupRollSeen` spend-on-roll write and BEFORE the `RandF()` roll → outcome-independent by position.
2. **Clones** — `EODup_WireClone` (deferred next-frame game-thread wiring callback), right after `DisableKillReward(true)`. Clones never reach point 1 (the clone gate precedes the roll path), and stat writes are legal in the wiring callback, unlike the harvest wrap (rule 3 untouched).

**Exactly-once**: dedicated FIFO ledger `@addField(PreventionSystem) m_eodupHpBuffSeen: array<EntityID>` (same pattern as `m_eodupRollSeen`; Common's `EO_SeenTryAdd`, cap `LedgerCap()` = 4096). The try-add result gates the apply — no removal/refund path exists (that absence is the guarantee).

**Mechanism** (mirrors F1 TierUprank's staging-proven recipe, steps 6a/6c): plain `StatsSystem.AddModifier(sid, RPGManager.CreateStatModifier(gamedataStatType.Health, gameStatModifierType.Multiplier, 1.0 + fraction))` — `statsSystem.script:38`, `rpgManager.script:1612`, enum member `statsData.script:13`; Multiplier value = DIRECT FACTOR (vanilla precedents: 1.0 neutral `playerWeaponHandler.script:24`, 0.0 zero-out `vendor.script:569`, inverse `1.0/x` `locomotionTransitions.script:2591`), so 1.10 = ×1.10. Then Health-pool max re-sync + pre-buff damage-fraction restore in the same 0-100 perc scale (`RequestSettingStatPoolMaxValue`/`RequestSettingStatPoolValue`, `statPoolsSystem.script:50-51`). Session-transient (never `AddSavedModifier`); a Multiplier composes independently of F1's replayed NPCRarity block + Additive PowerLevel/Level pairing → F1-stacking-safe (both recipes preserve the pool fraction).

**Accepted caveat** (same as F1's header): `ScalePlayerDamage` (`damageSystem.script:3468-3502`) rescales player-sourced damage by the target's Health ratio, so the buff shows fully in max HP and vs non-player damage but is largely cancelled for player TTK. The spec mandates max HP, not TTK — documented, not compensated.

**Consts** (USER CONFIG block): `DupHpBonusEnabled()` default `true` (master toggle; false = never applied, ledger untouched); `DupHpBonusFraction()` default `0.10` (tunable; modifier value is 1.0 + this).

**Debug**: one gated notify per applied buff via the existing `EODup_Notify` funnel — `hpbuff +10% id=<id> hp <before>-><after>`.
