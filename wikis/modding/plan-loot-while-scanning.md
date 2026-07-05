# Implementation Plan — Loot While Scanning

**Verdict: VALIDATED — Technical difficulty 3/5** (evaluated 2026-07-05, game v2.3x, macOS Steam).
Research basis: [scan-mode-looting.md](scan-mode-looting.md) — all load-bearing claims re-verified against the local decompiled 2.3x sources and the live `inputContexts.xml` before writing this plan (details in "Verified facts" below).

## Rating

- **REALISM: yes (partial certainty on UX tier).** Two paths, both pure REDscript (macOS-legal):
  - **Path A (primary)** — suppress the `UIGameContext.Scanning` push in `HUDManager` so the native ink HUD layer stops hiding the interaction/looting widgets while the scanner is up. If the native interaction visualizer keeps publishing `UIInteractions.LootData` during Focus (the one unknown), this yields the *vanilla-identical* loot tooltip + Pick Up. Input side is already proven open: `Vision` → `Aiming` → `Exploration` → `UIExploration` → `InteractionActions` (`Choice1` etc.) — verified in the live `inputContexts.xml`.
  - **Path B (fallback, guaranteed shippable)** — `Choice1` input listener while PSM `Vision == 1` + `TransactionSystem.TransferAllItems(target, player)`. Every API verified script-callable in the local decompile. UX approximate: real pickup, no vanilla tooltip.
- **TECHNICAL DIFFICULTY: 3/5.** Path A is ~80 lines but the context-stack compensation must stay balanced across three interacting HUDManager callbacks (scanner/quickhack/keepContext) — subtle, though the vanilla state formula is fully derivable from source (done below). The decisive unknown (native `LootData` publishing during Focus) is cheap to probe (a wrap on the existing `HUDManager.OnLootDataChanged` cb). If A fails, B ships something real but with honest UX degradation (no item tooltip — you loot "blind" or with a HUD notification). Not 2/5 because of the stack-bookkeeping subtlety + unknown; not 4/5 because the fallback is verified end-to-end and the probe is built into the same file.
- Decision rule: difficulty 3 ≤ 3 and realistic → **VALIDATED**.

### Verified facts this plan rests on (re-checked 2026-07-05)

Local decompile at `/private/tmp/claude-501/-Users-teazyou-dev-tmp-claude-cyberpunk/83a55f05-0e36-46b4-a285-563d965dec24/scratchpad/vanilla-scripts/` (adamsmasher dump matching installed 2.3x):

- `core/systems/hud/hudManager.swift:1150` `protected cb func OnScannerUIVisibleChanged(visible: Bool)` — pushes/pops `UIGameContext.Scanning`; early-outs when `!m_uiQuickHackKeepContext && m_uiQuickHackVisible`. Siblings `OnQuickHackUIVisibleChanged` / `OnQuickHackUIKeepContextChanged` swap `Scanning`↔`QuickHack`. Fields `m_uiScannerVisible` (line 75), `m_uiQuickHackVisible` (78), `m_uiQuickHackKeepContext` (81) — private, but `@addMethod`/`@wrapMethod` code is class-scope so it can read them.
- `hudManager.swift:1126/1211` — vanilla already registers `UIInteractions.LootData` listener → `OnLootDataChanged(value: Variant)`: perfect probe hook.
- `cyberpunk/UI/interactions/looting.swift` `LootingGameController` — pure `LootData` blackboard mirror, **zero scanner/Focus checks** (grep-verified).
- `r6/cache/inputContexts.xml` — `Vision`(87)→`Aiming`(75)→`Exploration`(55)→`UIExploration`(732)→`InteractionActions`(767: `Choice1`, `Choice1_Hold`, `ChoiceApply`, scroll). **No Input Loader xml needed.**
- `orphans.swift:18059` `public final native func TransferAllItems(source: ref<GameObject>, target: ref<GameObject>) -> Bool` (TransactionSystem); `scriptedPuppet.swift:3647` `EnableInteraction(n"Loot", ...)`; `hudManager.swift:1307` `GetCurrentTargetID()` (prefers `m_scannerTarget`, falls back to `m_lookAtTarget` — lines 773-777).
- `core/systems/uiSystem.swift:10-27` — `PushGameContext`/`PopGameContext`/`SwapGameContext` are queued events (`QueueEvent`), so ordering within one callback is preserved; compensation push/pop pairs stay balanced.
- **Favorable signal:** `scannerDetailsGameController.RefreshLayout()` (scanner_details decompile) drives the scanner detail panel's visibility from `gameScanningState` + `HUDManager.GetActiveMode(...) == ActiveMode.FOCUS` — script state, **not** `UIGameContext.Scanning`. Suppressing the context should not kill the scanner's own panel. (The native hudentries layer could still surprise us — test item T3.)
- Installed-mod overlap: **none** hooks `HUDManager` context callbacks (grep across `r6/scripts`): Toggle Sprint While Scanning wraps `AimWalkDecisions.EnterCondition` / `SprintEvents.OnEnter` / `PlayerVisionModeController.ActivateVisionMode`; DALC wraps `LootingController` + own input listener; no collisions.

## Mod identity

- **Name:** Custom Loot While Scanning
- **Slug:** `custom-loot-while-scanning`
- **File:** `mods/enabled/r6-scripts/custom-loot-while-scanning/LootWhileScanning.reds` (= `GAME/r6/scripts/custom-loot-while-scanning/LootWhileScanning.reds`)
- One file, one kebab-case subfolder, pure `@wrapMethod`/`@addMethod`/`@addField` — house style (Custom Switch Speed pattern). May later merge into a combined "scanner suite" custom mod with sibling features (auto-tag-on-hover, auto-pickup); every toggle is therefore **feature-distinctly named** (`EnableLootWhileScanning`, not `Enable`).

## Strategy

**Ship Path A with the probe built in; Path B is a documented alternate kept in this plan (not deployed) until/unless A's unknown resolves negative.**

1. Deploy Path A (context suppression) + the `DebugProbe` wrap (off by default; flip one literal to run the decisive experiment).
2. In-game test: if loot prompt appears while scanning → done, vanilla-identical UX.
3. If not: flip `DebugProbeLootWhileScanning()` to `true`, scan a loot pile, read HUD activity-log probe messages:
   - **No `LootData` events while scanning** → native visualizer stops publishing in Focus → Path A dead. Replace the HUDManager section with the Path B listener (sketch below), keep the same file/slug/toggle.
   - **`LootData` active but no widget** → gate is elsewhere (native hudentries per-context or `LootingGameController` lifecycle) → try Path A′: also wrap `LootingGameController` show-path, else fall back to B.
4. **Kill-switch:** `EnableLootWhileScanning()` → `false` = 100% vanilla (every hook early-outs into plain `wrappedMethod`), no uninstall needed.

### Why suppressing the context is safe (state-machine compensation)

Vanilla invariant, derived from the three callbacks: after any of them runs,
`Scanning is on the context stack ⇔ m_uiScannerVisible && (!m_uiQuickHackVisible || m_uiQuickHackKeepContext)`.

The mod maintains: *actual stack = vanilla stack minus Scanning*. Around **each** wrapped callback: (1) if we had removed Scanning, push it back first (restore the exact pre-state vanilla expects, so its push/pop/swap logic never operates on a desynced stack); (2) run `wrappedMethod` exactly once; (3) recompute the invariant — if vanilla now believes Scanning is on the stack, pop it and remember. Stack stays balanced in every scenario:

| Scenario | Restore | Vanilla does | Suppress after |
|---|---|---|---|
| Open scanner | — (not suppressed) | Push Scanning | Pop Scanning ✔ |
| Open QH panel while scanning | Push Scanning back | Swap Scanning→QuickHack | formula false → nothing ✔ |
| Close QH panel while scanning | — | Swap QuickHack→Scanning | Pop Scanning ✔ |
| Close scanner | Push Scanning back | Pop Scanning | formula false → nothing ✔ |
| keepContext toggle (Overclock) | same pattern via third wrap | swap branches | formula handles ✔ |

## Full `.reds` draft (Path A + probe)

```swift
// =============================================================================
// Custom Loot While Scanning — locally-authored custom mod (no Nexus source)
// Purpose: show the normal loot prompt (item tooltip + Pick Up) and allow
//          pickup while the scanner is up, as when not scanning. Vanilla
//          hides interaction/looting HUD widgets by pushing
//          UIGameContext.Scanning; input (Choice1) is ALREADY live in scan
//          mode (Vision input context includes InteractionActions), so this
//          mod only keeps UIGameContext.Scanning OFF the UI context stack
//          while preserving vanilla's own bookkeeping (see invariant below).
// Wraps:   HUDManager.OnScannerUIVisibleChanged      (restore/delegate/suppress)
//          HUDManager.OnQuickHackUIVisibleChanged    (restore/delegate/suppress)
//          HUDManager.OnQuickHackUIKeepContextChanged(restore/delegate/suppress)
//          HUDManager.OnLootDataChanged              (debug probe only)
// Safety:  each wrap calls wrappedMethod exactly once; vanilla state fields
//          are never written; the context stack is kept balanced (actual
//          stack == vanilla stack minus Scanning). Master toggle below
//          restores 100% vanilla behavior.
// =============================================================================
module LootWhileScanning

public class LWSConfig {

  // ===========================================================================
  // MASTER TOGGLE — set to false for 100% vanilla behavior (all hooks
  // early-out before any custom logic). Distinctly named so sibling scanner
  // features can live alongside it in a future combined scanner-suite mod.
  // ===========================================================================
  public final static func EnableLootWhileScanning() -> Bool {
    return true;
  }

  // Diagnostic probe: when true, prints a HUD activity-log line every time the
  // native interaction visualizer publishes LootData while the scanner is up.
  // Used ONCE to resolve the "does native publish LootData during Focus?"
  // unknown (see plan). Keep false for normal play.
  public final static func DebugProbeLootWhileScanning() -> Bool {
    return false;
  }
}

// True while WE have taken UIGameContext.Scanning off the stack even though
// vanilla bookkeeping believes it is on. Session-transient (not saved).
@addField(HUDManager)
let m_lwsScanningSuppressed: Bool;

// Restore vanilla's expected stack before letting a vanilla callback run.
@addMethod(HUDManager)
private final func LWS_RestoreScanningContext() -> Void {
  let uiSystem: ref<UISystem> = GameInstance.GetUISystem(this.GetGameInstance());
  if this.m_lwsScanningSuppressed && IsDefined(uiSystem) {
    uiSystem.PushGameContext(UIGameContext.Scanning);
    this.m_lwsScanningSuppressed = false;
  };
}

// After the vanilla callback ran: if vanilla now believes Scanning is on the
// stack (invariant derived from hudManager.swift: scanner UI visible AND the
// quickhack panel is not holding the context), take it off and remember.
@addMethod(HUDManager)
private final func LWS_SuppressScanningContext() -> Void {
  let uiSystem: ref<UISystem> = GameInstance.GetUISystem(this.GetGameInstance());
  let vanillaHasScanning: Bool = this.m_uiScannerVisible
    && (!this.m_uiQuickHackVisible || this.m_uiQuickHackKeepContext);
  if vanillaHasScanning && !this.m_lwsScanningSuppressed && IsDefined(uiSystem) {
    uiSystem.PopGameContext(UIGameContext.Scanning);
    this.m_lwsScanningSuppressed = true;
  };
}

@wrapMethod(HUDManager)
protected cb func OnScannerUIVisibleChanged(visible: Bool) -> Bool {
  if !LWSConfig.EnableLootWhileScanning() {
    return wrappedMethod(visible);
  };
  this.LWS_RestoreScanningContext();
  let result: Bool = wrappedMethod(visible);
  this.LWS_SuppressScanningContext();
  return result;
}

@wrapMethod(HUDManager)
protected cb func OnQuickHackUIVisibleChanged(visible: Bool) -> Bool {
  if !LWSConfig.EnableLootWhileScanning() {
    return wrappedMethod(visible);
  };
  this.LWS_RestoreScanningContext();
  let result: Bool = wrappedMethod(visible);
  this.LWS_SuppressScanningContext();
  return result;
}

@wrapMethod(HUDManager)
protected cb func OnQuickHackUIKeepContextChanged(visible: Bool) -> Bool {
  if !LWSConfig.EnableLootWhileScanning() {
    return wrappedMethod(visible);
  };
  this.LWS_RestoreScanningContext();
  let result: Bool = wrappedMethod(visible);
  this.LWS_SuppressScanningContext();
  return result;
}

// Decisive log-probe for the native-LootData unknown (vanilla already routes
// UIInteractions.LootData into this cb — hudManager.swift:1126/1211).
@wrapMethod(HUDManager)
protected cb func OnLootDataChanged(value: Variant) -> Bool {
  let result: Bool = wrappedMethod(value);
  if LWSConfig.EnableLootWhileScanning()
      && LWSConfig.DebugProbeLootWhileScanning()
      && this.m_uiScannerVisible {
    let data: LootData = FromVariant<LootData>(value);
    GameInstance.GetActivityLogSystem(this.GetGameInstance())
      .AddLog("LWS probe: LootData while scanning, isActive=" + ToString(data.isActive));
  };
  return result;
}
```

## Path B — documented alternate (deploy ONLY if the probe kills Path A)

Same file/slug/toggle; replace the three context wraps with an input listener. All APIs verified in local decompile; listener-object pattern verified in installed Street Vendors (`street_vendors.reds:92`).

```swift
// ALTERNATE: manual pickup on Choice1 while scanning (no vanilla tooltip).
public class LWSLootListener {
  private let m_player: wref<PlayerPuppet>;
  public final func Init(player: ref<PlayerPuppet>) -> Void { this.m_player = player; }

  protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
    if !LWSConfig.EnableLootWhileScanning() { return true; };
    if !Equals(ListenerAction.GetName(action), n"Choice1")
        || !ListenerAction.IsButtonJustPressed(action) { return true; };
    let player: ref<PlayerPuppet> = this.m_player;
    if !IsDefined(player) { return true; };
    let game: GameInstance = player.GetGame();
    // Gate 1: only while scanner vision is up (PSM Vision == 1).
    let psm: ref<IBlackboard> = GameInstance.GetBlackboardSystem(game)
      .GetLocalInstanced(player.GetEntityID(), GetAllBlackboardDefs().PlayerStateMachine);
    if psm.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Vision) != 1 { return true; };
    // Gate 2: never double-trigger — if the vanilla loot prompt is live
    // (LootData.isActive), vanilla Choice1 handling already owns this press.
    let lootData: LootData = FromVariant<LootData>(
      GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UIInteractions)
        .GetVariant(GetAllBlackboardDefs().UIInteractions.LootData));
    if lootData.isActive { return true; };
    // Resolve crosshair target: HUDManager prefers m_scannerTarget in FOCUS,
    // falls back to m_lookAtTarget (hudManager.swift:773-777).
    let targetID: EntityID = player.GetHudManager().GetCurrentTargetID();
    if !EntityID.IsDefined(targetID) { return true; };
    let obj: ref<GameObject> = GameInstance.FindEntityByID(game, targetID) as GameObject;
    if !IsDefined(obj) { return true; };
    // Range guard: vanilla-like interaction distance, no looting through walls
    // from across the street.
    if Vector4.Distance(player.GetWorldPosition(), obj.GetWorldPosition()) > 3.5 { return true; };
    // Lootable classes: containers, dropped items, defeated puppets.
    let puppet: ref<ScriptedPuppet> = obj as ScriptedPuppet;
    let isLootablePuppet: Bool = IsDefined(puppet) && !ScriptedPuppet.IsActive(obj);
    if (obj as gameLootContainerBase) == null && (obj as ItemDrop) == null && !isLootablePuppet {
      return true;
    };
    if GameInstance.GetTransactionSystem(game).TransferAllItems(obj, player) {
      GameInstance.GetAudioSystem(game).Play(n"ui_menu_item_generic_pickup");
    };
    return true;
  }
}

@addField(PlayerPuppet)
let m_lwsLootListener: ref<LWSLootListener>;

@wrapMethod(PlayerPuppet)
protected cb func OnGameAttached() -> Bool {
  let result: Bool = wrappedMethod();
  if LWSConfig.EnableLootWhileScanning() && !IsDefined(this.m_lwsLootListener) {
    this.m_lwsLootListener = new LWSLootListener();
    this.m_lwsLootListener.Init(this);
    this.RegisterInputListener(this.m_lwsLootListener, n"Choice1");
  };
  return result;
}
```

Path B caveats (accept before deploying): takes *everything* (`TransferAllItems`, no per-item choice), no tooltip, bypasses container-open animation/locks — check quest-flagged containers behave (skip anything with active quest markers if testing shows issues).

## Guards

- **Quickhack panel during scan:** the compensation restores Scanning before every quickhack callback, so vanilla's `SwapGameContext` branches always see the stack they expect; `QuickHack` context pushes/pops are untouched. Test T4 verifies.
- **No double-triggered interactions:** Path A adds zero input handling — `Choice1` was already mapped in the Vision context in vanilla; the only change is widget visibility. Path B explicitly early-outs when `LootData.isActive` (vanilla owns the press).
- **Tagging keeps working:** middle-click tagging is `TagButton` in the `Aiming`/`ScannerFocus` *input* contexts — input contexts are independent of the `UIGameContext` stack; untouched. Test T5.
- **Scanner panel/functions:** `scannerDetailsGameController` visibility is driven by `gameScanningState` + `ActiveMode.FOCUS` (script state), not the Scanning UI context — should survive suppression. Test T3 confirms (this is the main Path A UX risk besides the LootData unknown).
- **Vanilla-off guarantee:** every hook's first statement checks `EnableLootWhileScanning()`; false → plain `wrappedMethod` passthrough, no field writes, no context ops.
- **Stack hygiene:** `m_lwsScanningSuppressed` is transient (@addField, not persisted); on session load callbacks re-register and the field starts false — consistent with a fresh context stack.

## Edge cases

- **Vanilla early-outs** (`uiSystem == null`, `visible` unchanged): restore-then-suppress around a no-op wrapped call nets to push+pop of the same context in one queue batch — balanced, harmless.
- **HUD side effect (by design of Path A):** with `Scanning` off the context stack, HUD widgets that natively hide during scanning (minimap, quest tracker, healthbar…) will likely stay visible while scanning. This is the price of Path A; it's cosmetically *more* HUD, not less. If unacceptable → Path B. Note: mod 16238 shipped exactly this class of behavior on purpose.
- **Overclock keepContext flow** (base game keeps QH panel during scan): third wrap covers it; formula validated for keepContext toggling both directions.
- **Loot at scanner-frozen target:** in FOCUS with a scanner target locked, `GetCurrentTargetID()` may differ from crosshair (`hudManager.swift:392` freeze). Path A unaffected (native visualizer tracks the real look-at). Path B: if pickup grabs the wrong entity, switch the resolve to a raycast/`m_lookAtTarget` preference — noted in sketch.
- **Quest clues:** clue Choice prompts already display in scan mode; context suppression must not double them — covered by T6.

## Installed-mod interaction check (mod-manager.md)

| Mod | Hooks | Interaction |
|---|---|---|
| Toggle Sprint While Scanning | `AimWalkDecisions.EnterCondition`, `SprintEvents.OnEnter`, `PlayerVisionModeController.ActivateVisionMode` | **No overlap** (different classes/methods). Complementary: sprint + loot while scanning. |
| Disassemble As Looting Choice | `LootingController` wraps + `ChoiceDisassemble_Hold` listener | **No method overlap.** If Path A works, the DALC disassemble choice appears in the scan-mode loot prompt too. Caveat: DALC's custom action may not be mapped inside the `Vision` input context → its hotkey might not respond during scan (cosmetic; verify in T7, optionally extend its input xml later). |
| Preem Scanner (.archive) | scanner ink widget restyle | Independent of UI context stack; verify styling intact (T3). |
| Disappearing Enemy Health Bar Fix | look-at healthbar | With Scanning context suppressed, enemy healthbars may now show during scan — benign, consistent with the mod's intent. |
| Clean Voiceovers / Nova LUT / HD Reworked / NPCs Gone Wild | audio/visual archives | No interaction. |
| Custom XP / Switch Speed mods | `PlayerDevelopmentData.AddExperience`, equip transitions | No overlap. Path B would add a `PlayerPuppet.OnGameAttached` wrap — Custom Switch Speed also wraps it; wraps chain, both call `wrappedMethod` once → safe. |

## Verification

**Compile:** deploy the file → run `script/launch_modded.sh` (Steam running) → scc compiles all `r6/scripts` recursively; failure = compile error dialog (fix before testing). Remember REDscript "backup corrupted" is transient — clean serial recompile, never clear `r6/cache`.

**In-game checklist:**
- T1 *(decisive)*: scan mode ON, crosshair on ground loot (weapon drop, container, defeated enemy) → vanilla tooltip + Pick Up appears; F picks up; item lands in inventory.
- T2: same spot, scanner OFF → looting behaves exactly vanilla (no regressions when the feature is idle).
- T3: scanner detail panel still appears on NPCs/devices (data/hacking tabs switch); Preem Scanner styling intact.
- T4: open + close quickhack panel while scanning (both orders: QH first / scanner first); repeat 5×; then close scanner — no stuck HUD state, no missing crosshair, quickhack list populates every time. Also once during Overclock (keepContext path).
- T5: middle-click tagging while scanning still tags; zoom in/out still works.
- T6: scan a quest clue → clue choice prompt appears exactly once, confirm works.
- T7: with loot prompt visible during scan, DALC disassemble hold-choice listed; test its hotkey (may be inert in Vision context — record result).
- T8 *(probe, only if T1 fails)*: set `DebugProbeLootWhileScanning() = true`, recompile, scan at loot: HUD activity-log lines present → gate is widget-side (try Path A′ / investigate); absent → native stops publishing `LootData` in Focus → swap in Path B section, retest T1 (expect pickup w/o tooltip), then remove probe flag.
- T9 (kill-switch): set `EnableLootWhileScanning() = false`, recompile → scan-mode looting suppressed again, everything vanilla.

**Registry:** on install add a `### Gameplay: Custom Loot While Scanning` entry to mod-manager.md (COMPAT ✅ REDscript only, locally authored; FILES `r6-scripts/custom-loot-while-scanning/LootWhileScanning.reds`; NOTE which path shipped + probe outcome).
