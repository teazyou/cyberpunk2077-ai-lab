# Acceptance — enemy-duplication (20% extra spawn)

Owned file under review: `sprint/impl/custom-enemy-overhaul/EnemyOverhaul.Duplication.reds`. Plan: `sprint/plan-enemy-duplication.md` (Posture B, experimental spawn path, probe-gated by M1; Posture A bail-out = `DuplicationEnabled` default flip per plan Rung 2).

## Static checklist (reviewer-verifiable against code/compile/greps ONLY — no game launch)

### Compile & file discipline
- [x] S1 `sprint/bin/scc-serial.sh` exits 0 with "Output successfully saved", with `EnemyOverhaul.Duplication.reds` present in `sprint/impl/custom-enemy-overhaul/`.
- [x] S2 The implementation diff touches ONLY `EnemyOverhaul.Duplication.reds` — zero edits to `EnemyOverhaul.Common.reds`, other feature files, ScannerSuite, or any game/staging file.
- [x] S3 File declares `module EnemyOverhaul.Duplication`; its only module import (if any) is `EnemyOverhaul.Common.*`.

### USER CONFIG block
- [x] S4 A clearly-marked USER CONFIG block sits at the top of the file containing ALL 15 consts from the plan table with EXACT defaults: `DuplicationEnabled()=true`, `DuplicateChance()=0.20`, `UseFactionPools()=false`, `SweepInterval()=0.5`, `FirstTickDelay()=1.0`, `SweepRange()=50.0`, `MaxSpawnRequestsPerTick()=1`, `PlacementJitter()=3.0`, `PlacementRadius()=3.0`, `PendingTTLTicks()=60`, `CloneThreatDuration()=120.0`, `CloneUseCombatStimFallback()=false`, `LedgerCap()=4096`, `DebugNotify()=true`.
- [x] S5 `DuplicateChance()` is consumed at EXACTLY ONE roll site, shaped `RandF() < DuplicateChance()` (idiom `NPCPuppet.script:893`; `rand.script:3`).
- [x] S6 `DuplicationEnabled()` gates both the arm path (OnGameAttached wrap) and the tick (tick self-stops when false) — with default `false` the feature is fully dormant and all five wraps are pure passthrough.

### Roll-once / depth-cap semantics
- [x] S7 Roll ledger: candidate is skipped if its `EntityID` is already in `m_eodupRollSeen`; the id is appended AT roll time (spend-on-roll), BEFORE the placement/spawn attempt; no code path removes/refunds a ledger entry on placement or spawn failure.
- [x] S8 Roll ledger and pending/wiring queues are FIFO-capped (`LedgerCap()` = 4096 shape; oldest evicted) — no unbounded array growth.
- [x] S9 Clone gate PRECEDES the seen/roll gates in the per-candidate chain: registry `IsClone(id)` (Common, or local fallback) → skip — a marked clone can never enter the roll path (depth cap = 1 by construction).
- [x] S10 Clones are marked in the registry synchronously at HARVEST time (before any wiring/delay), closing the race where a sweep tick sees the clone before wiring.
- [x] S11 Eligibility failure does NOT mark the candidate seen (an NPC that later becomes eligible still gets its single roll); only the roll site writes the seen-set.
- [x] S12 F1 interplay: the file never reads/writes TierUprank state, and the eligibility predicate used does NOT exclude marked clones (clones stay eligible for F1's own roll).

### Spawn path (Posture B)
- [x] S13 The ONLY spawn call is `GameInstance.GetPreventionSpawnSystem(gi).RequestUnitSpawn(recordID, spawnTransform)` (`preventionSpawnSystem.script:40`); its returned `Uint32` is stored in the pending ledger with source id + records.
- [x] S14 Transform recipe matches vanilla `SpawnUnits` (`preventionSystem.script:2830-2832`): `WorldTransform.SetPosition(t, spawnPos)` (`worldTransform.script:5`) + `WorldTransform.SetOrientationFromDir(t, Vector4.Normalize2D(playerPos - spawnPos))` (`worldTransform.script:8`, `vector.script:54`).
- [x] S15 Harvest wrap `@wrapMethod(PreventionSystem) OnPreventionUnitSpawnedRequest` calls `wrappedMethod(request)` unconditionally on EVERY control path (police bookkeeping always runs), and only reacts to `request.requestResult.requestID` values present in our own pending ledger (`preventionSystem.script:1875-1890`; result struct `preventionSpawnSystem.script:20-27`).
- [x] S16 Inside the harvest wrap there is NO engine-state mutation: only script-array reads/writes (ledger removal, registry mark, wiring-queue push) and `DelayCallbackNextFrame` scheduling (`delaySystem.script:63`) — attitude/AI-command/inventory calls appear only in the deferred wiring/strip callbacks.
- [x] S17 Pending-ledger hygiene: entries age per tick and are dropped after `PendingTTLTicks()`; harvest removes the matched entry; wiring null-checks every `spawnedObjects` element and never assumes size 1.
- [x] S18 Per-tick budget: at most `MaxSpawnRequestsPerTick()` spawn requests per tick, enforced via an if-wrapper/counter (no `break`); budget-starved candidates are NOT marked seen and are retried next tick.

### Placement (validated or silent skip)
- [x] S19 Primary placement query is `FindPointInSphereOnlyHumanNavmesh(center, PlacementRadius(), NavGenAgentSize.Human, false)` requiring `status == worldNavigationRequestStatus.OK` (`navigationSystem.script:57,9-15,33-36`; `heightDetail=false` = the only vanilla-precedented value, `:73`); fallback is `GetNearestNavmeshPointBelowOnlyHumanNavmesh(center, 1.0, 5)` with `Vector4.IsZero` fail-check (`navigationSystem.script:66-86`, `vector.script:137`; vanilla params `deviceBase.script:3244`).
- [x] S20 Both placement attempts failing → NO spawn request is sent (silent skip, debug notify only); the roll stays spent; the jitter of the query center is bounded by `PlacementJitter()` via `RandRangeF` (`rand.script:4`).

### Identity
- [x] S21 Default identity is the verbatim source record: `source.GetRecordID()` (`puppet.script:13`) with `UseFactionPools()=false`; the PREFERRED same-faction pool path exists behind the flag, keyed via `GetCharacterRecord(id).Affiliation().Type()` (`tweakDB.script:371`, `tweakDBRecords.script:3476,2570`), and EVERY pool pick is null-checked via `TweakDBInterface.GetCharacterRecord(pick)` with automatic fallback to the verbatim record; factions without a pool fall back to verbatim.

### Hostility wiring (deferred, game-thread)
- [x] S22 Wiring (next-frame callback) performs, in order: attitude-group copy from source when source still resolves (`GetAttitudeAgent().SetAttitudeGroup(...)`, `gameObject.script:586`, `attitudeAgent.script:21,23`); ALWAYS `SetAttitudeTowards(playerAgent, EAIAttitude.AIA_Hostile)` (`attitudeAgent.script:25`); `AIInjectCombatThreatCommand` with `targetPuppetRef = CreateEntityReference("#player", ...)` and `duration = CloneThreatDuration()` sent via `AIComponent.SendCommand` (`aiCommand.script:469-476`, `aiComponent.script:72`, `questSystem.script:38`; recipe `dynamicSpawnSystem.script:18-40`).
- [x] S23 The `SendStimDirectly(player, gamedataStimType.CombatHit, clone)` secondary channel (`stimBroadcasterComponent.script:225`, `tweakDBEnums.script:2938`) fires ONLY when `CloneUseCombatStimFallback()` is true (default false).

### Reward suppression (per plan tier)
- [x] S24 `@wrapMethod(ScriptedPuppet) AwardsExperience()`: returns `false` for registered clones, otherwise returns `wrappedMethod()` unchanged; uses only const-context-safe calls inside (`scriptedPuppet.script:1835-1838`; gate consumers `rpgManager.script:2116`, `bountyManager.script:230`, `executorGivePlayerReward.script:19`).
- [x] S25 `@wrapMethod(ScriptedPuppet) DropHeldItems()`: for clones returns `false` WITHOUT calling `wrappedMethod()` (no world-dropped weapon); non-clones pass through (`scriptedPuppet.script:3092-3119`).
- [x] S26 `@wrapMethod(NPCPuppet) OnIncapacitated()`: calls `wrappedMethod()` FIRST, then for clones schedules the corpse strip via `DelayCallbackNextFrame` (`NPCPuppet.script:3935-3987`); the strip callback pairs `TransactionSystem.RemoveAllItems(clone)` with `ScriptedPuppet.EvaluateLootQualityByTask(clone)` (`transactionSystem.script:49`, `scriptedPuppet.script:440-446`).
- [x] S27 `RemoveAllItems` appears ONLY in the death-path strip callback — never at spawn/wiring time (would disarm the clone).
- [x] S28 `clone.DisableKillReward(true)` (`gameObject.script:1682`) is called once per clone during wiring.

### Exclusions (shared filter + clone gate)
- [x] S29 Include gates present: cast to `NPCPuppet` succeeds, `GetNPCType() == gamedataNPCType.Human` (`scriptedPuppet.script:1419-1437`), `IsActive()` (`:1955`), `IsEnemy()` (`:2003-2006`) — via Common's shared predicate or a same-shape local fallback.
- [x] S30 Boss/MaxTac exclusion present as the PAIRED check `IsBoss() || IsMaxTac()` (`scriptedPuppet.script:1640-1666`).
- [x] S31 Police exclusion `IsCharacterPolice()` present (`scriptedPuppet.script:1780-1794`).
- [x] S32 Civilian/crowd exclusion `!IsCharacterCivilian() && !IsCrowd()` present (`scriptedPuppet.script:1775-1778,1815-1818`).
- [x] S33 Quest/named best-effort check present: `GetCharacterRecord(GetRecordID()).Quest().Type() != gamedataNPCQuestAffiliation.General` with null record → ineligible and null `Quest()` → treated as General (`tweakDBRecords.script:3472,6215-6220`, `tweakDBEnums.script:4171-4181`); grep confirms `IsQuest(` appears NOWHERE in the file (footgun, `scriptedPuppet.script:3773-3776`).

### Loop & lifecycle shape
- [x] S34 Arm point is ONLY `@wrapMethod(PlayerPuppet) protected cb func OnGameAttached()` (`player.script:1161`) which calls `wrappedMethod()` exactly once; a `Bool` double-arm guard prevents duplicate loops on replacer re-attach.
- [x] S35 Tick re-arms FIRST (before any work), then applies the skip-but-stay-alive gate (`!IsDefined(player) || player.IsReplacer() || hud.IsBraindanceActive()` — `gameObject.script:1731`/`player.script:582`, `hudManager.script:615`).
- [x] S36 Enumeration uses `player.GetNPCsAroundObject(SweepRange())` (`gameObject.script:967-987`); `TSF_EnemyNPC()` is NOT used as the sweep filter (it would pre-filter to currently-hostile).

### Forbidden patterns (grep-verifiable, all must be ABSENT)
- [x] S37 Zero occurrences of the `continue` or `break` keywords (if-wrapper skips only).
- [x] S38 Zero hooks on per-entity `GameObject.OnGameAttached` (`gameObject.script:490`) — no `@wrapMethod(GameObject)`/`@addMethod(GameObject)` attach hooks of any kind.
- [x] S39 Zero TweakDB writes: all `TweakDBInterface` usage is `Get*`; no `Set*`/record-creation calls exist (none do on this platform).
- [x] S40 Zero calls to `RequestDespawn`/`RequestDespawnAll`, `CompanionSystem.*Spawn*`, `DynamicSpawnSystem`, `DynamicEntitySystem`; zero `GetEntityList`-based (or proximity-heuristic) clone acquisition — the requestID ticket match is the only acquisition path.
- [x] S41 Zero `AddSavedModifier` and zero `persistent` fields among the `@addField` state (transient-clone decision); all five hooks use `@wrapMethod` (no `@replaceMethod` anywhere in the file).

### Verified-API-only & debug wiring
- [x] S42 Verified-API spot-check: every engine API called in the file greps in `sprint/vanilla-scripts` at (or adjacent to) the plan's cited file:line — spot-check at minimum: `RequestUnitSpawn` (`preventionSpawnSystem.script:40`), `SpawnRequestResult.spawnedObjects` (`preventionSpawnSystem.script:24-26`), `PreventionUnitSpawnedRequest.requestResult` (`preventionSystem.script:5274-5277`), `FindPointInSphereOnlyHumanNavmesh` (`navigationSystem.script:57`), `AIInjectCombatThreatCommand` (`aiCommand.script:469`), `RemoveAllItems` (`transactionSystem.script:49`), `EvaluateLootQualityByTask` (`scriptedPuppet.script:440`), `DelayCallbackNextFrame` (`delaySystem.script:63`). No API in the file is sourced from Codeware/CET/NativeDB-only surfaces.
- [x] S43 Debug wiring: every notify site is gated by `DebugNotify()` and pairs `GameInstance.GetActivityLogSystem(gi).AddLog(...)` (`activityLogSystem.script:7`) with `FTLog(...)` (`testStepLogicImport.script:29`); all eight plan-mandated sites exist: roll success, placement fail, request sent, harvest, harvest failure, wired, corpse strip, pending TTL drop. (These notifies are M1-load-bearing — absence breaks the probe gate.)

## Manual in-game test plan (user-run; the reviewer NEVER ticks these)

Run with defaults (`DuplicationEnabled=true`, `DebugNotify=true`). M1 is the GATE for Posture B: if it fails, flip `DuplicationEnabled` default to `false` (plan Rung 2), re-verify S6, and skip M2-M12.

- [ ] M1 **Spawn probe (GATE)**: approach a street gang group (e.g. Maelstrom/Valentinos, no police heat active). Expect on ~1 in 5 eligible enemies: HUD lines `roll OK` → `req #<id>` → `harvest #<id> n=1 success=true` → `wired clone=<id>`, and a visible extra enemy appearing near the source. FAIL SIGNATURE = `req #` lines with NO matching `harvest` line (native rejected arbitrary records / no-heat context) → Posture A per plan Rung 2.
- [ ] M2 **Rate & once-only**: across ≥20 distinct eligible enemies, roughly 2/10 bring a friend (accept ~1-4/10); leaving and re-approaching the same living NPC never produces a second roll or second clone.
- [ ] M3 **Fights immediately**: each clone enters combat within a few seconds of appearing, targets the player/allies like its source, no idle statue-standing.
- [ ] M4 **Placement sanity**: no clone floats in the air, clips inside walls, or spawns out of reach; in navmesh-hostile spots (ledges, cramped geometry) `placement FAIL — skip` lines appear and no clone spawns.
- [ ] M5 **Identity (verbatim default)**: clones visually/behaviorally match the source archetype family (same faction look/weapons class), consistent with `UseFactionPools=false`.
- [ ] M6 **No XP**: killing a clone yields no XP/skill-proficiency ticks and no bounty payout (compare against killing its source: source pays normally).
- [ ] M7 **No loot**: a clone's corpse shows no loot highlight/mappin/prompt and drops no weapon into the world; source corpses loot normally.
- [ ] M8 **Exclusions hold**: bosses, MaxTac, police (NCPD scanner hustles with officers present), mechs/drones/turrets, and civilians NEVER duplicate — no `req #` lines fire for them.
- [ ] M9 **Transient persistence**: save mid-encounter with a live clone, reload — clone despawning on reload is ACCEPTABLE; there must be no save corruption, no permanently lingering duplicate, and no re-spawn stacking after repeated save/reload cycles.
- [ ] M10 **Heat-sweep lifecycle (observation)**: with a live clone present, gain then lose police heat (or let a chase end). Note whether clones vanish on heat-state changes (`RequestDespawnAll` native sweep). Acceptable for transient clones — document per plan Rung 3; report frequency.
- [ ] M11 **Quest encounter safety**: complete one "neutralize all enemies"-style objective (gig/NCPD hustle) with duplication active and a clone spawned inside it — the objective must still complete after all enemies incl. the clone die. If a kill-counter wedges, flip `DuplicationEnabled=false` and report (plan Risk 3).
- [ ] M12 **Depth cap & F1 interplay**: observed clones NEVER spawn their own friend (no `roll OK`/`req` lines keyed to a clone id); occasionally a clone gets F1's uprank notify (its allowed single uprank roll) — confirming clones are F1-eligible but duplication-immune.

## Addendum 2026-07-17: +10% HP on dup-processed enemies

Scope: one feature addition inside `EnemyOverhaul.Duplication.reds` only (plan addendum of the same date). Every dup-PROCESSED enemy — rolled sources (cloned or not) and spawned clones — gets one multiplicative +10% max-HP buff, exactly once per entity per session.

### Static (S44+)
- [x] S44 USER CONFIG consts `DupHpBonusEnabled()` (default `true`) and `DupHpBonusFraction()` (default `0.10`) exist in the config block; the fraction feeds EXACTLY ONE stat-modifier site shaped `RPGManager.CreateStatModifier(gamedataStatType.Health, gameStatModifierType.Multiplier, 1.0 + DupHpBonusFraction())` (`rpgManager.script:1612`; enum member `statsData.script:13`; Multiplier factor semantics `playerWeaponHandler.script:24` [1.0 neutral], `vendor.script:569` [0.0 zero-out], `locomotionTransitions.script:2591` [1.0/x inverse]); its only other consumption is the debug-notify display string.
- [x] S45 Exactly-once: dedicated FIFO ledger `@addField(PreventionSystem) m_eodupHpBuffSeen: array<EntityID>` (`m_eodupRollSeen` pattern; `EO_SeenTryAdd` with cap `LedgerCap()`); the apply body runs ONLY when the try-add returns true; grep shows the ledger written at exactly one site and NO removal/refund path (`ArrayErase`/`ArrayClear` never touch it).
- [x] S46 Apply points are exactly TWO calls to `EODup_ApplyHpBonus`: (a) in `EODup_ProcessCandidate` immediately after the `m_eodupRollSeen` spend and BEFORE the `RandF()` roll (outcome-independent for sources); (b) in `EODup_WireClone` (deferred game-thread wiring callback — NOT the harvest wrap; rule 3 intact). Clones cannot reach (a): the clone gate precedes the roll path (S9 unchanged).
- [x] S47 Mechanism mirrors TierUprank's staging-proven recipe: plain `AddModifier` (`statsSystem.script:38`; S41 still holds — zero `AddSavedModifier` calls, zero `continue`/`break` keywords added) + `RequestSettingStatPoolMaxValue` + `RequestSettingStatPoolValue(..., pctBefore, ..., true)` in the same 0-100 perc scale (`statPoolsSystem.script:50-51`); ONE notify per applied buff routed through the gated `EODup_Notify` funnel (S43 convention); `sprint/bin/scc-serial.sh` exits 0 with "Output successfully saved" and zero diagnostics naming custom-enemy-overhaul files.

### Manual (user-run; the reviewer NEVER ticks these)
- [ ] M13 **HP bonus once-only, outcome-independent**: with defaults, every dup-processed enemy emits exactly ONE `hpbuff +10% ... hp X->Y` line with Y ≈ 1.10×X — including sources whose roll produced NO clone, and every wired clone (its hpbuff line lands next to its `wired clone=` line). Leaving and re-approaching the same living NPC never re-fires it; an enemy that also receives an F1 uprank shows both notifies and no health-bar anomaly (fraction preserved, no full heal / instant drop).
