# Implementation Plan — Auto-Pickup on Hover While Scanning

**Verdict: VALIDATED — REALISM yes, technical difficulty 3/5** (evaluated 2026-07-05, game v2.3x, macOS Steam).
Research dossier: [scan-mode-auto-pickup.md](scan-mode-auto-pickup.md). All load-bearing signatures re-verified today against the local decompiled 2.3x sources (`/private/tmp/claude-501/-Users-teazyou-dev-tmp-claude-cyberpunk/83a55f05-0e36-46b4-a285-563d965dec24/scratchpad/vanilla-scripts/`) and the CNML 16040 full source (same scratchpad, `CNML.reds`).

## Feature

While in scan mode (focus vision), any pickable/lootable target the scanner crosshair acquires — loot container, dropped weapon, shard case, junk, lootable corpse — is collected automatically, instantly, no key press. Quest/iconic/HMG items and locked containers are left alone; one collection attempt per entity per session.

## Rating

- **REALISM: YES.** Every pickup building block is verified script-reachable in the local 2.3x decompile and proven shippable by CNML 16040 (pure-REDscript autoloot, source read in full): `TransactionSystem.GetItemList`/`TransferItem` (`orphans.swift:18087/18057`), type predicates on `GameObject` (`gameObject.swift:1347-1395, 2094`), `IsLocked` (`lootContainers.swift:60`), `IsVisibleTarget` (`orphans.swift:22453`), loot sound (`audioSystem.swift:108`), open animation (`lootContainers.swift:820/839`). The hover hook `scannerDetailsGameController.OnScannedObjectChanged(value: EntityID)` is verified (`scanner_details.swift:179`) and already validated by the sibling auto-tag plan. No CET/RED4ext/TweakXL/Codeware needed; no Input Loader xml (no key press involved).
- **TECHNICAL DIFFICULTY: 3/5.** More moving parts than auto-tag (2/5): a per-item filter matrix, transient-vs-final attempt bookkeeping (so a distant first hover doesn't burn the entity's one attempt), three class-scope helper shims for protected vanilla members, and coexistence with two sibling features. Plus one real unknown — whether the native scanner publishes plain loot objects to `UI_Scanner.ScannedObject` at all (loot classes verifiably carry unblocked scanning components, but the publisher is native). The unknown is cheap to probe (built-in log probe below) and has a verified fallback (`TargetingSystem.GetLookAtObject` polling, `orphans.swift:22401` — same call `FocusModeTaggingSystem` uses), so it caps risk, not feasibility. Not 4/5 because every call is individually verified and CNML proves the whole pipeline in production.
- Decision rule: difficulty 3 ≤ 3 and realistic → **VALIDATED**.

## Mod identity

- **Name:** Custom Auto Pickup On Scan
- **Slug:** `custom-auto-pickup-on-scan`
- **File:** `mods/enabled/r6-scripts/custom-auto-pickup-on-scan/AutoPickupOnScan.reds` (single `.reds`; portal → `GAME/r6/scripts/custom-auto-pickup-on-scan/`)
- House style: `@wrapMethod` calls `wrappedMethod` exactly once; `@addField` for state; `@addMethod` helpers; kebab-case subfolder; user-editable literals in a config block at the top (Custom Switch Speed pattern). Slated to merge into the combined "scanner suite" custom mod with auto-tag-on-scan and loot-while-scanning — toggle is feature-distinctly named.

## User config (ON/OFF toggle)

- **`AutoPickupOnScanConfig.EnableAutoPickupOnScan()` at the very top, default `true`.** Argument for ON-by-default: the mod exists only because the user asked for exactly this behavior; toggling requires editing a literal + relaunch (no Mod Settings on macOS), so shipping OFF would be a dead-on-arrival install; both sibling features default ON. The counterargument — this is the most gameplay-invasive of the trio (irreversibly moves items) — is answered by conservative guardrails baked in: 12 m range + LOS gate, quest/iconic/HMG/nameless filters, locked-container and stash skips, once-per-entity attempt cap. Encumbrance-spike worry is additionally moot in this vault: "No carry weight - Disable encumbrance" is ENABLED.
- **OFF = 100% vanilla:** checked immediately after the mandatory `wrappedMethod` call, before ANY custom logic — no ledger reads/writes, no entity resolution, no transfers. The `@addField`/`@addMethod` declarations still compile (unavoidable with REDscript annotations) but are inert dead code when disabled.
- Secondary knobs (same block, editable literals): `AutoPickupMaxDistance()` = 12.0 m, `AutoPickupPlaySound()` = true, `DebugProbeAutoPickup()` = false (the blackboard-unknown probe).

## Hooks (exact, verified)

1. **Hover → auto-pickup:** `@wrapMethod(scannerDetailsGameController)` on `protected cb func OnScannedObjectChanged(value: EntityID) -> Bool` (`scanner_details.swift:179`; fires on blackboard `UI_Scanner.ScannedObject` change — exactly when the scanner acquires a new target). Same hook as sibling auto-tag; wraps chain safely.
2. **Attempt ledger:** `@addField(PlayerPuppet) m_apsAttempted: array<EntityID>` + `@addMethod` `APS_AlreadyAttempted`/`APS_MarkAttempted` (CNML precedent for hanging autoloot state on the player entity).
3. **Class-scope shims for protected vanilla members** (cleaner than CNML's lax cross-class access, definitely legal since added methods compile as members):
   - `@addMethod(gameLootContainerBase) APS_IsLootLocked()` → `this.GetPS().IsLocked()` (`GetPS` is `protected const`, `lootContainers.swift:451`; `IsLocked` public on the PS, `:60`).
   - `@addMethod(LootContainerObjectAnimatedByTransform) APS_EnsureOpened()` → `wasOpened` (`protected let`, `:839`) + inherited `OpenContainerWithTransformAnimation()` (`protected final` on `gameContainerObjectBase`, `:820`).
   - `@addMethod(AudioSystem) APS_PlayLootedSound()` → private `PlayItemLootedSound(itemData)` (`audioSystem.swift:108`).
4. **Classify+loot worker:** `@addMethod(GameObject) APS_TryAutoPickup(player)` — needs GameObject class scope to call `protected final const IsItem()` (`gameObject.swift:1395`; CNML does the same).

Fallback hooks if the details-controller lifecycle misses hover frames or the blackboard unknown resolves negative (NOT deployed initially): `HUDManager.OnScannerTargetChanged(value: EntityID)` (`hudManager.swift:685`, listener registered on the same blackboard key at `:1041`; gate on `ActiveMode.FOCUS`), and/or a `DelaySystem` polling loop on `TargetingSystem.GetLookAtObject(player, true, true)` started from a `PlayerVisionModeController.ActivateVisionMode` wrap (dossier approach 3, `DelayCallback` verified `orphans.swift:11818`).

## Full draft — `AutoPickupOnScan.reds`

```swift
// =============================================================================
// Custom Auto Pickup On Scan — locally-authored custom mod (no Nexus source)
// While in scan mode (focus vision), the loot object the scanner crosshair
// acquires is collected automatically: lootable corpses, containers, shard
// cases, dropped items. Quest/iconic/HMG/nameless items stay behind; locked
// containers and the player stash are never touched. One attempt per entity
// per session (transient refusals — alive NPC, locked, out of range — do NOT
// spend the attempt). Pure REDscript; macOS-safe.
// =============================================================================

// ============================ USER CONFIG ====================================
// Toggle named per-feature: this file is slated to merge into a combined
// "scanner suite" mod where each feature carries its own switch.
public abstract class AutoPickupOnScanConfig {

  // ON/OFF for auto-pickup-on-hover. Set to false for 100% vanilla behavior.
  public static func EnableAutoPickupOnScan() -> Bool {
    return true;
  }

  // Max auto-loot distance in meters (scanner can hover targets much farther;
  // TransferItem itself has no engine range gate — this is policy).
  public static func AutoPickupMaxDistance() -> Float {
    return 12.0;
  }

  // Play the vanilla per-item loot sound on each collected item.
  public static func AutoPickupPlaySound() -> Bool {
    return true;
  }

  // Diagnostic probe for the one research unknown: does the native scanner
  // publish plain loot objects (containers/item drops) to
  // UI_Scanner.ScannedObject on hover? When true, every scanner hover prints
  // the resolved target's class name to the HUD activity log. Keep false for
  // normal play.
  public static func DebugProbeAutoPickup() -> Bool {
    return false;
  }
}
// =============================================================================

// ---------- one-attempt-per-entity ledger (session-scoped, not saved) ----------

@addField(PlayerPuppet)
let m_apsAttempted: array<EntityID>;

@addMethod(PlayerPuppet)
public final func APS_AlreadyAttempted(id: EntityID) -> Bool {
  return ArrayContains(this.m_apsAttempted, id);
}

@addMethod(PlayerPuppet)
public final func APS_MarkAttempted(id: EntityID) -> Void {
  if !ArrayContains(this.m_apsAttempted, id) {
    ArrayPush(this.m_apsAttempted, id);
  }
}

// ---------- class-scope shims for protected vanilla members ----------

// GetPS() is protected const on gameLootContainerBase; legal from a member.
@addMethod(gameLootContainerBase)
public final func APS_IsLootLocked() -> Bool {
  return this.GetPS().IsLocked();
}

// wasOpened / OpenContainerWithTransformAnimation are protected; legal from a
// member of the class. Mirrors CNML's visual-coherence compensation: a remote
// transfer does not animate the crate, so trigger the open animation once.
@addMethod(LootContainerObjectAnimatedByTransform)
public final func APS_EnsureOpened() -> Void {
  if !this.wasOpened {
    this.OpenContainerWithTransformAnimation();
  }
}

// PlayItemLootedSound is private on AudioSystem; expose via a member shim.
@addMethod(AudioSystem)
public final func APS_PlayLootedSound(itemData: wref<gameItemData>) -> Void {
  this.PlayItemLootedSound(itemData);
}

// ---------- classify + loot worker ----------
// Returns true when this attempt is FINAL for the entity (spend its one
// attempt): non-lootable class, player stash, or contents processed (some
// items transferred and/or all items filtered out).
// Returns false on TRANSIENT refusals (do NOT spend the attempt; a later
// hover retries): living puppet, locked container, out of range, no line of
// sight, empty item list.
// Declared on GameObject because IsItem() is protected final const
// (gameObject.swift:1395) — callable only from class scope (CNML pattern).
@addMethod(GameObject)
public final func APS_TryAutoPickup(player: ref<PlayerPuppet>) -> Bool {
  let game: GameInstance = this.GetGame();
  let transSys: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
  let puppet: ref<ScriptedPuppet> = this as ScriptedPuppet;

  // --- type gate ---
  if IsDefined(puppet) {
    if !puppet.IsIncapacitated() && !puppet.IsDead() {
      return false; // alive now, may be lootable later — transient
    }
  } else {
    if !this.IsContainer() && !this.IsShardContainer() && !this.IsItem() {
      return true; // not a lootable class — final, never retry
    }
    if this.IsPlayerStash() {
      return true; // never touch the stash — final
    }
    let container: ref<gameLootContainerBase> = this as gameLootContainerBase;
    if IsDefined(container) && container.APS_IsLootLocked() {
      return false; // may be unlocked later — transient
    }
  }

  // --- range + LOS policy gate (scanner hovers far and through walls;
  //     TransferItem has no engine range gate — CNML's 100 m mode proves it) ---
  if Vector4.Distance(player.GetWorldPosition(), this.GetWorldPosition())
      > AutoPickupOnScanConfig.AutoPickupMaxDistance() {
    return false; // walk closer, re-hover — transient
  }
  if !GameInstance.GetTargetingSystem(game).IsVisibleTarget(player, this) {
    return false; // through-wall hover — transient
  }

  // --- read contents ---
  let itemList: array<wref<gameItemData>>;
  transSys.GetItemList(this, itemList);
  if ArraySize(itemList) == 0 {
    return false; // nothing (yet) — transient, cheap to re-check
  }

  // --- per-item filters + transfer (CNML filter set, CNML.reds:455-475) ---
  let lootedAny: Bool = false;
  for itemData in itemList {
    let itemType: gamedataItemType = itemData.GetItemType();
    let name: String = UIItemsHelper.GetItemName(ItemID.GetTDBID(itemData.GetID()), itemData);
    if Equals(name, "") && !Equals(itemType, gamedataItemType.Gen_Readable) {
      // nameless internal placeholder (non-shard) — skip
    } else if Equals(itemType, gamedataItemType.Wea_HeavyMachineGun) {
      // HMG/turret weapons: known-harmful to loot (Autoloot research) — skip
    } else if itemData.HasTag(n"Quest") || this.IsQuest() {
      // quest-flagged item or quest object: leave for the story — skip
    } else if RPGManager.IsItemIconic(itemData) {
      // iconics: deliberate manual pickup only — skip
    } else {
      transSys.TransferItem(this, player, itemData.GetID(), itemData.GetQuantity());
      if AutoPickupOnScanConfig.AutoPickupPlaySound() {
        GameInstance.GetAudioSystem(game).APS_PlayLootedSound(itemData);
      }
      lootedAny = true;
    }
  }

  // visual coherence: animated crates (lockers/fridges/trunks) play their
  // open animation instead of silently emptying behind a closed lid.
  if lootedAny {
    let animated: ref<LootContainerObjectAnimatedByTransform> =
      this as LootContainerObjectAnimatedByTransform;
    if IsDefined(animated) {
      animated.APS_EnsureOpened();
    }
  }
  return true; // processed (transferred and/or filtered) — final
}

// ---------- hover hook: scanner acquires a target ----------

@wrapMethod(scannerDetailsGameController)
protected cb func OnScannedObjectChanged(value: EntityID) -> Bool {
  let result: Bool = wrappedMethod(value);
  if !AutoPickupOnScanConfig.EnableAutoPickupOnScan() {
    return result; // feature OFF -> 100% vanilla, no custom logic runs
  }
  if EntityID.IsDefined(value) {
    let player: ref<PlayerPuppet> = this.GetPlayerControlledObject() as PlayerPuppet;
    if IsDefined(player)
        && !player.IsReplacer()
        && !player.GetHudManager().IsBraindanceActive() {
      let game: GameInstance = player.GetGame();
      // scanner_details also serves the quickhack panel -> explicit focus gate
      if Equals(HUDManager.GetActiveMode(game), ActiveMode.FOCUS) {
        let target: ref<GameObject> = GameInstance.FindEntityByID(game, value) as GameObject;
        if AutoPickupOnScanConfig.DebugProbeAutoPickup() {
          GameInstance.GetActivityLogSystem(game).AddLog(
            s"APS probe: hover -> \(IsDefined(target) ? NameToString(target.GetClassName()) : "unresolved entity")");
        }
        if IsDefined(target)
            && !player.APS_AlreadyAttempted(value)
            && target.APS_TryAutoPickup(player) {
          player.APS_MarkAttempted(value);
        }
      }
    }
  }
  return result;
}
```

## Filters & safety (recommended defaults, with reasoning)

| Concern | Default | Why |
|---|---|---|
| **Range** | ≤ 12 m + `IsVisibleTarget` LOS, both required | Scanner hovers at long range and through walls; `TransferItem` has no engine gate (CNML's 100 m mode proves it). 12 m ≈ generous room-scale, ~4x vanilla manual loot range, still local. Editable literal. |
| **Quest items / quest objects** | skip (`HasTag(n"Quest")` or `IsQuest()`) | Taking them risks incomprehensible story beats (Autoloot docs); leaving them is conservative-safe — vanilla itself only force-transfers quest items on body-carry. Left for manual pickup via sibling loot-while-scanning. |
| **Iconics** | skip (`RPGManager.IsItemIconic`) | Deliberate-pickup items; both CNML and Autoloot skip them. |
| **HMG/turret weapons** | skip (`Wea_HeavyMachineGun`) | keanuWheeze's Autoloot research found looting these harmful. |
| **Nameless items** | skip unless `Gen_Readable` | CNML guard against internal placeholder items; shards exempt (auto-journal on add is verified vanilla behavior). |
| **Corpses vs living NPCs** | loot only `IsIncapacitated() \|\| IsDead()`; alive = transient (no attempt spent) | Never rob/disarm the living; hovering a live enemy must not burn its one attempt — kill-then-rehover must work. |
| **Containers** | skip locked (transient — may unlock later), skip `IsPlayerStash` (final) | CNML pattern; Go Where You Want (installed) can open paths to containers later, so locked must stay retryable. |
| **Opening-animation containers** | LOOT + trigger `OpenContainerWithTransformAnimation` once | Remote transfer doesn't animate; CNML's proven compensation keeps the visuals coherent (open lid over an emptied crate). Conservative alternative — skip `LootContainerObjectAnimatedByTransform` entirely — is a 3-line change at the type gate, documented in case animated-crate looting feels wrong in play. |
| **Shards** | loot | Auto-consume + journal entry on add is vanilla-verified; quest shards already excluded by the Quest tag filter. |
| **One-attempt-per-entity** | session ledger on `PlayerPuppet`, spent only on FINAL outcomes | Prevents hammering `TransferItem`/`GetItemList` on every re-hover of a container whose only remains are filtered (quest/iconic) items. Transient refusals (alive/locked/far/no-LOS/empty) deliberately do NOT spend it. `OnScannedObjectChanged` fires per target change, not per frame, so worst case is one cheap early-out per re-hover. |
| **Replacer/braindance** | early-out | CNML guards; avoids auto-looting inside scripted Johnny/braindance sequences. |
| **Dwell delay** | none (instant, per spec) | The feature is defined as instant collection on hover. If Midas-touch on sweep feels bad in play, a ~0.2 s `DelayCallback` dwell keyed on EntityID is the documented follow-up knob — design choice, not a blocker. |
| **Stealth** | no special handling | No script path read broadcasts a stim on transfer; loot sound is player-UI audio (dossier, SPECULATED — watch during T-checklist). |

## Coexistence — combined "scanner suite" (auto-tag + loot-while-scanning)

**Hook collision map:**

| Hook | This mod | Auto-tag | Loot-while-scanning |
|---|---|---|---|
| `scannerDetailsGameController.OnScannedObjectChanged` | wrap | **wrap (SHARED)** | — |
| `HUDManager.OnScannerUIVisibleChanged`/QH context cbs/`OnLootDataChanged` | — | — | wraps |
| `FocusModeTaggingSystem` fields | — | @addField `m_autoTagSeen` | — |
| `PlayerPuppet` fields | @addField `m_apsAttempted` | — | Path B only: @addField listener + `OnGameAttached` wrap |

- **Shared `OnScannedObjectChanged` wrap (auto-tag + this):** REDscript chains multiple `@wrapMethod`s on the same method — each calls `wrappedMethod` once, both run, no conflict. BUT chain order between separate files is not contractual. Semantics of each order: tag-then-pickup tags an object that is emptied milliseconds later (tag marker on an empty container — cosmetic clutter); pickup-then-tag tags an already-empty container (same clutter). Neither breaks anything (loot highlight self-clears via `OnInventoryEmptyEvent`, verified). **Recommendation for the combined suite:** merge into ONE wrap that runs deterministically **auto-tag first, then auto-pickup** — clue cascade (`ResolveFocusClues`) sees the object intact — and optionally skip auto-tag when auto-pickup is about to fully empty a non-quest container (one boolean handoff between the two feature calls; nice-to-have, not required).
- **Ledger independence:** auto-tag's seen-list lives on `FocusModeTaggingSystem`, this mod's attempt ledger on `PlayerPuppet` — intentionally separate. A target skipped by pickup (e.g. locked) can still be tagged, and vice versa.
- **Semantic overlap — what's left for the siblings on a hovered target:** auto-pickup deliberately leaves a niche for each. Loot-while-scanning remains the *manual* channel for exactly what auto-pickup filters out: quest items, iconics, HMGs, locked containers, targets beyond 12 m/through walls — plus tooltip inspection before taking. Its loot prompt will visibly appear-then-clear when auto-pickup empties a target mid-hover (benign flicker; the dossier's transfer-on-unhover variant is the fix if it looks bad). Auto-tag is barely affected: most of its value is NPCs/devices/vehicles, which pickup never touches; the only overlap is the tagged-empty-container cosmetic above. If Path B of loot-while-scanning ever ships, its `TransferAllItems` on an already-emptied target is a harmless no-op, and its `LootData.isActive` guard is unaffected.
- **Toggle matrix:** all three toggles are independently named (`EnableAutoPickupOnScan`, `EnableAutoTagOnScan`, `EnableLootWhileScanning`); any subset can be OFF with the others fully functional; each OFF is a pure `wrappedMethod` passthrough.

## Edge cases & installed-mod interaction check

Grepped every deployed `.reds` under `GAME/r6/scripts/` for `OnScannedObjectChanged|scannerDetailsGameController|TransferItem|TransferAllItems|GetItemList|OnScannerTargetChanged|FocusModeTaggingSystem` — single hit: **Rich Vendors** *calls* `TransferItem` in its own vendor-restock code (no hook on it) — no collision. Per-mod:

- **Disassemble As Looting Choice** (wraps `LootingController`, `InventoryDataManagerV2`, own `ChoiceDisassemble_Hold` listener): **no method overlap.** Semantic: items auto-collected during scan skip the loot prompt, so DALC's disassemble-at-loot choice is never offered for them *while scanning* — they can still be disassembled from the inventory. Outside scan mode (FOCUS gate) looting and DALC are byte-for-byte untouched. Auto-pickup's quest/iconic skips also mean the interesting DALC cases (junk/clothes) get hoovered — acceptable; if the user misses disassemble-at-loot, the fix is flipping this mod's toggle, not a code conflict.
- **Toggle Sprint While Scanning** (`PlayerVisionModeController` etc.): no overlap; behavioral synergy — sprint-scanning vacuums corridors faster. Note if the polling fallback (approach 3) is ever deployed it would wrap `ActivateVisionMode` alongside this mod's wrap — wraps chain, still safe.
- **Hacking Gets Tedious / Quickhacks sort by slot**: quickhack-side only; the `ActiveMode.FOCUS` gate keeps auto-pickup out of the quickhack panel path (`scanner_details` serves both — verified).
- **No carry weight**: removes the encumbrance-spike concern of bulk auto-looting entirely.
- **Go Where You Want**: may open routes/doors to containers; locked-container refusals being transient (retryable) composes correctly with late unlocks.
- **Preem Scanner / Clean Voiceovers** (.archive cosmetics): no script surface.
- **Custom XP / Switch Speed / others**: unrelated methods; Custom Switch Speed's `PlayerPuppet.OnGameAttached` wrap is untouched (this mod does not wrap it).
- **Scanner-details flicker** (dossier risk): emptying the hovered object may blank/retarget the scanner panel (item drops can despawn). Benign; test T6 — if ugly, switch to the transfer-on-unhover variant (act on the *previous* EntityID when `value` changes).
- **Empty item-drop husk**: whether `gameItemDropObject` despawns when emptied via script transfer is unverified; worst case an unlit husk remains until GC. Cosmetic.
- **Save/load mid-session**: `m_apsAttempted` lives on the puppet entity, not persisted; after a load the ledger resets — re-hovering an already-emptied container hits the empty-list transient path (no double loot possible; items are gone).
- **EntityID reuse** (crowd respawn): fresh ids get fresh attempts — correct behavior.
- **Balance**: instant hoovering trivializes loot pacing (Autoloot's own warning) — accepted by design; the 12 m gate keeps it to "what you're actually near".

## Verification steps

1. **Compile:** with Steam running, `script/launch_modded.sh` — scc compiles all of `r6/scripts/` at launch; signature drift vs the 2.3x macOS build = compile error dialog. (If a "backup corrupted" dialog appears: transient — stop workflow, clean serial `scc -compile`; never clear `r6/cache` or verify files.)
2. **Blackboard-unknown probe (do FIRST, resolves the dossier's main unknown):** set `DebugProbeAutoPickup() = true`, relaunch. In scan mode hover: a crate, an animated locker, a dropped weapon, a shard case, tiny ground junk, a corpse, an NPC, a device. Each hover should print `APS probe: hover -> <ClassName>` in the HUD activity log. **Loot classes appear** (`gameLootContainerBase`/`gameItemDropObject`/`ShardCaseContainer`/…) → unknown resolved positive, ship as-is. **Loot classes never appear** (only NPCs/devices/clues) → native scanner doesn't publish plain loot to `UI_Scanner.ScannedObject` → deploy the documented fallback: same worker driven by `HUDManager.OnScannerTargetChanged` first, then the `GetLookAtObject` polling loop (approach 3) if that also misses; the worker function is hook-agnostic and moves unchanged. Set probe back to `false`.
3. **In-game checklist:**
   - Scan-hover a container ≤ 12 m → contents (minus filters) land in inventory instantly, loot sound plays, highlight/markers clear.
   - Animated locker/fridge → loots AND plays its open animation.
   - Shard case → shard auto-journals with normal notification (Journal > Shards).
   - Dropped weapon → collected; observe whether the empty drop despawns (husk note).
   - Corpse → gear collected; a LIVING enemy hovered → nothing; kill it, re-hover → looted (transient/alive path works, attempt not burned).
   - Container at ~30 m or through a wall → nothing; walk within 12 m with LOS, re-hover → looted (transient/range path works).
   - Locked container → skipped; unlock it, re-hover → looted.
   - Container holding a quest item / an iconic → those remain (panel or manual loot shows them); re-hover → no repeated transfer attempts (final-attempt ledger works).
   - Player stash → never touched.
   - Quickhack panel (Tab) target cycling → no pickups (FOCUS gate).
   - Mid-stealth auto-loot near an enemy → no detection change (stealth speculation check).
   - With sibling mods enabled: hover a lootable → tag + pickup both fire, no errors; loot-while-scanning prompt flicker on emptied target = expected/benign.
   - Flip `EnableAutoPickupOnScan()` to `false`, relaunch → zero pickups anywhere, scanning 100% vanilla; flip back.
4. **Log sanity:** no script errors in `r6/logs/redscript_rCURRENT.log` after a session.
5. **Registry:** on install add the mod-manager.md entry (Gameplay: Custom Auto Pickup On Scan, COMPAT ✅ locally authored pure wrap-based `.reds`, URL —, FILES `r6-scripts/custom-auto-pickup-on-scan/AutoPickupOnScan.reds`, NOTE probe outcome + which hook shipped) per custom-mod house pattern.
