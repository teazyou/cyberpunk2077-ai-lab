# Search Index — Enemy Overhaul

Research phase FINAL (round 1 of 4 sufficed). Sources: 6 dossiers in `sprint/research/` (cited as `research/round1-<slug>.md`), plus a director compile-probe pass (2026-07-17, `sprint/bin/scc-serial.sh`, exit 0, "Output successfully saved") that converted every round-1 UNVERIFIED annotation-compile question into a verified fact. Planners: this index + the cited dossiers are decision-complete; do not reopen research. Every API below is vanilla-verified (`sprint/vanilla-scripts` file:line) unless explicitly flagged.

---

## Platform verdicts (pure REDscript / macOS / 2.3)

**Impossible — proven, do not revisit:**
| Capability | Proof | Dossier |
|---|---|---|
| Write/mutate TweakDB at runtime (records, flats) | `tweakDB.script` (1156 lines): every member is `Get*`; zero `Set*`/`CreateRecord`. Independently re-confirmed by stim dossier | tier-uprank F2; stim-aggro Dead ends |
| Change an NPC's rarity/record | `GetNPCRarity()/GetNPCRarityRecord()/GetRecordID()` are `import const final` (`puppet.script:95-96,13`); no setter/swap API anywhere | tier-uprank F1 |
| Enumerate TweakDB records by class/query ("all Characters of faction X") | Exhaustive scan: all ~1000+ `Get*Record` accessors require a known TweakDBID; no query entry point | spawn-wiring F5 |
| Generic runtime NPC spawn with handle back (`DynamicEntitySystem`/`DynamicEntitySpec`) | 0 hits in vanilla-scripts; confirmed Codeware = RED4ext C++ plugin (NOT AVAILABLE). No other by-record spawn primitive exists (exhaustive `import…Spawn` sweep) | runtime-npc-spawning F1-F3,F10 |
| Add an NPC to a squad at runtime | `AISquadHelper` has no Add/Join API; membership is data/proximity-authored | spawn-wiring F18 |
| Map/dict types; RNG seeding | No such types (seen-sets = `array<EntityID>`); `rand.script:1-6` exposes no seed | shared-infra F3,F6 |

**Possible — compile-verified this sprint (director probe; all 7 compiled clean against staging = vanilla 2.3 + all 43 enabled mods, zero conflicts):**
| # | Shape | Probe target |
|---|---|---|
| P1 | `@wrapMethod` on `public const func` | `ScriptedPuppet.AwardsExperience()` |
| P2 | `@wrapMethod` on `private func` | `ScriptedPuppet.DropHeldItems()` |
| P3 | `@wrapMethod` on `protected override func` | `NPCPuppet.OnIncapacitated()` |
| P4 | `@wrapMethod` on public func with `opt` params (forward all args) | `StimBroadcasterComponent.TriggerSingleBroadcast(...)` |
| P5 | `@wrapMethod` on `protected cb func` (decompiled `event`) | `StimBroadcasterComponent.OnBroadcastEvent(evt)` |
| P6 | `@replaceMethod` on public 8-arg func with `out` params | `ReactionManagerComponent.ShouldIgnoreCombatStim(8-arg)` |
| P7 | `@replaceMethod` on `private func` | `ReactionManagerComponent.ShouldHelpTargetFromSameAttitudeGroup` |

**Levers that DO exist:** `StatsSystem.AddModifier(s)` stat mutation; `StatPoolsSystem` pool re-syncs; `TransactionSystem` inventory ops; `AttitudeAgent` mutators; `AIComponent.SendCommand`; `NavigationSystem` synchronous navmesh queries; `DelaySystem` loops; `@addMethod/@addField` with private-member access (rule 5, now cross-proven by P2/P7).

---

## F1 tier-uprank — 30% one-tier upgrade

**Verdict: FEASIBLE via stat emulation. Literal rarity/record mutation BLOCKED structurally** (`research/round1-tier-uprank-mechanism.md`).

**Chosen mechanism (primary): per-tier StatModifier replay + PowerLevel pairing.**
1. Read current tier: `puppet.GetNPCRarity()` (`puppet.script:95`). Map to target tier via an EXPLICIT ladder table `Trash→Weak→Normal→Rare→Officer→Elite` (enum is alphabetical — `tweakDBEnums.script:3396-3408` — NEVER ordinal math). Elite/Boss/MaxTac never upranked.
2. Fetch target tier record: `TweakDBInterface.GetNPCRarityRecord(T"NPCRarity.<Tier>")` (`tweakDB.script:605`; path strings web-sourced — see Unresolved #3).
3. Replay its modifiers: `record.StatModifiers(out list)` (`tweakDBRecords.script:6224`) → per entry `RPGManager.StatRecordToModifier()` (`rpgManager.script:1659-1696`) → `StatsSystem.AddModifiers(entityID, mods)` (`statsSystem.script:39`). This is verbatim the vanilla device-init pipeline (`scriptableDeviceBasePS.script:535-554`).
4. PLUS a small `gamedataStatType.PowerLevel` (+`Level`) `Additive` bump via `RPGManager.CreateStatModifier` (`rpgManager.script:1612`) — tunable const, `NPCManager.ScaleToPlayer` pattern (`npcManager.script:107-121`). Load-bearing: `DamageSystem.ScalePlayerDamage` (`damageSystem.script:3468-3502`) algebraically cancels a bare Health bump for player-sourced damage (frozen-rarity baseline in the denominator); PowerLevel raises both sides. Armor/Accuracy/immunity deltas from step 3 are NOT subject to this compensation.
5. Re-sync health pool immediately after: `StatPoolsSystem.RequestSettingStatPoolMaxValue(objID, gamedataStatPoolType.Health, instigator)` (`statPoolsSystem.script:50`) — treat as required (every vanilla intentional-change site calls it). Optional current-HP top-off: `RequestSettingStatPoolValue(..., 1.0, ..., perc=true)` (`:51`).
6. Use plain `AddModifier(s)` ONLY — `AddSavedModifier` persists across reload and double-stacks against the session-only seen-set (all ~70 vanilla call sites are item/permanent-buff persistence; `research/round1-tier-uprank-mechanism.md` F13).

**Fallback ladder:** (a) primary above → (b) PowerLevel/Level bump alone (coarser; cascades Health/Level/DPS via `NPC_Base_Curves`) → (c) hand-tuned flat multipliers (last resort; contradicts "justified from game data"). Literal record swap is NOT a rung — it does not exist.

**Per-tier data (web-sourced from CDPR-Modding-Documentation/Cyberpunk-Tweaks `npcrarities.tweak`, multi-repo corroborated):** rarityValue 1.0→7.0 Trash→Boss; Health = PowerLevel-keyed Multiplier curve w/ tier column; Armor flat ×1.00/1.05/1.10/1.15/1.20/1.25; Officer inherits Rare's whole stat block (Officer bump ≈ rarityValue only — expect a weak visible delta on the Rare→Officer rung); vanilla Elite does NOT out-damage Normal (tier gap = Health×Armor×Accuracy). Full table: dossier F7.

**Key APIs:** inventory table in dossier (all VERIFIED except TweakDBID path strings). Predicates: `IsBoss()/IsMaxTac()` `scriptedPuppet.script:1640-1666`; direct `==` for unnamed tiers.

**Risks / accepted facts:**
- Nameplate badge, boss-bar, XP-reward tier, anti-Elite player perks all read the FROZEN `GetNPCRarity()` — an upranked NPC never changes badge. Acceptance must read "bigger healthbar + measurably harder fight," not "new badge" (dossier F3). Rewards stay natural at the original tier — exactly what the brief ordered.
- Modifier compounding arithmetic is native → treat computed HP as approximate; tune the PowerLevel const empirically with debug notify on.

---

## F2 enemy-duplication — 20% extra spawn

**Verdict: the spawn primitive is the single blocker — no clean pure-REDscript path exists (`research/round1-runtime-npc-spawning.md`). Everything downstream (identity, placement, hostility, reward suppression) is FEASIBLE and fully specified.** Planner must choose a posture (A or B below) and state it in the plan.

**Posture A — descope (safe default):** ship F1+F3; report the platform blocker (Codeware-only spawn API) to the user. Optionally keep F2's downstream wiring implemented-but-dormant behind a config const for a future platform change.

**Posture B — experimental spawn path (compile-sound, empirically gated).** Director consolidation upgraded the dossier's poll-and-guess workaround using the now-proven private-wrap capability (P2/P7):
1. Build transform: `WorldTransform.SetPosition(t, pos4)` + `WorldTransform.SetOrientationFromDir(t, Vector4.Normalize2D(playerPos - spawnPos))` — vanilla recipe `preventionSystem.script:2830-2832`.
2. Call the PUBLIC native `GameInstance.GetPreventionSpawnSystem(gi).RequestUnitSpawn(recordID, spawnTransform) : Uint32` (`preventionSpawnSystem.script:40`) directly; store the returned requestID in mod state.
3. `@wrapMethod(PreventionSystem)` on private `OnPreventionUnitSpawnedRequest(request)` (`preventionSystem.script:1875-1890`; private wrap = P2-proven). The native side queues this request UNCONDITIONALLY for every spawn result (`preventionSpawnSystem.script:81-92`); vanilla's handler no-ops on unknown tickets, so our requests are invisible to police bookkeeping. If `request.requestResult.requestID` is ours: harvest `request.requestResult.spawnedObjects : array<weak<GameObject>>` (`preventionSpawnSystem.script:20-27`) — EXACT handles, no heuristics — mark clone, apply wiring below; else pass through to `wrappedMethod`.
4. Defer any engine-state mutation out of the callback (rule 3): queue the handle, consume from the sweep tick or `DelayCallbackNextFrame`.
- **Empirically unknown (game-launch test required; researchers/implementers cannot):** (i) does native `RequestUnitSpawn` accept arbitrary non-police `Character_Record`s; (ii) does it spawn outside an active police-chase/heat context; (iii) `RequestDespawnAll` sweeps (native-tracked set, `preventionSpawnSystem.script:64`, fired from `preventionSystem.script:3215`) may despawn clones on unrelated heat-state changes — acceptable-ish for transient clones, but verify. Plan MUST front-load a probe milestone: spawn 1 hardcoded gang record at a fixed offset, log `spawnedObjects.Size()`, user manual-tests before any further F2 investment.

**Downstream wiring (ready regardless of posture; `research/round1-spawn-wiring.md`):**
- **Identity:** FALLBACK verbatim clone = `source.GetRecordID()` (`puppet.script:13`) — zero risk, recommended v1. PREFERRED same-faction pool: read `TweakDBInterface.GetCharacterRecord(id).Affiliation().Type()` (`tweakDB.script:371`, `tweakDBRecords.script:3476,2570`), pick from hardcoded per-faction `array<TweakDBID>` via `RandRange` — vanilla pool-pick idiom (`preventionSystem.script:589-662`). Starter 8-faction/122-ID list in dossier (third-party-sourced, 2 IDs cross-validated) — if used, null-check `GetCharacterRecord(id)` and fall back to verbatim clone.
- **Placement:** `GameInstance.GetNavigationSystem(gi).FindPointInSphereOnlyHumanNavmesh(center, radius, agentSize, heightDetail) : NavigationFindPointResult{status, point}` (`navigationSystem.script:57,33-36`) — synchronous; `status != OK` → skip spawn silently (brief rule). Robustness alt: `GetNearestNavmeshPointBelowOnlyHumanNavmesh(origin, 1.0, 5)` (`:66-86`, vanilla params `deviceBase.script:3244`), `Vector4.IsZero` = fail.
- **Hostility (spawned NPCs do NOT inherit it — vanilla proof `dynamicSpawnSystem.script:42-56`):** copy `source.GetAttitudeAgent().GetAttitudeGroup()` onto clone + `SetAttitudeTowards(playerAgent, EAIAttitude.AIA_Hostile)` (`attitudeAgent.script:21-26`), then send `AIInjectCombatThreatCommand{targetPuppetRef=CreateEntityReference("#player",[]), duration≈120}` via `AIComponent.SendCommand` (`aiCommand.script:469-476`, `aiComponent.script:72`, recipe `dynamicSpawnSystem.script:18-40`) — vanilla's own "fight immediately" mechanism; human-gated internally, matching eligibility for free. Secondary: `StimBroadcasterComponent.SendStimDirectly(player, gamedataStimType.CombatHit, clone)` (`stimBroadcasterComponent.script:225`; mod-precedented combo).
- **Reward suppression (`research/round1-reward-suppression.md`; ALL wrap shapes now compile-verified P1/P2/P3):** Full tier = (1) `@wrapMethod(ScriptedPuppet) AwardsExperience()` → false for marked clones — kills per-hit/kill proficiency XP + bounty + status-effect rewards at one gate (`rpgManager.script:2116`, `bountyManager.script:230`, `executorGivePlayerReward.script:19`); (2) after `@wrapMethod(NPCPuppet) OnIncapacitated()` (covers lethal + takedown paths) → deferred `TransactionSystem.RemoveAllItems(clone)` (`transactionSystem.script:49`) + `ScriptedPuppet.EvaluateLootQualityByTask(clone)` (`scriptedPuppet.script:440-446`) → `m_lootQuality=Invalid` → corpse stops being `EGameplayRole.Loot` (`scriptedPuppet.script:4687-4697,4516-4530`); (3) `@wrapMethod(ScriptedPuppet) DropHeldItems()` → skip `wrappedMethod()` for clones (no world-dropped weapon; `scriptedPuppet.script:3092-3119`); (4) bonus `clone.DisableKillReward(true)` (`gameObject.script:1682`; telemetry-only, free). Minimum bar (no lootable items) already met by (2) alone.
- **Depth cap / F1 interplay:** mark clones in a Common registry (`array<EntityID>` FIFO) at acquisition; sweep treats marked = never-duplicate, but DOES give them the single F1 roll (brief: their only roll).

**Risks:** posture B's three empirical unknowns (above); quest "kill-all" encounter counters with an extra hostile — unresolved by research, mitigated by eligibility exclusions + posture A; clone lifecycle tied to prevention sweeps (posture B).

---

## F3 aggro-range — clean-room port of Nexus 19351

**Verdict: FEASIBLE, both halves; zero planner-blocking questions (`research/round1-stim-aggro-pipeline.md`). All hook shapes compile-verified (P4/P5/P6/P7), and the probe confirmed NO other enabled mod touches either replaced method.**

**Half A — two `@replaceMethod(ReactionManagerComponent)` (replace justified: deltas remove distance gates from the MIDDLE of interleaved early-return chains — original author made the same choice; wrap cannot slice them):**
1. `ShouldIgnoreCombatStim` 8-arg (`reactionComponent.script:2590-2711`; the 5-arg shim `:2583-2588` is untouched). Deltas to reproduce: danger range `12.0→35.0` (`:2642`); Explosion never ignorable (drop `&& inDangerRange`, `:2643`); illegal-action-in-cone loses its range gate (`:2670`; cone = 15 DEGREES front-angle via `IsTargetInFrontOfSource`, `:5455` — after the delta it is direction-only, no distance cap); **plus undocumented delta #6**: vanilla's `if(!source && !instigator) return false` (`:2599-2606`) became unconditional `if(!IsDefined(instigator)) return false` — clean-room = behavior parity, so REPLICATE it and note it in the plan (dossier F2 row 6).
2. `ShouldHelpTargetFromSameAttitudeGroup` (private, `:5784-5803`; call sites `:918,1723`). Deltas: help if same `Affiliation` OR same attitude group (via `GetCharacterRecord(GetRecordID()).Affiliation()`); remove `!targetOfTarget.IsPlayer()` (`:5793-5796`) — THE line making NPCs pile on allies fighting the player; preserve the police join-chase branch byte-equivalent (`:5797-5801`).

**Half B — TweakDB radii are unwritable; port via script hooks. Knob → actual driver → mechanism:**
| Original knob | What it actually drives (evidence) | Port mechanism |
|---|---|---|
| `District.gunShotStimRange` default 30→50; Badlands 45→50; Dogtown 20→30 (reference `districts.tweak`/`schema.tweak`) | PLAYER's primary exterior gunshot radius — 6-hop verified chain to `PlayerPuppet.GetGunshotRange()` (`player.script:6999`) consumed at `weaponTransitions.script:2430` + `vehicleComponent.script:1611`. Enemy-aggro-relevant, NOT crime-only | `@wrapMethod(PlayerPuppet) GetGunshotRange()` mapping the vanilla return: `<40 → uplift toward 30/50 per original's table; ≥40 → 50` (exact mapping = planner's call; original: 30→50, 45→50, 20→30) |
| `stims.GunshotStimuli.radius` 30→50 | NPC-fired gunshots pass NO radius (`weapon.script:2027-2030`) → native falls back to the stim record. ALL Single stim broadcasts funnel through exactly two chokepoints: `TriggerSingleBroadcast` (`stimBroadcasterComponent.script:239-260`) + `OnBroadcastEvent` (`:351-385`) | Wrap BOTH chokepoints (P4/P5): for `gamedataStimType.Gunshot` with `radius == 0.0` → inject 50.0 (tunable) before forwarding |
| `stims.ExplosionStimuli.radius` 25→50 | Only the record-fallback path (player ground-slam perk, `locomotionTransitions.script:6218`); grenades/missiles pass their OWN per-weapon radii (`fragGrenade.script:886-889` etc.) which the original did NOT touch | Same chokepoint wraps: `Explosion` with `radius == 0.0` → inject 50.0. Do NOT max() explicit radii — parity with the original |
| `SilencedGunshotStimuli.radius = 8` | Confirmed RESTATEMENT of vanilla (forced by tweak inheritance), not a change | N/A — and the injection above must leave `SilencedGunshot` radius 0.0 untouched (native falls back to vanilla 8) |
| Squad convergence | `AISquadHelper.EnterAlerted` (`aiSquadHelper.script:415-444`) + `PullSquadSync` (`:332-371`) propagate squad-wide with NO distance gate (60 m cap = police only) | No work needed — wider individual reception alone delivers "converge from farther" |

**Debug:** in the replaced `ShouldIgnoreCombatStim`, when returning "not ignorable" for a stim at distance >12 m and ≤35 m (i.e., accepted only because of the widened range), fire the throttled notify; same idea for injected-radius broadcasts. Toggle const default ON.

**Risks (informational only):** `radius=0` native-fallback semantics inferred (hook overrides pre-native, so immaterial); possible silenced-shot double-broadcast unresolved (both paths hit the same chokepoints); `propagationChange=true` semantics opaque.

---

## Cross-cutting infra (`research/round1-shared-infra.md`) — Common.reds contract

- **Sweep loop:** subclass `DelayCallback` (`delaySystem.script:41-44`), schedule via `GameInstance.GetDelaySystem(gi).DelayCallback(cb, 0.5–1.0, false)` (`:59`); RE-ARM FIRST, then work; arm exactly once from `@wrapMethod(PlayerPuppet) protected cb func OnGameAttached()` (`player.script:1161`) with a `Bool` double-arm guard; skip-but-stay-alive during `IsReplacer()`/braindance. In-game-proven twice (ScannerSuite.reds:1303-1411, 1788-1882). NEVER per-entity `GameObject.OnGameAttached` (worker threads, rule 2). Ownership note: Common may not import feature files — either F1/F2 each arm their own loop (wraps chain, rule 6; ScannerSuite runs two loops fine) or Common exposes an abstract processor class features register at attach; planner picks.
- **Enumeration:** primary `player.GetNPCsAroundObject(range)` / `GetEntitiesAroundObject(range, TSF_EnemyNPC())` (`gameObject.script:936-987`; `TargetingSet.Complete` = 360°, camera-independent). `TSF_EnemyNPC()`/`TSF_NPC()` (`targetingSearchFilter.script:72-84`) upgraded to safe — live in vanilla combat-critical code (`damageSystem.script:3337` etc.). Note `TSF_EnemyNPC` pre-filters to CURRENTLY-hostile; for catching not-yet-aggroed gang NPCs use `TSF_NPC()`/`GetNPCsAroundObject` and classify script-side. Fallback/backstop channel: `GameInstance.GetEntityList` (`gameInstance.script:106`) — expensive, vanilla iterate+cast precedent `playerDevelopmentSystem.script:3041-3074`.
- **Eligibility — one verified predicate per excluded category** (compose on `ref<NPCPuppet>` cast, which itself excludes the whole Device tree — turrets/cameras):
  | Category | Predicate | Evidence |
  |---|---|---|
  | humanoid combat NPC (include) | `GetNPCType() == gamedataNPCType.Human` (+`IsActive()`; vanilla combo `TargetIsHumanTrashToElite` `NPCPuppet.script:3065-3068`) | `scriptedPuppet.script:1419-1437` |
  | Boss / MaxTac (exclude, always paired) | `IsBoss() \|\| IsMaxTac()` | `scriptedPuppet.script:1640-1666`; vanilla pairs them 10+ sites |
  | police/prevention | `IsCharacterPolice()` (`IsPrevention()` is its alias) | `scriptedPuppet.script:1780-1794,1976-1979` |
  | mech/drone/spiderbot/android | excluded by the Human type check; belt-and-suspenders `IsMechanical()` | `scriptedPuppet.script:1456-1461` |
  | civilian / crowd | `IsCharacterCivilian()`, `IsCrowd()` | `scriptedPuppet.script:1775-1778,1815-1818` |
  | combat-viable gate | `IsEnemy()` = hostile OR (neutral ∧ !civ ∧ !crowd) | `scriptedPuppet.script:2003-2006` |
  | quest/named/unique — NO clean predicate exists | best-effort `TweakDBInterface.GetCharacterRecord(GetRecordID()).Quest().Type() != gamedataNPCQuestAffiliation.General` (`tweakDBRecords.script:3472,6215`; enum `tweakDBEnums.script:4171-4181`). `IsQuest()` is a FOOTGUN (fires on quest-item carriers, `scriptedPuppet.script:3773-3776`) | see Unresolved #2 |
- **Session keying:** `EntityID` (`entityID.script:1-19`; `==` makes `ArrayContains` work). Stable across re-stream within a session; RECYCLED after despawn → FIFO-capped `array<EntityID>` ledgers, cap 4096 (ScannerSuite-proven). One seen-set per roll type + clone registry.
- **RNG:** `RandF() < 0.30` / `< 0.20` (idiom `NPCPuppet.script:893`); `RandRange(0, n)` for pool picks (`rand.script:1-6`).
- **Debug notify:** `GameInstance.GetActivityLogSystem(gi).AddLog(msg)` (`activityLogSystem.script:7`; ScannerSuite-proven HUD one-liner) + `FTLog(msg)` (`testStepLogicImport.script:29`; live non-test call site `worldMap.script:587`). Gate per-feature `DebugNotify` const, default true.

---

## Unresolved — accepted gaps + planner guidance

1. **F2 spawn primitive (the only feature-level blocker).** No further research can move it — remaining unknowns are game-launch-empirical only. Guidance: posture A (descope, safe) or posture B (experimental, front-loaded probe milestone with user manual test). Recommend planning F2 as posture B with the probe as gate and posture A as the documented bail-out; all downstream code is posture-independent.
2. **Quest/named/unique NPC detection.** Best-effort TweakDB `Quest().Type() != General` with unverified coverage. Guidance: use it AND layer the soft heuristic (exclude if rarity already ≥ target concerns, e.g. never touch `IsCrowd()`; uniques are rarely Trash/Weak) — then accept the residual: briefs already scope "everywhere incl. quest encounters," and Boss/MaxTac/police exclusions are hard. State this posture in each plan.
3. **TweakDB literal paths/values are web-sourced** (`NPCRarity.*` paths, per-tier floats, stim radii 30/25/8, district 30/45/20). High-confidence (CDPR-Modding-Documentation + multi-repo). Guidance: first in-game debug pass logs `GetNPCRarityRecord(T"NPCRarity.Elite").RarityValue()` (expect 5.0) via FTLog; null-check every record fetch and no-op gracefully.
4. **StatPool max auto-refresh** unproven → always call `RequestSettingStatPoolMaxValue` after Health-affecting modifiers (vanilla-matching, harmless if redundant).
5. **Modifier compounding arithmetic** native → tune F1's PowerLevel const empirically; debug notify prints before/after `GetStatValue(Health)`.
6. **`RemoveAllItems` → `OnInventoryEmptyEvent` synchronicity** unknown → always pair with `EvaluateLootQualityByTask` and defer the clear out of the wrap per rule 3 (`DelayCallbackNextFrame`).
7. **F2 quest-encounter kill-counters** with an extra hostile: no evidence either way; mitigations = eligibility exclusions + posture choice; verify during manual test.
8. **Informational:** `propagationChange=true` semantics; silenced double-broadcast; `radius=0` native fallback; `GetEntitiesAroundObject` vs `GetEntityList` streaming lag (backstop channel documented). None changes a mechanism choice.
