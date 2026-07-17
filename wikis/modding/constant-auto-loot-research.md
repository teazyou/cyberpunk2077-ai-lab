# Constant 360° Auto-Loot — Feasibility Research (2026-07-07)

Scope: a NEW, FOURTH feature for the locally-authored **Custom Scanner Suite**
(`mods/enabled/r6-scripts/custom-scanner-suite/ScannerSuite.reds`, ~875 lines). Pure REDscript only,
game v2.3x macOS Steam. NO CET / RED4ext / TweakXL / ArchiveXL / Codeware / Mod Settings.

**The feature (user spec):** a CONSTANT auto-loot loop of the player's SURROUNDINGS. Runs
**ALWAYS** — normal gameplay AND scan/focus mode. Within **50 m** and **respecting line of sight**,
auto-pick **EVERYTHING** lootable **360°** around the player (not just the crosshair target): every
container's contents, dropped item, shard, quest item, iconic, dead-body loot — every loot class.

Evidence tiers: **[V]** read directly in the local decompiled 2.x vanilla sources
(`…/scratchpad/vanilla-scripts/`, `.swift`). **[S]** inferred, not directly exercised.

## Verdict up front

**feasibility = feasible-full.** A true 360° / 50 m / LOS loot vacuum over EVERY loot class IS
achievable crash-safe in pure REDscript — via **`GameInstance.GetEntityList()`** ([V] orphans.swift:11551)
polled on a **dedicated, slow-cadence, self-re-arming DelaySystem loop** started from
**`PlayerPuppet.OnGameAttached`** (the PLAYER object only = game thread; already safely wrapped by
two installed mods). `GetEntityList` returns the RAW world entity list (`[ref<Entity>]`), NOT the
`TargetingComponent`-filtered set the two aborted radius channels were trapped by — so it is the ONE
enumerator that sees standalone containers / drops / shards, and it runs on the game thread, so
READING it is crash-safe. The prior work dismissed it only for a 0.35 s *shared* tick; a dedicated
0.5–2 s loop moves its cost well under the envelope a shipped mod (CNML) already proved acceptable.

This is the untaken path the two prior radius aborts never tried. It does NOT resurrect the
heap-corruption `OnGameAttached` registry (mechanism b), and it is not blocked by the
"loot carries no `TargetingComponent`" wall that killed mechanisms (a).

The one thing that MUST be probed in-game before shipping the fast end of the cadence: the SIZE of
`GetEntityList` in the densest scene (crowd + combat). Design mitigations below make even a large
list safe (slow cadence / chunked scan), so this gates *tuning*, not *feasibility*.

---

## Crash-safety law (non-negotiable — recap)

A shipped Scanner Suite version hard-crashed (heap corruption, EXC_BAD_ACCESS, identical wild fault
address across runs, on `redDispatcher` worker threads — see `scanner-suite-crash-analysis.md`). Root
cause: `@wrapMethod(GameObject) OnGameAttached` doing an unsynchronized `ArrayPush` into a shared
`PlayerPuppet` field. `OnGameAttached` fires on the RED entity-STREAMING WORKER threads; concurrent
pushes into one shared `DynArray` corrupted the allocator free-list.

Rules this design obeys:
- (a) all custom mutation runs on the GAME THREAD only (DelaySystem ticks, input/interaction
  callbacks, player-scoped wraps are game-thread);
- (b) READING engine state off-thread is fine; MUTATING shared script arrays off-thread is the crash;
- (c) NO always-on per-arbitrary-entity `GameObject.OnGameAttached` / `OnDetach` / entity-lifecycle
  registry. That removed registry stays removed.
- Note: `PlayerPuppet.OnGameAttached` (the PLAYER OBJECT ONLY) is game-thread and fine for STARTING a
  timer — it is NOT the per-arbitrary-entity streaming hook that crashed.

---

## Mechanisms evaluated (the core research question)

Can ANY crash-safe, game-thread, pure-REDscript mechanism enumerate loot-class entities
(`gameLootContainerBase` / `gameItemDropObject` / `ShardCaseContainer` / bare `ItemObject`) 360°
around the player? Five candidates, each against the decompile:

| # | Mechanism | sees loot? | crash-safe? | game-thread? | Verdict |
|---|---|---|---|---|---|
| a | `TargetingSystem.GetTargetParts` / `GameObject.GetEntitiesAroundObject` | **NO** (corpses/devices only) | yes | yes | **REJECT** — structurally blind to loot |
| b | `GameObject.OnGameAttached` registry (CNML) | yes | **NO** | **NO** (streaming workers) | **REJECT** — this IS the heap-corruption crash |
| c | **`GameInstance.GetEntityList()` slow dedicated loop** | **YES** | **YES** | **YES** | **RECOMMENDED** — the untaken viable path |
| d | Loot interaction-proximity layer wrap (`OnInteractionActivated`) | **YES** | **YES** | **YES** | **VIABLE ALTERNATIVE** — but range fixed & unconfigurable |
| e | `TriggerComponent.GetOverlappingEntities` / `SpatialQueriesSystem.Overlap` | yes / n-a | yes | yes | **REJECT** — not attachable to player / single-hit only |

### (a) Targeting queries — REJECT, re-confirmed [V]

`TargetingSystem.GetTargetParts` (orphans.swift:22383) and its wrapper
`GameObject.GetEntitiesAroundObject(range, filter)` (gameObject.swift:686) both surface an entity
ONLY through `TS_TargetPartInfo.GetComponent(part) -> wref<TargetingComponent>` then `.GetEntity()`.
An entity with **no `TargetingComponent` is unreturnable by any `TargetingSet`** (Frustum / Complete /
Visible / …). Grep of `RequestComponent(… n"gameTargetingComponent" …)` across the whole tree — the
exhaustive list of who carries one:

- `ScriptedPuppet` (scriptedPuppet.swift:430–433, four body parts) — so CORPSES are returnable.
- `deviceBase` (deviceBase.swift:348), `SensorDevice`, `SecurityTurret` (securityTurret.swift:51),
  `sniperNest` (sniperNest.swift:72), `chimeraBossComponent` (:125), `player` (player.swift:687).

**ZERO loot classes** request it (`inventoryComponent.swift`, `lootContainers.swift`, `item.swift`,
`shardCaseContainer.swift` request only `Collider`, e.g. inventoryComponent.swift:154). So containers,
dropped items, shard cases, bare items are invisible to EVERY targeting/frustum query. This is why
BOTH prior radius channels collapsed to "corpses-only". Re-verified this pass; unchanged.

### (b) `OnGameAttached` registry (CNML mechanism) — REJECT [V]

Wrapping `GameObject.OnGameAttached` (gameObject.swift:356) to push every streamed loot entity into a
shared `PlayerPuppet` array, then distance-filtering that registry, is CNML's (Nexus 16040) mechanism
— and it is **exactly the removed heap-corruption crash**. `OnGameAttached` runs on the streaming
worker pool; the unsynchronized shared-array `ArrayPush` corrupts the heap. Do NOT resurrect it.

The prior analysis also **rejected the "marshal to the game thread via a 0-delay `DelayCallback`"
softening** (`plan-fix-loot-pickup-containers-items.md` §Radius): calling `DelaySystem.DelayCallback`
*from* the streaming worker still touches a shared native queue unsynchronized (same race class) and
allocates one callback per stream-in (thousands on load — the crash amplifier). No game-thread-safe
variant of this mechanism exists at an acceptable bar. REJECT.

### (c) `GameInstance.GetEntityList()` — RECOMMENDED [V]

```
public final static native func GetEntityList(self: GameInstance) -> [ref<Entity>];   // orphans.swift:11551
```

**Why it is categorically different from (a):** it returns the engine's RAW world entity registry as
`[ref<Entity>]` — it does NOT go through `TargetingComponent`, so it enumerates **every streamed game
entity**, loot classes included. The class chain makes every loot class a member and safely castable:
`gameLootObject`/`gameItemDropObject` (inventoryComponent.swift:83/162), `gameLootContainerBase` and
its whole subtree `gameContainerObjectBase`→`ContainerObjectSingleItem`→`ShardCaseContainer`
(lootContainers.swift:409/693, orphans.swift:35180, shardCaseContainer.swift:2), and `ItemObject`
(item.swift:2) all `extends … GameObject extends GameEntity extends Entity` (gameObject.swift:87,
orphans.swift:11315, entity.swift:2).

**Cheap pre-filter WITHOUT casting:** `Entity` itself exposes `GetWorldPosition() -> Vector4` and
`GetEntityID() -> EntityID` as native const (entity.swift). So each pass can reject out-of-range
entities with one `Vector4.Distance` BEFORE any `as GameObject` cast — the expensive class casts +
`GetItemList` + `IsVisibleTarget` run only for the handful within 50 m.

**Game-thread & crash-safe:** the sole vanilla caller,
`PlayerDevelopmentSystem.ScaleNPCsToPlayerLevel` (playerDevelopmentSystem.swift:2522), calls it from a
plain game-thread system method with zero synchronization ceremony, iterating the whole list and
casting each `entityList[i] as GameObject` — the exact pattern this feature reuses. Called from OUR
DelaySystem tick (game thread), it only READS engine state and allocates a LOCAL ref array; the sole
shared mutation is the player attempt-ledger `ArrayPush`, on the game thread. No streaming-worker code,
no per-entity lifecycle hook. The removed `redDispatcher` crash class stays removed.

**Cost model — the honest part.** `GetEntityList` returns the CURRENTLY-streamed game-entity set
(NPCs, vehicles, devices, loot, interactive props, the player) — NOT static non-entity sector meshes
(walls/floors/décor are streaming nodes, not `Entity`s), so the count is hundreds in a normal
district, plausibly ~1–2 k in the worst crowd+combat scene ([S] — must be probed with a one-session
`ArraySize` log). Per pass:

1. ONE native `GetEntityList` call = an O(N) ref-array copy (~8 bytes × N; a few KB) — the only
   per-pass allocation.
2. N × (`GetWorldPosition` + `Vector4.Distance`) cheap reject.
3. For the few survivors (typically a handful–dozens within 50 m): `as GameObject` + loot-class casts
   + `APS_TryAutoPickup` (`GetItemList` + `IsVisibleTarget` + `TransferItem`).

At a **dedicated 1.0 s cadence** (configurable 0.5–2.0 s), that is ~N distance checks/s (≈1 k sqrt/s
worst case — negligible CPU) plus one small transient allocation/s. **Comparison that settles it:**
CNML (the shipped gold-precedent autoloot) walks an UNBOUNDED, ever-growing `OnGameAttached` registry
every ~0.35 s and ships acceptably; `GetEntityList`'s working set is BOUNDED to currently-loaded
entities and SELF-PRUNES as they stream out — a strictly smaller, self-cleaning version of what CNML
proved fine, the only delta being one native list-copy per pass (negligible at slow cadence).

**Why the prior dismissal doesn't apply:** the refinements dossier dismissed `GetEntityList` for a
**0.35 s SHARED** tick (co-resident with the tag sweep + enemy sweep, ~3×/s), i.e. "allocate + iterate
every entity each tick" at 3 Hz. A DEDICATED 1 s loop with no passengers is ~3× less frequent and
carries none of the other per-tick work — comfortably under the envelope.

### (d) Loot interaction-proximity layer wrap — VIABLE ALTERNATIVE [V]

Every loot class carries **quality-scaled proximity interaction layers**
(`QualityRange_Short/Medium/Max`) plus an `n"auto"` walk-over layer, and reacts to the player entering
them **on the game thread**:

```
protected cb func OnInteractionActivated(evt: ref<InteractionActivationEvent>) -> Bool {  // gameLootObject, inventoryComponent.swift:92
  if Equals(evt.layerData.tag, n"auto") { GameObject.PlaySoundEvent(evt.activator, n"ui_loot_ammo"); }  // vanilla walk-over ammo auto-pickup
}
```
```
if Equals(evt.eventType, gameinteractionsEInteractionEventType.EIET_activate) {   // gameItemDropObject, inventoryComponent.swift:343
  if evt.activator.IsPlayer() {
    if this.IsQualityRangeInteractionLayer(evt.layerData.tag) { this.m_isInIconForcedVisibilityRange = true; … }
```

`OnInteractionActivated` overrides exist on `gameLootObject` (inventoryComponent.swift:92),
`gameItemDropObject` (inventoryComponent.swift:343), `gameLootBag` (lootContainers.swift:335),
`gameLootContainerBase` (lootContainers.swift:723), AND `ScriptedPuppet` corpses (the same
QualityRange machinery, scriptedPuppet.swift:3610) — i.e. **essentially every loot class**. The event
carries `activator: wref<GameObject>` (the player) and `layerData.tag: CName`
(InteractionBaseEvent, orphans.swift:18261–18273); `EIET_activate=0`/`EIET_deactivate=1`
(orphans.swift:547) mark enter/exit.

**A `@wrapMethod(gameLootObject) OnInteractionActivated` (and one for `gameLootContainerBase`) is
crash-safe:** it is a method-body wrap on the class vtable — NOT an `OnGameAttached` registry, it
pushes nothing into a shared array on stream-in. Interaction activation is dispatched on the GAME
THREAD (interaction/input callbacks are game-thread per the crash law). When it fires, `this` is the
loot object and `evt.activator` is the player → call `APS_TryAutoPickup(this)` right there, gated by
the shared ledger. Event-driven, so ZERO polling cost.

**Why it is the ALTERNATIVE, not the primary — the range trap [V]:** the trigger DISTANCE of
`QualityRange_Short/Medium/Max` lives in each entity's authored interaction-component template
(redengine/TweakDB), not in script. These are the short, quality-scaled "loot-icon forced-visibility"
ranges (a few metres, wider for higher quality) — they are NOT 50 m and CANNOT be widened or made
configurable from pure REDscript (that needs TweakXL, which is off the table). It also fires only while
a layer is enabled (populated loot with valid quality; `SetQualityRangeInteractionLayerState`,
inventoryComponent.swift:102/149). So (d) delivers a genuine crash-safe 360° loot pickup, but at the
game's fixed proximity ranges — an approximation of the 50 m spec, not the full spec. Best role: a
zero-cost close-range complement to (c), or the fallback if (c)'s list-size probe ever comes back
pathological. Not recommended as the sole mechanism because it can't honor the 50 m / configurable
requirement.

### (e) TriggerComponent / SpatialQueries — REJECT [V]

- `TriggerComponent.GetOverlappingEntities() -> [ref<Entity>]` (orphans.swift:26438,
  `TriggerComponent extends AreaShapeComponent extends IPlacedComponent`) DOES return entities incl.
  loot (not `TargetingComponent`-gated) and is game-thread. BUT every vanilla caller reads it off an
  **authored `m_areaComponent`/`m_triggerComponents`** placed on a device entity at design time
  (aoeArea.swift:183, blindingLight.swift:104, disposalDevice.swift:485, ventilationArea.swift:142,
  activatedDeviceTrap.swift:89, …). There is no player-centred 50 m trigger volume, and creating +
  attaching + sizing an `AreaShapeComponent` on the player is NOT a pure-REDscript operation (needs
  RED4ext/Codeware). REJECT (toolchain).
- `SpatialQueriesSystem.Overlap(primitiveDimension, position, rotation, …, out result: TraceResult)`
  (orphans.swift:27637) returns a **single** `TraceResult.hitObject: wref<Entity>` (orphans.swift:27598/27540),
  not an enumeration — to cover a volume you'd fire many overlaps and still depend on loot collision
  groups. Not an enumerator. REJECT.
- Interactions blackboard (`InteractionChoiceHubData` orphans.swift:42008, `VisualizersInfo` :54559)
  expose only opaque `Int32` ids — no `EntityID`/activator — so "nearby loot from the interaction hub"
  is unresolvable in script (confirmed `plan-fix-loot-pickup-containers-items.md`). REJECT.

---

## Recommended design (mechanism c)

A new, self-contained FOURTH channel — call it **CAL** (Constant Auto-Loot) — additive to the file,
reusing the existing worker + ledger. It does NOT touch the scanner sweep loop, the cursor channel,
loot-while-scanning, or auto-tag.

### 1. Always-on driver (crash-safe) [V]

The existing sweep arms only while the scanner UI is visible (`OnScannerUIVisibleChanged`). A CONSTANT
loop needs a driver that runs regardless of UI. Use the player-object attach hook:

```reds
@wrapMethod(PlayerPuppet)
protected cb func OnGameAttached() -> Bool {           // player.swift:1065 — GAME THREAD, once per load
  let r: Bool = wrappedMethod();
  if ScannerSuiteConfig.EnableConstantAutoLoot() {
    this.CAL_StartLoop();                              // arm the self-re-arming DelaySystem loop
  };
  return r;
}
```

- `PlayerPuppet.OnGameAttached` is the PLAYER object attaching — game-thread, fires once per session /
  load, NOT the per-arbitrary-entity streaming hook. **Precedent (installed, safe):**
  `custom-switch-speed/SwitchSpeed.reds:185` and `street-vendors/street_vendors.reds:87` already wrap
  it with the identical `wrappedMethod(); …` shape. `@wrapMethod` chains compose.
- Loop = a `DelayCallback` subclass (base `delaySystem.swift:7`, `public func Call()`), re-armed each
  tick via `GameInstance.GetDelaySystem(game).DelayCallback(cb, ConstantAutoLootInterval(), true)`
  (orphans.swift:11818; `isAffectedByTimeDilation = true` so it pauses when the game pauses). Hold a
  `wref<PlayerPuppet>`; if it goes null (session end / load) the loop self-terminates and the next
  `OnGameAttached` re-arms a fresh one. Guard with an `m_calLoopArmed: Bool` field (mirror the existing
  `m_stSweepArmed` double-arm guard, ScannerSuite.reds:464) so a re-entrant attach can't spawn two
  loops. This is the SAME machinery already proven in-file, just driven from the player instead of the
  HUD.

### 2. The scan pass (game-thread) [V]

```reds
@addMethod(PlayerPuppet)
public final func CAL_RunOnce(game: GameInstance) -> Void {
  if this.IsReplacer() || this.GetHudManager().IsBraindanceActive() { return; }   // parity w/ cursor channel
  let origin: Vector4 = this.GetWorldPosition();
  let maxDist: Float = ScannerSuiteConfig.ConstantAutoLootRange();                 // 50.0
  let entities: array<ref<Entity>> = GameInstance.GetEntityList(game);            // RAW world list — sees loot
  let i: Int32 = 0;
  while i < ArraySize(entities) {
    let e: ref<Entity> = entities[i];
    // CHEAP reject first — Entity.GetWorldPosition is native const, no cast yet:
    if IsDefined(e) && Vector4.Distance(origin, e.GetWorldPosition()) <= maxDist {
      let go: ref<GameObject> = e as GameObject;
      if IsDefined(go) {
        let target: ref<GameObject> = go.APS_ResolveLootTarget();                 // bare ItemObject -> its drop (existing helper)
        let id: EntityID = target.GetEntityID();
        // shared ledger with cursor/hover: never re-hammer; transient refusals stay eligible
        if !this.APS_AlreadyAttempted(id) && target.APS_TryAutoPickup(this, true) {  // relaxFilters = true
          this.APS_MarkAttempted(id);
        };
      };
    };
    i += 1;
  }
}
```

- Reuses `APS_ResolveLootTarget` (ScannerSuite.reds:702), the shared `m_apsAttempted` ledger
  (`APS_AlreadyAttempted`/`APS_MarkAttempted`, :596–606), and the worker `APS_TryAutoPickup` (:723).
- The worker already: type-gates (corpse must be dead/incap; else must be a loot class; skips stash;
  locked-container transient), range-gates, LOS-gates (`IsVisibleTarget`, orphans.swift:22453),
  reads `GetItemList` (transactionSystem 18087), snapshots `{ItemID,qty}` then `TransferItem`
  (18057) — the mutation-during-iteration use-after-free is ALREADY fixed (snapshot-then-transfer,
  :767–799). Plays loot sound, opens animated crates. **No worker rewrite needed — only the filter
  relaxation below.**

### 3. Filter policy — take EVERYTHING, gated [V]

Spec: this channel takes quest + iconic too. Relax the worker's per-item skips **only for CAL**, keep
them for cursor/hover. Cleanest: add a `relaxFilters: Bool` param to `APS_TryAutoPickup` (existing call
sites pass `false`; CAL passes `true`), consulted where the worker currently skips:

- `itemData.HasTag(n"Quest") || this.IsQuest()` (ScannerSuite.reds:782) — bypass when `relaxFilters`.
- `RPGManager.IsItemIconic(itemData)` (:784) — bypass when `relaxFilters`.
- `Wea_HeavyMachineGun` (:780) — bypass when `relaxFilters` (spec: "Quest/iconic/HMG skips relaxed").
- **KEEP** the nameless-internal-placeholder skip (:778) unconditionally — those are non-items.
- The worker's LOS gate (`IsVisibleTarget`, :756) STAYS for CAL (spec: respect LOS).
- The worker's range gate (:752, `AutoPickupMaxDistance` = 40) must not clip CAL's 50 m: when
  `relaxFilters`, gate on `ConstantAutoLootRange()` instead (CAL already distance-filtered upstream, so
  this is belt-and-suspenders). Simplest robust form.

Prefer a `relaxFilters` param over the worker reading the config flag directly, so the two conservative
channels are unaffected and the branch is explicit at each call site. The worker body is otherwise
reused verbatim.

### 4. LOS + range + once-per-entity

- **Range 50 m:** cheap `Entity.GetWorldPosition` + `Vector4.Distance` pre-filter (pass 2 above) +
  worker re-gate. Config literal `ConstantAutoLootRange() = 50.0`.
- **LOS:** `TargetingSystem.IsVisibleTarget(player, target)` inside the worker (unchanged) — loot behind
  a wall within 50 m is a TRANSIENT refusal (no ledger spend), auto-picked once LOS clears. Matches the
  deliberate cursor-channel LOS asymmetry (info through walls = tag; moving items through walls = no).
- **Once-per-entity:** the shared `m_apsAttempted` ledger converges the constant loop naturally — each
  in-range visible loot is attempted once, looted, marked, then skipped; transient refusals (alive
  puppet, locked, occluded, empty, out-of-range) spend nothing and remain eligible.

### 5. Config surface (static funcs, no settings UI)

```reds
public final static func EnableConstantAutoLoot() -> Bool { return true; }      // false = 100% vanilla (loop never arms)
public final static func ConstantAutoLootRange() -> Float { return 50.0; }
public final static func ConstantAutoLootInterval() -> Float { return 1.0; }    // 0.5–2.0 s dedicated cadence
public final static func DebugProbeConstantAutoLoot() -> Bool { return false; } // logs ArraySize(GetEntityList) + picked count
```

`EnableConstantAutoLoot()=false` ⇒ `OnGameAttached` is a pure passthrough, no loop, no cost — 100%
vanilla, exactly like every other feature's kill-switch.

### Estimated impact on ScannerSuite.reds

| Change | Est. LOC |
|---|---|
| Config block: 4 CAL funcs | +8 |
| `@wrapMethod(PlayerPuppet) OnGameAttached` + `CAL_StartLoop` + `m_calLoopArmed` field + `CALTickCallback` subclass | +40 |
| `CAL_RunOnce` scan pass | +30 |
| `APS_TryAutoPickup` `relaxFilters` param threaded through 4 skip sites + 2 existing call sites pass `false` | ~15 (edit) |
| Header-comment feature block | ~20 (edit) |

Net ≈ **+80 new / ~35 edited LOC**; worker/ledger/cursor/tag/loot-while-scanning bodies otherwise
untouched. No new `OnGameAttached`-registry / streaming / worker hook.

---

## Crash-safety statement

Every element is game-thread: the driver is `PlayerPuppet.OnGameAttached` (player object = game
thread, precedent-wrapped by two installed mods); the loop is a `DelaySystem.DelayCallback` (game
tick); the scan READS engine state (`GetEntityList` + `Entity.GetWorldPosition` + `IsVisibleTarget`)
and MUTATES only the single-`PlayerPuppet` `m_apsAttempted` ledger, on the game thread. It adds NO
per-arbitrary-entity `OnGameAttached`/`OnDetach`/entity-lifecycle registry — so the removed
`redDispatcher` streaming-worker heap-corruption class (identical wild fault address, PoolStorage
Allocate free-list corruption) is structurally unreachable. `GetEntityList`'s sole vanilla caller
invokes it from an unsynchronized game-thread system method, so the native call is safe against
concurrent streaming by construction (any internal snapshot/lock is the engine's responsibility). All
CAL state is session-transient (never saved). `EnableConstantAutoLoot()=false` makes the whole feature
a pure passthrough.

---

## Risks & unknowns

1. **`GetEntityList` size in the densest scene** [S, MEDIUM] — the one thing to PROBE before shipping
   the fast cadence: `DebugProbeConstantAutoLoot` logs `ArraySize(GetEntityList)` in a crowd+combat
   district. If it returns pathologically large (many thousands), raise the cadence to 2 s and/or chunk
   the scan (process a slice of the list per tick, round-robin) — both keep it feasible. Gates tuning,
   not feasibility.
2. **Ledger growth / O(n) `ArrayContains`** [S, LOW-MEDIUM] — `m_apsAttempted` grows with distinct loot
   looted per session; the constant loop checks it more often than the cursor channel does. Late-game
   this is a linear scan per in-range entity per tick. Acceptable at slow cadence (CNML tolerated
   similar); if ever hot, cap or bucket the ledger. Session-transient, never saved.
3. **Economy / pacing** [design, by spec] — a true 50 m vacuum that also takes quest+iconic trivializes
   loot pacing and can spike encumbrance mid-mission. This is the explicit user spec; `EnableConstant
   AutoLoot` and `ConstantAutoLootRange` are the dials. Quest items auto-collected can, in rare
   scripted beats, matter — the user accepted "take everything"; note it, keep the nameless skip.
4. **Overlap with cursor/radius channels** [LOW] — CAL makes the aborted radius channel permanently
   unnecessary and largely subsumes the cursor channel (shared ledger ⇒ no double-loot). They coexist
   harmlessly; the cursor channel can stay for instant on-hover response or be retired.
5. **Loot-gen timing** [V/S, LOW] — containers fill at stream-in (`ContainerFilledEvent`/
   `wasLootInitalized`, lootContainers.swift). A just-streamed empty-now container is a TRANSIENT
   refusal (`GetItemList()==0`), re-checked next tick — same rule the cursor channel already relies on.
6. **Stealth** [S, LOW] — `TransferItem` broadcasts no stim in any read script path; auto-looting at
   50 m should be detection-neutral, but auto-emptying a body/container a guard is about to inspect
   could in principle change a scripted reaction. No counter-evidence found; note it.
7. **Two-class interaction wrap NOT used** — mechanism (d) is documented as the fallback; the shipped
   design uses only (c), so no always-on interaction hook is added either.

## Sources

- Local decompiled 2.x vanilla scripts (`…/scratchpad/vanilla-scripts/`):
  `orphans.swift` (`GetEntityList` 11551, `DelaySystem.DelayCallback` 11818 / `CancelCallback` 11834,
  `GameEntity` 11315, `TransactionSystem.TransferItem` 18057 / `GetItemList` 18087,
  `InteractionBaseEvent` 18261–18273, `gameinteractionsEInteractionEventType` 547,
  `TargetingSystem.GetLookAtObject` 22401 / `GetTargetParts` 22383 / `IsVisibleTarget` 22453,
  `TriggerComponent.GetOverlappingEntities` 26438, `SpatialQueriesSystem.Overlap` 27637 /
  `TraceResult` 27598/27540, `ContainerObjectSingleItem` 35180),
  `core/entity/entity.swift:2` (`Entity`, `GetWorldPosition`/`GetEntityID` native const),
  `core/entity/gameObject.swift` (`GameObject` 87, `OnGameAttached` 356, `GetEntitiesAroundObject` 686,
  type predicates `IsPuppet` 1319 / `IsPlayer` 1323 / `IsContainer` 1347 / `IsShardContainer` 1351 /
  `IsPlayerStash` 1355 / `IsItem` 1395),
  `core/components/inventoryComponent.swift` (`gameLootObject` 83, `OnInteractionActivated` 92,
  QualityRange layers 98–150, `gameItemDropObject` 162, drop `OnInteractionActivated` 343),
  `core/components/lootContainers.swift` (`gameLootBag` 91, container `OnInteractionActivated` 335/723,
  `gameLootContainerBase` 409, `gameContainerObjectBase` 693, `LootContainerObjectAnimatedByTransform`
  837),
  `cyberpunk/puppet/scriptedPuppet.swift` (TargetingComponent request 430–433, QualityRange 3610–3643),
  `cyberpunk/devices/core/deviceBase.swift:348`, `cyberpunk/devices/securityTurret/securityTurret.swift:51`,
  `cyberpunk/systems/playerDevelopmentSystem.swift:2522` (sole `GetEntityList` caller — game-thread
  iterate+cast precedent), `cyberpunk/player/player.swift` (`OnGameAttached` 1065, TargetingComponent
  request 687), `core/gameplay/delaySystem.swift:7` (`DelayCallback` base),
  vanilla trigger callers (aoeArea.swift:183, blindingLight.swift:104, disposalDevice.swift:485,
  ventilationArea.swift:142, activatedDeviceTrap.swift:89).
- Installed mods: `custom-switch-speed/SwitchSpeed.reds:185`, `street-vendors/street_vendors.reds:87`
  (safe `PlayerPuppet.OnGameAttached` wrap precedent).
- Prior vault dossiers: `scanner-suite-refinements.md` (radius aborts, no-TargetingComponent finding,
  `GetEntityList` 0.35 s dismissal), `scanner-suite-crash-analysis.md` (the `OnGameAttached` heap
  corruption), `plan-fix-loot-pickup-containers-items.md` (cursor `GetLookAtObject` fix; interaction
  blackboard / marshalling rejections), `scan-mode-auto-pickup.md` (CNML gold precedent, worker recipe).
- Current mod: `mods/enabled/r6-scripts/custom-scanner-suite/ScannerSuite.reds` (worker
  `APS_TryAutoPickup` 723, ledger 593–606, `APS_ResolveLootTarget` 702, sweep-loop machinery 451–508).
