# Plan — tier-uprank (30% one-tier enemy upgrade)

Owned file: `sprint/impl/custom-enemy-overhaul/EnemyOverhaul.TierUprank.reds`. Module `EnemyOverhaul.TierUprank`. Every API cited below is vanilla-verified in `sprint/vanilla-scripts` (file:line) or in-game-proven by ScannerSuite.reds, per `search_index.md` §F1 + `research/round1-tier-uprank-mechanism.md` + `research/round1-shared-infra.md`. Do not reopen research. ScannerSuite.reds line cites re-anchored 2026-07-17 against the live file (it drifts — anchor by symbol name if numbers moved again).

## Mechanism

**Chosen: stat emulation — per-tier `StatModifier_Record` replay + PowerLevel/Level pairing.** The brief's ideal (literal rarity/record upgrade) is INFEASIBLE — structurally proven, not a search gap: `GetNPCRarity()/GetNPCRarityRecord()/GetRecordID()` are `public import const final` native getters with zero setter/swap counterpart (`puppet.script:95-96,13`), and TweakDB has no write surface (`tweakDB.script`: 1156 lines, all `Get*`). Planning the agreed fallback (brief: "else stat-emulated tier"), which is unusually well-justified: it replays CDPR's OWN per-tier stat blocks through CDPR's OWN application pipeline.

Per-uprank apply recipe (all on the game-thread sweep tick, NOT inside any engine listener — rule 3 does not bite):

1. Current tier: `puppet.GetNPCRarity()` (`puppet.script:95`).
2. Target tier via EXPLICIT ladder table (enum is ALPHABETICAL — `tweakDBEnums.script:3396-3408` — never ordinal math): Trash→Weak→Normal→Rare→Officer→Elite; Elite = ceiling → no-op.
3. Fetch target record: `TweakDBInterface.GetNPCRarityRecord(T"NPCRarity.<Tier>")` (`tweakDB.script:605`). Path strings are web-sourced (index Unresolved #3) → `IsDefined` null-check mandatory.
4. Replay its modifiers — verbatim vanilla device-init pipeline (`scriptableDeviceBasePS.script:535-554`): `rec.StatModifiers(out list)` (`tweakDBRecords.script:6225`) → per entry `RPGManager.StatRecordToModifier(entry)` (`rpgManager.script:1659-1696`) → one `StatsSystem.AddModifiers(id, mods)` (`statsSystem.script:39`).
5. PLUS PowerLevel pairing — load-bearing, not optional: `DamageSystem.ScalePlayerDamage` (`damageSystem.script:3468-3502`) algebraically cancels a bare Health bump for player-sourced damage (denominator anchored to frozen rarity + current PowerLevel). Apply `RPGManager.CreateStatModifier(gamedataStatType.PowerLevel, gameStatModifierType.Additive, PowerLevelBump())` + same for `gamedataStatType.Level` with `LevelBump()` (`rpgManager.script:1612`; pattern `NPCManager.ScaleToPlayer`, `npcManager.script:107-121`; enum members `tweakDBEnums.script:1503,1300`; `gameStatModifierType.Additive` `statsData.script:9-16`). Each via plain `AddModifier` (`statsSystem.script:38`).
6. Health pool re-sync — treat as REQUIRED (index Unresolved #4): `GameInstance.GetStatPoolsSystem(game).RequestSettingStatPoolMaxValue(id, gamedataStatPoolType.Health, puppet)` (`statPoolsSystem.script:50`). Preserve damage fraction: read `pctBefore = GetStatPoolValue(id, Health, true)` (`statPoolsSystem.script:40`) BEFORE applying modifiers, then `RequestSettingStatPoolValue(id, Health, pctBefore, puppet, true)` (`statPoolsSystem.script:51`) after the max re-sync. **Percentage scale is 0–100, not 0–1**: vanilla full-heal passes `100.0` (`NPCPuppet.script:3930`). Read+write in the same scale; never mix.
7. `AddModifier`/`AddModifiers` ONLY — NEVER `AddSavedModifier` (persists across reload while the session seen-set resets → fresh roll stacks a second block; dossier F13, ~70 vanilla call sites are all item/permanent-buff persistence).

**Fallback ladder (failure → rung):**
- (a) PRIMARY: replay + PowerLevel/Level pairing (above).
- (b) `GetNPCRarityRecord` returns null at runtime (web-sourced path wrong) → DEGRADE PER-ENTITY, AUTOMATICALLY: skip the replay, still apply the PowerLevel/Level bump (coarser; cascades Health/Level/DPS via the PowerLevel-keyed `NPC_Base_Curves`), and debug-log `"MISSING <path>"`. This is rung (b) built into the code path, not a rewrite. The arm-time probe (Debug section) surfaces it on first session.
- (c) Rungs (a)+(b) both compile but produce no felt difference in-game → tune `PowerLevelBump` upward (empirical knob, index Unresolved #5) before considering hand-tuned flat multipliers (last resort; contradicts "justified from game data" — requires user sign-off).
- Literal record swap is NOT a rung — it does not exist.

**Known arithmetic caveat (accepted):** the replayed target block stacks ON TOP of the NPC's spawn-applied source block (no way to remove just the tier block; `RemoveAllModifiers` would strip vanilla base curves too — forbidden). Net Health on Trash→Weak ≈ trash_col × weak_col, not weak_col alone; Armor Rare→Officer ≈ 1.15×1.15. Deltas are therefore approximate; native compounding is invisible to script (dossier Open Q1). The debug notify prints before/after `GetStatValue(id, gamedataStatType.Health)` (`statsSystem.script:34`) so actuals are observable, and `PowerLevelBump` is the tuning knob. Also accepted: Officer inherits Rare's whole stat block (web table), so the Rare→Officer rung's replay is a near-no-op — the PowerLevel pairing carries that rung.

## Architecture

All inside `EnemyOverhaul.TierUprank.reds`:

- `module EnemyOverhaul.TierUprank` + `import EnemyOverhaul.Common.*` (only if consuming Common — drop the import if fully local-fallback).
- `public class TierUprankConfig` — USER CONFIG block: public static funcs returning literals (ScannerSuiteConfig pattern, in-game-proven).
- `public class EOUprankTickCallback extends DelayCallback { public let hud: wref<HUDManager>; public func Call() }` → calls `this.hud.EOUprank_Tick()` (base class `delaySystem.script:41-44`; shape = ScannerSuite `STSweepTickCallback`, ScannerSuite.reds:1372-1381).
- `@addField(HUDManager) let m_eoUprankArmed: Bool;` — double-arm guard (precedent `m_stSweepArmed`, ScannerSuite.reds:1385-1386). HUDManager is the state host because it is a session-stable ScriptableSystem (`hudManager.script:174`, extends ScriptableSystem `:162`) that survives replacer PlayerPuppet swaps — fields on PlayerPuppet would reset mid-session; ScannerSuite proved this host through months of iteration.
- `@addMethod(HUDManager) EOUprank_Arm() -> Void` — guard + schedule first tick.
- `@addMethod(HUDManager) EOUprank_Tick() -> Void` — the sweep (Lifecycle below).
- `@addMethod(HUDManager) EOUprank_ProcessOnce(puppet: ref<NPCPuppet>) -> Void` — per-candidate gates + roll + apply.
- Pure helper funcs (module-level or @addMethod, implementer's call): `EOUprank_TargetPath(current: gamedataNPCRarity) -> TweakDBID` returning `TDBID.None()` for no-target (decl `tweakDBID.script:8`; usage `gameObject.script:754`; check via `TDBID.IsValid`, decl `tweakDBID.script:4`, usage `widgetController.script:441`), + a tier-name helper for debug strings. Enum compares in modern dialect use `Equals()/NotEquals()` (ScannerSuite.reds:1362 precedent).
- `@wrapMethod(PlayerPuppet) protected cb func OnGameAttached() -> Bool` — arm point (`player.script:1161`; ScannerSuite.reds:2047-2073 wraps the same method; wraps chain, each calls `wrappedMethod` exactly once and preserves the returned Bool). Resolve host via `this.GetHudManager()` (`gameObject.script:3183`), `IsDefined`-guarded.

**Common APIs consumed** (from `EnemyOverhaul.Common`; per environment rule, if Common lacks any of these, implement the same shape LOCALLY in this file with `EOTU_`-prefixed names and flag it in implementer notes — never edit Common):
1. `EO_IsEligibleCombatHuman(puppet: ref<NPCPuppet>) -> Bool` — shared eligibility filter (exact composition in Exclusions; shared with enemy-duplication per brief).
2. `EO_UprankTrySpend(id: EntityID) -> Bool` — tier-uprank's once-per-session roll ledger: atomic contains+append, FIFO cap 4096, hosted on a session-stable object; returns true only on first visit (entry spent now). Split pair (`EO_UprankAlreadyRolled`/`EO_UprankMarkRolled`) equally acceptable.
3. `EO_Notify(game: GameInstance, msg: String) -> Void` — `GameInstance.GetActivityLogSystem(game).AddLog(msg)` (`gameInstance.script:10`, `activityLogSystem.script:7`) + `FTLog(msg)` (`testStepLogicImport.script:29`; non-test precedent `worldMap.script:587`). Caller gates on its own `DebugNotify()`.
4. Optional: `EO_SweepGateOK(hud: ref<HUDManager>) -> Bool` — replacer/braindance skip (`IsReplacer` `gameObject.script:1731`/`player.script:582`; `IsBraindanceActive` `hudManager.script:615`). Trivial to inline locally if absent.

## Lifecycle

- **Arm:** `PlayerPuppet.OnGameAttached` wrap (game thread, once per load) → `wrappedMethod()` first → if `EnableTierUprank()`: `GetHudManager()` → `EOUprank_Arm()`. Arm sets `m_eoUprankArmed`, schedules `EOUprankTickCallback` via `GameInstance.GetDelaySystem(gi).DelayCallback(tick, FirstTickDelay(), false)` (`delaySystem.script:59`, `gameInstance.script:21`). Double-arm guard makes replacer re-attach a no-op.
- **Tick (`EOUprank_Tick`):** (1) defensive stop: `!EnableTierUprank()` → clear armed flag, return — the ONLY permanent stop. (2) RE-ARM FIRST, before any work, at `SweepInterval()` (fault-proof re-arm, ScannerSuite.reds:1437-1448). (3) skip-but-stay-alive gate: player from `this.GetPlayer() as PlayerPuppet` (`hudManager.script:1803`); `!IsDefined(player) || player.IsReplacer() || this.IsBraindanceActive()` → return (same gate ScannerSuite.reds:1448). (4) enumerate.
- **Detect-new:** `player.GetNPCsAroundObject(SweepRange())` (`gameObject.script:967-987`; `TargetingSet.Complete` = 360°, camera-independent; backed by `TSF_NPC()` so NOT-YET-HOSTILE gang NPCs are included — `TSF_EnemyNPC` would pre-filter to currently-hostile and miss them). A just-streamed NPC missed this tick is caught next tick (no loss; index Unresolved #8). `for`-loop; skip candidates with if-wrappers (NO `continue`/`break`).
- **Per candidate (`EOUprank_ProcessOnce`):** ordered gates —
  1. `id = puppet.GetEntityID()`; already spent (`EO_UprankTrySpend` peek or `AlreadyRolled`) → skip. Cheapest gate first.
  2. Eligibility `EO_IsEligibleCombatHuman(puppet)` → false = skip WITHOUT spending (ScannerSuite "non-whitelisted spends nothing" rule: a transient `IsActive()` miss during stream-in retries next tick; category flags are record-static so nothing eligible ever flips to double-roll).
  3. **Spend the ledger entry NOW** — this is the exactly-once point; everything below runs at most once per entity per session.
  4. Ladder: `EOUprank_TargetPath(puppet.GetNPCRarity())`; `!TDBID.IsValid(target)` (Elite ceiling, or defensive default for Boss/MaxTac/Count/Invalid) → return silently.
  5. Roll: `RandF() < UprankChance()` (`rand.script:3`; idiom `rpgManager.script:893` `RandF() < 0.89999998`; a literal vanilla 30% roll: `NPCPuppet.script:2886` `RandF() < 0.30000001`) → fail = return. Roll happens ONCE ever per entity (ledger spent above); re-stream re-rolls impossible.
  6. Apply: Mechanism steps 3-6 (read `pctBefore` + `hpBefore` first; replay if record defined, else rung (b); PowerLevel/Level bump; max re-sync; pct restore).
  7. Mark/notify: if `DebugNotify()`: `EO_Notify(game, "EO uprank: <GetDisplayName()> [<EntityID.ToDebugString(id)>] <Old>-><New> hp <hpBefore>-><hpAfter>")` (`gameObject.script:442`; `entityID.script:1-19`).
- **Keying (exact):** `EntityID` from `GetEntityID()`; `==` operator makes `ArrayContains` work (`entityID.script:1-19`). Stable across re-stream within a session (ScannerSuite.reds:895) — satisfies "re-stream must not re-roll/stack". Recycled after despawn (ScannerSuite.reds:1698-1703) → FIFO cap 4096 ages entries out (worst case: a fresh NPC inheriting a retired ID silently skips its roll — accepted, ScannerSuite-proven tradeoff). Save/reload: plain modifiers do not persist and the in-memory ledger resets → clean fresh roll, no stacking (brief: accepted).
- **F2 clones:** NO special-casing in this file. Clones enter via the same enumeration, pass the same eligibility (human, hostile), get the same single roll — which the brief mandates as their only roll. The ledger alone guarantees exactly-once. This file never reads the clone registry.

## Constants — USER CONFIG block (top of file, clearly marked)

| Name | Default | Meaning |
|---|---|---|
| `EnableTierUprank()` | `true` | Master toggle; false = loop never arms (and tick self-stops defensively). |
| `UprankChance()` | `0.30` | The 30% — per-entity once-only upgrade probability. |
| `SweepInterval()` | `0.5` | Steady sweep cadence, seconds (sane range 0.5–1.0). |
| `FirstTickDelay()` | `1.0` | Delay of first tick after player attach, seconds. |
| `SweepRange()` | `50.0` | Enumeration radius around player, meters. |
| `PowerLevelBump()` | `2.0` | Additive PowerLevel pairing per uprank (anti self-cancel vs `ScalePlayerDamage`); `0.0` disables. THE empirical tuning knob. |
| `LevelBump()` | `2.0` | Additive Level pairing per uprank (mirrors `ScaleToPlayer` pairing); `0.0` disables. |
| `SeenCap()` | `4096` | FIFO cap of the roll ledger (used by the local-fallback ledger; Common's ledger carries its own cap). |
| `DebugNotify()` | `true` | HUD one-liner + FTLog on each uprank + arm-time record probe. |

## Exclusions — one VERIFIED predicate per category

Composed on `ref<NPCPuppet>` (enumeration already returns `NPCPuppet`, which structurally excludes the whole Device tree — turrets/cameras/sensors, `gameObject.script:1766-1779`, `sensorDevice.script:155`, `surveillanceCamera.script:33`, `glitchedTurret.script:1`). Order cheap cached checks first; the TweakDB quest fetch LAST (only cost-bearing check; crowd/civ NPCs never reach it).

| Category (brief) | Predicate | Evidence |
|---|---|---|
| humanoid combat NPC (INCLUDE gate) | `Equals(puppet.GetNPCType(), gamedataNPCType.Human)` + `puppet.IsActive()` | `scriptedPuppet.script:1419-1422,1955`; vanilla combo `TargetIsHumanTrashToElite` `NPCPuppet.script:3065-3068` |
| combat-viable (INCLUDE gate; excludes friendlies) | `puppet.IsEnemy()` = hostile OR (neutral ∧ !civ ∧ !crowd) | `scriptedPuppet.script:2003-2006` |
| Boss + MaxTac (always paired, vanilla pairs them 10+ sites) | `puppet.IsBoss() \|\| puppet.IsMaxTac()` → exclude | `scriptedPuppet.script:1640-1666`; pairing e.g. `NPCPuppet.script:448,840,2655` |
| police/prevention | `puppet.IsCharacterPolice()` → exclude (`IsPrevention()` is its literal alias) | `scriptedPuppet.script:1780-1794,1976-1979` |
| mech/drone/spiderbot/android/robot | excluded by the Human type check; belt-and-suspenders `!puppet.IsMechanical()` | `scriptedPuppet.script:1456-1461` |
| civilian / crowd | `!puppet.IsCharacterCivilian()` ∧ `!puppet.IsCrowd()` | `scriptedPuppet.script:1775-1778,1815-1818` |
| quest/named/scripted-unique — NO clean predicate exists (index Unresolved #2) | best-effort: `TweakDBInterface.GetCharacterRecord(puppet.GetRecordID()).Quest().Type() != gamedataNPCQuestAffiliation.General` → exclude; null-safe (missing record or Quest handle ⇒ treat as General = eligible) | `tweakDB.script:371`; `tweakDBRecords.script:3472,6215-6220`; enum `tweakDBEnums.script:4171-4181` |
| already-max-tier (Elite) — ceiling, not a filter | ladder returns `TDBID.None()` for Elite (and defensively for Boss/MaxTac/Count/Invalid) | brief ladder decision; `TDBID.None()` `gameObject.script:754` |

**Stated posture on quest/named (binding for implementer):** use the best-effort TweakDB check AND accept the residual both ways — a hand-placed unique left at `General` may occasionally uprank; a generic side-quest mook whose record carries a quest affiliation may be skipped. Brief scopes "everywhere incl. quest encounters"; Boss/MaxTac/police exclusions are the hard ones. Never use `IsQuest()` — footgun: fires on any puppet merely carrying a quest item (`scriptedPuppet.script:3773-3776`).

## What NOT to do

Global (absolute): no `continue`/`break` (if-wrapper skips only); no per-entity `GameObject.OnGameAttached` hook of any kind (worker threads → heap corruption; ONLY the `PlayerPuppet` wrap); no TweakDB writes (none exist); no game launch; compile only via `sprint/bin/scc-serial.sh`; edit ONLY `EnemyOverhaul.TierUprank.reds`; prefer `@wrapMethod` — this feature needs NO `@replaceMethod` at all.

Feature-specific forbiddens:
- NEVER `AddSavedModifier` — reload double-stack hazard (dossier F13).
- NEVER `RemoveAllModifiers` on an NPC — strips vanilla spawn/base-curve modifiers wholesale; the `ScaleToPlayer` remove is for its own scheme, do not mirror it.
- NEVER ordinal math on `gamedataNPCRarity` (alphabetical enum) — explicit ladder switch only.
- NEVER `RPGManager.GetRarityMultiplier` for the TARGET tier — hard-locked to the puppet's own frozen rarity (`rpgManager.script:262`); use `GetValueFromCurve`/record replay instead.
- NEVER write `gamedataStatType.NPCRarity` — proven cosmetic dead end (dossier F4/F9).
- NO reward tampering: no `AwardsExperience`/bounty/loot/XP/`DisableKillReward` code in this file (brief: rewards natural; reward suppression is F2's business for clones only).
- NO ledger-entry removal, no second roll path, no stacking: one spend point, one roll, one apply — ever.
- NO clone special-casing (no clone-registry reads here).
- Do NOT expect or code around a nameplate badge change — badge/XP-tier/anti-Elite perks all read the frozen `GetNPCRarity()` (dossier F3); the uprank is numeric toughness only.
- Do NOT mix stat-pool percentage scales — perc API is 0–100 (`NPCPuppet.script:3930`).

## Debug & manual-verification hooks

- **Per-uprank notify** (gated `DebugNotify()`, via `EO_Notify`): `"EO uprank: <name> [<id>] <OldTier>-><NewTier> hp <before>-><after>"` — name `GetDisplayName()` (`gameObject.script:442`), id `EntityID.ToDebugString` (`entityID.script`), hp via `GetStatValue(id, gamedataStatType.Health)` before/after apply. Delivers the brief's "who, old tier → new tier" and surfaces actual compounding results (Risks 2/3). `hpAfter` read immediately after apply is informational — native recompute timing unproven; if it reads unchanged, that alone is not a failure.
- **Arm-time ladder probe** (gated `DebugNotify()`, one-shot at arm or first tick): for each ladder path fetch `GetNPCRarityRecord(path)` and `FTLog` `path + " rarityValue=" + RarityValue()` or `"MISSING <path>"` if null (`tweakDBRecords.script:6231`). Expected (web table): Weak 2.0, Normal 3.0, Rare 4.0, Officer 4.5, Elite 5.0. Converts index Unresolved #3 into a first-session-log fact and announces rung-(b) degradation immediately.
- Manual verification plan lives in `acceptance-tier-uprank.md` (M-items) — keyed to notifies, healthbar magnitude, TTK, and exclusion silence; NOT to badges.

## Risks — residual unknowns + how the implementer surfaces them

1. **Web-sourced `NPCRarity.*` paths** (index Unresolved #3): null-check every fetch; arm-time probe FTLogs values/misses; per-entity auto-degrade to rung (b) keeps the feature alive.
2. **Native modifier compounding** (index Unresolved #5): replayed block stacks on the source block → approximate deltas (incl. trash×weak undershoot, armor overshoot). Surface: before/after HP in every notify. Knob: `PowerLevelBump`.
3. **`ScalePlayerDamage` compensation** partially eats Health-only gains: mitigated by design (PowerLevel pairing); if upranked enemies still melt, raise `PowerLevelBump` — do not add bare Health multipliers.
4. **Rare→Officer rung reads weak** (Officer inherits Rare's block): expected; the PL/Level pairing carries that rung. Acceptance wording accounts for it.
5. **StatPool max auto-refresh unproven** (index Unresolved #4): always call `RequestSettingStatPoolMaxValue` + pct restore; harmless if redundant.
6. **Quest-affiliation coverage unverified** (index Unresolved #2): posture stated in Exclusions; manual test M8 observes it; a residual uprank on a non-boss named NPC is logged, accepted, not a defect.
7. **`GetNPCsAroundObject` streaming lag** (index Unresolved #8): self-healing at 0.5 s cadence; `GameInstance.GetEntityList` (`gameInstance.script:106`) stays available as a documented backstop channel if live testing shows systematic misses — do NOT add it preemptively.
8. **Common API drift**: if the consolidated Common signatures differ from §Architecture's expectations, adapt call sites; if a helper is missing entirely, implement the same-shape local fallback (`EOTU_` prefix) and flag it in notes.
