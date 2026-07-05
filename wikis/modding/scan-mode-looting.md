# Scan-Mode Looting — Feasibility Research

Researched 2026-07-05. Game v2.3x, macOS Steam. Platform constraint: REDscript `.reds` + Input Loader `.xml` + raw `.archive` + engine `.ini` only (no CET / RED4ext / TweakXL / ArchiveXL / Codeware).

## Feature

While scanner vision is active (hold Tab / focus mode), pointing the crosshair at a lootable item should show the normal loot prompt (item tooltip + Pick Up choice) and allow picking it up, exactly as when not scanning. Vanilla suppresses the loot prompt while the scanner is up.

## Existing mods

**No mod found that implements loot-while-scanning** (searched Nexus keyword "while scanning" / "loot scanner", Google, Reddit, GitHub code search incl. the `rfuzzo/cyberpunk-nexus-script-dump` mirror of all Nexus `.reds` mods — July 2026). Demand exists: a user on the *Scanner Time Dilation Optional* (Nexus 9671) posts tab asked for looting while in scanner mode ("hate having to keep going in and out of scanner just to loot").

Adjacent mods (precedent evidence):

| Mod | Nexus ID | What it does | Framework | Status | Relevance |
|---|---|---|---|---|---|
| Toggle Sprint While Scanning | 14646 | Removes scan-mode movement restriction; wraps `AimWalkDecisions.EnterCondition`, `SprintEvents.OnEnter`, `PlayerVisionModeController.ActivateVisionMode` | **REDscript only** | v1.0, upd. 2024-05-10; works on 2.3 (installed in this vault) | VERIFIED source locally: scan-mode restrictions are script-side and wrappable |
| Toggle walking or jogging while scanning | 7529 | Same idea, older | REDscript only | upd. 2023-10-06 | Same precedent |
| Hold to Overclock while scanning | 21656 | Adds scanner-state input behavior | **REDscript only** | v1.0.2, upd. **2026-01-26** | Recent proof scanner-state hooks still work on 2.3 |
| REDUNDANT Force Overclock HUD | 16238 | Keeps health/RAM HUD visible **while scanning** by exploiting vanilla `UI_QuickSlotsData.quickhackPanelKeepContext` flag | **REDscript only** | superseded by base game | Proof HUD-during-scan visibility is script-alterable |
| Looting QoL | 14730 | Better loot naming/UI | REDscript + ArchiveXL | active | Shows loot UI heavily moddable; ArchiveXL part unusable on macOS |
| Autoloot | 5202 / Completely Non-Manual Looting 16040 | Programmatic auto-pickup | **CET (Lua)** | active | Proves programmatic pickup possible in principle; unusable on macOS |
| Better Loot Markers | 3486 | Scanner-only loot marker mode | CET | active | Opposite direction (markers, not prompt); unusable on macOS |
| Wireless Interactions | 30709 | Remote device interactions decoupled from scanner | CET | v1.0 (2022) | Interactions can fire outside vanilla flow; unusable on macOS |

## Vanilla systems involved

Primary source: full decompiled vanilla scripts (adamsmasher Codeberg dump, cloned locally) + live game files in `~/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077/r6/cache/`. Everything below marked VERIFIED was read directly in source; NativeDB (nativedb.red4ext.com) usable as cross-reference.

### VERIFIED

- **Input is NOT the blocker.** `r6/cache/inputContexts.xml`: context `Vision` (line 87) includes `Aiming` → `Exploration` → `UIExploration` → **`InteractionActions`**, which maps `Choice1`, `Choice1_Hold`, `ChoiceApply`, choice scrolling. The interact key stays mapped while scanning. → An Input Loader `.xml` is unnecessary for this feature.
- **`PlayerVisionModeController.ActivateVisionMode()`** (`cyberpunk/player/playerVisionModeController.swift`, script class extending `IScriptable`, wrappable — Toggle Sprint already wraps it): enters `ScanningController` `gameScanningMode.Heavy`, `VisionModeSystem.EnterMode(Focus)`, sets PSM blackboard `Vision = 1`, `ApplyFocusModeLocomotionRestriction()`, `AimSnap`.
- **`HUDManager.OnScannerUIVisibleChanged(visible)`** (`core/systems/hud/hudManager.swift:1149`, `HUDManager extends NativeHudManager`, `protected cb func` — wrappable): listens to `UI_Scanner.UIVisible` blackboard and does `uiSystem.PushGameContext(UIGameContext.Scanning)` / `PopGameContext(...)`. Sibling cbs `OnQuickHackUIVisibleChanged` / `OnQuickHackUIKeepContextChanged` swap `Scanning`↔`QuickHack` contexts; a vanilla escape hatch `m_uiQuickHackKeepContext` (fed by `UI_QuickSlotsData.quickhackPanelKeepContext`) already suppresses context pushes — the mechanism mod 16238 exploited.
- **Loot prompt UI is a dumb mirror.** `LootingGameController`/`LootingController` (`cyberpunk/UI/interactions/looting.swift`) shows/hides purely from `UIInteractions.LootData` blackboard (`LootData.isActive`); `interactionWidgetGameController` (`interactionsUI.swift`) likewise from `UIInteractions.InteractionChoiceHub`/`VisualizersInfo`. **Neither contains any scanner/focus check.** The writer of `LootData` is native (interaction visualizer system; `EVisualizerType.Loot`).
- Per-context HUD widget visibility is resolved **natively** (e.g. `RequestHealthBarVisibilityUpdate()` is `native func`; `UIGameContext` enum consumed by native ink HUD layer).
- Script APIs available for a manual fallback: `GameObject.EnableInteraction(layer: CName, b: Bool)` (queues `InteractionSetEnableEvent`, e.g. layer `n"Loot"` — `scriptedPuppet.swift:3647` uses it); `TransactionSystem.TransferItem(...)` / `TransferAllItems(source, target)` (native, script-callable); scan target readable from `UI_Scanner.ScannedObject` blackboard and `HUDManager.m_scannerTarget` / `m_lookAtTarget` / `GetCurrentTargetID()`.
- HUD gameplay-side scanner flow: `HUDManager.OnScannerUIVisibleChanged` → UI context; `OnVisionModeChanged` → `ActiveMode.FOCUS`; in FOCUS + scanner target set, `OnPlayerTargetChangedRequest` freezes current HUD target to the scanner target (`hudManager.swift:392`).

### SPECULATED (needs in-game experiment)

- **Where the prompt actually dies:** most likely (a) the native ink HUD entries config hides the interaction/looting widgets while `UIGameContext.Scanning` is on the context stack, and/or (b) the native interaction visualizer stops publishing `LootData`/choice hubs while vision mode is Focus. Not decidable from scripts; a 10-line log-only `.reds` probe (listen to `UIInteractions.LootData` while scanning) would answer (b) immediately.
- Quest **clue** interactions do show a Choice prompt inside scanner vision (gameplay observation), which suggests the interaction pipeline itself keeps running in Focus mode and gating is selective — favorable signal.
- `interactions.json`-style native interaction resources inside `.archive` may carry per-interaction visibility conditions; raw `.archive` replacement is macOS-legal but authoring needs WolvenKit (Windows) and it is unverified that scan-gating lives there. Redmodding wiki has no doc on hudentries-per-UIGameContext.

## Candidate implementation approaches (ranked)

1. **Suppress the `Scanning` UI game context (REDscript, ~20 lines).** `@wrapMethod(HUDManager) OnScannerUIVisibleChanged` (and, for consistency, the two QuickHack cbs) to skip `PushGameContext(UIGameContext.Scanning)` — mirroring the vanilla `m_uiQuickHackKeepContext` pattern. Input already works in scan mode (verified), so if the hidden-widget theory is right, the loot prompt + Pick Up simply reappear. *Viability: fully REDscript-only; cheapest decisive experiment. Risk: scanner detail panel / QHack panel may depend on the Scanning context to display; must keep the push/pop stack balanced.*
2. **Manual loot fallback (REDscript, guaranteed to ship something).** While PSM `Vision == 1`, register an input listener for `Choice1` (pattern verified in `VisionContextDecisions.OnAction`); resolve aim target via `UI_Scanner.ScannedObject` / `HUDManager.GetCurrentTargetID()`; if target is `gameLootContainerBase` / lootable corpse / `ItemDrop`, call `TransactionSystem.TransferAllItems(target, player)` (+ SFX `n"Loot"` via `AudioSystem`). No vanilla tooltip, but real pick-up-while-scanning. All APIs verified script-accessible. *Viability: HIGH; UX approximate (no item tooltip; could push a `ScannerHint` message instead).*
3. **Force the interaction pipeline awake in Focus (REDscript).** On scanner target change during Focus, call `EnableInteraction(n"Loot", true)` / re-trigger `DetermineInteractionState` on the target to force `LootData` publication. Only works if the gate is layer/visualizer deactivation — unverified. *Viability: MEDIUM-LOW until probe from approach 1 clarifies.*
4. **`.archive` data edit** of ink HUD entries or interaction visibility conditions. File type is macOS-legal, but gate location unverified and authoring requires WolvenKit on a Windows box. *Viability: LOW-MEDIUM, last resort.*
5. **Input Loader `.xml`: not applicable** — `Choice1` already exists in the `Vision` context (verified), so there is no missing input to re-add.

## Risks & unknowns

- Biggest unknown: whether native code stops writing `LootData` during Focus. Decides approach 1 vs 2. Cheap to probe with a log-only listener mod.
- Popping/skipping `UIGameContext.Scanning` could desync the context stack with the QuickHack panel swap logic → wrap all three HUDManager cbs together and test QHack panel open/close while scanning.
- Scanner time dilation, `AimSnap`, and the FOCUS target-freeze (`hudManager.swift:392`) may make the "current target" differ from the crosshair loot target; may need to prefer `m_lookAtTarget` over scanner target.
- REDscript wraps of `HUDManager` are version-sensitive; re-verify after CDPR patches (sources here are 2.x-current and match the installed 2.3 build behavior).
- All proposed viable paths are pure `.reds` → macOS toolchain (scc + launch_modded.sh) compatible.

## Sources

- Local decompiled vanilla scripts: https://codeberg.org/adamsmasher/cyberpunk (cloned; files cited: `core/systems/hud/hudManager.swift`, `cyberpunk/UI/interactions/looting.swift`, `cyberpunk/UI/interactions/interactionsUI.swift`, `cyberpunk/UI/interactions/interactionsHub.swift`, `cyberpunk/player/playerVisionModeController.swift`, `cyberpunk/player/psm/inputContextTransitions.swift`, `cyberpunk/puppet/scriptedPuppet.swift`, `core/systems/uiSystem.swift`, `orphans.swift`)
- Live game input contexts: `~/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077/r6/cache/inputContexts.xml`
- Installed mod source: `.../r6/scripts/toggle-sprint-while-scanning/EnableSprintingWhileScanning.reds`
- https://www.nexusmods.com/cyberpunk2077/mods/14646 (Toggle Sprint While Scanning)
- https://www.nexusmods.com/cyberpunk2077/mods/7529 (Toggle walking or jogging while scanning)
- https://www.nexusmods.com/cyberpunk2077/mods/21656 (Hold to Overclock while scanning)
- https://www.nexusmods.com/cyberpunk2077/mods/16238 (REDUNDANT Force Overclock HUD)
- https://www.nexusmods.com/cyberpunk2077/mods/14730 (Looting QoL)
- https://www.nexusmods.com/cyberpunk2077/mods/5202 (Autoloot, CET) / https://www.nexusmods.com/cyberpunk2077/mods/16040 (Completely Non-Manual Looting)
- https://www.nexusmods.com/cyberpunk2077/mods/3486 (Better Loot Markers)
- https://www.nexusmods.com/cyberpunk2077/mods/30709 (Wireless Interactions, CET)
- https://www.nexusmods.com/cyberpunk2077/mods/9671?tab=posts (Scanner Time Dilation Optional — user request for loot-while-scanning)
- https://github.com/rfuzzo/cyberpunk-nexus-script-dump (Nexus .reds mods mirror, searched)
- https://nativedb.red4ext.com (cross-reference DB)
- https://wiki.redmodding.org (no doc found on hudentries-per-UIGameContext)
