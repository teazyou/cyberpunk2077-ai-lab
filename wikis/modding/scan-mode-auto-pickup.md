# Scan-Mode Auto-Pickup — Feasibility Research

Researched 2026-07-05. Game: Cyberpunk 2077 v2.3x, macOS Steam (REDscript + Input Loader + `.archive` + engine `.ini` ONLY; no CET/RED4ext/TweakXL/ArchiveXL/Codeware/Mod Settings).

Sibling dossiers (facts reused, not re-verified here): [scan-mode-looting.md](scan-mode-looting.md) (scanner hover target readable from `UI_Scanner.ScannedObject`; `TransactionSystem.TransferAllItems` script-reachable; scanner suppression lives in script `HUDManager`), [scan-mode-auto-tagging.md](scan-mode-auto-tagging.md) (hover callback `scannerDetailsGameController.OnScannedObjectChanged(EntityID)` verified).

## Feature

While in scan mode (focus vision), any PICKABLE target the crosshair points at — loot container, dropped weapon, shard case, junk, lootable corpse — is collected AUTOMATICALLY, instantly, with no key press.

**Verdict: feasibility HIGH.** A shipped, pure-REDscript auto-loot mod (CNML 16040, source read in full) already proves every pickup building block; the only genuinely open question is whether the native scanner publishes plain loot objects as its hover target (mitigation exists: crosshair polling).

## Existing mods

No mod found that auto-picks on **scanner hover** specifically (Nexus/Google/Reddit/GitHub `rfuzzo/cyberpunk-nexus-script-dump`, July 2026). Notably, Autoloot 5202 explicitly *disables itself while scanning* — this feature is untaken territory.

| Mod | Nexus id | Mechanism | Framework | Status | macOS-usable? |
|---|---|---|---|---|---|
| **Completely Non-Manual Looting (CNML)** | [16040](https://www.nexusmods.com/cyberpunk2077/mods/16040) | Zero-keypress loot vacuum. Registers every `GameObject` on `OnGameAttached`, periodic `DelayCallback` sweep; per-object: type predicates (`IsPuppet/IsContainer/IsShardContainer/IsItem`), `TransactionSystem.GetItemList`, filters (quest tag, iconic, HMG, wardrobe, quality, per-type distance up to 100 m), LOS via `TargetingSystem.IsVisibleTarget`, pickup via `TransactionSystem.TransferItem` + `AudioSystem.PlayItemLootedSound` + container open animation. Source read in full (see Sources). | **Pure REDscript**; Mod Settings only for non-default settings (defaults hardcoded-usable) | v2.13.01, 2024-09-23; 2.3-compat untested but every API it touches matches current 2.x decompiled sources | **YES** (minus settings menu) — **gold precedent** |
| Autoloot | [5202](https://www.nexusmods.com/cyberpunk2077/mods/5202) | Key press/hold/burst loots "what the game reports as in your view"; quest/iconic/HMG-turret protection; optional auto-loot on takedowns; **explicitly does NOT loot while scanning** | CET (Lua) | active, v3.10.x | NO — evidence only |
| AlmostAutoLoot | [1886](https://www.nexusmods.com/cyberpunk2077/mods/1886) | Predecessor of 5202 (keanuWheeze) | CET | superseded | NO — evidence only |
| Better Loot Markers | [3486](https://www.nexusmods.com/cyberpunk2077/mods/3486) | Scanner-mode loot markers (display only, no pickup) | CET | active | NO — evidence only |
| Looting QoL | [14730](https://www.nexusmods.com/cyberpunk2077/mods/14730) | Loot UI naming | REDscript + ArchiveXL | active | NO (ArchiveXL) |
| Nearby bodies don't disappear | [11053](https://www.nexusmods.com/cyberpunk2077/mods/11053) | Corpse/loot-packet lifecycle tweaks | REDscript | active | YES — adjacent evidence only |

## Vanilla loot/pickup pipeline

Primary source: decompiled 2.x vanilla scripts, fresh local clone of `CDPR-Modding-Documentation/Cyberpunk-Scripts` (paths below relative to `scripts/`). VERIFIED = read directly in source.

### Lootable-object taxonomy (VERIFIED)

- `gameLootObject extends GameObject` (`core/components/inventoryComponent.script:147`) — base for world loot; owns loot-quality interaction layers (`QualityRange_Short/Medium/Max`) and an `'auto'` interaction layer (walk-over ammo pickup → `'ui_loot_ammo'`, line 154-160: **vanilla contact auto-loot exists**).
- `gameItemDropObject extends gameLootObject` (`inventoryComponent.script:238`) — dropped weapons/loot bags; `GetItemObject()`, `m_isEmpty`, `ToggleLootHighlight(false)` when empty.
- `gameLootContainerBase extends GameObject` (`core/components/lootContainers.script:503`; PS class line 30 with `IsLocked()` line 68) — crates/boxes; `LootContainerObjectAnimatedByTransform` (line 1056) adds `wasOpened` + `OpenContainerWithTransformAnimation()`; overrides `ShouldShowScanner()` (line 1032).
- `ShardCaseContainer extends ContainerObjectSingleItem` (`cyberpunk/containers/shardCaseContainer.script`) — overrides `IsShardContainer()`.
- Corpses: `ScriptedPuppet`/`NPCPuppet`; lootable when `IsIncapacitated() || IsDead()`.
- **Script-visible type predicates on `GameObject`** (`core/entity/gameObject.script`): `IsPuppet()` :1716, `IsContainer()` :1751, `IsShardContainer()` :1756, `IsPlayerStash()` :1761, `IsItem()` :1811 (protected const — callable from `@addMethod(GameObject)`, CNML does exactly this), `IsQuest()` :2699.

### Reading loot contents (VERIFIED)

`core/systems/transactionSystem.script:44-48`: `GetItemList(obj, out array<wref<gameItemData>>)`, plus `GetItemListByTag/ByTags/ExcludingTags/FilteredByTags`. Works on containers, item drops, puppets. Per-item data: `gameItemData.GetID()/GetQuantity()/GetItemType()/HasTag(...)`.

### The pickup call (VERIFIED)

- `TransactionSystem.TransferItem(source, target, itemID, amount, optional dynamicTags, optional force, optional flagItemAsSilent)` (:29) and `TransferAllItems(source, target)` (:30).
- **`TransferAllItems` IS the vanilla bulk-loot path**: the corpse "Loot All" choice runs `ScriptedPuppet.LootAllItems(choiceEvent)` → `TransferAllItems(this, choiceEvent.activator)` (`cyberpunk/puppet/scriptedPuppet.script:3645-3648`). Not a hack — the real interaction handler.
- Vanilla auto-behaviors to mimic (all VERIFIED): (a) body-carry auto-loot — `carriedObject.script:494-500` `EvaluateAutomaticLootPickupFromMountedPuppet` calls `TransferAllItems` when the carried NPC `HasQuestItems()`; (b) walk-over ammo auto-pickup via the `'auto'` interaction layer (above); (c) junk-scrapper perk — `CanAutomaticallyDisassembleJunk` stat auto-disassembles junk on add (`player.script:2648`).

### Downstream effects of a transfer into the player (VERIFIED)

Everything downstream is driven by inventory events, so `TransferItem` gets vanilla behavior **for free**:

- `PlayerPuppet.OnItemAddedToInventory(ItemAddedEvent)` (`cyberpunk/player/player.script:2451`): weight update, activity-log/loot-feed notification (suppressed when `evt.flaggedAsSilent` — the `flagItemAsSilent` param — or tags `SkipActivityLog`/`Currency`/broken; `inventoryEvents.script:5-11`), skill/cyberware-shard messages.
- **Shards**: `Gen_Readable` items are auto-consumed on add — `RemoveItem` + `JournalManager.ChangeEntryState(entry, "gameJournalOnscreen", Active, JournalNotifyOption.Notify)` (`player.script:2641-2646`). A transferred shard lands in Journal > Shards with the normal notification, same as manual pickup.
- **Container emptied state self-updates**: `gameLootContainerBase` tracks `m_isEmpty` via `OnInventoryEmptyEvent` (`lootContainers.script:244-248`) / `OnItemAddedEvent` (:282), re-runs `EvaluateLootQuality()` + `RequestHUDRefresh()` → loot highlight/markers clear automatically. `gameItemDropObject` mirrors this.
- Open-animation containers don't animate on remote transfer; CNML compensates: `if !openCheck.wasOpened { openCheck.OpenContainerWithTransformAnimation(); }`.
- Loot sound is not automatic: play `AudioSystem.PlayItemLootedSound(itemData)` (`core/systems/audioSystem.script:68/84` — private but reachable via the public wrapper CNML uses: `GameInstance.GetAudioSystem(...).PlayItemLootedSound(itemData)`).

### Scanner-hover applicability (VERIFIED components, INFERRED behavior)

- VERIFIED: `gameLootObject`, `gameItemDropObject`, and `gameLootContainerBase` all hold an `m_scanningComponent` and explicitly **unblock scanning** on attach (`SetScanningBlockedEvent { isBlocked = false }` — `inventoryComponent.script:259-266`, `lootContainers.script:142-149/527-534`); `gameLootContainerBase` overrides `ShouldShowScanner()`. Loot objects are built to be scanner-focusable.
- INFERRED (needs 5-min in-game probe): that the native scanner therefore publishes them to `UI_Scanner.ScannedObject` on hover the way it does NPCs/devices. If it doesn't for some subclass (e.g. tiny junk `ItemObject`s), the crosshair-polling fallback below covers it.
- Hover hooks (from sibling dossiers, VERIFIED there): `scannerDetailsGameController.OnScannedObjectChanged(value: EntityID)`; `HUDManager.OnScannerTargetChanged(value: EntityID)` (gate on PSM `Vision == 1`); resolve entity via `GameInstance.FindEntityByID`.
- Crosshair fallback: `TargetingSystem.GetLookAtObject(instigator, optional withLOS, optional ignoreTranparent)` (`core/systems/targetingSystem.script:93`) — same call `FocusModeTaggingSystem` uses as its scanner-target fallback.
- LOS/visibility check: `TargetingSystem.IsVisibleTarget(player, obj)` (CNML's seen-check). Distance: `Vector4.Distance(player.GetWorldPosition(), obj.GetWorldPosition())`.
- Range: `TransferItem` has **no engine range gate** — CNML ships user-configurable loot distances up to 100 m and works (vanilla manual loot range is ~3 m per CNML's docs). Any range/LOS policy must be implemented by the mod.

## Candidate implementation approaches (ranked)

### 1. Hover-event auto-pickup — wrap `scannerDetailsGameController.OnScannedObjectChanged` (RECOMMENDED, pure REDscript)

On each hover change while scanning: `FindEntityByID` → classify:
`(IsPuppet() && (IsIncapacitated() || IsDead())) || IsContainer() || IsShardContainer() || IsItem()`; skip `IsPlayerStash()`, locked (`(obj as gameContainerObjectBase).GetPS().IsLocked()`), `IsQuest()` objects; apply range + `IsVisibleTarget` LOS gate; `GetItemList` → per-item filters (below) → `TransferItem(obj, player, id, qty)` each passing item (+ `PlayItemLootedSound`, + open animation for `LootContainerObjectAnimatedByTransform`). Per-item `TransferItem` (CNML pattern) preferred over `TransferAllItems` because it lets quest/iconic/HMG items stay behind; `TransferAllItems` is the blunt variant for pre-filtered corpses. *Viability: HIGH — every call verified; identical hook already validated for auto-tagging.*

### 2. Same handler on `HUDManager.OnScannerTargetChanged`

Gate on PSM `Vision == 1` (fires outside scan mode too, e.g. quickhack target changes). Use if the details-controller lifecycle misses early hover frames. *Viability: HIGH (fallback).*

### 3. Crosshair polling while scanning (complement, pure REDscript)

Wrap `PlayerVisionModeController.ActivateVisionMode()` (wrappable — verified via Toggle Sprint While Scanning) to start a `DelaySystem` loop (~0.15 s) calling `TargetingSystem.GetLookAtObject(player, true, true)`; stop on vision exit. Catches anything the crosshair touches even if the native scanner never "focuses" it (small junk, ammo). CNML proves `DelayCallback` loops are shippable. *Viability: HIGH; slightly costlier; best paired with 1 as the safety net for non-scanner-focusable loot.*

### 4. Dispatch the vanilla loot interaction (`Choice1`) programmatically

Unnecessary and fragile: the interaction visualizer likely doesn't publish loot choice hubs during Focus (see scan-mode-looting dossier), and `TransferAllItems` already *is* the choice handler's body. *Viability: LOW — rejected.*

### 5. CET-style view-scrape (Autoloot 5202 mechanism)

Documented for principle only; CET unavailable on macOS. *Viability: N/A.*

All viable paths are single-`.reds` mods → `mods/enabled/r6-scripts/`, fully macOS-toolchain compatible. No Input Loader `.xml` needed (no key press involved at all).

## Filters & safety

- **Range**: scanner hovers targets at long distance and through walls. Recommend hardcoded gate (constant; no Mod Settings on macOS): e.g. loot ≤ 12 m AND `IsVisibleTarget` true. Engine won't stop a 50 m through-wall transfer (CNML's 100 m "cheater mode" proves it) — the filter is policy, not necessity.
- **Quest protection** (CNML pattern, VERIFIED flags): skip item if `itemData.HasTag(n"Quest")` or object `IsQuest()`. Note vanilla itself transfers quest items on body-carry, so leaving them is conservative-safe; taking them risks incomprehensible story beats (Autoloot's docs) — skip them.
- **Iconics**: skip via `RPGManager.IsItemIconic(itemData)` (CNML/Autoloot both do).
- **HMG/turret weapons**: skip `gamedataItemType.Wea_HeavyMachineGun` — Autoloot research (keanuWheeze) found looting these harmful.
- **Nameless items**: skip items with empty `UIItemsHelper.GetItemName(...)` unless `Gen_Readable` (CNML guard against internal placeholder items).
- **Bodies**: only `IsIncapacitated() || IsDead()`; never living NPCs (that would be theft/disarm). Bodies being carried/disposed: the hover target during body-carry is restricted anyway (`GameplayRestriction.BodyCarryingActionRestriction`), and scan mode is unavailable mid-disposal — no special case expected (SPECULATED).
- **Containers**: skip locked (`IsLocked()`), skip `IsPlayerStash()`; play `OpenContainerWithTransformAnimation` on animated crates for visual coherence.
- **Shards**: safe — auto-journal on add (VERIFIED above); quest shards excluded by the Quest tag filter.
- **Stealth**: `TransferItem` broadcasts no stim in any script path read; `PlayItemLootedSound` is player-UI audio. Auto-looting mid-stealth should be detection-neutral (SPECULATED — no native-side counter-evidence found).
- **Dwell option**: to avoid Midas-touch (looting everything a crosshair sweep grazes), optionally require the hover target stable for ~0.2 s before transferring (DelaySystem timer keyed on EntityID). Design choice, not a blocker.

## Risks & unknowns

- **Main unknown — hover coverage**: does the native scanner set `UI_Scanner.ScannedObject` for plain loot containers/item drops/junk, or only NPCs/devices/clues? Scanning components verified present+unblocked on all loot classes (strong signal), but the publisher is native. 5-minute probe: log-only wrap of `OnScannedObjectChanged` + hover a crate. Fallback: approach 3 polling makes the feature work regardless.
- **Scanner-details flicker**: emptying the hovered object may despawn it (item drops) or clear its loot data while the scanner panel displays it → panel may blank/retarget each pickup. Benign but test; if ugly, delay transfer until hover leaves the object (transfer-on-unhover variant).
- **Empty item-drop lifecycle**: whether `gameItemDropObject` despawns immediately when emptied via script transfer (vs the native pickup path) is unverified; worst case an empty husk without highlight remains until the engine GC collects it.
- **CNML 2.3 drift**: CNML last updated 2024-09; if it broke on 2.x-later patches, it broke on API drift the new mod would share. Mitigation: all signatures re-checked against current 2.x decompiled sources today; REDscript compile errors surface at launch via `launch_modded.sh`. LOW.
- **Balance/economy**: instant hoovering trivializes loot pacing and encumbrance can spike mid-mission (Autoloot's own warning). Design, not technical.
- **Interaction with the sibling scan-loot/auto-tag mods**: all three wrap adjacent scanner hooks (`OnScannedObjectChanged` is shared with auto-tagging). `@wrapMethod` chains compose fine, but keep the mods' filters consistent to avoid tag-then-vanish weirdness (auto-tagging a container the auto-pickup immediately empties).

## Sources

- CNML full source (pure REDscript autoloot): https://github.com/rfuzzo/cyberpunk-nexus-script-dump — `mods/16040/.../r6/scripts/Completely Non-Manual Loot/CNML.reds` (725 lines, read in full; local copy in session scratchpad); metadata: v2.13.01, updated 2024-09-23, author Thortok2000
- Decompiled vanilla scripts: https://github.com/CDPR-Modding-Documentation/Cyberpunk-Scripts (fresh shallow clone). Files cited: `core/systems/transactionSystem.script`, `core/components/inventoryComponent.script`, `core/components/lootContainers.script`, `core/entity/gameObject.script`, `core/events/inventoryEvents.script`, `core/systems/targetingSystem.script`, `core/systems/audioSystem.script`, `cyberpunk/player/player.script`, `cyberpunk/player/psm/carriedObject.script`, `cyberpunk/puppet/scriptedPuppet.script`, `cyberpunk/containers/shardCaseContainer.script`
- Nexus pages (via r.jina.ai): [Autoloot 5202](https://www.nexusmods.com/cyberpunk2077/mods/5202), [Completely Non-Manual Looting 16040](https://www.nexusmods.com/cyberpunk2077/mods/16040), [Better Loot Markers 3486](https://www.nexusmods.com/cyberpunk2077/mods/3486), [Looting QoL 14730](https://www.nexusmods.com/cyberpunk2077/mods/14730), [Nearby bodies don't disappear 11053](https://www.nexusmods.com/cyberpunk2077/mods/11053), [AlmostAutoLoot 1886](https://www.nexusmods.com/cyberpunk2077/mods/1886)
- Sibling dossiers in this vault: [scan-mode-looting.md](scan-mode-looting.md), [scan-mode-auto-tagging.md](scan-mode-auto-tagging.md)
- Cross-reference: https://nativedb.red4ext.com (not needed beyond decompiled sources this pass)
