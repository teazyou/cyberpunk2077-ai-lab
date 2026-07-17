module EnemyOverhaul.Duplication
import EnemyOverhaul.Common.*

// =============================================================================
// Enemy Overhaul — F2 enemy-duplication (20% extra spawn)
// Locally-authored custom mod (no Nexus source). macOS / Steam / pure REDscript
// / game v2.3. One of three feature units under slug `custom-enemy-overhaul`;
// consumes the shared substrate `EnemyOverhaul.Common.*` (eligibility filter,
// clone registry, seen-set helpers, notify funnel).
//
// WHAT IT DOES: on a self-re-arming game-thread sweep, each eligible combat
// human near the player gets ONE 20% roll; on success an extra hostile enemy is
// spawned nearby that fights immediately and pays NO XP / drops NO loot. Depth
// is capped at 1 (a clone never duplicates) — clones are registered in Common's
// registry and skipped before the roll gate, yet stay eligible for F1's own
// single uprank roll.
//
// POSTURE B (experimental spawn path, per plan-enemy-duplication + search_index
// F2). The ONLY script-callable by-record spawn primitive on this platform is
// the native `PreventionSpawnSystem.RequestUnitSpawn(recordID, transform)`
// (preventionSpawnSystem.script:40). Its async result is delivered ONLY to a
// PRIVATE `PreventionSystem.OnPreventionUnitSpawnedRequest` handler that no-ops
// on unknown tickets — so we @wrapMethod that private handler and harvest the
// EXACT spawned-object handles for OUR requestIDs (zero heuristics; police
// tickets pass straight through untouched). State therefore lives on
// `PreventionSystem` (the harvest wrap is a member of it — rule-5 member access
// to our own @addField state, no cross-class shim).
//
// PROBE GATE M1 (game-launch-empirical, cannot be settled statically): whether
// native RequestUnitSpawn accepts arbitrary non-police records outside a heat
// context. Every roll/req/harvest/wire step emits a DebugNotify line so the
// user's M1 test can read it. FAIL SIGNATURE = "req #" lines with no matching
// "harvest" line -> flip DuplicationEnabled() to false (plan Rung 2, Posture A:
// nothing arms, all five wraps become pure passthrough — one const flip, no
// code deletion).
//
// SAFETY (all learned the hard way — see plan "What NOT to do"):
//  * Arm ONLY from the PLAYER-object PlayerPuppet.OnGameAttached (game thread);
//    NEVER per-entity GameObject.OnGameAttached (worker-thread heap corruption).
//  * No engine-state mutation inside the harvest wrap or inside OnIncapacitated
//    before wrappedMethod() — script-array pushes + DelayCallbackNextFrame
//    scheduling only (rule 3). Attitude / AI-command / inventory writes happen
//    only in the deferred, game-thread wiring & corpse-strip callbacks.
//  * No continue/break (if-wrapper skips + a boolean budget counter).
//  * All five hooks are @wrapMethod (rule 6, wraps chain); all added state is
//    session-transient (no persistent fields, no AddSavedModifier).
//  * RequestUnitSpawn is the ONLY spawn call; the requestID ticket match is the
//    ONLY clone-acquisition path (never GetEntityList poll-and-guess);
//    RequestDespawn/RequestDespawnAll are NEVER called (native police-tracked).
//
// ADDENDUM 2026-07-17 — dup-processed +10% max-HP bonus: every enemy this
// feature PROCESSES gets one extra multiplicative max-HP buff, exactly once per
// entity per session, regardless of its 20% roll outcome. "Processed" = (a)
// each SOURCE at its once-per-entity spend-on-roll moment in
// EODup_ProcessCandidate (before the roll — outcome-independent), and (b) each
// spawned CLONE at its deferred wiring moment in EODup_WireClone (clones never
// reach (a): the clone gate precedes the roll path). Exactly-once is enforced
// by a dedicated FIFO ledger (m_eodupHpBuffSeen — same array<EntityID> pattern
// as the roll ledger). Mechanism mirrors F1 TierUprank's staging-proven recipe:
// plain StatsSystem.AddModifier on Health (Multiplier, 1.0 + fraction) + Health
// stat-pool max re-sync restoring the pre-buff damage fraction. Session-
// transient (never AddSavedModifier); composes independently and safely with an
// F1 uprank on the same entity. Accepted caveat (same as F1's header):
// ScalePlayerDamage (damageSystem.script:3468-3502) rescales PLAYER-sourced
// damage by the target's Health ratio, so the buff shows fully in max HP and
// vs non-player damage but is largely cancelled for player TTK — the spec
// mandates max HP, not TTK. Consts: DupHpBonusEnabled() (default true),
// DupHpBonusFraction() (default 0.10).
// =============================================================================

// ============================ USER CONFIG ====================================
// All tunables. DuplicationEnabled()=false is the Posture-A bail-out: nothing
// arms and every wrap is a pure passthrough.
public abstract class EODuplicationConfig {

  // Master toggle. false = Posture A (feature fully dormant).
  public final static func DuplicationEnabled() -> Bool { return true; }

  // Once-per-source probability of spawning one extra enemy.
  public final static func DuplicateChance() -> Float { return 0.20; }

  // false = verbatim clone of the source record (v1 default, recommended by the
  // wiring dossier). true = PREFERRED same-faction curated pool: each pick is
  // null-checked (GetCharacterRecord) with automatic fallback to the verbatim
  // record; factions without a pool also fall back to verbatim.
  public final static func UseFactionPools() -> Bool { return false; }

  // Seconds between sweep ticks (index-sanctioned 0.5-1.0; ScannerSuite-proven).
  public final static func SweepInterval() -> Float { return 0.5; }

  // Delay of the first tick after player attach.
  public final static func FirstTickDelay() -> Float { return 1.0; }

  // Enumeration radius (m) around the player.
  public final static func SweepRange() -> Float { return 50.0; }

  // Spawn-request budget per tick; unprocessed candidates retried next tick.
  public final static func MaxSpawnRequestsPerTick() -> Int32 { return 1; }

  // Max random XY offset (m) of the navmesh query center from the source.
  public final static func PlacementJitter() -> Float { return 3.0; }

  // Navmesh point-in-sphere search radius (m).
  public final static func PlacementRadius() -> Float { return 3.0; }

  // Sweep ticks before an unharvested spawn request is dropped (~30 s @ 0.5 s).
  public final static func PendingTTLTicks() -> Int32 { return 60; }

  // AIInjectCombatThreatCommand.duration (vanilla's own value,
  // dynamicSpawnSystem.script:37).
  public final static func CloneThreatDuration() -> Float { return 120.0; }

  // Also fire SendStimDirectly(CombatHit) at wiring (secondary hostility
  // channel). Default off (attitude + combat-threat command is primary).
  public final static func CloneUseCombatStimFallback() -> Bool { return false; }

  // FIFO cap for the roll-seen set + the pending/wiring ledgers (EntityID-
  // recycling mitigation; matches Common's LedgerCap()).
  public final static func LedgerCap() -> Int32 { return 4096; }

  // --- addendum 2026-07-17: dup-processed HP bonus ---------------------------
  // Master toggle for the one-shot max-HP bonus on every dup-processed entity
  // (rolled sources — cloned or not — AND spawned clones). false = never
  // applied (the HP ledger stays untouched).
  public final static func DupHpBonusEnabled() -> Bool { return true; }

  // Extra max-HP fraction, applied multiplicatively exactly once per entity per
  // session (0.10 = +10%; the Health Multiplier value is 1.0 + this).
  public final static func DupHpBonusFraction() -> Float { return 0.10; }

  // HUD AddLog + FTLog on every roll/skip/request/harvest/wire/strip event.
  // These lines are M1-load-bearing — absence breaks the probe gate.
  public final static func DebugNotify() -> Bool { return true; }
}

// ============================ plain state records =============================

// One in-flight spawn request awaiting its harvest.
public class EODupPendingReq {
  public let requestId: Uint32;
  public let sourceId: EntityID;
  public let sourceRecord: TweakDBID;
  public let spawnRecord: TweakDBID;
  public let ageTicks: Int32;
}

// One harvested clone awaiting next-frame hostility wiring.
public class EODupWiringTask {
  public let clone: wref<GameObject>;
  public let cloneId: EntityID;
  public let sourceId: EntityID;
}

// ======================== self-re-arming callbacks ===========================
// DelayCallback base = delaySystem.script:41; shape mirrors ScannerSuite's
// STSweepTickCallback (ScannerSuite.reds:1372). Each holds a wref to the
// session-stable PreventionSystem and forwards to a member on the game thread.

public class EODupSweepCallback extends DelayCallback {
  public let system: wref<PreventionSystem>;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.EODup_SweepTick();
    };
  }
}

public class EODupWiringCallback extends DelayCallback {
  public let system: wref<PreventionSystem>;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.EODup_ProcessWiringQueue();
    };
  }
}

public class EODupCorpseStripCallback extends DelayCallback {
  public let system: wref<PreventionSystem>;
  public let cloneId: EntityID;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.EODup_StripCorpse(this.cloneId);
    };
  }
}

// ===================== state (all @addField(PreventionSystem)) ===============
// PreventionSystem extends ScriptableSystem (preventionSystem.script:1) — the
// harvest wrap is a member of it, so these are own-class member access (rule 5).
// All session-transient (never saved).
@addField(PreventionSystem) let m_eodupArmed: Bool;                            // sweep-loop double-arm guard
@addField(PreventionSystem) let m_eodupRollSeen: array<EntityID>;             // per-source once-only roll ledger (FIFO)
@addField(PreventionSystem) let m_eodupPending: array<ref<EODupPendingReq>>;  // in-flight spawn requests
@addField(PreventionSystem) let m_eodupWiringQueue: array<ref<EODupWiringTask>>; // harvested clones awaiting wiring
@addField(PreventionSystem) let m_eodupWiringScheduled: Bool;                 // a next-frame wiring drain is pending
@addField(PreventionSystem) let m_eodupHpBuffSeen: array<EntityID>;           // once-per-entity dup-HP-bonus ledger (FIFO, addendum 2026-07-17)

// #############################################################################
// # ARM — player attach (game thread, once per load)
// #############################################################################
// PLAYER-object OnGameAttached (player.script:1161) = game thread, safe. Wraps
// chain (ScannerSuite / SwitchSpeed / street_vendors all wrap it) — each calls
// wrappedMethod exactly once; we capture + return its Bool to preserve the
// chain. PreventionSystem is resolved from the container (live during this event
// — vanilla's own idiom, preventionSpawnSystem.script:81-92).
@wrapMethod(PlayerPuppet)
protected cb func OnGameAttached() -> Bool {
  let result: Bool = wrappedMethod();
  if EODuplicationConfig.DuplicationEnabled() {
    let system: ref<PreventionSystem> = GameInstance.GetScriptableSystemsContainer(this.GetGame())
      .Get(n"PreventionSystem") as PreventionSystem;
    if IsDefined(system) {
      system.EODup_Arm();
    };
  };
  return result;
}

@addMethod(PreventionSystem)
public final func EODup_Arm() -> Void {
  if this.m_eodupArmed {
    return; // a tick is already pending — never run two loops (replacer re-attach)
  };
  let tick: ref<EODupSweepCallback> = new EODupSweepCallback();
  tick.system = this;
  GameInstance.GetDelaySystem(this.GetGameInstance())
    .DelayCallback(tick, EODuplicationConfig.FirstTickDelay(), false);
  this.m_eodupArmed = true;
}

// #############################################################################
// # SWEEP TICK — detect eligible enemies, roll, spawn
// #############################################################################
@addMethod(PreventionSystem)
public final func EODup_SweepTick() -> Void {
  // 1. Disabled -> permanent stop (only non-re-arming path; dead in practice,
  //    config is static). Clears the guard so a later attach can re-arm.
  if !EODuplicationConfig.DuplicationEnabled() {
    this.m_eodupArmed = false;
    return;
  };
  let gi: GameInstance = this.GetGameInstance();
  // 2. FAULT-PROOF RE-ARM FIRST (ScannerSuite.reds:1439) — schedule the
  //    successor tick before ANY work, so a fault below can never kill the loop.
  let tick: ref<EODupSweepCallback> = new EODupSweepCallback();
  tick.system = this;
  GameInstance.GetDelaySystem(gi).DelayCallback(tick, EODuplicationConfig.SweepInterval(), false);
  // 3. Resolve player + skip-but-stay-alive gate (loop stays armed above).
  let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(gi)
    .GetLocalPlayerMainGameObject() as PlayerPuppet;
  if !IsDefined(player) || player.IsReplacer() {
    return;
  };
  let hud: ref<HUDManager> = player.GetHudManager();
  if IsDefined(hud) && hud.IsBraindanceActive() {
    return;
  };
  // 4. Age the pending ledger (drop unharvested requests past TTL); backstop-
  //    drain the wiring queue (primary drain is the next-frame callback).
  this.EODup_AgePending();
  if ArraySize(this.m_eodupWiringQueue) > 0 {
    this.EODup_ProcessWiringQueue();
  };
  // 5. Detect-new: GetNPCsAroundObject (TSF_NPC, 360deg — INCLUDES not-yet-
  //    hostile gang NPCs; never TSF_EnemyNPC which pre-filters to hostile only).
  let npcs: array<ref<NPCPuppet>> = player.GetNPCsAroundObject(EODuplicationConfig.SweepRange());
  // 6. Per candidate, budget-gated. budgetLeft starts at the per-tick cap;
  //    candidates are only PROCESSED while budgetLeft > 0, so an un-processed
  //    candidate spends nothing (no seen mark) and is retried next tick.
  let budgetLeft: Int32 = EODuplicationConfig.MaxSpawnRequestsPerTick();
  let i: Int32 = 0;
  while i < ArraySize(npcs) {
    if budgetLeft > 0 {
      let npc: ref<NPCPuppet> = npcs[i];
      if IsDefined(npc) {
        if this.EODup_ProcessCandidate(player, npc) {
          budgetLeft -= 1; // a spawn request was actually sent
        };
      };
    };
    i += 1;
  };
}

// Returns true iff a spawn REQUEST was sent for this candidate (the caller then
// spends one budget unit). Every other outcome (clone/seen/eligibility/roll-
// fail/placement-fail) returns false and spends no budget.
@addMethod(PreventionSystem)
public final func EODup_ProcessCandidate(player: ref<PlayerPuppet>, npc: ref<NPCPuppet>) -> Bool {
  let gi: GameInstance = this.GetGameInstance();
  let id: EntityID = npc.GetEntityID();
  // clone gate FIRST — depth cap = 1, permanent (a marked clone never rolls).
  if EO_IsClone(gi, id) {
    return false;
  };
  // seen gate — this source already had its single roll.
  if EO_SeenContains(this.m_eodupRollSeen, id) {
    return false;
  };
  // eligibility (Common composite) — do NOT mark seen on failure: an NPC that
  // later becomes eligible (IsActive / hostility flips) still gets its one roll.
  if !EO_IsEligibleCombatHuman(npc) {
    return false;
  };
  // Null Character_Record -> INELIGIBLE (acceptance S33). Common's shared
  // composite is deliberately least-exclusionary — a null record there falls
  // THROUGH to ELIGIBLE (Common.reds:82-89) — but S33 demands the opposite, and
  // Common is read-only. So enforce the null-record exclusion locally here as a
  // same-shape eligibility refinement, BEFORE the seen-write (never marks the
  // candidate seen — consistent with the eligibility gate above; if the record
  // ever resolves later, the NPC still gets its single roll). Pathological for a
  // streamed combat human, but the criterion is exact. GetCharacterRecord is
  // already used below in EODup_PickSpawnRecord (tweakDB.script:371).
  if !IsDefined(TweakDBInterface.GetCharacterRecord(npc.GetRecordID())) {
    return false;
  };
  // roll-once: SPEND-ON-ROLL — mark seen BEFORE rolling / placing / spawning, so
  // a placement or spawn failure never refunds the roll (FIFO cap = LedgerCap()).
  EO_SeenTryAdd(this.m_eodupRollSeen, id, EODuplicationConfig.LedgerCap());
  // addendum 2026-07-17: dup-processed HP bonus — THE once-per-entity processing
  // moment for SOURCES. Positioned before the roll below, so a failed 20% roll
  // still buffs (outcome-independent). Exactly-once via the dedicated HP ledger
  // inside (safe against re-entry; clones never reach here — clone gate above).
  this.EODup_ApplyHpBonus(npc);
  // The single roll site (idiom NPCPuppet.script:893; rand.script:3).
  let rollHit: Bool = RandF() < EODuplicationConfig.DuplicateChance();
  if !rollHit {
    return false; // roll failed — done with this source forever
  };
  this.EODup_Notify("roll OK src=" + EntityID.ToDebugString(id));
  // placement: validated navmesh point, or silent skip (roll stays spent).
  let point: Vector4;
  if !this.EODup_FindSpawnPoint(npc.GetWorldPosition(), point) {
    this.EODup_Notify("placement FAIL — skip");
    return false;
  };
  // identity + transform (vanilla SpawnUnits recipe, preventionSystem.script:2830).
  let spawnRecord: TweakDBID = this.EODup_PickSpawnRecord(npc);
  let xform: WorldTransform;
  WorldTransform.SetPosition(xform, point);
  WorldTransform.SetOrientationFromDir(xform, Vector4.Normalize2D(player.GetWorldPosition() - point));
  // spawn: the ONLY by-record spawn primitive on this platform.
  let reqId: Uint32 = GameInstance.GetPreventionSpawnSystem(gi).RequestUnitSpawn(spawnRecord, xform);
  // ledger the request for harvest matching (FIFO-capped).
  let pend: ref<EODupPendingReq> = new EODupPendingReq();
  pend.requestId = reqId;
  pend.sourceId = id;
  pend.sourceRecord = npc.GetRecordID();
  pend.spawnRecord = spawnRecord;
  pend.ageTicks = 0;
  ArrayPush(this.m_eodupPending, pend);
  if ArraySize(this.m_eodupPending) > EODuplicationConfig.LedgerCap() {
    ArrayErase(this.m_eodupPending, 0);
  };
  this.EODup_Notify("req #" + ToString(Cast<Int32>(reqId)) + " rec=" + TDBID.ToStringDEBUG(spawnRecord) + " pos OK");
  return true;
}

// Placement — validated or silent skip (brief rule). Query center = source
// position with bounded random XY jitter (struct-field mutation idiom =
// navigationSystem.script:66-86). Primary FindPointInSphere, fallback nearest-
// below; both fail -> false (caller skips, no spawn).
@addMethod(PreventionSystem)
public final func EODup_FindSpawnPoint(sourcePos: Vector4, out point: Vector4) -> Bool {
  let nav: ref<NavigationSystem> = GameInstance.GetNavigationSystem(this.GetGameInstance());
  let jitter: Float = EODuplicationConfig.PlacementJitter();
  let center: Vector4 = sourcePos;
  center.X += RandRangeF(-jitter, jitter);
  center.Y += RandRangeF(-jitter, jitter);
  // primary: point-in-sphere on the human navmesh (heightDetail=false is the
  // only vanilla-precedented value, navigationSystem.script:73).
  let res: NavigationFindPointResult = nav.FindPointInSphereOnlyHumanNavmesh(
    center, EODuplicationConfig.PlacementRadius(), NavGenAgentSize.Human, false);
  if Equals(res.status, worldNavigationRequestStatus.OK) {
    point = res.point;
    return true;
  };
  // fallback: ground-snap-downward search (vanilla params 1.0, 5 —
  // deviceBase.script:3244); Vector4.IsZero == total failure.
  let below: Vector4 = nav.GetNearestNavmeshPointBelowOnlyHumanNavmesh(center, 1.0, 5);
  if !Vector4.IsZero(below) {
    point = below;
    return true;
  };
  return false;
}

// Identity pick. v1 DEFAULT = verbatim clone of the source record. With
// UseFactionPools() the PREFERRED same-faction curated pool is used, keyed via
// Affiliation().Type(); EVERY branch null-checks and falls back to verbatim.
// (Acceptance S33's null-record -> INELIGIBLE is enforced UPSTREAM in
// EODup_ProcessCandidate, not here — this site only picks a spawn IDENTITY and
// can never reach an already-ineligible source.)
@addMethod(PreventionSystem)
public final func EODup_PickSpawnRecord(source: ref<NPCPuppet>) -> TweakDBID {
  let verbatim: TweakDBID = source.GetRecordID();
  if !EODuplicationConfig.UseFactionPools() {
    return verbatim;
  };
  let rec: ref<Character_Record> = TweakDBInterface.GetCharacterRecord(verbatim);
  if !IsDefined(rec) {
    return verbatim; // null source record -> verbatim (which is what we already hold)
  };
  let aff: wref<Affiliation_Record> = rec.Affiliation();
  if !IsDefined(aff) {
    return verbatim;
  };
  let pool: array<TweakDBID> = this.EODup_FactionPool(aff.Type());
  if ArraySize(pool) == 0 {
    return verbatim; // faction has no curated pool -> verbatim
  };
  let pick: TweakDBID = pool[RandRange(0, ArraySize(pool))]; // RandRange max is EXCLUSIVE
  if !IsDefined(TweakDBInterface.GetCharacterRecord(pick)) {
    return verbatim; // stale/invalid pool ID -> verbatim
  };
  return pick;
}

// Curated per-faction generic-grunt pools (starter set harvested + cross-
// validated in research/round1-spawn-wiring.md Finding 9; two IDs marked (X)
// are independently confirmed vanilla data). Default-off; each pick is null-
// checked at the call site above. Only the 8 open-world street-gang factions
// are covered — every other affiliation returns empty -> verbatim fallback.
@addMethod(PreventionSystem)
public final func EODup_FactionPool(aff: gamedataAffiliation) -> array<TweakDBID> {
  let pool: array<TweakDBID>;
  if Equals(aff, gamedataAffiliation.Animals) {
    ArrayPush(pool, t"Character.animals_grunt1_ranged1_nova_mb");
    ArrayPush(pool, t"Character.animals_grunt1_ranged1_pulsar_mb");
    ArrayPush(pool, t"Character.animals_grunt2_ranged2_overture_mb");
    ArrayPush(pool, t"Character.animals_bouncer1_ranged1_kenshin_mb");
  } else {
    if Equals(aff, gamedataAffiliation.Barghest) {
      ArrayPush(pool, t"Character.bou_kurtz_grunt1_ranged1_handgun_ma");
      ArrayPush(pool, t"Character.bou_kurtz_grunt1_ranged1_saratoga_ma");
      ArrayPush(pool, t"Character.high_kurtz_grunt1_ranged1_handgun_ma");
      ArrayPush(pool, t"Character.high_kurtz_grunt1_ranged1_saratoga_ma");
    } else {
      if Equals(aff, gamedataAffiliation.Maelstrom) {
        ArrayPush(pool, t"Character.maelstrom_grunt1_ranged1_lexington_ma"); // (X) cross-validated
        ArrayPush(pool, t"Character.maelstrom_grunt1_ranged1_copperhead_ma");
        ArrayPush(pool, t"Character.maelstrom_grunt2_ranged2_ajax_ma");
        ArrayPush(pool, t"Character.maelstrom_grunt1_melee1_knife_ma");
      } else {
        if Equals(aff, gamedataAffiliation.Scavengers) {
          ArrayPush(pool, t"Character.scavenger_grunt1_ranged1_nova_ma");
          ArrayPush(pool, t"Character.scavenger_grunt1_ranged1_pulsar_ma");
          ArrayPush(pool, t"Character.scavenger_grunt2_ranged2_copperhead_ma");
          ArrayPush(pool, t"Character.scavenger_grunt1_melee1_tireiron_ma");
        } else {
          if Equals(aff, gamedataAffiliation.SixthStreet) {
            ArrayPush(pool, t"Character.sixthstreet_hooligan_ranged1_nova_ma");
            ArrayPush(pool, t"Character.sixthstreet_hooligan_ranged1_saratoga_ma");
            ArrayPush(pool, t"Character.sixthstreet_menace1_shotgun2_tactician_ma");
            ArrayPush(pool, t"Character.sixthstreet_hooligan_melee1_knife_ma");
          } else {
            if Equals(aff, gamedataAffiliation.TygerClaws) {
              ArrayPush(pool, t"Character.tyger_claws_gangster1_ranged1_copperhead_ma");
              ArrayPush(pool, t"Character.tyger_claws_gangster1_ranged1_nue_ma");
              ArrayPush(pool, t"Character.tyger_claws_gangster2_ranged2_shingen_ma");
              ArrayPush(pool, t"Character.tyger_claws_biker1_ranged1_nue_ma");
            } else {
              if Equals(aff, gamedataAffiliation.Valentinos) {
                ArrayPush(pool, t"Character.valentinos_grunt1_ranged1_nova_ma"); // (X) cross-validated
                ArrayPush(pool, t"Character.valentinos_grunt1_ranged1_nue_ma");
                ArrayPush(pool, t"Character.valentinos_grunt2_ranged2_ajax_ma");
                ArrayPush(pool, t"Character.valentinos_grunt1_melee1_knife_ma");
              } else {
                if Equals(aff, gamedataAffiliation.Wraiths) {
                  ArrayPush(pool, t"Character.bls_se_wraiths_grunt1_ranged1_nova_ma");
                  ArrayPush(pool, t"Character.bls_se_wraiths_grunt1_ranged1_pulsar_ma");
                  ArrayPush(pool, t"Character.bls_se_wraiths_grunt2_ranged2_copperhead_ma");
                  ArrayPush(pool, t"Character.bls_se_wraiths_grunt1_melee1_tireiron_ma");
                };
              };
            };
          };
        };
      };
    };
  };
  return pool;
}

// Age the pending ledger one tick; drop entries past TTL (notify each drop).
@addMethod(PreventionSystem)
public final func EODup_AgePending() -> Void {
  let ttl: Int32 = EODuplicationConfig.PendingTTLTicks();
  let i: Int32 = 0;
  while i < ArraySize(this.m_eodupPending) {
    let p: ref<EODupPendingReq> = this.m_eodupPending[i];
    p.ageTicks += 1;
    if p.ageTicks > ttl {
      this.EODup_Notify("req #" + ToString(Cast<Int32>(p.requestId)) + " TTL — dropped");
      ArrayErase(this.m_eodupPending, i); // do NOT advance i — array shifted down
    } else {
      i += 1;
    };
  };
}

// #############################################################################
// # HARVEST — private-wrap the native spawn-result handler
// #############################################################################
// Native queues a PreventionUnitSpawnedRequest for EVERY spawn result
// unconditionally (preventionSpawnSystem.script:81-92); vanilla's private
// handler no-ops on unknown tickets (PopRequestTicket fails -> return,
// preventionSystem.script:1875-1890). We ALWAYS pass through to
// wrappedMethod(request) FIRST (police bookkeeping must always run), then react
// ONLY to requestIDs present in OUR pending ledger — EXACT handles, zero
// heuristics, our tickets invisible to police bookkeeping. NO engine-state
// mutation here (rule 3): script-array reads/writes + the Common registry mark
// (pure script state) + DelayCallbackNextFrame scheduling only.
@wrapMethod(PreventionSystem)
private func OnPreventionUnitSpawnedRequest(request: ref<PreventionUnitSpawnedRequest>) -> Void {
  wrappedMethod(request); // ALWAYS — vanilla no-ops our tickets; police tickets need it
  if !EODuplicationConfig.DuplicationEnabled() || !IsDefined(request) {
    return;
  };
  let reqId: Uint32 = request.requestResult.requestID;
  // find OUR ledger entry (only-first via the idx<0 guard; no break needed).
  let idx: Int32 = -1;
  let i: Int32 = 0;
  while i < ArraySize(this.m_eodupPending) {
    if idx < 0 && this.m_eodupPending[i].requestId == reqId {
      idx = i;
    };
    i += 1;
  };
  if idx < 0 {
    return; // not our ticket (police spawn / already harvested) — pass through
  };
  // capture the source id BEFORE removing the ledger entry.
  let sourceId: EntityID = this.m_eodupPending[idx].sourceId;
  ArrayErase(this.m_eodupPending, idx);
  let result: SpawnRequestResult = request.requestResult;
  if !result.success || ArraySize(result.spawnedObjects) == 0 {
    this.EODup_Notify("harvest #" + ToString(Cast<Int32>(reqId)) + " FAIL success=" + ToString(result.success));
    return;
  };
  let gi: GameInstance = this.GetGameInstance();
  let n: Int32 = 0;
  let j: Int32 = 0;
  while j < ArraySize(result.spawnedObjects) {
    let obj: wref<GameObject> = result.spawnedObjects[j];
    if IsDefined(obj) {
      let cid: EntityID = obj.GetEntityID();
      // Mark clone SYNCHRONOUSLY (pure script-array state, NOT engine state —
      // closes the race where a sweep tick sees the clone before wiring).
      EO_MarkClone(gi, cid);
      let task: ref<EODupWiringTask> = new EODupWiringTask();
      task.clone = obj;
      task.cloneId = cid;
      task.sourceId = sourceId;
      ArrayPush(this.m_eodupWiringQueue, task);
      if ArraySize(this.m_eodupWiringQueue) > EODuplicationConfig.LedgerCap() {
        ArrayErase(this.m_eodupWiringQueue, 0);
      };
      n += 1;
    };
    j += 1;
  };
  this.EODup_Notify("harvest #" + ToString(Cast<Int32>(reqId)) + " n=" + ToString(n) + " success=" + ToString(result.success));
  // Schedule ONE next-frame wiring drain if not already pending.
  if n > 0 && !this.m_eodupWiringScheduled {
    let cb: ref<EODupWiringCallback> = new EODupWiringCallback();
    cb.system = this;
    GameInstance.GetDelaySystem(gi).DelayCallbackNextFrame(cb);
    this.m_eodupWiringScheduled = true;
  };
}

// #############################################################################
// # WIRE — deferred, game-thread hostility wiring (next frame)
// #############################################################################
@addMethod(PreventionSystem)
public final func EODup_ProcessWiringQueue() -> Void {
  let gi: GameInstance = this.GetGameInstance();
  // Snapshot + clear the queue and reset the scheduled flag FIRST (so a harvest
  // landing during this drain re-schedules cleanly).
  let tasks: array<ref<EODupWiringTask>> = this.m_eodupWiringQueue;
  ArrayClear(this.m_eodupWiringQueue);
  this.m_eodupWiringScheduled = false;
  let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(gi)
    .GetLocalPlayerMainGameObject() as PlayerPuppet;
  let i: Int32 = 0;
  while i < ArraySize(tasks) {
    let task: ref<EODupWiringTask> = tasks[i];
    if !IsDefined(task.clone) {
      this.EODup_Notify("wire anomaly — clone gone id=" + EntityID.ToDebugString(task.cloneId));
    } else {
      // Resolve a strong typed handle (FindEntityByID — aiComponent.script:376
      // precedent); the clone is alive one frame after harvest.
      let clone: ref<ScriptedPuppet> = GameInstance.FindEntityByID(gi, task.cloneId) as ScriptedPuppet;
      if IsDefined(clone) {
        this.EODup_WireClone(clone, task.sourceId, player);
      } else {
        this.EODup_Notify("wire anomaly — resolve fail id=" + EntityID.ToDebugString(task.cloneId));
      };
    };
    i += 1;
  };
}

@addMethod(PreventionSystem)
public final func EODup_WireClone(clone: ref<ScriptedPuppet>, sourceId: EntityID, player: ref<PlayerPuppet>) -> Void {
  let gi: GameInstance = this.GetGameInstance();
  // telemetry-only kill-reward flag (bonus, disposalDevice.script:302 precedent).
  clone.DisableKillReward(true);
  // addendum 2026-07-17: dup-processed HP bonus — CLONES are dup-processed
  // entities but never reach the source-side apply (the clone gate precedes the
  // roll path), so they get their one-shot buff HERE, at registration/wiring
  // time (deferred game-thread callback — stat writes are legal here, unlike
  // the harvest wrap). Exactly-once via the dedicated HP ledger inside.
  this.EODup_ApplyHpBonus(clone);
  let cloneAgent: ref<AttitudeAgent> = clone.GetAttitudeAgent();
  // attitude-group copy from the source when it still resolves (aiRole.script:315
  // idiom) — matches the source's real in-game group.
  let source: ref<ScriptedPuppet> = GameInstance.FindEntityByID(gi, sourceId) as ScriptedPuppet;
  if IsDefined(source) && IsDefined(cloneAgent) {
    let srcAgent: ref<AttitudeAgent> = source.GetAttitudeAgent();
    if IsDefined(srcAgent) {
      cloneAgent.SetAttitudeGroup(srcAgent.GetAttitudeGroup());
    };
  };
  // ALWAYS hostile toward the player (spawned NPCs do NOT inherit hostility —
  // vanilla proof dynamicSpawnSystem.script:42-56).
  if IsDefined(player) && IsDefined(cloneAgent) {
    let playerAgent: ref<AttitudeAgent> = player.GetAttitudeAgent();
    if IsDefined(playerAgent) {
      cloneAgent.SetAttitudeTowards(playerAgent, EAIAttitude.AIA_Hostile);
    };
  };
  // combat-threat injection = "fight immediately" (verbatim vanilla recipe,
  // dynamicSpawnSystem.script:18-40; human-gated inside SendCommand = matches
  // our humans-only eligibility for free).
  let cmd: ref<AIInjectCombatThreatCommand> = new AIInjectCombatThreatCommand();
  let emptyNames: array<CName>;
  let playerRef: String = "#player";
  cmd.targetPuppetRef = CreateEntityReference(playerRef, emptyNames);
  cmd.duration = EODuplicationConfig.CloneThreatDuration();
  AIComponent.SendCommand(clone, cmd);
  // optional secondary hostility channel.
  if EODuplicationConfig.CloneUseCombatStimFallback() && IsDefined(player) {
    StimBroadcasterComponent.SendStimDirectly(player, gamedataStimType.CombatHit, clone);
  };
  let grp: CName;
  if IsDefined(cloneAgent) {
    grp = cloneAgent.GetAttitudeGroup();
  };
  this.EODup_Notify("wired clone=" + EntityID.ToDebugString(clone.GetEntityID()) + " group=" + NameToString(grp));
}

// #############################################################################
// # DUP-PROCESSED HP BONUS (addendum 2026-07-17) — one-shot +10% max HP
// #############################################################################
// Applied to EVERY entity the duplication feature processes: each rolled source
// (at the spend-on-roll moment in EODup_ProcessCandidate — outcome-independent)
// and each spawned clone (at wiring in EODup_WireClone). Exactly once per
// entity per session: the EO_SeenTryAdd result on the dedicated FIFO ledger
// m_eodupHpBuffSeen IS the gate, so re-streamed NPCs / duplicate wiring tasks
// can never stack a second buff, and there is no removal/refund path (that
// absence is the guarantee — Common-ledger precedent). Mechanism = F1
// TierUprank's staging-proven recipe (EOUprank_ApplyUprank 6a/6c): plain
// StatsSystem.AddModifier (statsSystem.script:38; NEVER AddSavedModifier — the
// session ledger resets on load, a saved modifier would stack) on
// gamedataStatType.Health, then Health-pool max re-sync + pre-buff damage-
// fraction restore in the SAME 0-100 perc scale (statPoolsSystem.script:50-51).
// Modifier shape: gameStatModifierType.Multiplier (enum statsData.script:13)
// with value 1.0 + DupHpBonusFraction() — Multiplier value semantics are a
// DIRECT FACTOR (vanilla precedents: 1.0 = neutral playerWeaponHandler.script:
// 24, 0.0 = zero-out vendor.script:569, inverse 1.0/x locomotionTransitions.
// script:2591), so 1.10 = x1.10 = +10% max HP. A Multiplier composes
// independently of F1's replayed NPCRarity StatModifier block and its Additive
// PowerLevel/Level pairing — order-independent, no shared state, and both
// recipes' pool re-syncs preserve the damage fraction (F1-stacking-safe).
@addMethod(PreventionSystem)
public final func EODup_ApplyHpBonus(puppet: ref<ScriptedPuppet>) -> Void {
  if !EODuplicationConfig.DupHpBonusEnabled() || !IsDefined(puppet) {
    return;
  };
  let id: EntityID = puppet.GetEntityID();
  // exactly-once gate: false = already buffed this session (never stacks).
  if !EO_SeenTryAdd(this.m_eodupHpBuffSeen, id, EODuplicationConfig.LedgerCap()) {
    return;
  };
  let gi: GameInstance = this.GetGameInstance();
  let statsSys: ref<StatsSystem> = GameInstance.GetStatsSystem(gi);
  let poolsSys: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(gi);
  // EntityID -> StatsObjectID explicit cast (entityID.script:48 implicit cast;
  // .reds needs it explicit — TierUprank staging-proven).
  let sid: StatsObjectID = Cast<StatsObjectID>(id);
  // Read BEFORE the modifier: hp baseline for the notify + the current damage
  // fraction (0-100 perc scale) to preserve across the max re-sync.
  let hpBefore: Float = statsSys.GetStatValue(sid, gamedataStatType.Health);
  let pctBefore: Float = poolsSys.GetStatPoolValue(sid, gamedataStatPoolType.Health, true);
  // The single modifier site (rpgManager.script:1612 CreateStatModifier).
  statsSys.AddModifier(sid, RPGManager.CreateStatModifier(
    gamedataStatType.Health, gameStatModifierType.Multiplier,
    1.0 + EODuplicationConfig.DupHpBonusFraction()));
  // Health-pool re-sync: refresh the cached max to the new Health stat, then
  // restore the pre-buff damage fraction (recipe verbatim TierUprank 6c; the
  // vanilla full-heal passes 100.0 on the same perc scale, NPCPuppet.script:3930).
  poolsSys.RequestSettingStatPoolMaxValue(sid, gamedataStatPoolType.Health, puppet);
  poolsSys.RequestSettingStatPoolValue(sid, gamedataStatPoolType.Health, pctBefore, puppet, true);
  // ONE gated notify per applied buff (hpAfter read is informational — native
  // recompute timing unproven; an unchanged read is not itself a failure).
  let hpAfter: Float = statsSys.GetStatValue(sid, gamedataStatType.Health);
  this.EODup_Notify("hpbuff +" + FloatToString(EODuplicationConfig.DupHpBonusFraction() * 100.0)
    + "% id=" + EntityID.ToDebugString(id)
    + " hp " + FloatToString(hpBefore) + "->" + FloatToString(hpAfter));
}

// #############################################################################
// # DEATH-TIME SUPPRESSION — corpse strip (deferred, game thread)
// #############################################################################
// Clears the corpse inventory + re-evaluates loot quality so the corpse exits
// EGameplayRole.Loot (no mappin/highlight/prompt). Death-time ONLY — stripping
// at spawn/wiring would disarm the clone.
@addMethod(PreventionSystem)
public final func EODup_StripCorpse(cloneId: EntityID) -> Void {
  let gi: GameInstance = this.GetGameInstance();
  let clone: ref<ScriptedPuppet> = GameInstance.FindEntityByID(gi, cloneId) as ScriptedPuppet;
  if !IsDefined(clone) {
    return;
  };
  GameInstance.GetTransactionSystem(gi).RemoveAllItems(clone);
  ScriptedPuppet.EvaluateLootQualityByTask(clone);
  this.EODup_Notify("strip clone=" + EntityID.ToDebugString(cloneId));
}

// #############################################################################
// # REWARD-SUPPRESSION WRAPS (per plan tier; all @wrapMethod, rule 6)
// #############################################################################

// XP choke point: AwardsExperience()==false short-circuits proficiency XP
// (rpgManager.script:2116) + bounty (bountyManager.script:230) + status-effect
// rewards (executorGivePlayerReward.script:19) for the clone's whole life.
// const wrap (P1-proven): only const-safe calls inside — GetGame() (const
// final), GetEntityID() (const), and Common's GameInstance-keyed EO_IsClone
// (no `this`, const-context-safe by construction).
@wrapMethod(ScriptedPuppet)
public const func AwardsExperience() -> Bool {
  if EODuplicationConfig.DuplicationEnabled() && EO_IsClone(this.GetGame(), this.GetEntityID()) {
    return false;
  };
  return wrappedMethod();
}

// Loot container + corpse lootability: run vanilla ProcessLoot + bookkeeping
// FIRST (wrappedMethod), THEN for clones schedule the deferred corpse strip
// (NO engine mutation before wrappedMethod — rule 3). Covers both lethal and
// takedown paths (NPCPuppet.script:3935-3987).
@wrapMethod(NPCPuppet)
protected func OnIncapacitated() -> Void {
  wrappedMethod();
  if !EODuplicationConfig.DuplicationEnabled() {
    return;
  };
  let gi: GameInstance = this.GetGame();
  if !EO_IsClone(gi, this.GetEntityID()) {
    return;
  };
  let system: ref<PreventionSystem> = GameInstance.GetScriptableSystemsContainer(gi)
    .Get(n"PreventionSystem") as PreventionSystem;
  if !IsDefined(system) {
    return;
  };
  let cb: ref<EODupCorpseStripCallback> = new EODupCorpseStripCallback();
  cb.system = system;
  cb.cloneId = this.GetEntityID();
  GameInstance.GetDelaySystem(gi).DelayCallbackNextFrame(cb);
}

// Dropped weapon: for clones return false WITHOUT calling wrappedMethod (no
// world-dropped weapon entity); non-clones pass through
// (scriptedPuppet.script:3092-3119; private wrap = P2-proven).
@wrapMethod(ScriptedPuppet)
private func DropHeldItems() -> Bool {
  if EODuplicationConfig.DuplicationEnabled() && EO_IsClone(this.GetGame(), this.GetEntityID()) {
    return false;
  };
  return wrappedMethod();
}

// #############################################################################
// # DEBUG NOTIFY — the single gated funnel (M1-load-bearing)
// #############################################################################
// Self-gates on DebugNotify(); routes through Common's EO_Notify (AddLog +
// FTLog, activityLogSystem.script:7 / testStepLogicImport.script:29). Every
// notify site in this file calls THIS method, so DebugNotify() is the one gate.
@addMethod(PreventionSystem)
public final func EODup_Notify(msg: String) -> Void {
  if !EODuplicationConfig.DebugNotify() {
    return;
  };
  EO_Notify(this.GetGameInstance(), "EO-Dup: " + msg);
}
