module EnemyOverhaul.Common
// ZERO import statements — Common imports nothing (acyclic guarantee; in
// particular never EnemyOverhaul.TierUprank/Duplication/AggroRange).

// =============================================================================
// Enemy Overhaul — Common (shared infrastructure module)
// Locally-authored custom mod (no Nexus source). macOS / Steam / pure REDscript
// / game v2.3. This module is the shared substrate the three feature units
// (tier-uprank F1, enemy-duplication F2, aggro-range F3) import via
// `import EnemyOverhaul.Common.*`.
//
// DESIGN: Common is a PURELY PASSIVE utility module — it hooks nothing and
// arms nothing. No method wraps or replacers, no attach hook, no delayed-
// callback loop, no enumeration, no RNG, no engine-state mutation. Each feature
// arms its OWN sweep loop from its OWN player-attach wrap (wraps chain — proven
// in-game by ScannerSuite + several enabled mods). All code here runs
// synchronously inside CALLER frames (feature game-thread ticks and feature
// vanilla-call-flow wraps), so its single-threaded safety is inherited by
// construction.
//
// Common's entire mutable state = two FIFO-capped `array<EntityID>` ledgers
// hosted on the session-stable HUDManager ScriptableSystem (survives replacer
// PlayerPuppet swaps — the reason it, not PlayerPuppet, is the host):
//   * uprank roll ledger (m_eoUprankRolled) — F1's once-per-session spend.
//   * clone registry       (m_eoCloneReg)   — F2's clone mark/lookup.
// Both zero-init when the session HUDManager is created; a save load builds a
// fresh session -> empty ledgers -> fresh rolls (accepted per-session
// semantics). No saved-to-disk fields; no removal API on either ledger beyond
// the FIFO-cap eviction of the OLDEST entry — that absence IS the exactly-once
// guarantee.
// =============================================================================

// ============================ USER CONFIG ====================================
// The ENTIRE config surface of Common. Deliberately NO DebugNotify() (notify
// gating is caller-owned per all three feature plans — a Common-level gate
// would double-gate every feature's notifies) and NO sweep/interval/range/
// chance consts (Common owns no loop and rolls nothing).
public abstract class EOCommonConfig {
  // FIFO cap of BOTH Common-hosted ledgers (uprank roll ledger + clone
  // registry). ScannerSuite-proven value; bounds the ledgers so recycled
  // EntityIDs age stale entries out instead of accumulating unbounded.
  public final static func LedgerCap() -> Int32 { return 4096; }
}

// ==================== generic FIFO seen-set helpers ==========================
// Caller-owned `array<EntityID>` passed by script_ref so the helper mutates the
// caller's array in place (F2 uses these for its own seen-sets; F1 may
// substitute them for its local-fallback path). Spend-on-roll semantics live in
// the CALLER — these are pure add/lookup primitives.

public static func EO_SeenContains(seen: script_ref<array<EntityID>>, id: EntityID) -> Bool {
  return ArrayContains(Deref(seen), id);
}

// true = id was absent and is now recorded (oldest entry evicted above cap);
// false = already present (array left untouched).
public static func EO_SeenTryAdd(seen: script_ref<array<EntityID>>, id: EntityID, cap: Int32) -> Bool {
  if ArrayContains(Deref(seen), id) { return false; }
  ArrayPush(Deref(seen), id);
  if ArraySize(Deref(seen)) > cap { ArrayErase(Deref(seen), 0); }
  return true;
}

// ========================= shared eligibility ================================
// Composite F1/F2 filter — THE exclusions implementation for tier-uprank and
// duplication. Order: include gates first, cheap cached excludes next, the
// TweakDB quest fetch LAST (the only record-fetch-cost check). The `ref<
// NPCPuppet>` type itself structurally excludes the whole Device tree
// (turrets/cameras/sensors). MUST NOT read the clone registry — F2-marked
// clones must stay eligible for their single F1 roll. Null character record OR
// null Quest() handle => treated as General => ELIGIBLE (least-exclusionary;
// for a streamed NPCPuppet a null record is a pathological corner).
public static func EO_IsEligibleCombatHuman(puppet: ref<NPCPuppet>) -> Bool {
  if !IsDefined(puppet) { return false; }
  if !Equals(puppet.GetNPCType(), gamedataNPCType.Human) { return false; }  // include: humanoid combat NPC
  if !puppet.IsActive() { return false; }                                    // include: active
  if !puppet.IsEnemy() { return false; }                                     // include: combat-viable
  if puppet.IsBoss() || puppet.IsMaxTac() { return false; }                  // exclude: Boss + MaxTac (paired)
  if puppet.IsCharacterPolice() { return false; }                            // exclude: police/prevention
  if puppet.IsMechanical() { return false; }                                 // exclude: mech/drone (belt+suspenders)
  if puppet.IsCharacterCivilian() || puppet.IsCrowd() { return false; }      // exclude: civilian / crowd
  let rec: ref<Character_Record> = TweakDBInterface.GetCharacterRecord(puppet.GetRecordID());
  if IsDefined(rec) {
    let questRec: wref<NPCQuestAffiliation_Record> = rec.Quest();
    if IsDefined(questRec) && NotEquals(questRec.Type(), gamedataNPCQuestAffiliation.General) {
      return false;                                                          // exclude: quest/named/unique (best-effort, LAST)
    };
  };
  return true;
}

// =========================== debug notify ====================================
// UNCONDITIONAL emit — HUD activity-log one-liner + FTLog file line. Callers
// gate on their own DebugNotify() const (and throttle, where their plan says).
// Common emits NOTHING itself: there are zero call sites of this inside Common.
public static func EO_Notify(game: GameInstance, msg: String) -> Void {
  GameInstance.GetActivityLogSystem(game).AddLog(msg);
  FTLog(msg);
}

// ========================= sweep skip-gate ===================================
// true = OK to do sweep work this tick. false = skip-but-stay-alive (the caller
// has already re-armed its own loop). Player resolved internally via
// HUDManager.GetPlayer(); skips during replacer swaps and braindance.
public static func EO_SweepGateOK(hud: ref<HUDManager>) -> Bool {
  if !IsDefined(hud) { return false; }
  let player: ref<PlayerPuppet> = hud.GetPlayer() as PlayerPuppet;
  return IsDefined(player) && !player.IsReplacer() && !hud.IsBraindanceActive();
}

// ================== uprank roll ledger (hosted on HUDManager) ================
// F1's once-per-session exactly-once spend. Session-transient (never saved).
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

// Atomic contains+append: true ONLY on the first visit (entry spent now).
@addMethod(HUDManager)
public final func EO_UprankTrySpend(id: EntityID) -> Bool {
  if this.EO_UprankAlreadyRolled(id) { return false; }
  this.EO_UprankMarkRolled(id);
  return true;
}

// ==================== clone registry (hosted on HUDManager) ==================
// F2's clone mark/lookup. Session-transient (never saved). Marked entries are
// never removed except FIFO aging (depth-cap-1 guarantee).
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

// GameInstance-keyed forms — the shapes F2's WRAPS call. Zero `this` usage =>
// const-context-safe at any call site by construction (duplication calls
// EO_IsClone from inside a wrapped `public const func AwardsExperience()`).
// Host resolve recipe is vanilla-verbatim GameObject.GetHudManager
// (gameObject.script:3183-3186). Fail-open on a null host: EO_IsClone -> false
// (a clone treated as a normal enemy — worst case pays XP once, never a crash),
// EO_MarkClone -> silent no-op.
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

// =============================================================================
// IMPLEMENTER NOTES — smoke-probe protocol result (acceptance S25)
// =============================================================================
// The mandatory smoke probe was RUN and is RECORDED here (the probe file itself
// never ships). After Common first compiled clean, a temporary sibling
// `EnemyOverhaul.SmokeProbe.reds` (module EnemyOverhaul.SmokeProbe, consuming
// Common's public surface) was created exercising all FOUR legs, compiled
// through sprint/bin/scc-serial.sh, then DELETED, then a final clean compile was
// run. Result: PASS on every leg — the PRIMARY (no-rung) shape holds.
//
// Legs exercised (throwaway EOProbe_*/m_eoProbe* names):
//   (a) free-function leg — one module func called all SEVEN free funcs
//       (EO_SeenContains, EO_SeenTryAdd, EO_IsEligibleCombatHuman, EO_Notify,
//       EO_SweepGateOK, EO_IsClone, EO_MarkClone). Compiled clean.
//   (b) cross-module member leg — a throwaway member added onto HUDManager from
//       the probe module called all five HUDManager members Common adds
//       (this.EO_UprankTrySpend / EO_UprankAlreadyRolled / EO_UprankMarkRolled /
//       EO_CloneRegContains / EO_CloneRegMark). Cross-module member visibility
//       CONFIRMED at compile time (risk 1 retired). Compiled clean.
//   (c) field-as-script_ref leg — a throwaway `array<EntityID>` field added onto
//       HUDManager (m_eoProbeSeen) was passed to
//       EO_SeenTryAdd(this.m_eoProbeSeen, id, 8) from that member. The
//       field-as-script_ref argument shape CONFIRMED (risk 3 retired). Clean.
//   (d) const-context leg — a method-wrap of the vanilla
//       `public const func AwardsExperience() -> Bool` (scriptedPuppet.script:
//       1835) whose body called EO_IsClone(this.GetGame(), this.GetEntityID())
//       and returned wrappedMethod() on each path. Const-context free-func call
//       CONFIRMED (the two residual language risks are now compile facts). Clean.
//
// Compile evidence: probe-present compile -> exit 0 + "Output successfully
// saved", with both custom-enemy-overhaul/*.reds listed in the compiled set and
// ZERO diagnostics naming Common or the probe (the five warnings are all in
// unrelated staging mods: untrackQuestByRightClick, BetterFastTravelMap,
// dalc_base, DrinkAtTheCounter x2). Post-delete compile -> exit 0 + "Output
// successfully saved"; impl/ and staging/.../custom-enemy-overhaul/ then hold
// ONLY EnemyOverhaul.Common.reds.
//
// Fallback ladder: NO rung taken (none of rungs 1-4). The shipped file is the
// primary shape: module-level free funcs (leg a), the five HUDManager members
// (leg b), script_ref<array<EntityID>>+Deref seen-set helpers taking field args
// (leg c), and the GameInstance-keyed EO_IsClone/EO_MarkClone free funcs (leg d).
//
// Flags carried forward from plan-common (risks 5-6) for the F2/duplication
// implementer and the reviewer:
//   * Null-record posture vs duplication acceptance S33: a null Character_Record
//     OR null Quest() handle here is treated as General => ELIGIBLE (least-
//     exclusionary). S33's "null record -> ineligible" is satisfied inside
//     duplication's OWN flow at its spawn-record pick site (EODup_PickSpawnRecord),
//     NOT by this shared eligibility composite.
//   * EntityID recycling vs the 4096-cap ledgers is an accepted, ScannerSuite-
//     proven tradeoff (a recycled id can inherit a spent entry; a still-live
//     clone can age out after >4096 marks in one session). No action.
// =============================================================================
