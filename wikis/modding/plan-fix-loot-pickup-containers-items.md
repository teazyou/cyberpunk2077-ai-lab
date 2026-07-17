# Fix Plan — Scanner-Suite auto-pickup misses containers + floor items

**Bug (user-reported, in-game, v2.3x macOS Steam):** Custom Scanner Suite auto-pickup does **not** collect loot containers/crates or weapons/items lying on the floor. It **does** collect corpses. Both the cursor (hover) channel and the 360° radius channel fail for containers + floor items; only corpses work.

**Verdict:** primary cause is **DETECTION**, not pickup. The pickup worker (`GetItemList` + `TransferItem`) is already correct for every loot class; the two channels simply never *hand it* a container or floor item. One latent pickup gap exists (bare `ItemObject`). Fix = give the **cursor** channel a game-thread `GetLookAtObject` poll (vanilla's own crosshair-resolution path) + a small worker redirect. Radius stays corpses-only by construction (crash-safe). Research is decompile-verified below.

Decompile cited = adamsmasher 2.x dump at `…/scratchpad/vanilla-scripts/` (`.swift`); mod = `mods/enabled/r6-scripts/custom-scanner-suite/ScannerSuite.reds` (`.reds`). Tags: **[V]** verified in source, **[S]** speculated/inferred.

---

## Confirmed root cause(s)

### A — Cursor channel binds detection to `UI_Scanner.ScannedObject`, which excludes non-focusable loot [V, PRIMARY]

The cursor channel is `@wrapMethod(scannerDetailsGameController) OnScannedObjectChanged(value: EntityID)` (`ScannerSuite.reds:851-909`). It only runs when the **native scanner** publishes an entity to the `UI_Scanner.ScannedObject` blackboard (`scanner_details.swift:112` registers the listener; `:179` is the cb). That blackboard is written **natively** (no script setter except a C4 fake at `c4.swift:55`), and the native scanner only "focuses" an object that passes `GameObject.ShouldShowScanner()`:

- `gameObject.swift:2224-2237` — `ShouldShowScanner()` returns false unless `m_scanningComponent.HasValidObjectDescription()` (or a clue is enabled).
- `scanningComponent.swift:583-586` — `HasValidObjectDescription()` = has an `ObjectScanningDescription` that `IsValid()`.
- Loot classes carry a `scanningComponent` and *unblock* scanning on attach (`inventoryComponent.swift:184-191` drop, `lootContainers.swift:434-441` container) — but that only enables the loot **highlight/outline**, it does **not** give them a valid object description. NPCs/devices do have one (`deviceBase.swift:591` `DeviceScanningDescription`; puppets carry name/threat descriptions), which is why they focus and loot crates do not.

**Decisive proof that `ScannedObject` misses crosshair-lootables:** vanilla's *own* tagging system does not trust it. `FocusModeTaggingSystem.OnActionWithOwner` (the middle-click tag handler) resolves its target in three tiers — `focusModeTagging.swift:203-209`:

```
target = FindEntityByID(GetScannerTargetID()) as GameObject;      // 1) UI_Scanner.ScannedObject
if !IsDefined(target) { target = GetTargetingSystem().GetLookAtObject(owner, true, true); }  // 2) crosshair + LOS
if !IsDefined(target) { target = GetTargetingSystem().GetLookAtObject(owner, false); ... }    // 3) crosshair no-LOS
```

If `ScannedObject` covered loot crates, tiers 2/3 would be dead code. They exist precisely because plain loot is **not** published to `ScannedObject` — you tag a crate in vanilla via `GetLookAtObject`, not via the scanner focus. The mod's cursor channel only implements tier 1, so containers/floor items never reach `APS_TryAutoPickup`.

### B — Radius channel is structurally puppets-only [V, by design]

`APS_RunRadiusPickup` (`ScannerSuite.reds:669-713`) enumerates via `GameObject.GetEntitiesAroundObject(radius, TSF_Any(Obj_Puppet))`. That helper surfaces entities **only through their `TargetingComponent`** — `gameObject.swift:699-709` iterates `TS_TargetPartInfo.GetComponent(...).GetEntity()`. Loot classes carry **no** `TargetingComponent` (grep: `inventoryComponent.swift`, `lootContainers.swift`, `item.swift`, `shardCaseContainer.swift` request none — only `Collider`, `inventoryComponent.swift:152-155`). So radius returns puppets/devices only → corpses, never loot. This is documented and intended (`ScannerSuite.reds:652-668`).

### Net: why corpses work and the other two don't [V]
- **Corpse** (`ScriptedPuppet`): covered by **radius** (a puppet — primary) **and** cursor (has a valid scanner description → published to `ScannedObject`). Its inventory is already populated, so `GetItemList` returns items. ✔ loots.
- **Container / floor item / shard**: **radius** can't see them (no `TargetingComponent`); **cursor** never fires for them (no valid scanner description → never published to `ScannedObject`). Covered by **neither channel** → the reported bug.

### C — Latent pickup gap: a bare `ItemObject` has no inventory [V/S, secondary]
`IsItem()` is true **only** for `ItemObject` (`gameObject.swift:1395-1397` = `(this as ItemObject) != null`; `ItemObject extends TimeDilatable extends GameObject`, `item.swift:2` / `orphans.swift:11867`). A floor weapon's `ItemObject` reports `IsContainer()==true` when connected to a drop (`item.swift:81-86` = `IsConnectedWithDrop()`), so it passes the worker's type gate — **but its loot lives on the connected `gameItemDropObject`, not on the `ItemObject`**, so `TransactionSystem.GetItemList(itemObject, …)` is empty → worker returns transient-false forever (`ScannerSuite.reds:790-794`) → never loots. Fix = redirect `ItemObject` → `GetConnectedItemDrop()` (`item.swift:20-22`). **[S]** which entity `GetLookAtObject` returns for a floor weapon (the drop carries the `Collider` so it is usually the raycast hit → often no redirect needed); the redirect is cheap insurance for the `ItemObject` case.

### What is already correct on the pickup side (no change needed) [V]
- **Container** `gameLootContainerBase.IsContainer()` = `!IsEmpty() && !IsDisabled()` (`lootContainers.swift:507-509`); loot is filled at stream-in (`ContainerFilledEvent` → `wasLootInitalized`, `lootContainers.swift:411,557-560`), so `GetItemList` is populated by the time you can hover it. Shard cases (`ShardCaseContainer extends ContainerObjectSingleItem extends gameContainerObjectBase extends gameLootContainerBase`, `shardCaseContainer.swift:2`) go through the same container path; `IsShardContainer()==true`.
- **Drop** `gameItemDropObject.IsContainer()` = `!IsEmpty()` (`inventoryComponent.swift:283-285`) and holds a real transaction inventory (`ResolveInvotoryContent` reads `GetTotalItemQuantity`, `:202-204`; `EvaluateLootQuality` reads `GetItemList`, `:225`). So `GetItemList` + `TransferItem` is the correct call — identical to the corpse path.

**Therefore the worker's pickup recipe (`GetItemList` → per-item filters → `TransferItem` + loot sound + open animation, `ScannerSuite.reds:756-840`) is right for containers, drops, shards and corpses.** This is exactly CNML's (Nexus 16040) loot recipe, re-verified — the suite already adapted it. What CNML does differently is **detection**: CNML enumerates every loot entity through a global `OnGameAttached` registry — which is the multithreaded heap-corruption crash we removed (`scanner-suite-crash-analysis.md`). We must fix detection **without** that registry.

---

## Fix design

Two changes, both on the **game thread**, reusing the existing worker + ledger + filters + toggles.

### 1. Cursor channel — add a game-thread `GetLookAtObject` poll on the existing sweep tick [primary fix]

The suite already runs a safe, self-re-arming DelaySystem loop while the scanner is up (`ST_SweepTick`, `ScannerSuite.reds:466-497`) on the game thread. Add a **cursor-pickup pass** to it that resolves the crosshair loot target via `TargetingSystem.GetLookAtObject` — vanilla's own tier-2/3 resolution (`focusModeTagging.swift:205-208`) — and feeds it to the unchanged worker. This catches containers/floor items/shards the scanner never focuses, on steady hover (not just on focus-change events).

The existing `OnScannedObjectChanged` wrap **stays** (immediate response for scanner-focusable loot: corpses, scannable devices). Both channels share the `m_apsAttempted` ledger, so nothing double-hammers.

**Lifecycle:** the loop currently arms only for tag/radius. Arm it for cursor pickup too.

```reds
// --- OnScannerUIVisibleChanged arm condition (ScannerSuite.reds:251) ---
if visible && (ScannerSuiteConfig.EnableAutoTagOnScan()
            || ScannerSuiteConfig.EnableAutoPickupRadius()
            || ScannerSuiteConfig.EnableAutoPickupOnScan()) {   // <-- added
  this.ST_ArmSweep();
};

// --- ST_SweepTick stop condition (ScannerSuite.reds:469-477) ---
let tagOn: Bool    = ScannerSuiteConfig.EnableAutoTagOnScan();
let radiusOn: Bool = ScannerSuiteConfig.EnableAutoPickupRadius();
let cursorOn: Bool = ScannerSuiteConfig.EnableAutoPickupOnScan();   // <-- added
if (!tagOn && !radiusOn && !cursorOn) || !this.m_uiScannerVisible {  // <-- + !cursorOn
  this.m_stSweepArmed = false;
  return;
};

// --- ST_SweepTick FOCUS block (ScannerSuite.reds:481-492): add cursor pass ---
if Equals(HUDManager.GetActiveMode(game), ActiveMode.FOCUS) {
  if tagOn { this.ST_RunSweepOnce(game); this.ST_RunEnemySweepOnce(game); };
  let player: ref<PlayerPuppet> = this.GetPlayer() as PlayerPuppet;
  if IsDefined(player) {
    if radiusOn { player.APS_RunRadiusPickup(game); };
    if cursorOn { player.APS_RunCursorPickup(game); };   // <-- added, game-thread crosshair loot
  };
};
```

New pass on `PlayerPuppet` (mirrors `APS_RunRadiusPickup` guards + shared ledger):

```reds
// ---------- cursor-pickup channel: game-thread crosshair loot resolution ------
// Detection via TargetingSystem.GetLookAtObject — vanilla's own crosshair path
// (focusModeTagging.swift:205-208). Unlike UI_Scanner.ScannedObject (scanner-
// focusable objects only), a look-at raycast returns whatever collider the
// crosshair hits: loot crates, dropped weapons, shard cases, corpses. Runs on
// the game thread from the existing sweep tick — no streaming/worker-thread code.
@addMethod(PlayerPuppet)
public final func APS_RunCursorPickup(game: GameInstance) -> Void {
  if this.IsReplacer() || this.GetHudManager().IsBraindanceActive() {
    return; // hover-path parity: never auto-loot in Johnny/braindance
  };
  // No-LOS look-at (withLOS=false): matches the channel's through-wall policy as
  // far as the physics raycast allows (it still stops at the first collider, so
  // this is naturally "point at the visible loot"). Flip to (this, true, true)
  // for a strict LOS variant.
  let raw: ref<GameObject> =
    GameInstance.GetTargetingSystem(game).GetLookAtObject(this, false);
  if !IsDefined(raw) { return; };
  let target: ref<GameObject> = raw.APS_ResolveLootTarget(); // ItemObject -> its drop
  let id: EntityID = target.GetEntityID();
  let probe: Bool = ScannerSuiteConfig.DebugProbeAutoPickup();
  if probe {
    GameInstance.GetActivityLogSystem(game)
      .AddLog("APS cursor: lookAt -> " + NameToString(target.GetClassName()));
  };
  // Shared ledger with radius + the OnScannedObjectChanged hook.
  if !this.APS_AlreadyAttempted(id) && target.APS_TryAutoPickup(this) {
    this.APS_MarkAttempted(id);
  };
}
```

### 2. Worker/target redirect — resolve a bare `ItemObject` to its drop [secondary fix]

```reds
// A floor weapon can resolve to its visual ItemObject, whose inventory lives on
// the connected gameItemDropObject (item.swift:20-22, 81-86). Redirect so the
// worker reads the drop's real item list. No-op for every other class.
@addMethod(GameObject)
public final func APS_ResolveLootTarget() -> ref<GameObject> {
  let item: ref<ItemObject> = this as ItemObject;
  if IsDefined(item) && item.IsConnectedWithDrop() {
    let drop: ref<gameItemDropObject> = item.GetConnectedItemDrop();
    if IsDefined(drop) { return drop; };
  };
  return this;
}
```

Also apply the redirect in the existing `OnScannedObjectChanged` cursor path (`ScannerSuite.reds:864` after `FindEntityByID`): `target = target.APS_ResolveLootTarget();` — cheap, covers the rare case a bare `ItemObject` is ever published.

### 3. (Recommended robustness) worker type gate — treat an empty-*now* loot object as transient, not final

Current gate (`ScannerSuite.reds:768`): `if !IsContainer() && !IsShardContainer() && !IsItem() { return true; }` returns **final** for a container that is momentarily empty (`IsContainer()==!IsEmpty()`), spending its one attempt before loot may have streamed in. Gate on **class** instead so emptiness routes to the existing `GetItemList()==0 → transient` branch (`:792-794`):

```reds
// class-based lootable test (survives a transient IsEmpty window):
let isLootClass: Bool = IsDefined(this as gameLootContainerBase)   // crates, shard cases, single-item
                     || IsDefined(this as gameItemDropObject)      // dropped loot/weapons
                     || this.IsItem();                             // bare ItemObject (redirected upstream)
if !isLootClass { return true; };   // truly not loot — final, never retry
if this.IsPlayerStash() { return true; };   // stash — final (unchanged, :771-773)
// ... locked-container transient + range + GetItemList unchanged ...
```

`gameLootContainerBase` covers crates, `gameContainerObjectBase`, `ContainerObjectSingleItem` and `ShardCaseContainer` (all subclasses). This is optional — the dominant fix is #1 — but it closes the "hovered a crate one frame before its loot table resolved" hole cleanly.

### Radius channel — stays corpses-only (deliberately) [V rationale]
There is **no** game-thread-safe enumeration that returns loot classes:
- `GetEntitiesAroundObject` / any `TargetingSystem` query surfaces only `TargetingComponent`-bearing entities (`gameObject.swift:699-709`) — loot carries none.
- The interactions blackboard cannot help: `InteractionChoiceHubData` (`orphans.swift:42008-42021`) and `VisualizersInfo` (`orphans.swift:54559-54564`) expose only opaque `Int32` ids — **no EntityID/activator** — so the "hovered/nearby loot entity from the interaction hub" idea is not resolvable in script. **[V]**
- A global loot **registry** is the removed crash (see next section). Marshalling attach-discovery to the game thread via a 0-delay `DelayCallback` is **rejected [S]**: calling `DelaySystem.DelayCallback` *from* the streaming worker still touches a shared native queue unsynchronized (same race class), and it allocates one callback per entity stream-in (thousands on load — the exact amplifier the crash analysis flagged). Not worth it.

Consequence: the **cursor** `GetLookAtObject` poll is the loot fix. Because it re-runs every `AutoTagSweepInterval` (0.35 s) following the crosshair, sweeping your view across a room vacuums loot piece-by-piece — the natural scanner interaction, and exactly what the user needs (containers/floor items get collected). A future 360° loot vacuum would need a Codeware/RED4ext spatial query we don't have on this macOS pure-REDscript toolchain. One unexplored **[S]** game-thread option noted for later: the loot proximity interaction layer (`gameLootObject.OnInteractionActivated`, `inventoryComponent.swift:92-96`) fires on the game thread when the player enters a loot object's range — a self-register there would be game-thread-safe, but it re-introduces an always-on per-entity hook and only the `'auto'` ammo layer is confirmed to fire; not recommended for this fix.

---

## Crash-safety argument

The 2026-07-06 crash (`scanner-suite-crash-analysis.md`) was `@wrapMethod(GameObject) OnGameAttached` doing an unsynchronized `ArrayPush` into a shared player field, running on RED `redDispatcher` entity-**streaming worker threads** → heap free-list corruption (identical wild fault address across two runs). The rule adopted: **never mutate shared REDscript state off the game thread; add no always-on per-entity streaming hook.**

Every element of this fix obeys that:
- **`APS_RunCursorPickup`** is invoked only from `ST_SweepTick`, a `DelaySystem.DelayCallback` (`ScannerSuite.reds:459-462,493-496`). DelaySystem callbacks run on the **game thread** (game tick) — same execution context as the already-shipped radius pass. Not a streaming/worker path.
- **`GetLookAtObject`** is a native crosshair raycast that **reads** engine state and returns a ref; it mutates no shared script state. Vanilla calls it from ordinary game-thread contexts — the input-listener tag handler (`focusModeTagging.swift:205-208`), device operations, player scripts.
- The only mutation is `APS_MarkAttempted` → `ArrayPush(this.m_apsAttempted, …)` on the single `PlayerPuppet`, on the game thread — **identical** to the existing cursor/radius channels. Single-threaded, so no race.
- **No new `OnGameAttached` / entity-lifecycle / streaming hook is added.** The only new wrap-surface is *inside* the existing game-thread sweep; `APS_ResolveLootTarget` and the worker are `@addMethod` helpers called synchronously from game-thread callers. The removed registry stays removed.
- Toggles unchanged: `EnableAutoPickupOnScan()=false` ⇒ the cursor pass never arms/runs (100% vanilla cursor channel); all three toggles false ⇒ the sweep loop never arms.

Net: the fix is strictly additive to an already-game-thread-safe loop. It cannot reach the `redDispatcher` worker pool, so the entire heap-corruption class is ruled out.

---

## Edge cases + interactions

- **Locked container** — worker casts `this as gameLootContainerBase` and returns **transient** on `APS_IsLootLocked()` (`ScannerSuite.reds:774-777`); re-tried when unlocked. `GetLookAtObject` returns the container (it has the collider), so the cast succeeds. ✔
- **Quest / iconic / HMG / nameless items** — per-item filters in the worker (`:806-822`) already skip them; unchanged. Quest *object* skip via `IsQuest()` (`:811`) unchanged.
- **Already-looted / empty container** — `IsEmpty()` true ⇒ with fix #3 the class-cast still matches but `GetItemList()==0` returns transient (cheap re-check, spends nothing); without #3 it returns final (harmless — nothing to loot). Either is acceptable; #3 is the clean choice.
- **Loot-gen timing** — containers fill at stream-in (`ContainerFilledEvent`/`wasLootInitalized`, `lootContainers.swift:557-560`), so hovering an in-range crate sees populated loot; the transient path covers the rare not-yet-generated frame. **[S]** no lazy-on-open generation seen in the decompile.
- **Shards** — `ShardCaseContainer` loots via the container path; `Gen_Readable` items survive the nameless filter (`:807`) and auto-journal on transfer (verified in `scan-mode-auto-pickup.md`). ✔
- **Animated crates** (lockers/fridges/trunks) — `LootContainerObjectAnimatedByTransform.APS_EnsureOpened()` plays the open animation after a remote transfer (`:734-739,832-837`); unchanged, now actually reached for hovered crates. ✔
- **Stash** — `IsPlayerStash()` final-skip (`:771-773`) unchanged; `GetLookAtObject` on a stash → marked attempted, never looted. ✔
- **Live NPC / vendor / quest-giver under crosshair** — worker puppet branch returns transient for a living puppet (`:764-766`); no spend, no theft; loots once dead (parity with radius). ✔
- **Range/LOS gates** — cursor keeps the worker's 40 m `AutoPickupMaxDistance` cap (`:784-787`); `GetLookAtObject(this, false)` is naturally first-collider so it does not grab crates through walls (a mild behavior tightening vs the theoretical through-wall cursor — call `GetLookAtObject(this, true, true)` if strict LOS is wanted). Radius keeps its 20 m pre-gate. No change to gate constants.
- **Cross-mod collisions** (grep of deployed `r6/scripts`):
  - `OnScannedObjectChanged` — **only** custom-scanner-suite wraps it. ✔
  - `GetLookAtObject` — only `street-vendors` *calls* it (its own module-static wrapper, `street_vendors.reds:164-167`); we call the native directly. No override collision. ✔
  - `PlayerPuppet.OnGameAttached` — wrapped by custom-switch-speed + street-vendors; **this fix adds no `OnGameAttached` wrap**, so it does not join that chain. ✔
  - `TransferItem` — only rich-vendors uses it elsewhere; no shared method. ✔
  - New `@addField`/`@addMethod` names (`APS_RunCursorPickup`, `APS_ResolveLootTarget`) are suite-prefixed and unique across deployed mods. ✔

---

## Verification plan

**Compile:** deploy edits → `script/launch_modded.sh` (Steam running) → scc recompiles all `r6/scripts`; a compile error shows the launch dialog. If "backup corrupted" appears, it is transient — clean serial `scc -compile`, do **not** clear `r6/cache` or verify files (per MEMORY note).

**Probe first (decisive):** set `DebugProbeAutoPickup()` → `true`. In scan mode, crosshair a loot crate, a dropped weapon, a shard case, a corpse. Expect HUD activity-log `APS cursor: lookAt -> <ClassName>` lines showing `gameLootContainerBase`/`gameContainerObjectBase…`, `gameItemDropObject` (or `ItemObject`), `ShardCaseContainer`, `NPCPuppet`. This confirms `GetLookAtObject` returns the loot classes (root cause A) and shows whether floor weapons resolve to the drop or the `ItemObject` (validates the redirect). Set back to `false` after.

**In-game checklist:**
- T1 (bug): scan mode, hover a **loot crate** within 40 m → its items land in inventory; the crate empties/plays open animation. Repeat for a **locker/fridge** (animated).
- T2: hover a **weapon/loot bag on the floor** → collected (this is the previously-broken case). Confirm both a *dropped* weapon (NPC death drop = `gameItemDropObject`) and a *placed* world weapon.
- T3: hover a **shard case** → shard auto-journals (Journal > Shards notification).
- T4 (regression): **corpse** still auto-loots — via radius (walk within 20 m, no hover) **and** via cursor (hover at range).
- T5 (filters): a crate with a **quest/iconic** item → those stay; the rest transfer. A **locked** crate → nothing taken; unlock (hack/key) → next hover loots (transient not spent).
- T6 (once-per-entity): hover a looted crate again → no repeat, no error; hovering a still-alive NPC repeatedly → no spend, loots once it dies.
- T7 (kill-switch): `EnableAutoPickupOnScan()=false` → hover loots nothing (radius corpses still work); all three pickup/tag toggles false → sweep loop never arms, 100% vanilla.
- T8 (crash regression — the important one): with `EnableAutoPickupOnScan()=true` **and** `EnableAutoPickupRadius()=true`, play a streaming-heavy stretch (drive, fast-travel, district transitions) → **no** `redDispatcher` crash (this fix adds only game-thread work).

**Registry:** on ship, update the Scanner Suite entry / header comment to note the cursor channel now detects via `GetLookAtObject` (not just `OnScannedObjectChanged`) and the `ItemObject`→drop redirect.

---

## Summary

- **Root cause (detection, primary) [V]:** cursor channel only listens to `UI_Scanner.ScannedObject`, which the native scanner sets only for objects with a valid scanner description (NPCs/devices) — never plain loot crates/drops/shards (`gameObject.swift:2224-2237`, `scanningComponent.swift:583-586`); proven by vanilla's own `GetLookAtObject` fallback in `focusModeTagging.swift:203-209`. Radius is puppets-only (`gameObject.swift:699-709`, loot carries no `TargetingComponent`). Corpses work because they satisfy both; containers/floor items satisfy neither.
- **Root cause (pickup, secondary) [V/S]:** a bare `ItemObject` has no inventory (it lives on the connected `gameItemDropObject`) → `GetItemList` empty → never loots without a `GetConnectedItemDrop()` redirect. Containers/drops/shards/corpses already loot correctly via `GetItemList`+`TransferItem`.
- **Crash-safe mechanism:** add a game-thread `TargetingSystem.GetLookAtObject` poll to the existing DelaySystem sweep tick (cursor channel), reusing the worker + `m_apsAttempted` ledger + filters; add an `ItemObject`→drop redirect; no `OnGameAttached`/streaming hook, so the removed heap-corruption class stays removed.
- **Correct pickup call per type:** container/shard case/animated crate → `GetItemList` + `TransferItem` (+ `APS_EnsureOpened`); floor drop (`gameItemDropObject`) → same; bare `ItemObject` → redirect to `GetConnectedItemDrop()` then same; corpse → unchanged puppet path.
- **Plan file:** `/Users/teazyou/dev/tmp-claude/cyberpunk/wikis/modding/plan-fix-loot-pickup-containers-items.md`

---

## 2026-07-06 — loot-pickup fix IMPLEMENTED (containers + floor items)

Applied to `mods/enabled/r6-scripts/custom-scanner-suite/ScannerSuite.reds` exactly per §Fix design #1 + #2. **§3 (class-based worker type gate) was deliberately NOT applied** — it is optional/robustness only and the task scope was "keep the existing container/shard/animated-crate/corpse worker paths unchanged"; the redirect happens upstream so the worker's existing `IsContainer()` gate already passes for the redirected `gameItemDropObject`. Compiles clean; game not launched; `r6/cache` untouched.

**What changed (code):**
1. **New `@addMethod(PlayerPuppet) APS_RunCursorPickup(game)`** — the game-thread cursor poll. Guards replacer/braindance (hover-path parity), resolves the crosshair loot via `GameInstance.GetTargetingSystem(game).GetLookAtObject(this, false)`, runs it through `APS_ResolveLootTarget()` (ItemObject→drop), then the SHARED `m_apsAttempted` ledger + SHARED worker `APS_TryAutoPickup`. Debug line gated on `DebugProbeAutoPickup()` prints `APS cursor: lookAt -> <ClassName>`.
2. **New `@addMethod(GameObject) APS_ResolveLootTarget() -> ref<GameObject>`** — redirects a bare `ItemObject` that `IsConnectedWithDrop()` to its `GetConnectedItemDrop()` (`gameItemDropObject`); returns `this` for every other class. Placed just before the worker.
3. **`ST_SweepTick` FOCUS block** — added `let cursorOn = EnableAutoPickupOnScan();`; the pickup branch is now `if radiusOn || cursorOn { … if radiusOn { APS_RunRadiusPickup } if cursorOn { APS_RunCursorPickup } }` (single `GetPlayer()` cast shared).
4. **Lifecycle (both paths):** `OnScannerUIVisibleChanged` arm condition and `ST_SweepTick` stop condition each extended with `|| EnableAutoPickupOnScan()` / `&& !cursorOn` so the loop arms/persists for the cursor channel even when tag+radius are off. `wrappedMethod` still called exactly once on every path.
5. **`OnScannedObjectChanged`** — added `target = target.APS_ResolveLootTarget();` as the first statement inside the `if IsDefined(target)` guard (covers the rare bare-ItemObject publish; benefits both the auto-tag and auto-pickup sub-branches). The hover hook otherwise unchanged and still kept.
6. **Header comment** (Feature 3 CURSOR bullet + Wraps note) rewritten to describe the GetLookAtObject tick-poll (containers/floor items/shards/corpses within 40 m, no LOS), the ItemObject→drop redirect, and radius staying corpses-only.

**Toggles / crash-safety:** gated on the existing `EnableAutoPickupOnScan`; `false` ⇒ the cursor poll never runs (100% vanilla cursor channel); all three pickup/tag toggles `false` ⇒ the sweep loop never arms. `APS_RunCursorPickup` runs ONLY from `ST_SweepTick` (a `DelaySystem.DelayCallback` = game thread, same context as the shipped radius pass); `GetLookAtObject` only reads engine state; the sole mutation is `APS_MarkAttempted`→`ArrayPush` on the single `PlayerPuppet` on the game thread. No `OnGameAttached`/streaming/worker hook added — the removed `redDispatcher` heap-corruption class stays removed. No double-loot (shared `m_apsAttempted`).

**Decompile-verified signatures used** (adamsmasher 2.x dump at `…/scratchpad/vanilla-scripts/`):
- `TargetingSystem.GetLookAtObject(instigator: wref<GameObject>, opt withLOS: Bool, opt ignoreTranparent: Bool) -> ref<GameObject>` (`orphans.swift:22401`; `TargetingSystem extends ITargetingSystem`) → the 2-arg `GetLookAtObject(this, false)` form is valid (withLOS=false, ignoreTranparent default).
- `ItemObject.IsConnectedWithDrop() -> Bool` and `ItemObject.GetConnectedItemDrop() -> wref<gameItemDropObject>` (both `public final native const`, `cyberpunk/items/item.swift:20,22`).
- Class chain: `gameItemDropObject extends gameLootObject extends GameObject` (`inventoryComponent.swift:162,83`; `gameObject.swift:87`); `ItemObject extends TimeDilatable extends GameObject` (`item.swift:2`; `orphans.swift:11867`) — both are `GameObject`s, so upcast to `ref<GameObject>` and the `@addMethod(GameObject)` worker call are valid. `wref`→`ref` assignment for the drop compiles (implicit conversion; vanilla precedent `scriptedConditions.swift:286`).

**Compile:** `"$HOME/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077/engine/tools/scc" -compile "$HOME/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077/r6/scripts"` (serial) → *Compilation complete*, exit 0. Zero WARN/ERROR lines mention `custom-scanner-suite` (only the file-list mention). The 5 pre-existing WARNs are other mods (simple-untrack-quest / better-fast-travel `@replaceMethod` collision, disassemble-loot redundant cast, drink-at-the-counter type compare x2).

**In-game test checklist (pending — user only):** set `DebugProbeAutoPickup()`→true first, scan mode, crosshair a crate / dropped weapon / shard case / corpse → expect `APS cursor: lookAt -> gameLootContainerBase|gameItemDropObject|ItemObject|ShardCaseContainer|NPCPuppet` (confirms detection + whether floor weapons resolve to the drop or the ItemObject), then set false. Then: T1 hover a loot crate + locker/fridge (animated) within 40 m → looted, open animation plays; T2 hover a floor/dropped weapon → collected (previously broken); T3 hover a shard case → shard auto-journals; T4 corpse still loots via radius (walk within 20 m) AND cursor (hover); T5 quest/iconic/HMG stay behind, locked crate takes nothing until unlocked (transient not spent); T6 re-hover a looted crate → no repeat/error; T7 `EnableAutoPickupOnScan=false` → cursor loots nothing (radius corpses still work), all three toggles false → sweep never arms (100% vanilla); T8 crash regression — streaming-heavy stretch (drive/fast-travel/district transitions) with cursor+radius ON → no `redDispatcher` crash. Through-wall: `GetLookAtObject(this, false)` stops at the first collider, so it does not grab crates through walls — point at visible loot within 40 m (flip to `GetLookAtObject(this, true, true)` for strict LOS).
