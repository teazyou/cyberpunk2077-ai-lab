# Acceptance — Common (`EnemyOverhaul.Common.reds` shared infrastructure)

Target file: `sprint/impl/custom-enemy-overhaul/EnemyOverhaul.Common.reds`. Plan: `sprint/plan-common.md`. Static items are verifiable by reading the file, running `sprint/bin/scc-serial.sh`, and grepping `sprint/vanilla-scripts` / `sprint/staging` — never by launching the game. If any fallback rung from the plan's ladder was taken, the implementer notes MUST name it and the reviewer verifies the documented substitute shape instead of the primary (S25).

## Static checklist (reviewer-verifiable against code/compile/greps ONLY — no game launch)

Compile & scope
- [x] S1 `sprint/bin/scc-serial.sh` exits 0 and prints "Output successfully saved" with `EnemyOverhaul.Common.reds` present in `sprint/impl/custom-enemy-overhaul/`.
- [x] S2 File opens with `module EnemyOverhaul.Common` and contains ZERO `import` statements (grep `^import` → no hits) — acyclic by construction; in particular no reference to `EnemyOverhaul.TierUprank`, `EnemyOverhaul.Duplication`, or `EnemyOverhaul.AggroRange` anywhere in the file.
- [x] S3 The implementation touched ONLY `EnemyOverhaul.Common.reds`; the transient `EnemyOverhaul.SmokeProbe.reds` is DELETED (absent from `sprint/impl/custom-enemy-overhaul/` and from `sprint/staging/r6/scripts/custom-enemy-overhaul/` after the final compile); no edits to feature files, ScannerSuite, or any other repo/game file (verify via `git status`/diff scope).

USER CONFIG
- [x] S4 A clearly-marked USER CONFIG block sits at the top of the file containing `public abstract class EOCommonConfig` with EXACTLY ONE const: `LedgerCap() -> Int32` returning `4096`.
- [x] S5 No `DebugNotify`-style const exists anywhere in Common (notify gating is caller-owned), and no sweep/interval/range/chance consts exist (Common owns no loop and no rolls).

Public API surface — must match plan-common EXACTLY (names, params, returns; nothing extra)
- [x] S6 Seven module-level `public static func`s exist with exactly these signatures: `EO_IsEligibleCombatHuman(puppet: ref<NPCPuppet>) -> Bool`; `EO_Notify(game: GameInstance, msg: String) -> Void`; `EO_SweepGateOK(hud: ref<HUDManager>) -> Bool`; `EO_SeenContains(seen: script_ref<array<EntityID>>, id: EntityID) -> Bool`; `EO_SeenTryAdd(seen: script_ref<array<EntityID>>, id: EntityID, cap: Int32) -> Bool`; `EO_IsClone(game: GameInstance, id: EntityID) -> Bool`; `EO_MarkClone(game: GameInstance, id: EntityID) -> Void`.
- [x] S7 Five `@addMethod(HUDManager) public final func`s exist with exactly these signatures: `EO_UprankAlreadyRolled(id: EntityID) -> Bool`; `EO_UprankMarkRolled(id: EntityID) -> Void`; `EO_UprankTrySpend(id: EntityID) -> Bool`; `EO_CloneRegContains(id: EntityID) -> Bool`; `EO_CloneRegMark(id: EntityID) -> Void`.
- [x] S8 Exactly two `@addField(HUDManager)` declarations exist: `m_eoUprankRolled: array<EntityID>` and `m_eoCloneReg: array<EntityID>`; no `@addField` on any other class (especially NOT PlayerPuppet — session-stability requirement); no `persistent` keyword anywhere.
- [x] S9 NO other public symbol exists in the file beyond S4/S6/S7 (+ optional non-public module-internal helpers) — the surface table in plan-common is exhaustive.

Eligibility composite (`EO_IsEligibleCombatHuman`)
- [x] S10 Contains ALL of, and returns false on failure of: `IsDefined(puppet)`; `Equals(puppet.GetNPCType(), gamedataNPCType.Human)`; `puppet.IsActive()`; `puppet.IsEnemy()`; then excludes on `puppet.IsBoss() || puppet.IsMaxTac()` (paired in one condition); `puppet.IsCharacterPolice()`; `puppet.IsMechanical()`; `puppet.IsCharacterCivilian() || puppet.IsCrowd()`.
- [x] S11 The quest-affiliation check is the LAST check in the composite (nothing but `return true` after it), reads `TweakDBInterface.GetCharacterRecord(puppet.GetRecordID())` then `.Quest()` then `.Type()`, excludes only when the type `NotEquals ... gamedataNPCQuestAffiliation.General`, and is null-safe with ELIGIBLE-on-null semantics: `!IsDefined(record)` falls through to `return true`, `!IsDefined(questRec)` falls through to `return true`.
- [x] S12 `IsQuest(` appears NOWHERE in the file (quest-item-carrier footgun).
- [x] S13 The composite performs NO clone-registry read: neither `m_eoCloneReg` nor `EO_CloneRegContains` nor `EO_IsClone` is referenced inside `EO_IsEligibleCombatHuman` (F2-marked clones must stay eligible for their single F1 roll).

Ledgers — exactly-once safety
- [x] S14 Both Mark methods follow the ScannerSuite FIFO shape: `ArrayContains` guard → `ArrayPush` → evict oldest via `ArrayErase(<array>, 0)` only when `ArraySize > EOCommonConfig.LedgerCap()`.
- [x] S15 `ArrayErase` appears in the file ONLY in those two eviction sites — no un-roll/un-mark/removal API of any kind exists on either ledger (roll failure, Elite ceiling, clone death etc. can never refund an entry from Common's side).
- [x] S16 `EO_UprankTrySpend` is atomic contains+append: returns `false` when `EO_UprankAlreadyRolled(id)`, else calls `EO_UprankMarkRolled(id)` and returns `true`; no other code path writes `m_eoUprankRolled`.
- [x] S17 `EO_SeenTryAdd` returns `false` on duplicate without modifying the array; on add, pushes then evicts index 0 only when size exceeds the CALLER-supplied `cap`; `EO_SeenContains`/`EO_SeenTryAdd` bodies access the parameter via `Deref(seen)` (or, under documented rung 2, use `out seen: array<EntityID>` accessing it directly).

Clone registry free functions (const-context contract)
- [x] S18 `EO_IsClone` and `EO_MarkClone` resolve the host EXACTLY via `GameInstance.GetScriptableSystemsContainer(game).Get(n"HUDManager") as HUDManager` with an `IsDefined` guard; `EO_IsClone` returns `false` on null hud; `EO_MarkClone` no-ops on null hud; both bodies contain ZERO `this` usage (const-callable at any call site by construction).
- [x] S19 `EO_Notify` body is exactly the unconditional pair `GameInstance.GetActivityLogSystem(game).AddLog(msg)` + `FTLog(msg)` — no gating, no throttling, no early return.
- [x] S20 `EO_SweepGateOK` returns true only when `IsDefined(hud)` AND `hud.GetPlayer() as PlayerPuppet` is defined AND `!player.IsReplacer()` AND `!hud.IsBraindanceActive()`.

Forbidden patterns (grep-verifiable, all must be ABSENT from the file)
- [x] S21 Zero `@wrapMethod` and zero `@replaceMethod` annotations; the string `OnGameAttached` appears nowhere; zero `DelayCallback`/`DelaySystem`/`DelayCallbackNextFrame` references; zero enumeration calls (`GetNPCsAroundObject`, `GetEntitiesAroundObject`, `GetEntityList`, `GetTargetParts`, `TSF_`); zero RNG calls (`RandF`, `RandRange`, `RandRangeF`, `RandNoiseF`).
- [x] S22 Zero `continue`/`break` keywords; zero TweakDB writes (the ONLY `TweakDBInterface` usage is the `GetCharacterRecord` read in the composite; no `Set*`/`CreateRecord`/`TweakDBManager`); zero `AddSavedModifier`; zero engine-state mutation calls (no StimBroadcaster/attitude/AIComponent/StatsSystem/StatPools/TransactionSystem/journal APIs) — the only writes in the file are `ArrayPush`/`ArrayErase` on the two `@addField` arrays and the local `let` bindings.

Verified-API-only
- [x] S23 Spot-check ≥4 engine APIs used in the file at random against `sprint/vanilla-scripts` at (approximately) the plan's cited lines — at minimum recommended: `GetScriptableSystemsContainer` (`gameInstance.script:41`) + `ScriptableSystemsContainer.Get` (`scriptableSystem.script:5-8`) + the vanilla-verbatim resolve precedent (`gameObject.script:3183-3186`); `IsEnemy` (`scriptedPuppet.script:2003-2006`); `Quest().Type()` (`tweakDBRecords.script:3472, 6215-6220`); `AddLog` (`activityLogSystem.script:7`); `FTLog` (`testStepLogicImport.script:29`). Zero APIs sourced from Codeware/CET/NativeDB-only surfaces.
- [x] S24 Language-shape precedents hold: dotted module + `import EnemyOverhaul.Common.*` consumability mirrors `staging/r6/scripts/talk-to-me/` (TalkToMeConfig.reds:1,4 + TalkToMe.reds:1); `script_ref<array<>>`+`Deref` mutation mirrors `staging/.../UnequipWeaponModsAndAttachements.reds:96,148`.

Smoke probe & rungs
- [x] S25 Implementer notes record the smoke-probe protocol result: probe file created with all four legs — (a) free-function calls, (b) cross-module `@addMethod(HUDManager)` member calls, (c) `@addField` array passed as `script_ref` arg, (d) `@wrapMethod(ScriptedPuppet) public const func AwardsExperience()` calling `EO_IsClone(this.GetGame(), this.GetEntityID())` — compiled clean via `scc-serial.sh`, then probe DELETED and a final clean compile run. Any fallback rung taken (1: static-class holder; 2: `out` params; 3: game-keyed uprank frees `EO_Uprank*G`) is named in the notes with its exact substitute signatures, and the file matches that documented shape.

## Manual in-game test plan (user-run; the reviewer NEVER ticks these)

Near-empty by design, as the consolidator prompt anticipates: **Common alone has no visible in-game behavior** — no hooks, no loops, no notifies of its own. Its correctness is exercised through the feature test plans: tier-uprank M4 (no re-roll on re-stream = uprank ledger), duplication M6/M7 (no XP/no loot = `EO_IsClone` incl. the const path), duplication M12 (depth cap + clone gets its single uprank roll = clone registry + composite's clone-blindness), tier-uprank M5-M8 / duplication M8 (exclusion silence = eligibility composite), and every feature debug line (= `EO_Notify`).

- [ ] M1 **Inertness check (only meaningful while Common is the sole EnemyOverhaul file installed).** Compile and launch with ONLY `EnemyOverhaul.Common.reds` present: the game boots normally, plays 100% vanilla, and produces ZERO new HUD activity-log lines and zero behavior changes over a few minutes of city roaming and one firefight. Any visible difference = defect in Common (it must be passive).
