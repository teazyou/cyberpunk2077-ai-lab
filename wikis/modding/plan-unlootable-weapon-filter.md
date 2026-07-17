# Unlootable-Weapon Auto-Pickup Filter — Implementation Plan (2026-07-14)

> ## ⚠ AMENDED BY THE FINAL REVIEW PASS (2026-07-14) — READ THIS FIRST
>
> The plan below was built on the dossier's §2 claim that **no vanilla force-drop branch exists in the
> decompile** ("honest gap", "no reactive hook to catch"). **That claim was false.** The review pass
> found the force-drop verbatim in the player state machine:
>
> ```
> // [V] cyberpunk/player/psm/equipment.script:1362  (weapon-unequip state exit)
> if( ( GetEquipAreaFromItemID( item ) == gamedataEquipmentArea.WeaponHeavy
>       || ((ItemObject)(itemObject)).GetItemData().HasTag( 'DiscardOnEmpty' ) )
>     && ( upperBodyState != gamePSMUpperBodyStates.ForceEmptyHands ) )
>     DropActiveWeapon( ... );   // -> LootManager.SpawnItemDrop at V's feet, equipment.script:363-377
> ```
>
> It was missed because the greps never covered `cyberpunk/player/psm/` and searched for the names
> `ForceDrop`/`DropItem` while vanilla calls it **`DropActiveWeapon`**. Consequences for this plan:
>
> | Plan said | Reality |
> |---|---|
> | Layer 1 = `HasTag('NPCMeleeware')` is the primary predicate | **Wrong target.** Melee-cyberware-scoped; almost certainly not the user's weapon. Kept only as a cheap superset. |
> | Layer 2 (bounce memo) is "judged ESSENTIAL — the only self-healing mechanism" | **Demoted to BACKSTOP.** It is a *bet* that the native `SpawnItemDrop` removal fires the inventory listener — plausible, but not decompile-verified. It cannot be the primary fix. |
> | Option D (`EquipArea()`) = "REJECT — data correlation unverified… speculation" | **This was the answer.** Not a correlation: `EquipArea().Type() == WeaponHeavy` is *literally the `if` that guards the drop*. Now the PRIMARY hard rule. |
> | "the fix has to be prophylactic because no reactive hook exists" | Conclusion right, reasoning wrong — and the prophylactic predicate is **exact**, not inferred. |
>
> **SHIPPED (see `unlootable-weapon-filter-research.md` §2 for the full evidence):**
> 1. **`APS_IsForceDroppedWeapon`** (HARD RULE, primary): `HasTag('DiscardOnEmpty')` ‖
>    `HasTag('NPCMeleeware')` ‖ `EquipmentSystem.GetEquipAreaType(itemID) == gamedataEquipmentArea.WeaponHeavy`
>    ([V] `equipmentSystem.script:5748`, enum [V] `tweakDBEnums.script:3130`).
> 2. **`AutoPickupTakeHeavyWeapons()` flipped `true` -> `false`** — a type-level belt behind the rule.
>    The mod's own comment already predicted this ("if a looted turret/HMG ever misbehaves, THIS is the
>    first flag to flip back to false"); the user's loop *is* the heavy-weapon carry mechanic.
> 3. **`APS_IsRejectedLoot`** (bounce memo) — kept, unchanged, as the self-healing backstop for
>    modded/DLC weapons the rule above cannot name, and to stop the vacuum re-stealing manual drops.
>
> §§3, 5.1 and 9 below are superseded on these points. §§4, 5.2-5.4, 6, 7 remain accurate.

Target file (one file, two paths to the same bytes):
- live: `/Users/teazyou/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077/r6/scripts/custom-scanner-suite/ScannerSuite.reds` (1519 lines at planning time)
- vault portal: `mods/enabled/r6-scripts/custom-scanner-suite/ScannerSuite.reds`

Pure REDscript only, game v2.3 macOS Steam. NO CET / RED4ext / TweakXL. Config = static funcs.
REDscript has NO `continue`/`break` (if-wrappers only); `ArrayPush`/`ArrayErase`/`ArrayContains`/
`ArraySize` are valid. NEVER touch the per-arbitrary-entity `GameObject.OnGameAttached` streaming hook.

Input dossier: `wikis/modding/unlootable-weapon-filter-research.md` (2026-07-14). **Every API in this
plan was re-grepped this pass** against the v2.3 decompile
(`…/8dbf7d7b…/scratchpad/vanilla-scripts/scripts/`, `.script`); §2 records the audit result.

---

## 1. The bug and the fix altitude

With the 360° radius channel on, some enemy-dropped weapons enter the player inventory via
`TransactionSystem.TransferItem` (worker `APS_TryAutoPickup`, ScannerSuite.reds:1437) but cannot live
there: the game force-ejects them back into the world the moment the player re-equips a weapon. The
ejected weapon respawns as a FRESH drop entity (new `EntityID`), so the one-attempt-per-entity ledger
(`m_apsAttempted`, :884-906) never matches, and the 360° pass (`APS_RunSurroundingsPickup`,
:1032-1074) vacuums it again — infinite drop → pickup → drop loop.

**Fix altitude — single chokepoint.** All three pickup channels (360° radius :1061, cursor look-at
:1152, hover hook :1510) funnel into the ONE worker `APS_TryAutoPickup` and its per-item filter chain
(:1393-1418). `TransferItem` occurs nowhere else in the mod. Therefore ALL edits land in/around the
worker's filter loop — no per-channel code. The fix is prophylactic (never transfer the item), because
no reactive "the game just force-dropped X" hook exists in the decompile (dossier §2, honest gap —
confirmed this pass).

## 2. Adversarial audit of the research (all signatures re-grepped)

Verdict: **dossier is sound — zero hallucinated APIs.** Every proposed signature exists verbatim.

| API (verbatim) | Where | Audit |
|---|---|---|
| `public import const function HasTag( tag : CName ) : Bool` | core/data/itemData.script:9 | CONFIRMED |
| `RemoveNPCMeleeware()` body incl. `HasTag( 'NPCMeleeware' )` + `TS.RemoveItemByTDBID( player, ItemID.GetTDBID( itemData ), 1 )` | cyberpunk/systems/equipmentSystem.script:5547-5568 | CONFIRMED verbatim |
| migration gate `GetFact(… 'NPCMeleewareRemoved')`, `gameGameVersion.Current >= 2099`, `saveVersion <= 257` | equipmentSystem.script:5195-5199 | CONFIRMED verbatim |
| `public import function EquipArea() : weak< EquipmentArea_Record >` | core/data/tweakDBRecords.script:5076 (class `Item_Record` :5067) | CONFIRMED |
| `public import function ItemCategory() : weak< ItemCategory_Record >` | tweakDBRecords.script:5094 | CONFIRMED |
| `public import function Type() : gamedataItemCategory` | tweakDBRecords.script:5295 (class `ItemCategory_Record` :5291) | CONFIRMED |
| `public import static function GetItemRecord( path : TweakDBID ) : Item_Record` (on `TweakDBInterface`) | core/data/tweakDB.script:517 | CONFIRMED |
| looting UI null-`EquipArea()` → `gamedataEquipmentArea.Invalid` fallback | cyberpunk/UI/interactions/looting.script:576-584 | CONFIRMED verbatim |
| `IsEquippable( itemData : weak< gameItemData > ) : Bool` (broken/prereq/level checks) | equipmentSystem.script:2019-2035 | CONFIRMED — dossier's REJECTION is correct (refuses broken + above-level loot the vacuum must keep taking) |
| `public static function CanItemBeDropped( puppet : GameObject, itemData : gameItemData ) : Bool` (refuses IconicWeapon/Quest/UnequipBlocked) | cyberpunk/managers/rpgManager.script:2961-2975 | CONFIRMED — REJECTION correct (inverse question; would block iconic pickup) |
| `ItemDropSettings_Record` = `DesiredAngularVelocity()`/`DesiredInitialRotation()` only | tweakDBRecords.script:5308-5312 | CONFIRMED — dead end as claimed |
| `T"Items.NeoFiberLegendary"` hardcoded removal (`RemoveDeprecatedReginaCWReward`) | equipmentSystem.script:5538-5545 | CONFIRMED — CDPR's own per-item-blacklist precedent |
| `IsItemAWeapon` = `record.ItemCategory().Type() == gamedataItemCategory.Weapon` | equipmentSystem.script:1991-1996 (dossier said 1990-1995 — off-by-one, content exact) | CONFIRMED |

Audit nits (conclusions unaffected):
- Appendix A enumerated `HasTag('…')` **literals** only; tags reaching `HasTag` via a *variable* were
  invisible to that method. Found one: `weaponTag = 'Meleeware'`
  (core/systems/workspotSystem.script:280,343) — a workspot **animation-condition** tag for
  melee-cyberware weapons, NOT a lootability signal (would over-block Mantis Blades class items).
  No `NPCRanged*`-style sibling exists; `NPCWeaponDropHelper/NPCWeaponDropRandomizer`
  (tweakDBEnums.script:1401-1402) are `gamedataStatType` entries (drop-chance stats), not item flags.
  The dossier's "no broader tag exists" claim **holds**.
- All ScannerSuite.reds line references in the dossier re-checked against the current file: correct.

New APIs verified for THIS plan (not in the dossier), all `[V]` verbatim:

```
// core/systems/transactionSystem.script:89,91
public import function RegisterInventoryListener( owner : GameObject, callback : InventoryScriptCallback ) : InventoryScriptListener;
public import function UnregisterInventoryListener( owner : GameObject, listener : InventoryScriptListener );

// core/components/inventoryComponent.script:1-12
import class InventoryScriptCallback extends IScriptable { …
  public export virtual function OnItemRemoved( item : ItemID, difference : Int32, currentQuantity : Int32 ); … }
import class InventoryScriptListener extends InventoryListener

// override + register precedent: dropPointSystem.script:19-30 (DropPointCallback overrides
// OnItemRemoved with this exact signature); craftingSystem.script:37-40 (new callback; .player = player;
// RegisterInventoryListener(player, callback)) — fires on the game thread for every inventory removal.

// cyberpunk/managers/rpgManager.script:662-665
public static function IsItemWeapon( itemID : ItemID ) : Bool   // == gamedataItemCategory.Weapon

// core/data/itemID.script:11
public import static function GetTDBID( itemID : ItemID ) : TweakDBID;

// core/systems/gameInstance.script:7            core/data/engineTime.script:5
public import static function GetSimTime( self : GameInstance ) : EngineTime;
public import static function ToFloat( self : EngineTime ) : Float;
// usage precedent: EngineTime.ToFloat( GameInstance.GetSimTime( … ) ) — vehicleComponent.script:4442

// core/data/tweakDBID.script:9
public import static function ToStringDEBUG( tdbID : TweakDBID ) : String;

// core/systems/activityLogSystem.script:7
public import function AddLog( logEntry : String );

// TweakDBID `==` precedent: uiInventoryScriptableSystem.script:155 (tweakDBID == T"Items.…")
```

## 3. Design decision — HYBRID (two hard rules), one option rejected

| Option | Verdict |
|---|---|
| **A. Predicate `itemData.HasTag(n"NPCMeleeware")`** | **ADOPT (Layer 1).** CDPR's own strip-from-player-inventory criterion; zero new API (same `HasTag` the quest rule uses on the same `wref<gameItemData>`); zero false-positive risk. But melee-scoped by design — the user's repro weapon is unconfirmed melee, so it is NOT sufficient alone. |
| **B. Runtime bounce-back rejection memo** | **ADOPT (Layer 2) — judged ESSENTIAL, not optional.** The only self-healing mechanism: catches ANY weapon the game ejects from the player inventory (melee/ranged/DLC/modded, cause unknown) on its FIRST bounce, and session-blacklists its TweakDB record. Without it the fix is a bet that the user's weapon happens to carry `NPCMeleeware`. Bonus: also stops the vacuum from stealing back weapons the player drops on purpose (a real pre-existing flaw of the 360° channel). |
| C. Static hardcoded TDBID blacklist | **DO NOT SHIP (empty).** CDPR precedent proves it is endless reactive whack-a-mole. Layer 2 builds the same list at runtime from evidence and prints the TDBID (log line, §5.4) so a permanent cross-session entry can be added later in one line if a specific record keeps recurring. |
| D. `EquipArea()`-null weapon backstop (dossier candidate #2) | **REJECT.** Data correlation unverified (lives in TweakDB archives, out of REDscript reach); a false positive would permanently refuse a legitimate weapon class. Layer 2 covers its entire intended territory with runtime evidence instead of speculation. |

**Memo mechanics (Layer 2), precision by conjunction.** Record: an inventory listener on the player
notes `(TweakDBID, simTime)` of every **weapon** (`RPGManager.IsItemWeapon`) that LEAVES the inventory
(FIFO, 16 entries). Detect: the worker meets an item whose record was removed within
`AutoPickupRejectWindow` (5 s sim) **AND** whose source entity is a `gameItemDropObject` (ground drop —
force-drops always respawn as drops; corpse/container loot can't match) **AND** which lies within
`AutoPickupRejectRadius` (6 m — force-drops land at V's feet; enemy drops lie where enemies died).
All three true ⇒ promote the record into a session blacklist (`m_apsRejectedTDBIDs`) + one HUD log
line, skip. Enforcement thereafter is a cheap `ArrayContains` first-clause, matching the record even
inside later corpses (another ganger with the same NPC weapon never starts a new loop). Weapons-only
gating keeps ammo/consumable stack-removal noise out of the memo entirely. False-positive envelope:
dismantling/selling weapon X within 5 s (sim) of standing <6 m from a same-record ground drop —
narrow, cost is only "that record needs hand-pickup this session", and the log line makes it visible.

Skip semantics = identical to the existing quest rule: per-item, the object's OTHER items still
vacuum; if nothing passed, the worker returns `false` (TRANSIENT, no ledger spend) — the known cheap
re-check treadmill (:1420-1434) already accepted for quest-only objects. The respawned drop is
re-encountered each pass and re-skipped by the `ArrayContains` clause. (The auto-TAG side may tag each
respawned drop once — cosmetic, harmless, unchanged.)

## 4. Config changes (`ScannerSuiteConfig`)

Insert after `AutoPickupTakeHeavyWeapons()` (:314-316), before the `AutoPickupPlaySound` block (:318):

```reds
  // Bounce-back rejection memo (HARD RULE in the worker; breaks the infinite
  // drop->pickup loop, 2026-07-14): when a WEAPON leaves the player inventory
  // (game force-eject of an NPC-only weapon on re-equip, or a deliberate manual
  // Drop) and the SAME TweakDB record is then met as a GROUND DROP near the
  // player within this many SIM seconds, the record is session-blacklisted from
  // auto-pickup and left on the ground (hand-pickup still works).
  public final static func AutoPickupRejectWindow() -> Float {
    return 5.0;
  }

  // Bounce-back memo: max player->drop distance (m) for a reappearance to count
  // as a bounce. Force-drops/manual drops land at V's feet (< ~3 m even moving
  // between 0.5 s passes); enemy weapon drops lie where enemies died — this keeps
  // far-away same-record drops from false-positive blacklisting.
  public final static func AutoPickupRejectRadius() -> Float {
    return 6.0;
  }
```

## 5. Exact code changes

### 5.1 Layer-1 predicate — after `APS_IsQuestItem` (:1277-1280), before the worker banner (:1282)

```reds
// ---------- HARD NPC-ONLY-WEAPON RULE (2026-07-14) -----------------------------
// 'NPCMeleeware' is the tag CDPR's own save-migration retrofix
// EquipmentSystem.RemoveNPCMeleeware (equipmentSystem.script:5547-5568, gated on
// fact 'NPCMeleewareRemoved' :5195-5199) forcibly strips out of the PLAYER
// inventory — vanilla's own definition of "must never be held by V". Such a
// weapon transferred anyway gets force-ejected on the next re-equip, respawns as
// a fresh drop entity (new EntityID, ledger blind) and the 360 pass re-vacuums
// it forever. Skipping it pre-transfer is the prophylactic mirror of the vanilla
// retrofix. Same HasTag API/type as APS_IsQuestItem above (itemData.script:9).
// HARD RULE, not a knob; the weapon stays hand-lootable via the Take prompt.
@addMethod(GameObject)
public final func APS_IsNPCOnlyWeapon(itemData: wref<gameItemData>) -> Bool {
  return itemData.HasTag(n"NPCMeleeware");
}
```

### 5.2 Layer-2 memo state + listener — after `APS_MarkAttempted` (:906), before the removed-radius-channel comment (:908)

```reds
// ---------- bounce-back rejection memo (2026-07-14) ----------------------------
// Layer 2 of the unlootable-weapon fix (Layer 1 = APS_IsNPCOnlyWeapon): a vanilla
// inventory listener records the TweakDBID of every WEAPON that LEAVES the player
// inventory; if the worker then meets a ground drop carrying a recently-removed
// record close to the player, that is a bounce (the game ejected it, or the
// player deliberately dropped it — either way it must stay out) -> the record is
// session-blacklisted and never auto-collected again. Self-healing: catches
// ranged/DLC/modded offenders no tag can name, on their first bounce. Weapons
// only (RPGManager.IsItemWeapon), so ammo/consumable stack noise never enters.
// All state session-transient (never saved). Listener API + register/override
// precedent: transactionSystem.script:89, inventoryComponent.script:1-12,
// craftingSystem.script:37-40, dropPointSystem.script:19-30. OnItemRemoved fires
// on the GAME THREAD (same context every vanilla UI/crafting listener runs in).

@addField(PlayerPuppet)
let m_apsRemovedWeaponTDBIDs: array<TweakDBID>;

@addField(PlayerPuppet)
let m_apsRemovedWeaponTimes: array<Float>;

@addField(PlayerPuppet)
let m_apsRejectedTDBIDs: array<TweakDBID>;

@addField(PlayerPuppet)
let m_apsInvCallback: ref<APSInventoryCallback>;

@addField(PlayerPuppet)
let m_apsInvListener: ref<InventoryScriptListener>;

public class APSInventoryCallback extends InventoryScriptCallback {
  public let player: wref<PlayerPuppet>;

  // Exact vanilla virtual signature (inventoryComponent.script:7); override
  // precedent DropPointCallback.OnItemRemoved (dropPointSystem.script:23).
  public func OnItemRemoved(item: ItemID, difference: Int32, currentQuantity: Int32) -> Void {
    if IsDefined(this.player) {
      this.player.APS_NoteItemRemoved(item);
    };
  }
}

// Record a weapon leaving the inventory (record + sim timestamp), FIFO-capped.
// Sim time (pauses in menus) so a menu dwell never eats the reject window.
@addMethod(PlayerPuppet)
public final func APS_NoteItemRemoved(item: ItemID) -> Void {
  if RPGManager.IsItemWeapon(item) {
    ArrayPush(this.m_apsRemovedWeaponTDBIDs, ItemID.GetTDBID(item));
    ArrayPush(this.m_apsRemovedWeaponTimes,
      EngineTime.ToFloat(GameInstance.GetSimTime(this.GetGame())));
    if ArraySize(this.m_apsRemovedWeaponTDBIDs) > 16 {
      ArrayErase(this.m_apsRemovedWeaponTDBIDs, 0);
      ArrayErase(this.m_apsRemovedWeaponTimes, 0);
    };
  };
}

// Register the listener once per player attach (game thread). No unregister on
// purpose: the listener handle lives ON this puppet and targets this puppet's
// own inventory — both die together at session end. (Vanilla systems that
// unregister on PlayerDetach are ScriptableSystems that OUTLIVE the puppet;
// nothing here does.) A replacer (Johnny) puppet gets its own fields/listener —
// harmless and symmetric.
@addMethod(PlayerPuppet)
public final func APS_StartRejectMemo() -> Void {
  if IsDefined(this.m_apsInvListener) {
    return; // already listening — never double-register
  };
  this.m_apsInvCallback = new APSInventoryCallback();
  this.m_apsInvCallback.player = this;
  this.m_apsInvListener = GameInstance.GetTransactionSystem(this.GetGame())
    .RegisterInventoryListener(this, this.m_apsInvCallback);
}

// True = this item must NOT be auto-collected. First clause: session blacklist.
// Then bounce PROMOTION — all three must hold: source is a GROUND DROP
// (gameItemDropObject; force-drops always respawn as drops, corpse/container
// loot can never match), drop is near the player (force-drops land at V's
// feet), record was removed from the inventory within the reject window.
// source = the loot entity the worker is reading (post-APS_ResolveLootTarget).
@addMethod(PlayerPuppet)
public final func APS_IsRejectedLoot(source: ref<GameObject>, itemData: wref<gameItemData>) -> Bool {
  let tdbid: TweakDBID = ItemID.GetTDBID(itemData.GetID());
  if ArrayContains(this.m_apsRejectedTDBIDs, tdbid) {
    return true; // blacklisted earlier this session
  };
  if !IsDefined(source as gameItemDropObject) {
    return false;
  };
  if Vector4.Distance(this.GetWorldPosition(), source.GetWorldPosition())
      > ScannerSuiteConfig.AutoPickupRejectRadius() {
    return false;
  };
  let now: Float = EngineTime.ToFloat(GameInstance.GetSimTime(this.GetGame()));
  let i: Int32 = 0;
  while i < ArraySize(this.m_apsRemovedWeaponTDBIDs) {
    if this.m_apsRemovedWeaponTDBIDs[i] == tdbid
        && (now - this.m_apsRemovedWeaponTimes[i]) <= ScannerSuiteConfig.AutoPickupRejectWindow() {
      ArrayPush(this.m_apsRejectedTDBIDs, tdbid);
      if ArraySize(this.m_apsRejectedTDBIDs) > 64 {
        ArrayErase(this.m_apsRejectedTDBIDs, 0); // FIFO bound, mirrors the attempt ledger
      };
      GameInstance.GetActivityLogSystem(this.GetGame()).AddLog(
        "Scanner Suite: auto-loot now ignores " + TDBID.ToStringDEBUG(tdbid)
        + " (bounced out of inventory) - pick it up by hand if you want it");
      return true;
    };
    i += 1;
  };
  return false;
}
```

Compile contingency: if `scc` rejects `ArrayContains` on `array<TweakDBID>` (untested generic
instantiation), replace that one clause with a manual `while` + `==` compare — TweakDBID `==` has
direct vanilla precedent (uiInventoryScriptableSystem.script:155). Everything else is unaffected.

### 5.3 Arm the listener — inside the EXISTING `@wrapMethod(PlayerPuppet) OnGameAttached` (:1085-1105)

Add ONE line inside the existing pickup-enabled branch (after `this.APS_StartLootLoop();` :1090).
Do NOT add a new wrap; `wrappedMethod()` still runs exactly once:

```reds
  if ScannerSuiteConfig.EnableAutoPickupCursor()
      || ScannerSuiteConfig.EnableConstantAutoLoot() {
    this.APS_StartLootLoop(); // idempotent (double-arm guard); OFF/OFF = pure passthrough
    this.APS_StartRejectMemo(); // idempotent (listener-defined guard); memo only needed while a pickup channel is live
  };
```

### 5.4 Worker filter arms — in `APS_TryAutoPickup`'s per-item chain (:1393-1418)

Insert TWO `else if` arms between the quest arm (:1401-1405) and the HMG arm (:1406) — hard rules
before policy knobs, mirroring the quest rule. `player` (`ref<PlayerPuppet>`, worker param :1292) and
`this` (source object) are both in scope:

```reds
      } else if this.APS_IsQuestItem(itemData) {
        // (existing quest arm — unchanged)
      } else if this.APS_IsNPCOnlyWeapon(itemData) {
        // HARD RULE (2026-07-14): NPC-only melee prop — vanilla's own
        // RemoveNPCMeleeware strips these from player inventory; never transfer,
        // so the force-drop/re-vacuum infinite loop never starts. Stays on the
        // ground/corpse, hand-lootable.
      } else if player.APS_IsRejectedLoot(this, itemData) {
        // HARD RULE (2026-07-14): bounce-back memo — this weapon record left the
        // inventory moments ago and is back as a ground drop at our feet (game
        // force-eject or deliberate player drop). Session-blacklisted; skipped
        // here AND in every later corpse/container carrying the same record.
      } else if !takeHeavy && Equals(itemType, gamedataItemType.Wea_HeavyMachineGun) {
```

No other worker change: range/LOS gates, transient-vs-final semantics, snapshot-then-transfer
two-pass shape all untouched. An object whose ONLY item is skipped falls into the existing
`!lootedAny -> return false` transient branch (:1419-1434) exactly like quest-only loot.

### 5.5 Header documentation (comments only)

- FEATURE 3 header block, after the QUEST EXCLUSION paragraph (:92-97): add two lines — "NPC-ONLY
  WEAPON EXCLUSION + BOUNCE-BACK MEMO (2026-07-14): hard rules; NPCMeleeware-tagged props are never
  transferred (vanilla RemoveNPCMeleeware precedent), and any weapon record that leaves the inventory
  and reappears as a nearby ground drop within seconds is session-blacklisted (breaks the
  force-drop/re-vacuum infinite loop; also stops the vacuum stealing back deliberate manual drops)."
- Wraps block (:115-137): no new wraps added; optionally note the inventory LISTENER (not a wrap)
  registered from the existing PlayerPuppet.OnGameAttached wrap.

## 6. Crash-safety statement

- No new wraps; no `GameObject.OnGameAttached`/per-entity streaming hook — the removed
  heap-corruption class stays structurally unreachable.
- Listener registration: inside the existing `PlayerPuppet.OnGameAttached` wrap = PLAYER object,
  game thread, once per load (the mod's established safe driver).
- `InventoryScriptCallback.OnItemRemoved` fires on the game thread (inventory transactions are
  game-thread; every vanilla listener — crafting, drop-points, UI notification queues — mutates its
  own script state there unsynchronized, e.g. dropPointSystem.script:23-29). Our callback mutates only
  the single PlayerPuppet's own arrays — same thread, same pattern as the existing `m_apsAttempted`
  ledger.
- Worker-side promotion (`ArrayPush` into `m_apsRejectedTDBIDs`) runs inside the DelayCallback loop
  tick = game thread. All new state is session-transient, never saved. Memory: two arrays FIFO-capped
  at 16 + one at 64 — bounded.

## 7. Getting rid of the item already stuck in the user's save

After installing the fix, no code change is needed on the save:

1. Player equips/cycles their normal weapon → the game force-ejects the stuck weapon (the exact
   behavior the user reported) → it lands as a ground drop at V's feet.
2. Within ≤0.5 s the 360° pass reads it: Layer 1 skips it silently if `NPCMeleeware`-tagged; else
   Layer 2 sees "weapon record removed <5 s ago + ground drop <6 m" → blacklists + logs ONE HUD line.
3. The drop stays on the ground forever (every later pass hits the `ArrayContains` clause; the
   nothing-passed path is transient, so no ledger churn matters). Player walks away — done.

No-re-grab audit (verified against the full current file): the ONLY `TransferItem` call site is the
worker (:1437); radius (:1061), cursor (:1152), hover (:1510) all route through the worker, so the new
arms govern every channel — including cursor/hover if the user re-enables them later. The auto-TAG
feature only calls `TagObject` (never transfers). Vanilla Take prompt remains available = deliberate
manual pickup still possible (and if taken by hand, the next force-drop re-blacklists it again —
self-healing). If the user prefers not to wait for a force-drop, a manual inventory Drop of the item
triggers the identical Layer-2 path (drop → not re-vacuumed).

## 8. Compile + in-game test plan

Compile (serial, game NOT running — see redscript-backup-corrupted memory note; never clear
`r6/cache`, never verify game files):

```bash
GAME="/Users/teazyou/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077"
cp "$GAME/r6/scripts/custom-scanner-suite/ScannerSuite.reds" <scratchpad>/ScannerSuite.pre-unlootable.reds  # backup
"$GAME/engine/tools/scc" -compile "$GAME/r6/scripts"     # must end with no errors
```

Full launch for in-game tests: `script/launch_modded.sh` (compiles + input-merges + launches; Steam
must be running).

1. **Compile clean.** Watch: the `APSInventoryCallback` override signature, `ArrayContains` on
   `array<TweakDBID>` (fallback in §5.2 if rejected), `EngineTime.ToFloat(GameInstance.GetSimTime(…))`.
2. **Stuck-save exit (the user's actual case).** Load the affected save → equip the normal weapon →
   the offending weapon force-drops ONCE → expect either silence (Layer 1) or the HUD line
   `Scanner Suite: auto-loot now ignores Items.… ` (Layer 2) → weapon stays on the ground through
   several 0.5 s passes and further re-equips → walk away. **Record the logged TDBID in this plan.**
3. **Fresh repro guard.** Kill an enemy of the same type, stand in vacuum range: the same weapon
   record must NOT be auto-collected anymore this session (corpse's other loot still vacuums).
4. **Manual-drop regression fix.** Drop a normal weapon from the inventory on purpose → one log line,
   NOT re-vacuumed; a different weapon record on the ground still vacuums normally.
5. **False-positive envelope.** Dismantle a weapon while a same-record ground drop lies >6 m away →
   no log; walk to it → it still auto-picks (radius gate held).
6. **Existing behavior unchanged.** Quest loot still skipped; iconics/HMG still taken (knobs true);
   corpses/containers/shards vacuum as before.
7. **Session semantics.** Reload → blacklist empty → first bounce re-blacklists with one log line —
   expected (state is deliberately transient; promote a recurring TDBID to a permanent entry only if
   this ever annoys, see §3-C).
8. **Crash gate (mandatory).** 5-10 min dense district + firefight + fast-travel hops: no
   `EXC_BAD_ACCESS`/heap-corruption recurrence.

## 9. Residual risks / follow-ups

- Exact vanilla force-drop trigger remains unidentified (dossier §2) — moot: Layer 2 is
  trigger-agnostic (any removal followed by a nearby drop reappearance is caught).
- Memo is weapons-only by design; if some exotic NON-weapon item ever loops, widen the
  `RPGManager.IsItemWeapon` gate in `APS_NoteItemRemoved` (one line) — do not pre-widen.
- If a bounce somehow evades the 5 s/6 m envelope (not expected: respawn is same-tick, pass cadence
  0.5 s), bump `AutoPickupRejectWindow`/`AutoPickupRejectRadius` — but investigate first with
  `DebugProbeAutoPickup` + the §8.2 TDBID capture.
- Dossier candidate #2 (`EquipArea()` null) stays rejected/unbuilt; revisit only with TweakDB-dump
  evidence (WolvenKit), which is outside this repo's REDscript-only scope.
