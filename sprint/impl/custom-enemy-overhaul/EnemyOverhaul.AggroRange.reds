module EnemyOverhaul.AggroRange
import EnemyOverhaul.Common.*

// =============================================================================
// Enemy Overhaul — Aggro Range (feature F3)
// Locally-authored, CLEAN-ROOM REDscript port of the behavior of Nexus 19351
// "Enemy Aggro Improvements". macOS / Steam / pure REDscript / game v2.3. The
// original ships a mix of TweakDB tweaks + two ReactionManagerComponent
// replacers; TweakDB is read-only at runtime here, so the data edits are
// reproduced at their runtime consumption points via wraps. NOTHING is copied
// from the reference source — structure, names and comments are original; only
// vanilla-decompile-derived log strings are shared (their source is the game).
//
// The single knob users normally touch is EnableAggroRange() below. With it OFF
// every one of the five hooks behaves exactly vanilla (the replacers restore
// vanilla values/structure, the chokepoint wraps inject nothing, the district
// map returns the wrapped value untouched).
//
// TWO HALVES:
//   Half A — two @replaceMethod(ReactionManagerComponent). These are the ONLY
//     replacers in the whole mod (its siblings are wrap/add only). Replace is
//     required, not preferred: each delta REMOVES a distance gate from the
//     MIDDLE of an interleaved early-return chain, which a wrap (before/after
//     wrappedMethod only) cannot do.
//       * ShouldIgnoreCombatStim (8-arg) — makes NPCs stop ignoring player
//         combat stims: danger radius 12 -> 35 m (D1); explosions never
//         ignorable (D2); illegal-action-at-me loses its distance gate, becomes
//         direction-only (D3); a stim with no instigator is never ignorable
//         (D4). Everything else stays vanilla-exact and in vanilla order.
//       * ShouldHelpTargetFromSameAttitudeGroup — NPCs help same-faction allies
//         whose target is the player: help if affiliation OR attitude group
//         matches (D5); the "...unless the target is the player" exemption is
//         removed (D6). Police work-spot join-chase branch preserved verbatim.
//   Half B — three @wrapMethod reproducing the reference's TweakDB radius/range
//     edits at consumption:
//       * StimBroadcasterComponent.TriggerSingleBroadcast — record-fallback
//         (radius 0) Gunshot -> 50, Explosion -> 50 (covers NPC gunfire and the
//         player ground-slam). Explicit non-zero radii pass through untouched.
//       * StimBroadcasterComponent.OnBroadcastEvent — belt-and-suspenders
//         closure of the same funnel for any non-vanilla producer; silent.
//       * PlayerPuppet.GetGunshotRange — district gunshot range bucket map
//         (Dogtown 20 -> 30, standard 30 -> 50, Badlands 45 -> 50), never
//         reducing a value another mod already raised (MaxF).
//
// STATELESS: no attach hook, no tick loop, no per-entity ledger, no RNG. The
// only mutable state in the file is one debug-throttle timestamp on HUDManager.
// SilencedGunshot / IllegalAction radii are deliberately never touched (stealth
// balance survives). No new stim is ever emitted — this mod only widens signals
// that vanilla already produces.
// =============================================================================

// ============================ USER CONFIG ====================================
// Edit the literals, relaunch to apply. Percentages/ranges/caps in meters.
public abstract class AggroRangeConfig {

  // Master toggle. false => all five hooks behave 100% vanilla (D1-D6 revert,
  // chokepoints inject nothing, district map is a pass-through).
  public final static func EnableAggroRange() -> Bool { return true; }

  // D1 — combat-stim danger radius (meters). Vanilla is 12.
  public final static func DangerRange() -> Float { return 35.0; }

  // Vanilla danger baseline (reactionComponent danger check). Used on the
  // toggle-off path AND as the "accepted only because we widened it" compare
  // that decides whether a debug line fires. Do NOT change.
  public final static func VanillaDangerRange() -> Float { return 12.0; }

  // Injected radius for radius-0 Gunshot broadcasts (vanilla record is 30).
  public final static func GunshotFallbackRadius() -> Float { return 50.0; }

  // Injected radius for radius-0 Explosion broadcasts (vanilla record is 25).
  public final static func ExplosionFallbackRadius() -> Float { return 50.0; }

  // Mapped player gunshot range for standard districts (vanilla 30, Badlands 45).
  public final static func DistrictGunshotRange() -> Float { return 50.0; }

  // Mapped range for low-noise districts (Dogtown, vanilla 20).
  public final static func DistrictGunshotRangeLow() -> Float { return 30.0; }

  // District classifier: vanilla ranges <= this map to the low-noise tier.
  // Known vanilla values are exactly {20, 30, 45}.
  public final static func DistrictLowVanillaThreshold() -> Float { return 25.0; }

  // Master debug toggle: throttled HUD one-liner + FTLog per extended-range event.
  public final static func DebugNotify() -> Bool { return true; }

  // Minimum seconds between debug notifications (global, sim-time so it is
  // menu-pause-proof).
  public final static func DebugThrottleSec() -> Float { return 5.0; }
}

// =========================== DEBUG FUNNEL ====================================
// One throttled sink for every debug line this feature emits. The throttle
// timestamp lives on the session-stable HUDManager (survives replacer swaps).
// Gating (DebugNotify) + throttling (DebugThrottleSec, sim-time) happen here so
// the per-class EOAR_Note helpers below just resolve the host and forward.
// Emission itself is Common's EO_Notify (HUD activity-log + FTLog).
@addField(HUDManager)
let m_eoarLastNotify: Float;

@addMethod(HUDManager)
public final func EOAR_Notify(game: GameInstance, msg: String) -> Void {
  if !AggroRangeConfig.DebugNotify() {
    return;
  };
  let now: Float = EngineTime.ToFloat(GameInstance.GetSimTime(game));
  if (now - this.m_eoarLastNotify) < AggroRangeConfig.DebugThrottleSec() {
    return;
  };
  this.m_eoarLastNotify = now;
  EO_Notify(game, msg);
}

// Component-side note helper (ReactionManagerComponent + StimBroadcasterComponent
// share the same body: resolve owner -> HUD, IsDefined-guarded, forward). const
// so it is callable from any context; it mutates only the HUD, never `this`.
@addMethod(ReactionManagerComponent)
private const final func EOAR_Note(msg: String) -> Void {
  let owner: ref<GameObject> = this.GetOwner();
  if !IsDefined(owner) {
    return;
  };
  let hud: ref<HUDManager> = owner.GetHudManager();
  if IsDefined(hud) {
    hud.EOAR_Notify(owner.GetGame(), msg);
  };
}

@addMethod(StimBroadcasterComponent)
private const final func EOAR_Note(msg: String) -> Void {
  let owner: ref<GameObject> = this.GetOwner();
  if !IsDefined(owner) {
    return;
  };
  let hud: ref<HUDManager> = owner.GetHudManager();
  if IsDefined(hud) {
    hud.EOAR_Notify(owner.GetGame(), msg);
  };
}

// Player-side note helper — the PlayerPuppet IS the GameObject. const so the
// const GetGunshotRange wrap can call it (it mutates only the HUD object).
@addMethod(PlayerPuppet)
private const final func EOAR_Note(msg: String) -> Void {
  let hud: ref<HUDManager> = this.GetHudManager();
  if IsDefined(hud) {
    hud.EOAR_Notify(this.GetGame(), msg);
  };
}

// ======================= HALF A — reaction replacers =========================

// Full vanilla body reproduced with deltas D1-D4; every non-delta line and its
// order is vanilla-exact. GetOwnerPuppet/HasCombatTarget/CombatGracePeriodPassed
// /IsTargetPositionClose/IsTargetVeryClose/InGunshotCone/LogInfo are private
// members of ReactionManagerComponent, reachable here because @replaceMethod is
// a member (rule 5).
@replaceMethod(ReactionManagerComponent)
public func ShouldIgnoreCombatStim(stimType: gamedataStimType, instigator: wref<ScriptedPuppet>, source: wref<ScriptedPuppet>, sourcePos: Vector4, canDelay: Bool, out canIgnoreOnlyDueToDelay: Bool, out canIgnorePlayerCombatStim: Bool, log: Bool) -> Bool {
  let en: Bool = AggroRangeConfig.EnableAggroRange();
  let ownerPup: ref<ScriptedPuppet>;
  let matePup: ref<ScriptedPuppet>;
  let npcInFight: Bool;
  let plyrInFight: Bool;
  let nearDanger: Bool;
  let mates: array<wref<Entity>>;
  let danger: Float;

  // D4 — instigator-null guard. Enabled: a stim with no instigator is never
  // ignorable, even if `source` is the player. Disabled: vanilla pair-guard.
  if en {
    if !IsDefined(instigator) {
      return false;
    };
  } else {
    if !IsDefined(source) && !IsDefined(instigator) {
      return false;
    };
  };
  if !IsDefined(source) {
    source = instigator;
  };
  if !IsDefined(source) || !source.IsPlayer() {
    return false;
  };

  if !StimFilters.CanBeIgnoredInCombat(stimType) {
    return false;
  };

  npcInFight = this.HasCombatTarget();
  let srcPlayer: ref<PlayerPuppet> = source as PlayerPuppet;
  plyrInFight = srcPlayer.IsInCombat();
  if (!npcInFight && !plyrInFight) && this.CombatGracePeriodPassed(srcPlayer) {
    if canDelay {
      canIgnoreOnlyDueToDelay = true;
    } else {
      return false;
    };
  };

  ownerPup = this.GetOwnerPuppet();
  if NPCPuppet.IsInCombatWithTarget(ownerPup, source) {
    return false;
  };

  canIgnorePlayerCombatStim = true;

  // Projectile hit within 4 m — literal untouched (the reference left it alone).
  if StimFilters.IsProjectile(stimType) && this.IsTargetPositionClose(sourcePos, 4.0) {
    if log {
      this.LogInfo("can't be ignored - projectile hit nearby");
    };
    return false;
  };

  // D1 — danger radius: 35 m when enabled, vanilla 12 m otherwise.
  if en {
    danger = AggroRangeConfig.DangerRange();
  } else {
    danger = AggroRangeConfig.VanillaDangerRange();
  };
  nearDanger = this.IsTargetPositionClose(sourcePos, danger);
  // LOS GATE (bugfix): the widened 12->35 m band applies only to a player this
  // NPC can actually SEE — IsTargetVisible (reactionComponent.script:5409, the
  // same primitive vanilla's police combat branch gates on at :2564). Inside
  // vanilla's own 12 m the no-LOS reaction is vanilla behavior and is kept.
  let nearVanillaDanger: Bool = this.IsTargetPositionClose(sourcePos, AggroRangeConfig.VanillaDangerRange());
  let sourceSeen: Bool = this.IsTargetVisible(source);
  if en && nearDanger && !nearVanillaDanger && !sourceSeen {
    nearDanger = false;
  };

  // D2 — Explosion: never ignorable when enabled (drop the inDanger conjunct);
  // vanilla requires it in range. LOS GATE (bugfix): beyond vanilla's 12 m the
  // never-ignorable rule now also requires this NPC to SEE the player
  // (sourceSeen); inside 12 m vanilla's own no-LOS reaction is preserved.
  if Equals(stimType, gamedataStimType.Explosion) && (nearVanillaDanger || (en && sourceSeen)) {
    if log {
      this.LogInfo("can't be ignored - explosion nearby");
    };
    if en && !this.IsTargetPositionClose(sourcePos, AggroRangeConfig.VanillaDangerRange()) {
      this.EOAR_Note("EO aggro: explosion accepted beyond vanilla range (" + FloatToStringPrec(Vector4.Distance(sourcePos, this.GetOwner().GetWorldPosition()), 1) + "m)");
    };
    return false;
  };

  if StimFilters.IsGunshot(stimType) {
    if nearDanger {
      if log {
        this.LogInfo("can't be ignored - gunshot nearby");
      };
      if en && !this.IsTargetPositionClose(sourcePos, AggroRangeConfig.VanillaDangerRange()) {
        this.EOAR_Note("EO aggro: gunshot accepted beyond vanilla range (" + FloatToStringPrec(Vector4.Distance(sourcePos, this.GetOwner().GetWorldPosition()), 1) + "m)");
      };
      return false;
    };
    // Cone check is direction-only in vanilla already (15-degree front angle) —
    // no distance term, so this branch is unchanged by the deltas.
    if ReactionManagerComponent.InGunshotCone(source, ownerPup) {
      if log {
        this.LogInfo("can't be ignored - gunshot at owner");
      };
      return false;
    };
  };

  // D3 — illegal action aimed at me: enabled drops the distance gate, leaving a
  // direction-only cone; disabled keeps the vanilla `nearDanger &&`.
  if StimFilters.IsIllegal(stimType) && (en || nearDanger) && ReactionManagerComponent.InGunshotCone(source, ownerPup) {
    if log {
      this.LogInfo("can't be ignored - nearby illegal action directed at owner");
    };
    if en && !this.IsTargetPositionClose(sourcePos, AggroRangeConfig.VanillaDangerRange()) {
      this.EOAR_Note("EO aggro: illegal accepted beyond vanilla range (" + FloatToStringPrec(Vector4.Distance(sourcePos, this.GetOwner().GetWorldPosition()), 1) + "m)");
    };
    return false;
  };

  if this.IsTargetVeryClose(source) {
    if log {
      this.LogInfo("can't be ignored - player very close to owner");
    };
    return false;
  };

  if ownerPup.IsConnectedToSecuritySystem() {
    if ownerPup.IsTargetTresspassingMyZone(source) {
      if log {
        this.LogInfo("can't be ignored - player trespassing security zone");
      };
      return false;
    };
  };

  // Squadmate scan — if-wrapper + early return (no break/continue in REDscript).
  AISquadHelper.GetSquadmates(ownerPup, mates);
  for mate in mates {
    matePup = mate as ScriptedPuppet;
    if IsDefined(matePup) && NPCPuppet.IsInCombatWithTarget(matePup, source) {
      if log {
        this.LogInfo("can't be ignored - squadmate in combat with player");
      };
      return false;
    };
  };
  return true;
}

// D5/D6 replacer. Call sites pass target = the ally candidate, targetOfTarget =
// that ally's combat target (frequently the player).
@replaceMethod(ReactionManagerComponent)
private func ShouldHelpTargetFromSameAttitudeGroup(target: wref<GameObject>, targetOfTarget: wref<GameObject>) -> Bool {
  let en: Bool = AggroRangeConfig.EnableAggroRange();
  let ownerPup: ref<ScriptedPuppet> = this.GetOwnerPuppet();
  // literal reference parity — see plan D5: the affiliation leg compares the
  // owner against targetOfTarget (the ally's ENEMY), NOT against the ally. This
  // is an author oversight in the reference (inert vs the player, since V's
  // record affiliation never matches a gang's) but observable-behavior parity is
  // the binding rule, so it is reproduced literally and flagged, NOT "fixed".
  let foePup: ref<ScriptedPuppet> = targetOfTarget as ScriptedPuppet;
  let prevSys: ref<PreventionSystem>;

  if en {
    // D5 — deny help only if BOTH the affiliations differ AND the attitude
    // groups differ; either record unresolvable falls back to the vanilla
    // group-only gate.
    if IsDefined(ownerPup) && IsDefined(foePup) {
      let affilOwner: wref<Affiliation_Record> = TweakDBInterface.GetCharacterRecord(ownerPup.GetRecordID()).Affiliation();
      let affilFoe: wref<Affiliation_Record> = TweakDBInterface.GetCharacterRecord(foePup.GetRecordID()).Affiliation();
      let groupsDiffer: Bool = NotEquals(ownerPup.GetAttitudeAgent().GetAttitudeGroup(), target.GetAttitudeAgent().GetAttitudeGroup());
      if NotEquals(affilOwner, affilFoe) && groupsDiffer {
        return false;
      };
      // If we got past that deny with groups differing, the affiliation leg (not
      // the group leg) is what allowed help — surface it.
      if groupsDiffer {
        this.EOAR_Note("EO aggro: affiliation-leg help");
      };
    } else {
      if NotEquals(ownerPup.GetAttitudeAgent().GetAttitudeGroup(), target.GetAttitudeAgent().GetAttitudeGroup()) {
        return false;
      };
    };
  } else {
    if NotEquals(ownerPup.GetAttitudeAgent().GetAttitudeGroup(), target.GetAttitudeAgent().GetAttitudeGroup()) {
      return false;
    };
  };

  // D6 — the load-bearing line. Enabled: any defined target grants help; for a
  // PLAYER target the helper must additionally SEE the player right now —
  // LOS GATE (bugfix): IsTargetVisible (reactionComponent.script:5409). An
  // unseen player keeps the vanilla exemption (fall through — no help; vanilla
  // :5793-5802 falls through to the police branch then returns false).
  // Disabled: vanilla exemption.
  if en {
    if IsDefined(targetOfTarget) {
      if targetOfTarget.IsPlayer() {
        if this.IsTargetVisible(targetOfTarget) {
          this.EOAR_Note("EO aggro: ally joins vs player");
          return true;
        };
      } else {
        return true;
      };
    };
  } else {
    if IsDefined(targetOfTarget) && !targetOfTarget.IsPlayer() {
      return true;
    };
  };

  // Police work-spot join-chase branch — preserved verbatim (toggle-independent).
  prevSys = ownerPup.GetPreventionSystem();
  if ((prevSys.IsChasingPlayer() && target.IsPrevention()) && ownerPup.IsPrevention()) && prevSys.ShouldWorkSpotPoliceJoinChase(ownerPup) {
    return true;
  };
  return false;
}

// ===================== HALF B — radius / range wraps =========================

// Primary chokepoint: NPC gunfire and the player ground-slam broadcast their
// stim with NO radius (opt defaults to 0), so the native side falls back to the
// TweakDB record radius. We inject the widened value BEFORE forwarding, only for
// the record-fallback (radius <= 0) Gunshot/Explosion case. Explicit non-zero
// radii (interior fire, grenades, silenced sniper, visual broadcasts) pass
// through byte-identical — that is the parity line the original drew.
@wrapMethod(StimBroadcasterComponent)
public func TriggerSingleBroadcast(contextOwner: wref<GameObject>, gdStimType: gamedataStimType, opt radius: Float, opt investigateData: stimInvestigateData, opt propagationChange: Bool) -> Void {
  if AggroRangeConfig.EnableAggroRange() && radius <= 0.0 {
    if Equals(gdStimType, gamedataStimType.Gunshot) {
      radius = AggroRangeConfig.GunshotFallbackRadius();
      this.EOAR_Note("EO aggro: Gunshot radius 0 -> " + FloatToStringPrec(radius, 0));
    } else {
      if Equals(gdStimType, gamedataStimType.Explosion) {
        radius = AggroRangeConfig.ExplosionFallbackRadius();
        this.EOAR_Note("EO aggro: Explosion radius 0 -> " + FloatToStringPrec(radius, 0));
      };
    };
  };
  wrappedMethod(contextOwner, gdStimType, radius, investigateData, propagationChange);
}

// Belt-and-suspenders closure of the same funnel. Every vanilla Single broadcast
// is built INSIDE TriggerSingleBroadcast (which already injected the radius), so
// for vanilla producers this wrap sees a non-zero radius and does nothing —
// idempotent by construction. It exists only to catch a non-vanilla producer
// that queues a Single BroadcastEvent directly. Silent (it almost never fires).
// It mutates only the in-flight event payload before forwarding (no re-entrant
// engine mutation — rule 3), and calls wrappedMethod exactly once.
@wrapMethod(StimBroadcasterComponent)
protected cb func OnBroadcastEvent(evt: ref<BroadcastEvent>) -> Bool {
  if AggroRangeConfig.EnableAggroRange() && Equals(evt.broadcastType, EBroadcasteingType.Single) && evt.radius <= 0.0 {
    if Equals(evt.stimType, gamedataStimType.Gunshot) {
      evt.radius = AggroRangeConfig.GunshotFallbackRadius();
    } else {
      if Equals(evt.stimType, gamedataStimType.Explosion) {
        evt.radius = AggroRangeConfig.ExplosionFallbackRadius();
      };
    };
  };
  return wrappedMethod(evt);
}

// District gunshot range: reproduce the reference's per-district table by mapping
// the vanilla return. Bucket by the vanilla value (Dogtown 20 is low-noise, 30/
// 45 are standard), then MaxF so we never REDUCE a range another mod/patch has
// already raised. Disabled -> pass-through. No write to m_gunshotRange, no hook
// on OnDistrictChanged, GetExplosionRange untouched.
@wrapMethod(PlayerPuppet)
public const func GetGunshotRange() -> Float {
  let v: Float = wrappedMethod();
  if !AggroRangeConfig.EnableAggroRange() {
    return v;
  };
  let bucket: Float;
  if v <= AggroRangeConfig.DistrictLowVanillaThreshold() {
    bucket = AggroRangeConfig.DistrictGunshotRangeLow();
  } else {
    bucket = AggroRangeConfig.DistrictGunshotRange();
  };
  let mapped: Float = MaxF(v, bucket);
  if mapped > v {
    this.EOAR_Note("EO aggro: district gunshot range " + FloatToStringPrec(v, 0) + " -> " + FloatToStringPrec(mapped, 0));
  };
  return mapped;
}
