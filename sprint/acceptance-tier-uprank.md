# Acceptance — tier-uprank (30% one-tier enemy upgrade)

Target file: `sprint/impl/custom-enemy-overhaul/EnemyOverhaul.TierUprank.reds`. Static items are verifiable by reading the file, running `sprint/bin/scc-serial.sh`, and grepping `sprint/vanilla-scripts` — never by launching the game. Manual items are user-run only.

## Static checklist (reviewer-verifiable against code/compile/greps ONLY — no game launch)

Compile & scope
- [x] S1 `sprint/bin/scc-serial.sh` exits 0 and prints "Output successfully saved" with `EnemyOverhaul.TierUprank.reds` present in `sprint/impl/custom-enemy-overhaul/`.
- [x] S2 File opens with `module EnemyOverhaul.TierUprank` (plus `import EnemyOverhaul.Common.*` only if a Common symbol is actually consumed).
- [x] S3 The implementation touched ONLY `EnemyOverhaul.TierUprank.reds` — no edits to `EnemyOverhaul.Common.reds`, other feature files, or any other repo file (verify via `git status`/diff scope).

USER CONFIG block
- [x] S4 A clearly-marked USER CONFIG block sits at the top of the file and contains exactly these consts with exactly these defaults: `EnableTierUprank()=true`, `UprankChance()=0.30`, `SweepInterval()=0.5`, `FirstTickDelay()=1.0`, `SweepRange()=50.0`, `PowerLevelBump()=2.0`, `LevelBump()=2.0`, `SeenCap()=4096`, `DebugNotify()=true`.
- [x] S5 `UprankChance()` is consumed by exactly ONE roll site, of shape `RandF() < ...UprankChance()`; no other probability roll exists in the file.

Exactly-once semantics
- [x] S6 One ledger keyed by `EntityID` (`array<EntityID>` + `ArrayContains`), ONE spend point; the spend precedes the ladder lookup, the roll, and the apply in `EOUprank_ProcessOnce` (or equivalent).
- [x] S7 A candidate already present in the ledger is skipped BEFORE any roll/apply — no code path rolls or applies for an already-spent `EntityID` (once per entity per session).
- [x] S8 No refund path: the uprank ledger has no `ArrayErase`/removal except FIFO-cap eviction; roll failure and Elite-ceiling no-op both leave the entry spent.
- [x] S9 Eligibility failure does NOT spend the ledger entry (skip without marking — transient `IsActive()` misses retry next tick).
- [x] S10 Ledger is FIFO-capped at `SeenCap()` (4096): push + oldest-entry eviction present (locally or via Common's capped ledger).

Ladder & mechanism
- [x] S11 Ladder is an explicit switch/if table mapping exactly Trash→Weak, Weak→Normal, Normal→Rare, Rare→Officer, Officer→Elite; Elite and every other enum value (Boss, MaxTac, Count, Invalid) yield the no-target sentinel (`TDBID.None()` / `!TDBID.IsValid`).
- [x] S12 No ordinal/arithmetic operation on `gamedataNPCRarity` anywhere (no `Cast`, `EnumInt`, `+1`, comparison operators on the enum — `Equals`/`NotEquals`/switch only; enum is alphabetical, `tweakDBEnums.script:3396-3408`).
- [x] S13 Apply pipeline present and ordered: `TweakDBInterface.GetNPCRarityRecord(target)` result `IsDefined`-checked → if defined, `StatModifiers(out ...)` → `RPGManager.StatRecordToModifier(...)` per entry → single `StatsSystem.AddModifiers(...)`; if null, replay skipped but PowerLevel/Level bump still applied + a "MISSING <path>" debug log (rung-b degradation).
- [x] S14 PowerLevel/Level pairing present: `RPGManager.CreateStatModifier(gamedataStatType.PowerLevel, gameStatModifierType.Additive, ...PowerLevelBump())` and same for `gamedataStatType.Level` with `LevelBump()`, each applied via plain `AddModifier`.
- [x] S15 Health pool re-sync after all stat modifiers: `RequestSettingStatPoolMaxValue(id, gamedataStatPoolType.Health, ...)` present; damage-fraction preservation reads `GetStatPoolValue(..., true)` BEFORE modifiers and restores after via `RequestSettingStatPoolValue(..., pctBefore, ..., true)` — read and write in the SAME 0–100 percentage scale (no ×100/÷100 conversion anywhere; vanilla full-heal passes `100.0`, `NPCPuppet.script:3930`).
- [x] S16 `AddSavedModifier` does NOT appear in the file (reload double-stack hazard).
- [x] S17 `RemoveAllModifiers` does NOT appear in the file (would strip vanilla base curves).

Exclusions (each predicate present & correct, composed on `ref<NPCPuppet>`)
- [x] S18 Include gate: `Equals(puppet.GetNPCType(), gamedataNPCType.Human)` AND `puppet.IsActive()` AND `puppet.IsEnemy()` all required before spending.
- [x] S19 Boss+MaxTac excluded as a PAIR: `puppet.IsBoss() || puppet.IsMaxTac()` → skip.
- [x] S20 Police excluded: `puppet.IsCharacterPolice()` → skip.
- [x] S21 Mech/drone/robot/android excluded: the Human type check plus belt-and-suspenders `!puppet.IsMechanical()`.
- [x] S22 Civilian/crowd excluded: `!puppet.IsCharacterCivilian() && !puppet.IsCrowd()`.
- [x] S23 Quest/named best-effort: `TweakDBInterface.GetCharacterRecord(puppet.GetRecordID()).Quest().Type() != gamedataNPCQuestAffiliation.General` → skip, with null-safe handling (null record or null `Quest()` handle ⇒ treated as General = eligible); `IsQuest()` does NOT appear anywhere in the file (quest-item-carrier footgun).
- [x] S24 These checks may live in Common's `EO_IsEligibleCombatHuman` instead of locally — then S18–S23 are verified against Common's implementation and this file calls it; any missing piece is implemented locally in THIS file (never by editing Common).

Loop & threading safety
- [x] S25 Exactly one `@wrapMethod(PlayerPuppet) protected cb func OnGameAttached()` in the file; it calls `wrappedMethod()` exactly once, preserves/returns its `Bool`, and does nothing beyond resolving `GetHudManager()` and arming (no stat mutation inside the wrap).
- [x] S26 Grep for `OnGameAttached` in the file yields ONLY that PlayerPuppet wrap — no `GameObject`/`ScriptedPuppet`/`NPCPuppet` `OnGameAttached` hook of any kind (worker-thread heap-corruption rule).
- [x] S27 Arm is guarded by an `@addField(HUDManager)` Bool double-arm guard (replacer re-attach = no-op); all mutable state lives on HUDManager (or module-local class), none on PlayerPuppet.
- [x] S28 Tick re-arms FIRST — the successor `DelayCallback(...)` is scheduled before any enumeration/processing work; the only non-re-arming path is `!EnableTierUprank()`.
- [x] S29 Skip-but-stay-alive gate present: `!IsDefined(player) || player.IsReplacer() || this.IsBraindanceActive()` → return (after re-arm).
- [x] S30 Enumeration = `player.GetNPCsAroundObject(SweepRange())` (or `GetEntitiesAroundObject` with `TSF_NPC()`); `TSF_EnemyNPC` does NOT appear (would pre-filter to currently-hostile and miss un-aggroed gangs).

Forbidden patterns & purity
- [x] S31 No `continue` and no `break` keywords anywhere in the file (if-wrapper skips only).
- [x] S32 No TweakDB writes (no `SetFlat`/`CreateRecord`/`TweakDBManager` — reads via `TweakDBInterface.Get*` only) and no `@replaceMethod` (wrap/add only).
- [x] S33 No reward tampering: `AwardsExperience`, `DisableKillReward`, `RemoveAllItems`, `EvaluateLootQualityByTask`, bounty/loot APIs do NOT appear in this file (rewards stay natural at the frozen tier).
- [x] S34 No clone special-casing: no clone-registry read (`IsClone`/registry API) in this file — F2 clones flow through the identical gates and get their single roll via the same ledger.
- [x] S35 Verified-API-only spot-check: pick ≥3 engine APIs used in the file at random; each must be declared in `sprint/vanilla-scripts` at (approximately) the plan's cited file:line, or be an in-game-proven ScannerSuite call — zero APIs outside the plan/dossier inventories.

Debug wiring
- [x] S36 Every notify site is gated by `DebugNotify()` and emits BOTH `GameInstance.GetActivityLogSystem(...).AddLog(...)` and `FTLog(...)` (directly or via Common `EO_Notify`).
- [x] S37 Per-uprank notify message contains: NPC display name, `EntityID` debug string, old tier → new tier, and hp before → after (`GetStatValue(id, gamedataStatType.Health)` read before and after apply).
- [x] S38 One-shot arm-time (or first-tick) ladder probe present, gated by `DebugNotify()`: fetches each ladder target path via `GetNPCRarityRecord` and FTLogs `RarityValue()` (expected Weak 2.0, Normal 3.0, Rare 4.0, Officer 4.5, Elite 5.0) or `"MISSING <path>"` when null.

## Manual in-game test plan (user-run; the reviewer NEVER ticks these)

- [ ] M1 **Path probe.** Load any save with `DebugNotify=true`. Within seconds of spawn, the log/HUD shows the 5 ladder-probe lines with rarityValues 2.0 / 3.0 / 4.0 / 4.5 / 5.0. Any `MISSING` line = web-sourced path wrong → report the exact path string (feature keeps running in rung-b PowerLevel-only mode).
- [ ] M2 **~30% hit rate.** Enter a street/gang area with ~10 low-tier hostiles (e.g. a Watson gang hangout). Expect roughly 3 uprank notifies (binomial spread 1–6 of 10 is normal), each naming the NPC, old→new tier, and an hp before→after jump.
- [ ] M3 **Felt power jump, not badge.** Fight one notified enemy and one non-notified same-pack enemy: the upranked one shows a larger health pool and survives noticeably longer. Its nameplate badge does NOT change — that is EXPECTED (badge reads the frozen rarity); a missing badge change is not a failure. Note: Rare→Officer upranks read weaker than other rungs (Officer inherits Rare's stat block; the PowerLevel/Level bump carries that rung).
- [ ] M4 **No re-roll on re-stream.** After notifies fire, walk ~100 m away (out of `SweepRange`) and return to the same group: NO second notify for the same NPCs, and no further hp growth (no stacking).
- [ ] M5 **Exclusions silent — police/MaxTac.** Provoke a wanted level: police and MaxTac units produce ZERO uprank notifies.
- [ ] M6 **Exclusions silent — non-humans & civilians.** Around drones/mechs/turrets/robots and civilian crowds: ZERO uprank notifies.
- [ ] M7 **Exclusions silent — boss.** In any boss encounter: ZERO uprank notify for the boss (generic human adds in the arena MAY uprank — allowed).
- [ ] M8 **Quest encounters.** During a quest firefight: generic quest mooks may uprank (in-scope by design). If a clearly named/unique non-boss NPC ever gets a notify, log who — accepted residual of the best-effort quest filter, report for posture review, not a defect.
- [ ] M9 **Save/reload.** Reload a save where upranks had fired: buffs are gone and fresh rolls may occur (accepted per brief). Verify no double-height hp (no stacking of an old buff under a new one) on any single enemy.
- [ ] M10 **F2 clones (only if duplication is active).** Spawned clones occasionally receive their own single uprank notify — exactly one roll each, never more.
- [ ] M11 **Tuning knob.** If upranked enemies do NOT feel tougher vs your own damage (ScalePlayerDamage compensation), raise `PowerLevelBump` to 3.0–4.0, recompile via `sprint/bin/scc-serial.sh`, retest M3. Do not add bare Health multipliers.
- [ ] M12 **Toggle check (optional).** With `DebugNotify=false`: no HUD/log lines while fights still show the M3 power jump. With `EnableTierUprank=false`: no upranks and no loop activity at all.
