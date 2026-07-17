# Unified Auto-Loot — Implementation Plan (2026-07-07)

Target file: `mods/enabled/r6-scripts/custom-scanner-suite/ScannerSuite.reds` (~875 lines).
Pure REDscript only, game v2.3x macOS Steam. NO CET / RED4ext / TweakXL / ArchiveXL / Codeware / Mod
Settings. One file, compiled by `scc`. Config = static funcs (no runtime UI).

This plan UNIFIES two requested features into ONE always-on loop feeding ONE worker + ONE ledger:

- **F1 — cursor pickup** (audited by Agent A): collect anything lootable the crosshair points at, 50 m,
  LOS. Already present as the `APS_RunCursorPickup` cursor channel (`GetLookAtObject`), today driven by
  the scanner-gated `ST_SweepTick` and range-capped at 40 m.
- **F2 — constant surroundings** (researched by Agent B): always-on 360° auto-loot, normal + scan
  mode, 50 m, LOS, take EVERYTHING incl. quest + iconic. New; mechanism = `GameInstance.GetEntityList`
  polled on a slow self-re-arming `DelaySystem` loop.

Prior dossiers: `constant-auto-loot-research.md` (F2 feasibility/mechanism), `scan-mode-auto-pickup.md`,
`scanner-suite-refinements.md`, `plan-fix-loot-pickup-containers-items.md`,
`scanner-suite-crash-analysis.md` (the crash law). Agent A's audit + Agent B's research are the inputs
this plan reconciles.

Evidence tier `[V]` = read directly in the local decompiled 2.x vanilla scripts
(`…/scratchpad/vanilla-scripts/`, `.swift`); all API line numbers below were re-verified this pass.

---

## 1. One-loop decision (STEP 1)

**Verdict: `oneLoopFeasible = TRUE`.** A SINGLE always-on `DelaySystem` loop drives BOTH F1 and F2.

Why one loop works and is correct:

- Both features feed the **same worker** `APS_TryAutoPickup` (ScannerSuite.reds:723) and the **same
  per-entity ledger** `m_apsAttempted` (:593–606). Convergence on one ledger means F1 and F2 can never
  double-loot the same entity, no matter which pass reaches it first — the second pass sees
  `APS_AlreadyAttempted(id) == true` and skips.
- `TargetingSystem.GetLookAtObject` (the F1 detector) works in normal gameplay, not only in scan mode
  `[V]` — so F1 does NOT need the scanner-gated tick it lives on today. It can run on an always-on loop.
- Because F2 is an indiscriminate 360° / 50 m / LOS / take-everything vacuum, it **strictly subsumes**
  F1's coverage: anything the crosshair points at within 50 m + LOS is also enumerated by
  `GetEntityList`. F1 therefore contributes exactly ONE thing over F2 — **latency**: it grabs the item
  you are actively aiming at faster than the next slow surroundings sweep would. The task requires F1
  and F2 to "ship together," so F1 is kept (not retired) precisely for that responsiveness.

**Cadence conflict + resolution.** F1 wants a FAST poll (one cheap raycast, responsive aim-to-grab).
F2 wants a SLOW poll — `GetEntityList` is an O(N) whole-world list copy, and Agent B's dossier
explicitly warns it must NOT run at the 0.35 s rate (`constant-auto-loot-research.md` §c: prior
dismissal was for a 0.35 s tick; a dedicated ~1 s loop is the safe envelope). Resolve with **one loop
at the fast base cadence + a seconds-accumulator sub-gate for the expensive pass**:

- Base tick = `AutoPickupLoopInterval()` (default **0.35 s**). Every tick does the cheap F1 cursor
  look-at.
- A float accumulator `m_apsSurroundAccum` adds the base interval each tick; when it reaches
  `ConstantAutoLootInterval()` (default **1.0 s**) it fires the F2 `GetEntityList` pass and resets. So
  F2 runs roughly every 3rd tick (~1.05 s) while F1 runs every tick (~0.35 s), from ONE loop, ONE
  lifecycle, ONE arm-guard. (Accumulator chosen over an integer tick-counter so the two knobs stay in
  intuitive seconds and there is no `Float`→`Int32` rounding footgun.)

**The auto-TAG frustum sweep stays on its own scanner-gated loop** (`ST_SweepTick`), per the task — it
is a separate concern (tags, never picks up; different ledger `m_autoTagSeen`). This plan only
**removes the cursor-pickup duty** that `ST_SweepTick` carries today and moves it into the new
always-on loop. The two loops then never fight: different guard fields (`m_stSweepArmed` vs
`m_apsLoopArmed`), different ledgers, no shared mutable state, no double-arm — one tags while scanning,
one loots always.

---

## 2. Resolved decisions (STEP 2)

### 2.1 Filter policy — ONE unified policy via one config flag

Agent A recommended dropping the Quest/iconic/HMG skips for the cursor channel; Agent B recommended a
`relaxFilters: Bool` param so only F2 relaxes them. **Unify into ONE policy** governed by a single
config flag, because the worker `APS_TryAutoPickup` is the single chokepoint for **all** channels
(cursor look-at :666, surroundings, hover hook :867) — a per-channel param would let the channels
diverge for no benefit now that both are supposed to take everything.

`filterPolicyResolved`: add `AutoPickupTakeQuestAndIconic() -> Bool { return true; }`. When **true**
(default), the worker's three *policy* skips are bypassed — **Quest** (`itemData.HasTag(n"Quest") ||
this.IsQuest()`, :782), **iconic** (`RPGManager.IsItemIconic`, :784) and **HMG/turret**
(`Wea_HeavyMachineGun`, :780). The one *structural* skip — nameless internal placeholders
(`name == "" && itemType != Gen_Readable`, :778) — is **kept unconditionally** (engine placeholders the
player cannot meaningfully hold; the `!= Gen_Readable` carve-out is what still lets empty-name shards
loot + auto-journal). Setting the flag `false` restores today's exact conservative behavior.

Reject Agent B's `relaxFilters` param: the flag is read INSIDE the worker, so **no call site of
`APS_TryAutoPickup` changes its signature** — cursor, surroundings, and hover all keep calling
`target.APS_TryAutoPickup(this)`/`(player)` unchanged, and all inherit the one policy. Fewer edited
lines, no divergence.

Two consequences to record:

- **The persistent-flag footgun is fixed by the default.** `this.IsQuest()` (:782) reads the persistent
  `m_markAsQuest` field (`gameObject.swift:2094` `[V]`) — a junk fridge/drop that got that sticky flag
  would have its ENTIRE contents skipped. With `takeAll == true` the whole
  `!takeAll && (… || this.IsQuest())` branch short-circuits and never evaluates `IsQuest()`, so the
  over-skip is gone by default. (This is the same class of stuck-flag bug the auto-tag path already
  removed on 2026-07-06.)
- **HMG caveat.** The `Wea_HeavyMachineGun` skip carries a "known-harmful to loot" comment of
  unverified origin. The user spec is "take EVERYTHING" and both research agents recommend lifting it,
  so it is lifted under the same flag. **If** after shipping you see a broken weapon in inventory or an
  equip glitch, re-adding just the HMG skip (or making it its own always-on branch) is the first
  mitigation — call it out in the worker comment so the knob is discoverable.

### 2.2 Range — one shared 50 m constant

`AutoPickupMaxDistance()` 40.0 → **50.0** (ScannerSuite.reds:142). This single constant is BOTH the
reach cap and the worker's distance gate (:752–753), and it is now the shared range for **both**
channels: F1's worker gate and F2's cheap upstream `Vector4.Distance` pre-filter both read it. **Reject
Agent B's separate `ConstantAutoLootRange()`** — the task says "AutoPickupMaxDistance 40 → 50 (both
channels)", so one constant governs everything (belt-and-suspenders: F2 distance-rejects at 50 upstream,
then the worker re-gates at the same 50).

Open item to confirm in-game (Agent A + B both flagged): the native `GetLookAtObject` raycast max
length is not visible in the decompile, so F1's effective reach = `min(raycast length, 50)`. F2 has no
such cap (`Entity.GetWorldPosition` distance is exact), so F2 covers the full 50 m regardless; the probe
in §7 confirms F1 too.

### 2.3 Lifecycle — crash-safe always-on driver

The loop is driven by **`PlayerPuppet.OnGameAttached`** `[V] player.swift:1065` (`protected cb func …
-> Bool`). This is the PLAYER object attaching = **game thread**, fires once per load. It is NOT the
per-arbitrary-entity `GameObject.OnGameAttached` streaming hook that crashed. Precedent (installed,
safe, verified this pass): `custom-switch-speed/SwitchSpeed.reds:185` and
`street-vendors/street_vendors.reds:87` both wrap it with the identical `wrappedMethod(); …` shape.

- Loop = an `APSLootLoopCallback extends DelayCallback` `[V]` base `delaySystem.swift:7`, `func Call()`
  :9), holding a `wref<PlayerPuppet>`. It self-re-arms each tick via
  `GameInstance.GetDelaySystem(game).DelayCallback(cb, AutoPickupLoopInterval(), false)`
  `[V] orphans.swift:11818` (signature `DelayCallback(ref<DelayCallback>, Float, opt Bool) -> DelayID`;
  `false` = not affected by time dilation, matching the existing sweep at :474 for constant real-time
  cadence — set `true` instead if you want the loop to slow with Sandevistan/pause).
- Guard field `m_apsLoopArmed: Bool` (mirrors `m_stSweepArmed` :464) so a re-entrant attach cannot
  spawn two loops.
- Self-termination: when the `wref<PlayerPuppet>` goes null (session end / load) `Call()` no-ops and
  does not re-arm; the loop dies with the old player. The next load's `OnGameAttached` re-arms a fresh
  loop on the new player (whose `m_apsLoopArmed` defaults false). This is the same machinery already
  proven in-file for the sweep, just driven from the player instead of the HUD.

**Feature-OFF path is 100% vanilla.** `OnGameAttached` calls `APS_StartLootLoop()` only when
`EnableAutoPickupCursor() || EnableConstantAutoLoot()`. If both are false the wrap is a pure
passthrough — no loop, no cost, and `EnableConstantAutoLoot()` false alone means the `GetEntityList`
pass never runs.

### 2.4 Crash-safety — restated for THIS design

Every element is game-thread; nothing can reach a worker thread. See §6 for the full argument. In one
line: the driver is `PlayerPuppet.OnGameAttached` (player object = game thread), the loop is a
`DelaySystem.DelayCallback` (game tick), each tick only READS engine state
(`GetLookAtObject` / `GetEntityList` / `Entity.GetWorldPosition` / `IsVisibleTarget` / `GetItemList`)
and the only shared-state mutations are `ArrayPush` into the single-`PlayerPuppet` `m_apsAttempted`
ledger and the `m_apsSurroundAccum` float — both on the game thread. NO per-arbitrary-entity
`GameObject.OnGameAttached` / `OnDetach` / entity-lifecycle registry is added, so the removed
`redDispatcher` heap-corruption class stays structurally unreachable.

### 2.5 Coverage — honest statement

**`coverageHonest`:** F2 is a genuine 360° / 50 m / LOS loot vacuum over **every loot class**
(containers, drops, shards, bare floor items, dead-body loot), taking quest + iconic + HMG by default —
this is feasible-FULL, not an approximation, because `GetEntityList` returns the RAW world entity list
(`[ref<Entity>]`), NOT the `TargetingComponent`-filtered set that blinded the two prior radius aborts to
standalone loot `[V] orphans.swift:11551`. The ONE honest nuance: an entity must be **streamed in** to
be enumerated — but at 50 m everything is well inside the streaming radius, so there is no practical
coverage gap. LOS is respected: loot behind a wall within 50 m is a TRANSIENT refusal (no ledger spend)
and is auto-picked once line of sight clears — the deliberate cursor-channel asymmetry (information
through walls for tagging; physical transfer requires LOS). No claim is made of a through-wall container
vacuum — that cannot be built crash-safe and is not built.

---

## 3. Exact config changes (`ScannerSuiteConfig`, ScannerSuite.reds:84–165)

All are static funcs; edit the literal + relaunch to apply (no runtime UI).

1. **Rename** `EnableAutoPickupOnScan()` → `EnableAutoPickupCursor()` (def at :133–135, keep
   `return true;`). The old name now lies — the cursor channel is no longer scan-gated. Update its two
   remaining references (after the §4 edits remove the others): the hover hook (:826) and the new
   OnGameAttached wrap / loop tick (§4). Doc comment (:129–132): rewrite to "CURSOR channel: collect the
   loot object the crosshair points at (now ALWAYS-ON, not scan-only), 50 m, LOS required."

2. **`AutoPickupMaxDistance()`** (:141–143): `return 40.0;` → **`return 50.0;`**. Update its comment
   (:137–140) and the "40 m" mention wherever it appears (see §5) — shared cap for both channels.

3. **Add** (place right after `AutoPickupMaxDistance`, before `AutoPickupPlaySound` at :145):

   ```reds
   // --- Feature 3b: constant 360° auto-loot (always-on, normal + scan). ---
   // Enumerates every streamed loot entity around the player each pass via
   // GameInstance.GetEntityList (game-thread), 50 m (AutoPickupMaxDistance),
   // LINE OF SIGHT required (worker IsVisibleTarget). false = this pass never
   // runs (cursor channel unaffected). Feeds the SAME worker + ledger as cursor.
   public final static func EnableConstantAutoLoot() -> Bool {
     return true;
   }

   // Base cadence (seconds) of the always-on auto-loot loop; also the cursor
   // look-at poll rate. Cheap per tick (one raycast). Raise to reduce always-on
   // cost; the surroundings pass runs on the slower cadence below.
   public final static func AutoPickupLoopInterval() -> Float {
     return 0.35;
   }

   // Cadence (seconds) of the expensive 360° GetEntityList surroundings pass.
   // Effective rate ≈ ceil(ConstantAutoLootInterval / AutoPickupLoopInterval)
   // ticks. 0.5–2.0 s is the safe envelope (Agent B); raise to 2.0 if the
   // DebugProbe shows a very large entity list in the densest crowd+combat scene.
   public final static func ConstantAutoLootInterval() -> Float {
     return 1.0;
   }

   // Take-everything policy (governs ALL pickup channels — cursor, surroundings,
   // hover). true = auto-pickup also grabs QUEST items, ICONICS, and HMG/turret
   // weapons (bypasses those three "policy" skips in APS_TryAutoPickup); the
   // nameless-placeholder "structural" skip always stays. false = conservative
   // (leave quest/iconic/HMG). NOTE: HMG lift is per user "take everything"; if a
   // looted HMG/turret weapon misbehaves, re-skip it in the worker.
   public final static func AutoPickupTakeQuestAndIconic() -> Bool {
     return true;
   }
   ```

4. **`DebugProbeAutoPickup()`** (:162–164): unchanged signature; extend its comment to note it now also
   prints the surroundings pass line `"APS surround: entities=N picked=M"` (used to size `GetEntityList`
   before finalizing `ConstantAutoLootInterval`). Keep `return false;` for play.

Net config: 1 rename, 1 value change (40→50), 4 new funcs.

---

## 4. Exact code changes

### 4.1 Strip cursor-pickup duty from the scanner-gated sweep

**`OnScannerUIVisibleChanged`** (:218–237). The arm condition currently arms the sweep for tag OR
cursor:

- :232–233 change `if visible && (ScannerSuiteConfig.EnableAutoTagOnScan()
  || ScannerSuiteConfig.EnableAutoPickupOnScan())` → **`if visible &&
  ScannerSuiteConfig.EnableAutoTagOnScan()`** (cursor no longer needs this loop). Update the comment
  block (:228–231) to say the sweep is armed for the tag channel only; cursor pickup now runs on the
  always-on loot loop.

**`ST_SweepTick`** (:478–508). Remove the cursor pass; the sweep becomes tag-only:

- :482 delete `let cursorOn: Bool = ScannerSuiteConfig.EnableAutoPickupOnScan();`.
- :486 change `if (!tagOn && !cursorOn) || !this.m_uiScannerVisible {` →
  **`if !tagOn || !this.m_uiScannerVisible {`**.
- :497–502 delete the entire `if cursorOn { … player.APS_RunCursorPickup(game); … }` block. Keep
  `if tagOn { this.ST_RunSweepOnce(game); }`.
- Update the comments (:483–485, :490–492) to drop cursor references.

`APS_RunCursorPickup` (:642–669) itself is **UNCHANGED** — it is now invoked from the always-on loop
(§4.3) instead of `ST_SweepTick`. Its body (`GetLookAtObject` → `APS_ResolveLootTarget` → shared ledger
→ `APS_TryAutoPickup`) already does exactly F1.

### 4.2 Add the always-on loot loop machinery

Place this as a new subsection inside FEATURE 3, e.g. right after the removed-radius-channel comment
(:608–620) and before the cursor-pickup channel (:622). Mirror the existing `STSweepTickCallback` /
`ST_ArmSweep` idiom exactly.

```reds
// ---------- always-on auto-loot loop (drives F1 cursor + F2 surroundings) -----
// Self-re-arming DelayCallback, started once from PlayerPuppet.OnGameAttached
// (player object = GAME THREAD). Runs regardless of scanner UI. One loop:
// every tick does the cheap cursor look-at (F1); every ConstantAutoLootInterval
// seconds it also does the expensive GetEntityList 360° pass (F2). Both feed the
// shared m_apsAttempted ledger + APS_TryAutoPickup worker — no double-loot.
public class APSLootLoopCallback extends DelayCallback {
  public let player: wref<PlayerPuppet>;

  public func Call() -> Void {
    if IsDefined(this.player) {       // null after session end/load -> loop dies, re-armed by next OnGameAttached
      this.player.APS_LootLoopTick();
    };
  }
}

// Double-arm guard (mirror m_stSweepArmed :464) + surroundings-cadence accumulator.
// Both session-transient (never saved).
@addField(PlayerPuppet)
let m_apsLoopArmed: Bool;

@addField(PlayerPuppet)
let m_apsSurroundAccum: Float;

@addMethod(PlayerPuppet)
public final func APS_StartLootLoop() -> Void {
  if this.m_apsLoopArmed {
    return; // a tick is already pending — never run two loops
  };
  this.m_apsLoopArmed = true;
  this.APS_ArmLootTick();
}

@addMethod(PlayerPuppet)
private final func APS_ArmLootTick() -> Void {
  let cb: ref<APSLootLoopCallback> = new APSLootLoopCallback();
  cb.player = this;
  GameInstance.GetDelaySystem(this.GetGame())
    .DelayCallback(cb, ScannerSuiteConfig.AutoPickupLoopInterval(), false);
}

@addMethod(PlayerPuppet)
public final func APS_LootLoopTick() -> Void {
  let game: GameInstance = this.GetGame();
  let cursorOn: Bool = ScannerSuiteConfig.EnableAutoPickupCursor();
  let constantOn: Bool = ScannerSuiteConfig.EnableConstantAutoLoot();
  // Defensive stop (both channels off) — dead in practice since config is static
  // and the loop only arms when one is on; mirrors ST_SweepTick's stop logic.
  if !cursorOn && !constantOn {
    this.m_apsLoopArmed = false;
    return;
  };
  // Johnny/braindance parity (matches APS_RunCursorPickup :644): skip ALL pickup
  // this tick, keep the loop alive.
  if this.IsReplacer() || this.GetHudManager().IsBraindanceActive() {
    this.APS_ArmLootTick();
    return;
  };
  // (a) F1 — cheap cursor look-at pickup EVERY tick (one native raycast; responsive).
  if cursorOn {
    this.APS_RunCursorPickup(game);
  };
  // (b) F2 — expensive 360° GetEntityList pass on the slower cadence (accumulator).
  if constantOn {
    this.m_apsSurroundAccum += ScannerSuiteConfig.AutoPickupLoopInterval();
    if this.m_apsSurroundAccum >= ScannerSuiteConfig.ConstantAutoLootInterval() {
      this.m_apsSurroundAccum = 0.0;
      this.APS_RunSurroundingsPickup(game);
    };
  };
  this.APS_ArmLootTick(); // re-arm — exactly one successor, always one loop
}

// F2 pass: enumerate the RAW world entity list (GetEntityList — sees loot classes,
// unlike any TargetingComponent query), cheap distance-reject BEFORE any cast
// (Entity.GetWorldPosition is native const), then route survivors through the SAME
// APS_ResolveLootTarget + shared ledger + APS_TryAutoPickup worker as the cursor.
// CRASH-SAFE: game-thread DelayCallback; GetEntityList only READS; sole shared
// mutation is the ledger ArrayPush on the game thread. Precedent for the
// iterate+cast: PlayerDevelopmentSystem.ScaleNPCsToPlayerLevel
// (playerDevelopmentSystem.swift:2522) does the identical `entityList[i] as
// GameObject` on the game thread with zero synchronization.
@addMethod(PlayerPuppet)
public final func APS_RunSurroundingsPickup(game: GameInstance) -> Void {
  let origin: Vector4 = this.GetWorldPosition();
  let maxDist: Float = ScannerSuiteConfig.AutoPickupMaxDistance(); // shared 50 m
  let entities: array<ref<Entity>> = GameInstance.GetEntityList(game);
  let picked: Int32 = 0;
  let i: Int32 = 0;
  while i < ArraySize(entities) {
    let e: ref<Entity> = entities[i];
    if IsDefined(e)
        && Vector4.Distance(origin, e.GetWorldPosition()) <= maxDist {
      let go: ref<GameObject> = e as GameObject; // GameObject extends GameEntity extends Entity (gameObject.swift:87)
      if IsDefined(go) {
        let target: ref<GameObject> = go.APS_ResolveLootTarget(); // bare ItemObject -> its drop
        let id: EntityID = target.GetEntityID();
        // shared m_apsAttempted ledger with cursor + hover — never re-hammer;
        // transient refusals (alive/locked/occluded/empty/out-of-range) stay eligible.
        if !this.APS_AlreadyAttempted(id) && target.APS_TryAutoPickup(this) {
          this.APS_MarkAttempted(id);
          picked += 1;
        };
      };
    };
    i += 1;
  };
  if ScannerSuiteConfig.DebugProbeAutoPickup() {
    GameInstance.GetActivityLogSystem(game).AddLog(
      "APS surround: entities=" + ToString(ArraySize(entities)) + " picked=" + ToString(picked));
  };
}
```

### 4.3 Add the player-attach driver (start the loop)

Place near the loop machinery (any top-level location in the file is fine).

```reds
// Start the always-on auto-loot loop on player attach. PLAYER-object OnGameAttached
// = GAME THREAD, once per load — NOT the per-arbitrary-entity GameObject streaming
// hook that caused the heap-corruption crash (scanner-suite-crash-analysis.md).
// Precedent: custom-switch-speed/SwitchSpeed.reds:185, street-vendors/street_vendors.reds:87
// both wrap this same method safely. @wrapMethod chains compose (all call
// wrappedMethod exactly once), so load order does not matter.
@wrapMethod(PlayerPuppet)
protected cb func OnGameAttached() -> Bool {
  let result: Bool = wrappedMethod();
  if ScannerSuiteConfig.EnableAutoPickupCursor()
      || ScannerSuiteConfig.EnableConstantAutoLoot() {
    this.APS_StartLootLoop();
  };
  return result;
}
```

### 4.4 Relax the worker filter (the take-everything policy)

**`APS_TryAutoPickup`** per-item filter chain (:775–793). Add one local before the loop and gate the
three policy branches on it; leave the nameless branch and the take/sound branch untouched.

Before the `for itemData in itemList {` at :775, add:

```reds
  let takeAll: Bool = ScannerSuiteConfig.AutoPickupTakeQuestAndIconic();
```

Then change the skip chain (:778–785) to:

```reds
    if Equals(name, "") && !Equals(itemType, gamedataItemType.Gen_Readable) {
      // nameless internal placeholder (non-shard) — ALWAYS skip (structural: can't be held)
    } else if !takeAll && Equals(itemType, gamedataItemType.Wea_HeavyMachineGun) {
      // HMG/turret weapons — skip unless take-everything (see HMG caveat in the plan)
    } else if !takeAll && (itemData.HasTag(n"Quest") || this.IsQuest()) {
      // quest item/object — skip unless take-everything (takeAll also short-circuits
      // the persistent m_markAsQuest whole-object over-skip footgun)
    } else if !takeAll && RPGManager.IsItemIconic(itemData) {
      // iconics — skip unless take-everything
    } else {
      // ... unchanged take + sound branch (:786–792) ...
    };
```

No other worker change. The range gate (:752–753) already reads `AutoPickupMaxDistance()`, now 50, so
it needs no edit. The LOS gate (:756–758, `IsVisibleTarget`) is **KEPT for every channel** — do not
touch it.

### 4.5 Explicitly NOT changed

- **`APS_RunCursorPickup`** (:642–669) — body unchanged; only its caller moved (ST_SweepTick → loop).
- **Hover hook** `OnScannedObjectChanged` (:822–875) — left intact, including its pickup branch
  (:863–869). It shares the ledger (no double-loot), inherits the unified 50 m range + take-everything
  filter automatically via the worker (zero edits needed there), and gives instant pickup the moment the
  scanner focuses an object. Only sync the rename: `EnableAutoPickupOnScan()` → `EnableAutoPickupCursor()`
  at :826. Its auto-TAG branch is unrelated and untouched.
- **`APS_TryAutoPickup` type/range/LOS gates, `APS_ResolveLootTarget`, ledger, loot-while-scanning,
  auto-tag sweep classification** — all unchanged.

---

## 5. Documentation edits (comments only, no behavior)

Make the self-documenting header stop lying. Sites:

- :3–5 — "Three independent scan-mode features … auto-pickup is a single cursor channel": auto-pickup is
  now cursor + an always-on 360° surroundings channel, and it is no longer scan-scoped.
- :34–58 — the FEATURE 3 block: rewrite to describe the unified auto-loot (F1 cursor look-at, always-on;
  F2 GetEntityList surroundings; 50 m; LOS; take-everything incl. quest/iconic/HMG by default via
  `AutoPickupTakeQuestAndIconic`; nameless kept; game-thread DelaySystem loop driven by
  `PlayerPuppet.OnGameAttached`).
- :60–74 — the Wraps block: ADD `PlayerPuppet.OnGameAttached (arms the always-on loot loop; game-thread,
  once per load)`. Rewrite the "(NO GameObject.OnGameAttached wrap …)" note to clarify the distinction:
  the PLAYER-object `OnGameAttached` is now wrapped (safe, game-thread), while the per-arbitrary-entity
  `GameObject.OnGameAttached` streaming registry stays removed and must never return.
- :587 — section header "cursor 40 m channel": → "cursor look-at + 360° surroundings, 50 m".
- Any remaining "40 m" literals in comments (:36, :130) → 50 m.

---

## 6. Crash-safety argument (`crashSafetyStatement`)

Fully compliant with the non-negotiable crash law. Every element runs on the GAME THREAD; no path can
reach a `redDispatcher` streaming worker:

1. **Driver** = `@wrapMethod(PlayerPuppet) OnGameAttached` `[V] player.swift:1065`. This is the PLAYER
   object attaching, which is game-thread and fires once per load — it is categorically NOT the
   per-arbitrary-entity `GameObject.OnGameAttached` (`gameObject.swift:356`) that runs on
   entity-streaming worker threads and, via an unsynchronized shared-array `ArrayPush`, caused the
   shipped heap corruption (`scanner-suite-crash-analysis.md`). Two installed mods already wrap this
   exact player method safely (`SwitchSpeed.reds:185`, `street_vendors.reds:87`).
2. **Loop** = `APSLootLoopCallback extends DelayCallback`, re-armed via `DelaySystem.DelayCallback`
   `[V] orphans.swift:11818`. `DelayCallback.Call()` fires on the game tick (game thread), the same
   context as the existing `ST_SweepTick` sweep.
3. **Reads only, off nothing.** Each tick calls `GetLookAtObject`, `GetEntityList`
   `[V] orphans.swift:11551`, `Entity.GetWorldPosition` `[V] entity.swift:44`, `IsVisibleTarget`,
   `GetItemList` — all READ engine state. `GetEntityList`'s sole vanilla caller
   (`PlayerDevelopmentSystem.ScaleNPCsToPlayerLevel`, `playerDevelopmentSystem.swift:2522`) invokes it
   from an unsynchronized game-thread system method and iterates + casts `as GameObject` exactly as this
   design does — game-thread-safe by construction.
4. **Only game-thread mutations.** `ArrayPush` into the single-`PlayerPuppet` `m_apsAttempted` ledger
   (:602–605) and the `m_apsSurroundAccum` float write, both inside the `DelayCallback` (game thread).
   `TransferItem` is a native game-thread transaction (identical to vanilla looting). No shared script
   array is mutated off-thread.
5. **No new lifecycle registry.** The design adds NO `GameObject.OnGameAttached` / `OnDetach` /
   per-entity registry. The removed `redDispatcher` heap-corruption class (identical wild fault address,
   PoolStorage free-list corruption) is structurally unreachable.
6. **Kill-switch = pure vanilla.** `EnableAutoPickupCursor() == false && EnableConstantAutoLoot() ==
   false` ⇒ `OnGameAttached` is a passthrough, no loop, no cost. All added state is session-transient.

---

## 7. Cross-mod collision notes

- **`PlayerPuppet.OnGameAttached` is now wrapped by three mods** (SwitchSpeed, street_vendors, and this
  one). REDscript `@wrapMethod` composes into a chain; each of the three calls `wrappedMethod()` exactly
  once, so the chain stays intact and load order is irrelevant to correctness. Our wrap captures and
  returns the inner `Bool` (`let result = wrappedMethod(); …; return result;`), matching the file's own
  idiom and preserving the return value up the chain.
- No conflict with the scanner suite's existing wraps (`HUDManager.*`,
  `scannerDetailsGameController.OnScannedObjectChanged`) — different methods.
- The new always-on loot loop and the existing scanner-gated tag sweep are independent: distinct guard
  fields (`m_apsLoopArmed` vs `m_stSweepArmed`), distinct ledgers (`m_apsAttempted` vs `m_autoTagSeen`),
  distinct callbacks (`APSLootLoopCallback` vs `STSweepTickCallback`). They never double-arm or fight.
- Any other installed autoloot mod (e.g. CNML) would share loot targets, but the ledger only prevents
  OUR channels from re-hammering; a third-party mod looting the same container first just means our
  worker finds an empty `GetItemList` (transient refusal, no spend) — harmless coexistence.

---

## 8. In-game test plan (`testPlan`)

Compile + launch via `script/launch_modded.sh` (Steam running; scc compiles the single file).

1. **Compile clean** — no scc errors after the edits (watch for the rename touching all sites, the new
   `DelayCallback` subclass, and the worker `takeAll` local).
2. **Crash-safety ship-gate (mandatory)** — load a save in a dense crowd+combat district; play a
   streaming-heavy stretch (fast-travel hops, drive across the map, a firefight) for 5–10 min. Confirm
   NO crash. A regression would present as the old `EXC_BAD_ACCESS` on `redDispatcher` — it must not
   recur (this design cannot reach that path, but exercise streaming to be sure).
3. **Size the entity list** — set `DebugProbeAutoPickup() = true`; read the HUD activity log for
   `"APS surround: entities=N picked=M"`. Confirm N is sane (hundreds, low thousands worst case) in the
   densest scene; if N is pathological, raise `ConstantAutoLootInterval()` to 2.0 and re-check. Then set
   the probe back to `false`.
4. **F2 surroundings (no aiming)** — stand within 50 m of dropped items / killed NPCs / open+closed
   containers, do NOT aim at them; confirm they auto-collect within ~1 s, 360° around you.
5. **LOS respected** — place loot behind a wall within 50 m; confirm it is NOT taken until you step
   where you can see it (LOS clears), then it is.
6. **F1 cursor responsiveness + 50 m** — aim the crosshair at a container/corpse near 50 m; confirm it
   is grabbed fast (~0.35 s, before the slower surroundings sweep). Confirm loot beyond the old 40 m cap
   (40–50 m) IS now collected — validates the range bump AND, per §2.2, that `GetLookAtObject` actually
   reaches 50 m (if F1 stops short but F2 still grabs it, the raycast cap < 50 is the cause; F2 coverage
   is unaffected).
7. **Take-everything** — confirm quest items + iconics + an HMG/turret weapon ARE auto-collected with
   `AutoPickupTakeQuestAndIconic() = true`. Then set it `false`, relaunch, confirm quest/iconic/HMG are
   left behind (conservative parity with today).
8. **HMG sanity** — after taking an HMG/turret weapon, confirm no broken weapon state / equip glitch
   (per the §2.1 caveat). If broken, re-skip HMG in the worker.
9. **Kill-switch** — set both `EnableAutoPickupCursor() = false` and `EnableConstantAutoLoot() = false`,
   relaunch; confirm ZERO auto-loot (fully manual/vanilla), no loop armed.
10. **Tag coexistence** — with auto-tag on, open the scanner; confirm auto-TAG still works (sweep
    tag-only path intact) and the loot loop runs alongside without interference.

---

## 2026-07-07 — IMPLEMENTED (Agent D)

Applied to `mods/enabled/r6-scripts/custom-scanner-suite/ScannerSuite.reds` (875 -> 1077 lines). Pristine
pre-edit copy backed up to the session scratchpad (`ScannerSuite.orig.reds`) for the reviewer diff.
Compile not run here (deploy agent runs `scc`). All API signatures re-verified in the decompile this
pass: `GameInstance.GetEntityList` (orphans.swift:11551, `-> [ref<Entity>]`), `PlayerPuppet.OnGameAttached`
(player.swift:1065, `protected cb func … -> Bool`), `DelayCallback` base + `Call()` (delaySystem.swift:7-9),
`DelaySystem.DelayCallback` (orphans.swift:11818), `Entity.GetWorldPosition` (entity.swift:44, native const),
`GameObject extends GameEntity extends Entity` (gameObject.swift:87, orphans.swift:11315).

**Config (`ScannerSuiteConfig`):**
- Renamed `EnableAutoPickupOnScan()` -> `EnableAutoPickupCursor()` (still `return true;`); refs updated at
  the hover hook + the new loop/wrap. Comment rewritten (now always-on, 50 m).
- `AutoPickupMaxDistance()` 40.0 -> 50.0 (shared range for both channels); comment rewritten.
- Added `EnableConstantAutoLoot()` (true), `AutoPickupLoopInterval()` (0.35), `ConstantAutoLootInterval()`
  (1.0), `AutoPickupTakeQuestAndIconic()` (true), each with the planned doc comment.
- `DebugProbeAutoPickup()` comment extended to mention the `"APS surround: entities=N picked=M"` line.

**Code:**
- `OnScannerUIVisibleChanged` arm condition narrowed to `EnableAutoTagOnScan()` only (cursor left the sweep).
- `ST_SweepTick` is now tag-only: deleted the `cursorOn` local, the `APS_RunCursorPickup` block, and the
  `&& !cursorOn` in the stop guard; comments updated.
- Added the always-on loot loop subsection in FEATURE 3: `APSLootLoopCallback extends DelayCallback`;
  `@addField(PlayerPuppet) m_apsLoopArmed: Bool` + `m_apsSurroundAccum: Float`; `APS_StartLootLoop`,
  `APS_ArmLootTick`, `APS_LootLoopTick` (cursor every tick + accumulator-gated surroundings), and
  `APS_RunSurroundingsPickup` (GetEntityList walk, distance-reject-before-cast, shared ledger + worker).
- Added `@wrapMethod(PlayerPuppet) OnGameAttached` driver: `let result = wrappedMethod(); if
  EnableAutoPickupCursor() || EnableConstantAutoLoot() { APS_StartLootLoop(); }; return result;`.
- `APS_TryAutoPickup`: added `let takeAll = AutoPickupTakeQuestAndIconic();` before the loop; gated the
  HMG / Quest+IsQuest / iconic skips on `!takeAll && …`; nameless structural skip + take/sound branch
  unchanged. Range gate + LOS gate untouched (range now reads 50 via the constant).
- Doc: header intro, FEATURE 3 block, Wraps block, section banner, and the cursor-channel comment block
  updated (the last two also fixed the now-stale "invoked ONLY from ST_SweepTick" / "every
  AutoTagSweepInterval" statements — a small accuracy edit beyond §5's listed sites).

**Crash-safety self-check (all game-thread):** driver = `PlayerPuppet.OnGameAttached` (player object,
game thread, once per load — NOT the per-arbitrary-entity `GameObject.OnGameAttached` streaming hook that
crashed). Loop = `DelaySystem.DelayCallback` on the game tick. Each tick only READS engine state
(`GetLookAtObject`, `GetEntityList`, `Entity.GetWorldPosition`, `IsVisibleTarget`, `GetItemList`); the
sole shared mutations (`m_apsAttempted` ArrayPush, `m_apsSurroundAccum`, `m_apsLoopArmed`, `TransferItem`)
all run inside the game-thread DelayCallback / the game-thread `OnGameAttached` wrap. NO per-arbitrary-entity
`GameObject.OnGameAttached`/`OnDetach`/entity-lifecycle registry added — the removed heap-corruption class
stays structurally unreachable.

**Toggles / kill-switch:** with `EnableAutoPickupCursor() == false && EnableConstantAutoLoot() == false`,
`OnGameAttached` never calls `APS_StartLootLoop` (no loop armed), the hover pickup branch is gated off,
and pickup is 100% vanilla. `AutoPickupTakeQuestAndIconic() == false` restores today's conservative
quest/iconic/HMG skips. All added fields are session-transient.

**Not done here (by task):** did not run `scc`, did not launch the game, did not clear `r6/cache`. The
in-game test plan (§8) — especially the mandatory crash-safety streaming gate, the `DebugProbe` entity-list
sizing, and the F1 50 m / HMG-sanity checks — remains for the deploy/verify pass.
