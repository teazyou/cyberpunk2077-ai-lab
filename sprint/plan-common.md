# Plan — Common (shared infrastructure module `EnemyOverhaul.Common`)

Owned file: `sprint/impl/custom-enemy-overhaul/EnemyOverhaul.Common.reds`. Module `EnemyOverhaul.Common`. Verdict: **FEASIBLE** — every engine API below is vanilla-verified (`sprint/vanilla-scripts` file:line, re-grepped 2026-07-17 for this plan) or in-game-proven by ScannerSuite.reds; every *language* shape (dotted module, cross-module import, module-level `public static func`, `script_ref<array<>>`+`Deref` mutation) is compile-proven by mods inside `sprint/staging/r6/scripts/` (the director probe compiled that full set clean). Consolidates the three planners' declared `common_needs`; feature plans pre-authorized signature adaptation ("if the consolidated names/shapes differ, adapt call sites").

**Design verdict (per prompt-common-consolidator):** Common is a **purely passive utility module** — zero `@wrapMethod`/`@replaceMethod`, zero `OnGameAttached` of any kind, zero DelayCallback loops, zero enumeration, zero RNG, zero engine-state mutation. Each feature arms its OWN loop via its own `PlayerPuppet.OnGameAttached` wrap (wraps chain — ScannerSuite.reds:2056-2077 + SwitchSpeed.reds:185 + street_vendors.reds:87 all wrap it today, in-game-proven). No Common-owned loop/registration hub: the simplest verified design, and exactly what the three plans already assume. Common's entire mutable state = two FIFO-capped `array<EntityID>` script arrays hosted on HUDManager.

## Mechanism

**1. State host = `HUDManager`.** Session-stable ScriptableSystem (`class HUDManager extends NativeHudManager` `hudManager.script:174`; `import class NativeHudManager extends ScriptableSystem` `:162`), survives replacer PlayerPuppet swaps, months-proven as an `@addField`/`@addMethod` host by ScannerSuite (`m_stSweepArmed` etc., ScannerSuite.reds:1385-1386). Resolvable from a bare `GameInstance` via the vanilla-verbatim recipe used by `GameObject.GetHudManager()` itself — a **`public const function`** whose whole body is `(HUDManager)(GameInstance.GetScriptableSystemsContainer(GetGame()).Get('HUDManager'))` (`gameObject.script:3183-3186`; `GetScriptableSystemsContainer` `gameInstance.script:41`; `ScriptableSystemsContainer.Get(systemName: CName) -> ScriptableSystem` `scriptableSystem.script:5-8`; same container idiom in-game-proven ScannerSuite.reds:1503-1505). That the recipe lives inside a vanilla `const function` is the const-safety proof duplication needs (below).

**2. Two hosted ledgers, one shape.** `array<EntityID>` + `ArrayContains`/`ArrayPush` + FIFO eviction `ArrayErase(arr, 0)` when size exceeds cap 4096 — verbatim the ScannerSuite ledger shape (ScannerSuite.reds:1722-1746 incl. the EntityID-recycling rationale comment). `EntityID` `==` operator makes `ArrayContains` work (`entityID.script:1-19`); IDs are stable across re-stream within a session, recycled after despawn → cap ages stale entries out (accepted, proven tradeoff).
- **Uprank roll ledger** (`m_eoUprankRolled`) — tier-uprank's once-per-session exactly-once spend.
- **Clone registry** (`m_eoCloneReg`) — duplication's mark/lookup; marked entries are never removed except FIFO aging (depth-cap-1 guarantee).

**3. Const-context laundering via GameInstance-keyed free functions.** Duplication must call `EO_IsClone` from inside a wrapped `public const func AwardsExperience()` (P1-proven wrap shape). REDscript const-ness restricts `this` usage only; a module-level function has no `this`. So the const wrap calls `EO_IsClone(this.GetGame(), this.GetEntityID())` — `GetGame()` is `public import const final` (`gameObject.script:226`), `GetEntityID()` is `import const` (`entity.script:5`) — and the free function body does the container resolve + member call in its own (non-const) context. Additional vanilla proof that const funcs may run this exact resolve chain: `GetHudManager()` itself is const (`gameObject.script:3183`). REDscript has **no static mutable state** (shared-infra dossier F3/F6: no map types, no statics) — this GameInstance parameter is therefore mandatory, resolving the declared-need signature `EO_IsClone(id)` into `EO_IsClone(game, id)` (drift table below).

**4. Rule-3 safety of `EO_MarkClone` inside wraps.** Marking = pushing onto a script array on the script-side HUDManager object — pure REDscript state, not engine state; no re-entrant native-dispatcher mutation. Synchronously legal inside the PreventionSystem harvest wrap (exactly what duplication S10 requires). Common never touches engine systems except the read-only `TweakDBInterface.GetCharacterRecord` and the notify sinks.

**5. Language-shape precedents (all inside the compile-proven staging set):**
- Dotted module + cross-module import of module-level funcs: `module TalkToMe.Config` declaring `public static func npcFov() -> Float = 90.0;` consumed via `import TalkToMe.Config.*` and a bare `npcFov()` call (`staging/r6/scripts/talk-to-me/TalkToMeConfig.reds:1,4`, `TalkToMe.reds:1,22`). Also `module DALC.Base`/`import DALC.Base.DALC`.
- `script_ref<array<T>>` param mutated via `ArrayPush(Deref(ref), ...)` in a user-defined func, caller passing a plain array variable: `staging/r6/scripts/auto-unequip-weapon-mods-and-attachments-when-selling-or-disassembling/UnequipWeaponModsAndAttachements.reds:96,148` (call chain from `:73`). Same file proves `out array<>` params as the fallback shape. Vanilla passes FIELDS to by-ref params (`CachedBoolValue.GetIfNotDirty(cachedValue: ref<CachedBoolValue>, out value: Bool)` `aiScripting.script:225`, field arg `m_isActiveCached` at `scriptedPuppet.script:1958`).
- `public abstract class` + `public final static func` config block: ScannerSuiteConfig (ScannerSuite.reds:241, in-game-proven).

**Fallback ladder (rung = specific `sprint/bin/scc-serial.sh` failure; each rung preserves behavior and EO_ names; any rung taken MUST be recorded in implementer notes — feature implementers read those notes):**
1. Module-level `public static func` rejected → move the seven free functions into `public abstract class EOCommon` as `public final static func` (ScannerSuiteConfig-proven shape); call sites become `EOCommon.EO_*(...)`. Feature implementers adapt (pre-authorized by all three plans).
2. `script_ref<array<EntityID>>` param shape rejected → redeclare both seen-set helpers with `out seen: array<EntityID>` (same-file precedent `UnequipWeaponModsAndAttachements.reds:96`); bodies drop `Deref`; call sites unchanged (array passed bare either way).
3. Cross-module visibility failure of the `@addMethod(HUDManager)` members (smoke probe's member-context call fails to resolve) → members stay (Common-internal), and Common ADDS GameInstance-keyed free equivalents `EO_UprankAlreadyRolledG(game, id) -> Bool` / `EO_UprankMarkRolledG(game, id) -> Void` / `EO_UprankTrySpendG(game, id) -> Bool` (free functions are the TalkToMe-proven import surface; they call the members same-module). Tier-uprank then calls those with `this.GetGameInstance()`.
4. `as HUDManager` cast or `n"HUDManager"` container name failing at compile is not expected (vanilla-verbatim); if the probe's runtime-shape ever proves the resolve wrong, the fallback host is unchanged — only the resolve path would move to `GetHudManager()` on a GameObject caller, which duplication's non-const call sites can supply. No rung needed for tier-uprank (it resolves hud once in its own wrap via `this.GetHudManager()`).

## Architecture — EXACT file contents (normative)

File layout top→bottom. Everything below is the complete public surface; **nothing else public may exist in the file**.

```reds
module EnemyOverhaul.Common
// ZERO import statements — Common imports nothing (acyclic guarantee).

// ============================ USER CONFIG ====================================
public abstract class EOCommonConfig {
  // FIFO cap of BOTH Common-hosted ledgers (uprank roll ledger + clone
  // registry). ScannerSuite-proven value; EntityID-recycling mitigation.
  public final static func LedgerCap() -> Int32 { return 4096; }
}
// NOTE: deliberately NO DebugNotify() here — notify gating/throttling is
// caller-owned per all three feature plans; Common itself emits nothing.

// ==================== generic FIFO seen-set helpers ==========================
public static func EO_SeenContains(seen: script_ref<array<EntityID>>, id: EntityID) -> Bool {
  return ArrayContains(Deref(seen), id);
}

// true = id was absent and is now recorded (oldest entry evicted above cap);
// false = already present. Spend-on-roll semantics live in the CALLER.
public static func EO_SeenTryAdd(seen: script_ref<array<EntityID>>, id: EntityID, cap: Int32) -> Bool {
  if ArrayContains(Deref(seen), id) { return false; }
  ArrayPush(Deref(seen), id);
  if ArraySize(Deref(seen)) > cap { ArrayErase(Deref(seen), 0); }
  return true;
}

// ========================= shared eligibility ================================
// Composite F1/F2 filter. Include gates first, cheap cached excludes next,
// the TweakDB quest fetch LAST (the only record-fetch-cost check). MUST NOT
// read the clone registry (F2 clones need their single F1 roll).
// Null character record / null Quest() handle => treated as General => ELIGIBLE.
public static func EO_IsEligibleCombatHuman(puppet: ref<NPCPuppet>) -> Bool {
  if !IsDefined(puppet) { return false; }
  if !Equals(puppet.GetNPCType(), gamedataNPCType.Human) { return false; }  // include
  if !puppet.IsActive() { return false; }                                    // include
  if !puppet.IsEnemy() { return false; }                                     // include
  if puppet.IsBoss() || puppet.IsMaxTac() { return false; }                  // exclude (paired)
  if puppet.IsCharacterPolice() { return false; }                            // exclude
  if puppet.IsMechanical() { return false; }                                 // exclude (belt+suspenders)
  if puppet.IsCharacterCivilian() || puppet.IsCrowd() { return false; }      // exclude
  let rec: ref<Character_Record> = TweakDBInterface.GetCharacterRecord(puppet.GetRecordID());
  if IsDefined(rec) {
    let questRec: wref<NPCQuestAffiliation_Record> = rec.Quest();
    if IsDefined(questRec) && NotEquals(questRec.Type(), gamedataNPCQuestAffiliation.General) {
      return false;                                                          // exclude (best-effort)
    };
  };
  return true;
}

// =========================== debug notify ====================================
// UNCONDITIONAL emit — HUD activity-log one-liner + FTLog file line. Callers
// gate on their own DebugNotify() const (and throttle, where their plan says).
public static func EO_Notify(game: GameInstance, msg: String) -> Void {
  GameInstance.GetActivityLogSystem(game).AddLog(msg);
  FTLog(msg);
}

// ========================= sweep skip-gate ===================================
// true = OK to do sweep work this tick. false = skip-but-stay-alive (caller
// already re-armed its loop). Player resolve via HUDManager.GetPlayer().
public static func EO_SweepGateOK(hud: ref<HUDManager>) -> Bool {
  if !IsDefined(hud) { return false; }
  let player: ref<PlayerPuppet> = hud.GetPlayer() as PlayerPuppet;
  return IsDefined(player) && !player.IsReplacer() && !hud.IsBraindanceActive();
}

// ================== uprank roll ledger (hosted on HUDManager) ================
@addField(HUDManager)
let m_eoUprankRolled: array<EntityID>;

@addMethod(HUDManager)
public final func EO_UprankAlreadyRolled(id: EntityID) -> Bool {
  return ArrayContains(this.m_eoUprankRolled, id);
}

@addMethod(HUDManager)
public final func EO_UprankMarkRolled(id: EntityID) -> Void {
  if !ArrayContains(this.m_eoUprankRolled, id) {
    ArrayPush(this.m_eoUprankRolled, id);
    if ArraySize(this.m_eoUprankRolled) > EOCommonConfig.LedgerCap() {
      ArrayErase(this.m_eoUprankRolled, 0);
    };
  };
}

// Atomic contains+append: true ONLY on first visit (entry spent now).
@addMethod(HUDManager)
public final func EO_UprankTrySpend(id: EntityID) -> Bool {
  if this.EO_UprankAlreadyRolled(id) { return false; }
  this.EO_UprankMarkRolled(id);
  return true;
}

// ==================== clone registry (hosted on HUDManager) ==================
@addField(HUDManager)
let m_eoCloneReg: array<EntityID>;

@addMethod(HUDManager)
public final func EO_CloneRegContains(id: EntityID) -> Bool {
  return ArrayContains(this.m_eoCloneReg, id);
}

@addMethod(HUDManager)
public final func EO_CloneRegMark(id: EntityID) -> Void {
  if !ArrayContains(this.m_eoCloneReg, id) {
    ArrayPush(this.m_eoCloneReg, id);
    if ArraySize(this.m_eoCloneReg) > EOCommonConfig.LedgerCap() {
      ArrayErase(this.m_eoCloneReg, 0);
    };
  };
}

// GameInstance-keyed forms — the shapes feature WRAPS call. Zero `this` usage
// => const-context-safe at any call site by construction. Resolve recipe is
// vanilla-verbatim GameObject.GetHudManager (gameObject.script:3183-3186).
public static func EO_IsClone(game: GameInstance, id: EntityID) -> Bool {
  let hud: ref<HUDManager> = GameInstance.GetScriptableSystemsContainer(game)
    .Get(n"HUDManager") as HUDManager;
  if !IsDefined(hud) { return false; }
  return hud.EO_CloneRegContains(id);
}

public static func EO_MarkClone(game: GameInstance, id: EntityID) -> Void {
  let hud: ref<HUDManager> = GameInstance.GetScriptableSystemsContainer(game)
    .Get(n"HUDManager") as HUDManager;
  if IsDefined(hud) {
    hud.EO_CloneRegMark(id);
  };
}
```

### Public API surface (the contract — features import `EnemyOverhaul.Common.*`)

| # | Symbol | Kind | Consumers |
|---|---|---|---|
| 1 | `EOCommonConfig.LedgerCap() -> Int32` (=4096) | config const | Common-internal; features MAY read |
| 2 | `EO_IsEligibleCombatHuman(puppet: ref<NPCPuppet>) -> Bool` | module func | F1 tier-uprank, F2 duplication |
| 3 | `EO_Notify(game: GameInstance, msg: String) -> Void` | module func | F1, F2, F3 aggro-range |
| 4 | `EO_SweepGateOK(hud: ref<HUDManager>) -> Bool` | module func | F1, F2 (optional for both) |
| 5 | `EO_SeenContains(seen: script_ref<array<EntityID>>, id: EntityID) -> Bool` | module func | F2 (F1 optional substitute) |
| 6 | `EO_SeenTryAdd(seen: script_ref<array<EntityID>>, id: EntityID, cap: Int32) -> Bool` | module func | F2 (F1 optional substitute) |
| 7 | `EO_IsClone(game: GameInstance, id: EntityID) -> Bool` | module func | F2 (incl. const `AwardsExperience` wrap) |
| 8 | `EO_MarkClone(game: GameInstance, id: EntityID) -> Void` | module func | F2 (harvest wrap, synchronous) |
| 9 | `HUDManager.EO_UprankAlreadyRolled(id: EntityID) -> Bool` | @addMethod member | F1 (peek gate) |
| 10 | `HUDManager.EO_UprankMarkRolled(id: EntityID) -> Void` | @addMethod member | F1 |
| 11 | `HUDManager.EO_UprankTrySpend(id: EntityID) -> Bool` | @addMethod member | F1 (spend point) |
| 12 | `HUDManager.EO_CloneRegContains(id: EntityID) -> Bool` | @addMethod member | Common-internal shim (F2 uses #7) |
| 13 | `HUDManager.EO_CloneRegMark(id: EntityID) -> Void` | @addMethod member | Common-internal shim (F2 uses #8) |

`@addField` names (implementation detail, member-access only): `m_eoUprankRolled`, `m_eoCloneReg` — both on HUDManager, both session-transient, both non-persistent. No collision with feature fields (`m_eoUprankArmed` F1, `m_eodup*` F2, `m_eoarLastNotify` F3 — all distinct names).

### Signature drift vs declared common_needs (binding for feature implementers)

| Declared | Consolidated | Why |
|---|---|---|
| `EO_IsClone(id) -> Bool` | `EO_IsClone(game: GameInstance, id) -> Bool` | REDscript has no static mutable state; duplication's own need-note pre-authorized "reachable given only GameInstance". Call as `EO_IsClone(this.GetGame(), this.GetEntityID())` in the const wrap; `EO_IsClone(this.GetGameInstance(), id)` in PreventionSystem members. |
| `EO_MarkClone(id) -> Void` | `EO_MarkClone(game: GameInstance, id) -> Void` | Same. Harvest wrap: `EO_MarkClone(this.GetGameInstance(), id)` (vanilla uses `GetGameInstance()` inside PreventionSystem, `preventionSystem.script:207`). |
| `EO_UprankTrySpend(id) -> Bool` (+ split pair) | Kept `(id)` — as `@addMethod(HUDManager)` members; all THREE shapes shipped (#9-11) | F1's tick/process funcs are themselves `@addMethod(HUDManager)` → `this.EO_UprankTrySpend(id)` — zero drift at their call sites. Ledger cap is Common's `LedgerCap()`, not F1's `SeenCap()` (F1's const remains for its local-fallback path only). |
| `EO_SweepGateOK(hud)` | As declared | Resolves player internally via `hud.GetPlayer()` (`hudManager.script:1803`). |
| Everything else | Exact as declared | — |

### Deliberately NOT shipped (minimality rule: only what ≥2 features need or what enforces safety)

- **RNG roll helper** — `RandF() < chance` is a one-liner both feature plans already write inline (`rand.script:3`; idiom `NPCPuppet.script:893`). A wrapper adds drift, not safety.
- **NPC enumeration helper** — `player.GetNPCsAroundObject(range)` is already a single vanilla call (`gameObject.script:967-987`); both plans call it directly.
- **Sweep-loop scaffolding / DelayCallback base / registration hub** — each feature arms and owns its loop (its own tick-callback class, its own armed-guard, its own cadence consts) per its plan; Common owning a loop would add an unneeded lifecycle and an unverified registration pattern.
- **Notify throttling** — F3 owns its throttle (sim-time + `m_eoarLastNotify`); F1/F2 are unthrottled by design.

Per environment rule: any helper a feature finds missing → same-shape LOCAL fallback in the feature's own file (`EOTU_`/`EODup_`/`EOAR_` prefixes), flagged in implementer notes — **Common is never edited by feature implementers.**

## Lifecycle

Common has none of its own — this is a checkable property, not an omission:
- **No arm, no tick, no hooks.** The file contains no `@wrapMethod`, no `@replaceMethod`, no `OnGameAttached` token, no `DelayCallback`, no enumeration call. All Common code executes synchronously inside CALLER frames (feature ticks = game-thread DelayCallbacks; feature wraps = vanilla game-thread call flow) — thread-safety is inherited, single-threaded by construction (rule 2 untouchable: nothing here can run on a worker thread unless a caller violates its own plan).
- **State birth/reset:** the two arrays zero-init when the session's HUDManager is created; a save load builds a fresh session → empty ledgers → fresh rolls (exactly the accepted per-session semantics of both briefs). Replacer swaps do NOT reset them (HUDManager persists across player-object swaps — the reason it is the host).
- **No persistence:** no `persistent` fields; `AddSavedModifier`-class hazards structurally impossible here.
- **Exactly-once semantics** live in the ledger shape: no public removal API exists on either ledger (no un-roll, no un-mark) — the only erase in the file is the FIFO-cap eviction of the OLDEST entry inside the two Mark methods.

## Constants — USER CONFIG block (top of file, clearly marked)

| Name | Default | Meaning |
|---|---|---|
| `EOCommonConfig.LedgerCap()` | `4096` | FIFO cap of both Common-hosted ledgers (uprank roll ledger, clone registry). ScannerSuite-proven EntityID-recycling mitigation. |

That is the ENTIRE config block. Explicitly absent: `DebugNotify` (caller-gated by design — a Common-level gate would double-gate every feature's notifies), sweep/interval/range consts (loop-less module), chance consts (rolls are feature-owned).

## Exclusions — the shared eligibility composite (one VERIFIED predicate per category)

`EO_IsEligibleCombatHuman` is THE exclusions implementation for F1+F2 (F3 selects no entities and consumes none of this). Composed on `ref<NPCPuppet>` — the cast (done by callers via `GetNPCsAroundObject`'s return type) structurally excludes the whole Device tree (turrets/cameras/sensors: `gameObject.script:1766-1779`, `sensorDevice.script:155`, `surveillanceCamera.script:33`). Order: include gates → cheap cached excludes → TweakDB quest fetch LAST.

| Category | Predicate (in composite order) | Evidence |
|---|---|---|
| humanoid combat NPC (INCLUDE) | `Equals(puppet.GetNPCType(), gamedataNPCType.Human)` | `scriptedPuppet.script:1419-1422`; enum `tweakDBEnums.script:3371-3384`; vanilla combo `TargetIsHumanTrashToElite` `NPCPuppet.script:3065-3068` |
| active (INCLUDE) | `puppet.IsActive()` | `scriptedPuppet.script:1955` (`const override`, cached) |
| combat-viable (INCLUDE) | `puppet.IsEnemy()` = hostile OR (neutral ∧ ¬civ ∧ ¬crowd) | `scriptedPuppet.script:2003-2006` |
| Boss + MaxTac (EXCLUDE, always paired) | `puppet.IsBoss() \|\| puppet.IsMaxTac()` | `scriptedPuppet.script:1640-1666`; vanilla pairs them 10+ sites (`NPCPuppet.script:448,840,2655` …) |
| police/prevention (EXCLUDE) | `puppet.IsCharacterPolice()` | `scriptedPuppet.script:1780-1782` (+static `:1785-1794`; `IsPrevention()` alias `:1976-1979`) |
| mech/drone/spiderbot/android (EXCLUDE) | Human type check already excludes; belt-and-suspenders `puppet.IsMechanical()` → false | `scriptedPuppet.script:1456-1461` |
| civilian / crowd (EXCLUDE) | `puppet.IsCharacterCivilian() \|\| puppet.IsCrowd()` → false | `scriptedPuppet.script:1775-1778, 1815-1818` |
| quest/named/unique (EXCLUDE, best-effort, LAST) | `GetCharacterRecord(GetRecordID()).Quest().Type() != gamedataNPCQuestAffiliation.General` → false | `puppet.script:13` (GetRecordID); `tweakDB.script:1,371`; `tweakDBRecords.script:3472, 6215-6220`; enum `tweakDBEnums.script:4171-4181` |
| F2-marked clones | **NOT excluded** — composite never reads the clone registry (clones must get their single F1 roll) | brief-mandated; enforced by construction + acceptance grep |

**Null-safety posture (binding, resolves an F1/F2 plan divergence):** null `Character_Record` OR null `Quest()` handle ⇒ treated as `General` ⇒ **ELIGIBLE** (tier-uprank's declared semantics; least-exclusionary; for a streamed NPCPuppet a null record is a pathological corner). Duplication's acceptance S33 wanted "null record → ineligible" **inside its own flow** — its plan already mandates null-checked record fetches with verbatim-fallback at the spawn-record pick site (`EODup_PickSpawnRecord`), which is where record-resolvability actually matters mechanically; the duplication implementer therefore gets S33's protection from its own pick-site guard, not from the shared composite. Flagged here so both implementers and the reviewer read the same resolution. `IsQuest()` appears NOWHERE (footgun: fires on quest-item carriers, `scriptedPuppet.script:3773-3776`).

## What NOT to do

Global (absolute): no `continue`/`break` (none needed — no loops beyond the intrinsic-free bodies above); no per-entity `GameObject.OnGameAttached` hooks — in fact **no `OnGameAttached` token at all**; no TweakDB writes (read = `GetCharacterRecord` only); no game launch; compile only via `sprint/bin/scc-serial.sh`; edit ONLY `EnemyOverhaul.Common.reds` (plus the transient smoke probe below).

Common-specific forbiddens:
- NO `import` statements of any kind — Common imports nothing (acyclic rule; especially never `EnemyOverhaul.TierUprank/Duplication/AggroRange`).
- NO `@wrapMethod` / `@replaceMethod` anywhere — Common hooks nothing.
- NO `DelayCallback`/`DelaySystem`/`DelayCallbackNextFrame`, no enumeration (`GetNPCsAroundObject`/`GetEntitiesAroundObject`/`GetEntityList`/`GetTargetParts`), no `RandF`/`RandRange*` — loops, sweeps and rolls are feature-owned.
- NO engine-state mutation: no StimBroadcaster/attitude/AI-command/stat/stat-pool/transaction/journal calls. Common's only writes are its two script arrays.
- NO gating inside `EO_Notify` (a Common-level DebugNotify would double-gate callers) and no throttling (F3 throttles caller-side).
- NO removal APIs on either ledger beyond the FIFO-cap eviction (no un-roll/un-mark path — exactly-once safety).
- NO clone-registry read inside `EO_IsEligibleCombatHuman` (clones stay eligible for F1).
- NO `IsQuest()`, no `TSF_EnemyNPC` (no targeting code at all), no `AddSavedModifier`, no `persistent` fields.
- NO extra public symbols beyond the 13-item surface table + `EOCommonConfig` (feature plans treat the surface as exhaustive; additions = drift).
- Do NOT "improve" feature ergonomics by hosting feature-specific state beyond the two ledgers (e.g. duplication's pending/wiring queues stay in F2's file).

## Debug & manual-verification hooks

- Common OWNS the shared funnel `EO_Notify` (AddLog `activityLogSystem.script:7` via `gameInstance.script:10` — in-game-proven ScannerSuite.reds:1492-1499; FTLog `testStepLogicImport.script:29`, live non-test site `worldMap.script:587`) but EMITS NOTHING itself: zero notify call sites inside Common, zero self-logging. Every debug line the user ever sees through this funnel is a feature's line, gated by that feature's `DebugNotify()`.
- Consequently Common's runtime correctness is observed ONLY through feature behavior: F1's M4 (no re-roll on re-stream) exercises the uprank ledger; F2's M6/M7 (no XP/loot) exercises `EO_IsClone` incl. the const path; F2's M12 (depth cap + clone uprank) exercises registry + composite's clone-blindness; F1's M5-M8 / F2's M8 exercise the eligibility composite; every debug line of all three features exercises `EO_Notify`.
- **Implementation-time verification (smoke probe — mandatory, converts the two residual language risks into compile facts):** after Common first compiles clean, the Common implementer creates a TEMPORARY `sprint/impl/custom-enemy-overhaul/EnemyOverhaul.SmokeProbe.reds` (`module EnemyOverhaul.SmokeProbe` + `import EnemyOverhaul.Common.*`) containing, with throwaway `m_eoProbe*`/`EOProbe_*` names: (a) a module func calling all seven free functions; (b) an `@addMethod(HUDManager)` member calling `this.EO_UprankTrySpend(...)`, `this.EO_UprankAlreadyRolled(...)`, `this.EO_UprankMarkRolled(...)`, `this.EO_CloneRegContains(...)`, `this.EO_CloneRegMark(...)` (cross-module member visibility); (c) an `@addField(HUDManager) let m_eoProbeSeen: array<EntityID>;` passed to `EO_SeenTryAdd(this.m_eoProbeSeen, id, 8)` from that member (field-as-script_ref arg); (d) a `@wrapMethod(ScriptedPuppet) public const func AwardsExperience() -> Bool` wrap whose body is `if EO_IsClone(this.GetGame(), this.GetEntityID()) { return wrappedMethod(); }; return wrappedMethod();`-shaped (const-context call proof; calls `wrappedMethod` exactly once per path). Compile via `scc-serial.sh` → then DELETE the probe file → final clean compile. Record pass/fail + any rung taken in implementer notes. The probe never ships and never coexists with feature implementations (it is deleted before F1/F2/F3 are written; its throwaway wrap would not conflict anyway — wraps chain — but deletion keeps ownership clean).

## Risks — residual unknowns + how the implementer surfaces them

1. **Cross-module `@addMethod` member visibility** (members added by `EnemyOverhaul.Common` called from `EnemyOverhaul.TierUprank` member bodies): expected to work (annotations attach to the global class; public members), but not yet proven in this exact repo — the smoke probe's (b) leg proves/disproves it at Common-implementation time, BEFORE features build. Fail → rung 3 (game-keyed free equivalents), noted for the F1 implementer.
2. **Module-level `public static func` + block bodies**: TalkToMe precedent is expression-bodied; block-bodied global `func` proven by `CustomProgressionXP.reds:33` (same staging set). Combination failing → rung 1 (static-class shape). Probe leg (a) covers.
3. **`script_ref` + field args**: staging precedent passes locals; vanilla passes fields to by-ref params. Probe leg (c) proves the exact field-arg shape. Fail → rung 2 (`out` params).
4. **HUDManager container-resolve null corner** (`Get(n"HUDManager")` before system creation): vanilla resolves it during `PlayerPuppet.OnGameAttached` (ScannerSuite comment + `player.script:1170` queueing) and every feature call site runs at/after attach. Guarded anyway: `EO_IsClone` → `false` (fail-open = clone treated as normal enemy — worst case a clone pays XP once, never a crash), `EO_MarkClone` → silent no-op, `EO_SweepGateOK` → `false` (skip tick). Surfaced naturally by F2's harvest/wire notify pairs if it ever fired.
5. **EntityID recycling vs the 4096-cap ledgers** (accepted, ScannerSuite-proven tradeoff): a recycled ID inheriting a spent uprank entry silently skips its roll; a clone-registry entry aging out after 4096 later marks would re-expose a still-alive clone to rolls/XP — requires >4096 marked-or-rolled entities in one session while that clone lives; accepted. No action; noted for the reviewer.
6. **Null-record eligibility divergence with duplication's acceptance S33** — resolved by posture (Exclusions above); the F2 implementer must satisfy S33 at the spawn-record pick site. Flagged in this plan + must be repeated in Common's implementer notes.
7. **Any vanilla API in this plan failing the implementer's own grep** against `sprint/vanilla-scripts` → STOP, re-verify against the dossiers, document the discrepancy; never substitute a guessed API. (All cites in this plan were re-grepped 2026-07-17: `gameInstance.script:10,21,41`; `scriptableSystem.script:5-8`; `gameObject.script:226,1731,3183-3186`; `player.script:582,1161`; `hudManager.script:162,174,615,1803`; `scriptedPuppet.script:1419-1422,1456-1461,1640-1666,1775-1794,1815-1818,1955,2003-2006,3773-3776`; `puppet.script:13`; `entity.script:5`; `entityID.script:1-19`; `tweakDB.script:1,371`; `tweakDBRecords.script:3472,6215-6220`; `tweakDBEnums.script:3371-3384,4171-4181`; `activityLogSystem.script:7`; `testStepLogicImport.script:29`; `worldMap.script:587`; `aiScripting.script:225`.)
