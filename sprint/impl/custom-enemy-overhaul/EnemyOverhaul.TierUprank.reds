module EnemyOverhaul.TierUprank
import EnemyOverhaul.Common.*

// =============================================================================
// Enemy Overhaul — F1 TIER UPRANK (30% one-tier enemy upgrade)
// Locally-authored custom mod (no Nexus source). macOS / Steam / pure REDscript
// / game v2.3. Feature unit of the `custom-enemy-overhaul` mod; consumes the
// shared substrate in EnemyOverhaul.Common (eligibility filter, once-per-session
// roll ledger hosted on HUDManager, debug-notify funnel).
//
// WHAT IT DOES: a self-re-arming game-thread sweep enumerates humanoid combat
// NPCs around the player; each eligible enemy is rolled exactly ONCE per session
// (30% default) and, on success, upgraded ONE tier up the rarity ladder
// (Trash->Weak->Normal->Rare->Officer->Elite; Elite is the ceiling).
//
// MECHANISM (stat emulation — the agreed, well-justified fallback; the brief's
// literal rarity/record swap is STRUCTURALLY INFEASIBLE: GetNPCRarity()/
// GetNPCRarityRecord()/GetRecordID() are import-const-final getters with zero
// setter, and TweakDB is read-only from REDscript). Per uprank we replay CDPR's
// OWN per-tier StatModifier block through CDPR's OWN device-init pipeline
// (record.StatModifiers -> RPGManager.StatRecordToModifier -> StatsSystem
// .AddModifiers, exactly scriptableDeviceBasePS.script:535-554) PLUS a
// PowerLevel/Level Additive pairing (NPCManager.ScaleToPlayer pattern,
// npcManager.script:107-121). The PowerLevel bump is LOAD-BEARING, not cosmetic:
// DamageSystem.ScalePlayerDamage (damageSystem.script:3468-3502) algebraically
// cancels a bare Health bump for player-sourced damage — bumping PowerLevel
// raises both sides of that ratio so the tankiness survives. After the stat
// writes we re-sync the Health pool max and restore the pre-uprank damage
// fraction (same 0-100 perc scale, never converted).
//
// NOTE (accepted): only numeric toughness shifts — the nameplate tier badge,
// XP-reward tier and anti-Elite perks all read the FROZEN GetNPCRarity() and do
// NOT change. Deltas are approximate (the replayed block stacks on the NPC's
// spawn block; native modifier compounding is invisible to script) — the debug
// notify prints before/after Health so actuals are observable, and
// PowerLevelBump is the empirical tuning knob.
//
// THREADING / SAFETY (rules learned the hard way):
//  * Only the PLAYER-object PlayerPuppet.OnGameAttached is wrapped (game thread,
//    once per load). NO per-entity GameObject.OnGameAttached hook anywhere
//    (entity streaming = worker threads -> heap corruption).
//  * All per-entity work runs on the game thread inside a DelaySystem tick.
//    Nothing here mutates state inside an engine listener callback (rule 3 does
//    not bite — the sweep tick is not a listener frame).
//  * Session-transient state (the armed guard, the roll ledger) lives on the
//    session-stable HUDManager ScriptableSystem, which survives replacer
//    PlayerPuppet swaps (ScannerSuite-proven host).
//  * Plain AddModifier/AddModifiers ONLY (never AddSavedModifier — it persists
//    across reload while the session ledger resets -> a fresh roll would stack a
//    second block). Never RemoveAllModifiers (would strip vanilla base curves).
// =============================================================================

// ============================ USER CONFIG ====================================
// All tunables live here. Edit a return value, recompile via
// sprint/bin/scc-serial.sh, done. (Static funcs, ScannerSuiteConfig-proven shape.)
public abstract class TierUprankConfig {

  // Master toggle. false = the sweep loop never arms (and the tick self-stops
  // defensively if flipped false mid-session). true = feature active.
  public final static func EnableTierUprank() -> Bool { return true; }

  // The 30%. Per-entity, once-only upgrade probability (the ONLY roll site).
  public final static func UprankChance() -> Float { return 0.30; }

  // Steady sweep cadence, seconds (sane range 0.5-1.0).
  public final static func SweepInterval() -> Float { return 0.5; }

  // Delay of the FIRST tick after player attach, seconds (world settles first).
  public final static func FirstTickDelay() -> Float { return 1.0; }

  // Enumeration radius around the player, meters.
  public final static func SweepRange() -> Float { return 50.0; }

  // Additive PowerLevel pairing per uprank — the anti-self-cancel lever vs
  // ScalePlayerDamage AND the master toughness knob (Health/Level/DPS cascade
  // off the PowerLevel curves). 0.0 disables the PowerLevel bump. THE tuning
  // knob: if upranked enemies do not feel tougher, raise this (3.0-4.0) — never
  // add bare Health multipliers.
  public final static func PowerLevelBump() -> Float { return 2.0; }

  // Additive Level pairing per uprank (mirrors ScaleToPlayer's Level bump).
  // 0.0 disables the Level bump.
  public final static func LevelBump() -> Float { return 2.0; }

  // FIFO cap of the roll ledger. Used ONLY by the local-fallback ledger path;
  // the active ledger is Common's HUDManager-hosted one, which carries its own
  // cap (EOCommonConfig.LedgerCap()). Kept here per the config contract.
  public final static func SeenCap() -> Int32 { return 4096; }

  // Debug HUD one-liner + FTLog on each uprank AND the arm-time ladder probe.
  // false = silent (feature still runs). Keep true while verifying.
  public final static func DebugNotify() -> Bool { return true; }
}

// ============================ ladder helpers =================================
// The uprank ladder (one step up the power order). gamedataNPCRarity is
// ALPHABETICAL (tweakDBEnums.script:3396-3408), so NEVER ordinal math — each
// rung is an explicit Equals() case. Returns the target tier's short name, or
// "" for NO target: Elite is the ceiling, and Boss/MaxTac/Count/Invalid are
// never upgraded here (Boss/MaxTac are excluded upstream anyway).
public static func EOUprank_TargetTierName(current: gamedataNPCRarity) -> String {
  if Equals(current, gamedataNPCRarity.Trash)   { return "Weak"; }
  if Equals(current, gamedataNPCRarity.Weak)    { return "Normal"; }
  if Equals(current, gamedataNPCRarity.Normal)  { return "Rare"; }
  if Equals(current, gamedataNPCRarity.Rare)    { return "Officer"; }
  if Equals(current, gamedataNPCRarity.Officer) { return "Elite"; }
  return ""; // Elite ceiling + Boss/MaxTac/Count/Invalid -> no target
}

// TweakDBID form of the ladder. Yields the TDBID.None() sentinel (checked via
// !TDBID.IsValid at the call site) for the no-target case. The path strings are
// web-sourced (community TweakDB dump) so the record fetch downstream is always
// IsDefined-guarded; TDBID.Create hashes the same path a T"" literal would.
public static func EOUprank_TargetPath(current: gamedataNPCRarity) -> TweakDBID {
  let name: String = EOUprank_TargetTierName(current);
  if StrLen(name) == 0 {
    return TDBID.None();
  };
  return TDBID.Create("NPCRarity." + name);
}

// Readable tier name for debug strings (old tier in the per-uprank notify).
public static func EOUprank_TierName(r: gamedataNPCRarity) -> String {
  if Equals(r, gamedataNPCRarity.Trash)   { return "Trash"; }
  if Equals(r, gamedataNPCRarity.Weak)    { return "Weak"; }
  if Equals(r, gamedataNPCRarity.Normal)  { return "Normal"; }
  if Equals(r, gamedataNPCRarity.Rare)    { return "Rare"; }
  if Equals(r, gamedataNPCRarity.Officer) { return "Officer"; }
  if Equals(r, gamedataNPCRarity.Elite)   { return "Elite"; }
  if Equals(r, gamedataNPCRarity.Boss)    { return "Boss"; }
  if Equals(r, gamedataNPCRarity.MaxTac)  { return "MaxTac"; }
  return "?";
}

// Arm-time one-shot probe of one ladder path: converts the web-sourced-path risk
// into a first-session log fact. Expected rarityValues (web table): Weak 2.0,
// Normal 3.0, Rare 4.0, Officer 4.5, Elite 5.0. A MISSING line means the path
// string is wrong -> the feature keeps running in rung-(b) PowerLevel-only mode.
public static func EOUprank_ProbeTier(game: GameInstance, tierName: String) -> Void {
  let path: TweakDBID = TDBID.Create("NPCRarity." + tierName);
  let rec: ref<NPCRarity_Record> = TweakDBInterface.GetNPCRarityRecord(path);
  if IsDefined(rec) {
    EO_Notify(game, "EO uprank probe: NPCRarity." + tierName + " rarityValue=" + FloatToString(rec.RarityValue()));
  } else {
    EO_Notify(game, "EO uprank probe: MISSING NPCRarity." + tierName);
  };
}

// ============================ sweep loop =====================================
// Self-re-arming DelayCallback (pure-REDscript periodic tick; ScannerSuite
// STSweepTickCallback shape). Armed once per load from the PlayerPuppet
// .OnGameAttached wrap; each tick re-arms itself for the whole session.
public class EOUprankTickCallback extends DelayCallback {
  public let hud: wref<HUDManager>;

  public func Call() -> Void {
    if IsDefined(this.hud) {
      this.hud.EOUprank_Tick();
    };
  }
}

// True while a tick is scheduled — double-arm guard (a replacer PlayerPuppet
// re-attaching mid-session fires OnGameAttached again on the SAME session
// HUDManager). Session-transient; distinct from ScannerSuite's m_stSweepArmed
// and Common's ledger fields.
@addField(HUDManager)
let m_eoUprankArmed: Bool;

// Arm the always-on loop. Called from the PlayerPuppet.OnGameAttached wrap
// (= game thread, once per load). The double-arm guard makes replacer
// re-attaches a no-op. Also fires the one-shot arm-time ladder probe.
@addMethod(HUDManager)
public final func EOUprank_Arm() -> Void {
  if this.m_eoUprankArmed {
    return; // a tick is already pending — never run two loops
  };
  let game: GameInstance = this.GetGameInstance();
  let tick: ref<EOUprankTickCallback> = new EOUprankTickCallback();
  tick.hud = this;
  GameInstance.GetDelaySystem(game)
    .DelayCallback(tick, TierUprankConfig.FirstTickDelay(), false);
  this.m_eoUprankArmed = true;
  // One-shot ladder probe (gated) — the 5 upgrade targets, logged once.
  if TierUprankConfig.DebugNotify() {
    EOUprank_ProbeTier(game, "Weak");
    EOUprank_ProbeTier(game, "Normal");
    EOUprank_ProbeTier(game, "Rare");
    EOUprank_ProbeTier(game, "Officer");
    EOUprank_ProbeTier(game, "Elite");
  };
}

// One sweep tick (GAME THREAD — DelayCallback fires on the game tick).
@addMethod(HUDManager)
public final func EOUprank_Tick() -> Void {
  // (1) Defensive permanent stop — the ONLY non-re-arming path. Dead in practice
  // (config is static and the loop only arms when on), mirrors ScannerSuite.
  if !TierUprankConfig.EnableTierUprank() {
    this.m_eoUprankArmed = false;
    return;
  };
  let game: GameInstance = this.GetGameInstance();
  // (2) RE-ARM FIRST, before any work: a fault in enumeration/apply must not kill
  // the loop for the session (fault-proof re-arm, ScannerSuite precedent).
  let tick: ref<EOUprankTickCallback> = new EOUprankTickCallback();
  tick.hud = this;
  GameInstance.GetDelaySystem(game)
    .DelayCallback(tick, TierUprankConfig.SweepInterval(), false);
  // (3) Skip-but-stay-alive gate (loop already re-armed): no work as a replacer
  // (Johnny) or inside a braindance. Same gate as ScannerSuite.reds:1448-1452.
  let player: ref<PlayerPuppet> = this.GetPlayer() as PlayerPuppet;
  if !IsDefined(player) || player.IsReplacer() || this.IsBraindanceActive() {
    return;
  };
  // (4) Enumerate every NPC around the player (TargetingSet.Complete = 360,
  // camera-independent; TSF_NPC backs it so NOT-YET-HOSTILE gang NPCs are
  // included — TSF_EnemyNPC would pre-filter to currently-hostile and miss them).
  // A just-streamed NPC missed this tick is caught next tick (self-healing).
  let npcs: array<ref<NPCPuppet>> = player.GetNPCsAroundObject(TierUprankConfig.SweepRange());
  let i: Int32 = 0;
  while i < ArraySize(npcs) {
    this.EOUprank_ProcessOnce(npcs[i]); // per-candidate; skips are early returns (no continue/break)
    i += 1;
  };
}

// Per-candidate ordered gates + roll + apply. Runs at most ONCE with effect per
// entity per session (the ledger spend below is the exactly-once point).
@addMethod(HUDManager)
public final func EOUprank_ProcessOnce(puppet: ref<NPCPuppet>) -> Void {
  if !IsDefined(puppet) {
    return;
  };
  let id: EntityID = puppet.GetEntityID();
  // (1) CHEAPEST gate first: already rolled this session -> skip, no re-roll, no
  // re-apply. Keeps re-streamed NPCs stable (no stacking).
  if this.EO_UprankAlreadyRolled(id) {
    return;
  };
  // (2) Eligibility (Common composite: human + active + enemy; excludes Boss/
  // MaxTac/police/mech/civilian/crowd/quest-affiliated). Ineligible skips
  // WITHOUT spending — a transient IsActive() miss during stream-in retries next
  // tick; record-static category flags never flip to a double-roll.
  if !EO_IsEligibleCombatHuman(puppet) {
    return;
  };
  // (3) SPEND the ledger entry NOW — the exactly-once point. Everything below
  // runs at most once per entity per session; roll failure and Elite-ceiling
  // no-op both leave the entry spent (no refund path).
  this.EO_UprankMarkRolled(id);
  // (4) Ladder: no valid target (Elite ceiling / non-upgradable) -> done.
  let current: gamedataNPCRarity = puppet.GetNPCRarity();
  let target: TweakDBID = EOUprank_TargetPath(current);
  if !TDBID.IsValid(target) {
    return;
  };
  // (5) The 30% roll — happens ONCE ever per entity (ledger already spent above).
  if !(RandF() < TierUprankConfig.UprankChance()) {
    return;
  };
  // (6) APPLY.
  this.EOUprank_ApplyUprank(puppet, id, current, target);
}

// The stat-emulation apply + per-uprank notify. Split out for readability; still
// an @addMethod(HUDManager) member (state host = this HUDManager).
@addMethod(HUDManager)
public final func EOUprank_ApplyUprank(puppet: ref<NPCPuppet>, id: EntityID, current: gamedataNPCRarity, target: TweakDBID) -> Void {
  let game: GameInstance = this.GetGameInstance();
  let statsSys: ref<StatsSystem> = GameInstance.GetStatsSystem(game);
  let poolsSys: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(game);
  // The stat/stat-pool systems key on StatsObjectID; an EntityID casts to one
  // (entityID.script:48 implicit cast; .reds needs it explicit, staging-proven).
  let sid: StatsObjectID = Cast<StatsObjectID>(id);
  // Read BEFORE any modifier: hp baseline for the notify, and the current damage
  // fraction (0-100 perc scale) to preserve across the max re-sync.
  let hpBefore: Float = statsSys.GetStatValue(sid, gamedataStatType.Health);
  let pctBefore: Float = poolsSys.GetStatPoolValue(sid, gamedataStatPoolType.Health, true);
  // (6a) Replay the target tier's StatModifier block — verbatim the vanilla
  // device-init pipeline (scriptableDeviceBasePS.script:535-554). If the
  // web-sourced path resolved to no record, DEGRADE PER-ENTITY to rung (b): skip
  // the replay, keep the PowerLevel/Level bump below (coarser but still cascades
  // Health/Level/DPS via the PowerLevel curves), and log the miss.
  let rec: ref<NPCRarity_Record> = TweakDBInterface.GetNPCRarityRecord(target);
  if IsDefined(rec) {
    let statList: array<wref<StatModifier_Record>>;
    rec.StatModifiers(statList);
    let mods: array<ref<gameStatModifierData>>;
    let j: Int32 = 0;
    while j < ArraySize(statList) {
      ArrayPush(mods, RPGManager.StatRecordToModifier(statList[j]));
      j += 1;
    };
    statsSys.AddModifiers(sid, mods);
  } else {
    if TierUprankConfig.DebugNotify() {
      EO_Notify(game, "EO uprank: MISSING " + TDBID.ToStringDEBUG(target));
    };
  };
  // (6b) PowerLevel pairing (anti self-cancel vs ScalePlayerDamage) + Level
  // pairing (mirrors NPCManager.ScaleToPlayer). Each a plain Additive AddModifier.
  if TierUprankConfig.PowerLevelBump() > 0.0 {
    statsSys.AddModifier(sid, RPGManager.CreateStatModifier(gamedataStatType.PowerLevel, gameStatModifierType.Additive, TierUprankConfig.PowerLevelBump()));
  };
  if TierUprankConfig.LevelBump() > 0.0 {
    statsSys.AddModifier(sid, RPGManager.CreateStatModifier(gamedataStatType.Level, gameStatModifierType.Additive, TierUprankConfig.LevelBump()));
  };
  // (6c) Health pool re-sync: refresh the cached max to reflect the new Health
  // stat, then restore the pre-uprank damage fraction. Read+write in the SAME
  // 0-100 perc scale (vanilla full-heal passes 100.0, NPCPuppet.script:3930) —
  // NO ratio conversion anywhere.
  poolsSys.RequestSettingStatPoolMaxValue(sid, gamedataStatPoolType.Health, puppet);
  poolsSys.RequestSettingStatPoolValue(sid, gamedataStatPoolType.Health, pctBefore, puppet, true);
  // (7) Per-uprank notify (gated): who, old->new tier, hp before->after. hpAfter
  // read immediately after apply is informational (native recompute timing
  // unproven — an unchanged read is not itself a failure).
  if TierUprankConfig.DebugNotify() {
    let hpAfter: Float = statsSys.GetStatValue(sid, gamedataStatType.Health);
    EO_Notify(game, "EO uprank: " + puppet.GetDisplayName()
      + " [" + EntityID.ToDebugString(id) + "] "
      + EOUprank_TierName(current) + "->" + EOUprank_TargetTierName(current)
      + " hp " + FloatToString(hpBefore) + "->" + FloatToString(hpAfter));
  };
}

// ============================ arm point ======================================
// PLAYER-object PlayerPuppet.OnGameAttached (player.script:1161) = GAME THREAD,
// once per load — NOT the per-arbitrary-entity GameObject streaming hook (worker
// threads -> heap corruption). @wrapMethod chains compose (each wrap calls
// wrappedMethod exactly once), so load order does not matter; we capture and
// return the inner Bool to preserve the chain's return value. ScannerSuite,
// SwitchSpeed and street_vendors all wrap this same method safely.
@wrapMethod(PlayerPuppet)
protected cb func OnGameAttached() -> Bool {
  let result: Bool = wrappedMethod();
  if TierUprankConfig.EnableTierUprank() {
    // HUDManager is a ScriptableSystem live during this very event (vanilla
    // queues PlayerAttachRequest to it here); GetHudManager (gameObject.script:
    // 3183) is therefore valid. IsDefined is belt-and-braces; the m_eoUprankArmed
    // guard inside EOUprank_Arm keeps this idempotent across replacer re-attaches.
    let hud: ref<HUDManager> = this.GetHudManager();
    if IsDefined(hud) {
      hud.EOUprank_Arm();
    };
  };
  return result;
}
