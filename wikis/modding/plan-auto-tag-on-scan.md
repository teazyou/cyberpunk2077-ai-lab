# Implementation Plan — Auto-Tag on Hover While Scanning

**Status: VALIDATED — difficulty 2/5, realism YES (pure REDscript).** Planned 2026-07-05; revised same day per user design change: **once-per-entity auto-tag** (seen-list) replaces the manual-untag blocklist. Game v2.3x, macOS Steam.
Research dossier: [scan-mode-auto-tagging.md](scan-mode-auto-tagging.md) — all load-bearing hooks re-verified against `CDPR-Modding-Documentation/Cyberpunk-Scripts` raw sources (`focusModeTagging.script`, `scanner_details.script`, `gameObject.script`) and local `r6/config/inputContexts.xml` (`TagButton` → `Tag_Button`, 5 contexts).

## Feature

In scan mode (focus vision), hovering the scanner over a target auto-tags it — anything vanilla middle-click would tag, no extra curation. **Auto-tag fires only the FIRST time a given entity is ever hovered (session-scoped): one attempt per entity, then never again.** Consequence (by design): if the user middle-click-untags a target, later hovers do NOT re-tag it — falls out automatically from the once-per-entity rule. Manual middle-click tag/untag stays fully vanilla and always works.

## Rating

- **REALISM: YES.** Entire tag decision layer is script-side (`FocusModeTaggingSystem extends ScriptableSystem`); hover event surfaces as scripted callback `scannerDetailsGameController.OnScannedObjectChanged`; tag path reachable from an added method on the system. No CET/RED4ext/Codeware needed. No Input Loader xml needed (no new input action).
- **DIFFICULTY: 2/5** (revision is simpler than the original blocklist design: one wrap instead of two). Single `@wrapMethod` + one `@addField` + two small `@addMethod`s, all on verified 2.x signatures still shipped by live mods (Auto Tag Enemies Jan 2026, Aim Reveals Aug 2025). Residual risk is tuning feel (over-tagging clutter), not feasibility.

## Mod identity

- **Name:** Custom Auto Tag On Scan
- **Slug:** `custom-auto-tag-on-scan`
- **File:** `mods/enabled/r6-scripts/custom-auto-tag-on-scan/AutoTagOnScan.reds` (single `.reds`; portal → `GAME/r6/scripts/custom-auto-tag-on-scan/`)
- House style: `@wrapMethod` only, calls `wrappedMethod` exactly once; `@addField` for state; kebab-case subfolder; user-editable literals in a config block at the top of the `.reds` (Custom Switch Speed pattern).

## User config (ON/OFF toggle)

- **Editable boolean at the very top of the script:** `AutoTagOnScanConfig.EnableAutoTagOnScan()` returns `true` by default; user flips the `true` literal to `false` in the `.reds` (no Mod Settings on macOS — same editable-literal convention as Custom Switch Speed's `SwitchSpeed.Multiplier()`).
- **OFF = 100% vanilla:** the toggle is checked as an early-out guard immediately after the mandatory `wrappedMethod` call, before ANY custom logic — no seen-list reads/writes, no tag attempts, no blackboard/system access. The `@addField`/`@addMethod` declarations still compile (unavoidable with REDscript annotations) but are inert dead code when disabled.
- **Per-feature naming:** the toggle is named `EnableAutoTagOnScan` (not a generic `Enable`) because this mod is slated to ship inside a combined "scanner suite" custom mod with 1-2 sibling scanner features, each carrying its own distinctly named toggle in the shared config class.

## Hooks (exact, verified)

1. **Hover → once-per-entity tag:** `@wrapMethod(scannerDetailsGameController)` on `protected cb func OnScannedObjectChanged(value: EntityID) -> Bool` (scanner_details, fires on blackboard `UI_Scanner.ScannedObject` change, i.e. exactly when the scanner acquires a new target).
2. **State + helpers on the system:** `@addField(FocusModeTaggingSystem) m_autoTagSeen: array<EntityID>` + `@addMethod` `AutoTagAlreadySeen` / `AutoTagTryOnce`.

**Dropped: the `FocusModeTaggingSystem.OnActionWithOwner` (middle-click) wrap.** Under once-per-entity there is nothing for it to do: the seen-list already guarantees no re-tag after a manual untag, and a manual re-tag re-arming nothing is exactly the desired behavior. Removing it keeps the vanilla input handler untouched (fewer moving parts, zero input-path risk).

Private member access (`IsTagged`, `TagObject`, `ResolveFocusClues`) is legal because wraps/added methods compile as members of the class.

Fidelity choice: auto-tag goes through the system's own private `TagObject` + `ResolveFocusClues(true, target)` (via added method `AutoTagTryOnce`) — identical to the vanilla middle-click tag branch, including quest focus-clue cascade, `CanTag()` cybereye/`GameplayRestriction.NoScanning` check and `target.CanBeTagged()` (both re-checked inside `TagObject`, so no extra guards needed). Fallback if the class-wrap path misbehaves: public request path `GameObject.TagObject(target)` (verified static, `gameObject.script:1973`), losing only the clue cascade.

## Full draft — `AutoTagOnScan.reds`

```reds
// Custom Auto Tag On Scan — hover-tags scanner targets in focus mode,
// at most ONCE per entity per session (first hover only). Manual middle-click
// tag/untag stays fully vanilla; a manually untagged target is never re-tagged
// because its one auto-tag attempt is already spent.

// ======================= USER CONFIG =======================
// Toggle named per-feature: this file may later merge into a combined
// "scanner suite" mod where each feature has its own switch.
public abstract class AutoTagOnScanConfig {
  // ON/OFF for auto-tag-on-hover. Set to false for 100% vanilla behavior.
  public static func EnableAutoTagOnScan() -> Bool {
    return true;
  }
}
// ===========================================================

// ---------- session seen-list on the tagging system ----------

@addField(FocusModeTaggingSystem)
let m_autoTagSeen: array<EntityID>;

@addMethod(FocusModeTaggingSystem)
public final func AutoTagAlreadySeen(id: EntityID) -> Bool {
  return ArrayContains(this.m_autoTagSeen, id);
}

// First-and-only auto-tag attempt for this entity. Marks the id as seen
// unconditionally, then mirrors the vanilla middle-click tag branch
// (TagObject re-checks CanTag() and target.CanBeTagged() internally;
// ResolveFocusClues cascades quest clues).
@addMethod(FocusModeTaggingSystem)
public final func AutoTagTryOnce(target: ref<GameObject>) -> Void {
  ArrayPush(this.m_autoTagSeen, target.GetEntityID());
  if !this.IsTagged(target) {
    this.TagObject(target);
    this.ResolveFocusClues(true, target);
  }
}

// ---------- hover hook: scanner acquires a target ----------

@wrapMethod(scannerDetailsGameController)
protected cb func OnScannedObjectChanged(value: EntityID) -> Bool {
  let result: Bool = wrappedMethod(value);
  if !AutoTagOnScanConfig.EnableAutoTagOnScan() {
    return result; // feature OFF -> 100% vanilla, no custom logic runs
  }
  if EntityID.IsDefined(value) {
    let player: ref<GameObject> = this.GetPlayerControlledObject();
    if IsDefined(player) {
      let game: GameInstance = player.GetGame();
      // scanner_details also serves the quickhack panel -> explicit focus-mode gate
      if Equals(HUDManager.GetActiveMode(game), ActiveMode.FOCUS) {
        let target: ref<GameObject> = GameInstance.FindEntityByID(game, value) as GameObject;
        let tagSys: ref<FocusModeTaggingSystem> =
          GameInstance.GetScriptableSystemsContainer(game)
            .Get(n"FocusModeTaggingSystem") as FocusModeTaggingSystem;
        if IsDefined(target) && IsDefined(tagSys) && !tagSys.AutoTagAlreadySeen(value) {
          tagSys.AutoTagTryOnce(target);
        }
      }
    }
  }
  return result;
}
```

## Once-per-entity memory design (seen-list)

- **Storage:** `array<EntityID>` added to `FocusModeTaggingSystem` (a `ScriptableSystem` — one instance per game session).
- **Semantics:** on scanner hover, EntityID not in list → append + one vanilla-path tag attempt; in list → do nothing. Appended **unconditionally** on first hover — even if the attempt is a no-op (target already tagged by ping/aim-reveal) or vanilla refuses it (`CanTag`/`CanBeTagged` false). "One attempt ever" is taken literally; see edge cases for the restricted-scan trade-off.
- **Lifetime:** whole play session; NOT `persistent`, so never written to saves. Quitting to desktop / fresh session resets the list (acceptable per spec).
- **Reset behavior:** no per-entity or global reset (no Mod Settings on macOS, and none needed — manual middle-click tagging always works regardless of the list).
- **Growth:** unbounded within a session but tiny in practice (only entities actually hovered in scan mode; EntityIDs are 8 bytes). No cleanup needed.
- **EntityID reuse:** despawn/respawn of crowd NPCs issues fresh ids → respawned NPC counts as a new entity and gets one fresh auto-tag. Accepted per spec (session-scoped, per-entity-instance).

## Filters / guards

- **Master toggle first:** `AutoTagOnScanConfig.EnableAutoTagOnScan()` early-out right after `wrappedMethod` — OFF means zero custom logic executes (100% vanilla).
- **Scope (decided): exactly what vanilla middle-click would tag** on the hovered scanner target — enemies, devices, loot containers, vehicles, civilians, anything with `CanBeTagged()` while the player `CanTag()`. No extra curation, matching the task default. If clutter proves annoying in play, a follow-up constant-guard (e.g. only `target.IsNPC() || (target as Device) != null`) can be added at the single `AutoTagTryOnce` call site.
- Focus-mode gate: `HUDManager.GetActiveMode(game) == ActiveMode.FOCUS` — required because `scannerDetailsGameController` also drives the quickhack panel (verified: `m_isQuickHackPanelOpened` handling in `scanner_details.script`), and the same blackboard key feeds quickhack target changes.
- Seen-list check before tagging (replaces both the old blocklist check and the `IsTaggedinFocusMode()` short-circuit; the residual already-tagged case is handled inside `AutoTagTryOnce` via `IsTagged`).
- `CanTag()` (cybereye stat + `GameplayRestriction.NoScanning`) and `CanBeTagged()` enforced inside vanilla `TagObject` — no restricted-state tagging (cutscene/quest scan restrictions honored for free).
- Null-safety: `EntityID.IsDefined(value)`, `IsDefined(target)` (entity may be unstreamed), `IsDefined(player)`, `IsDefined(tagSys)`.

## Edge cases & installed-mod interactions

Checked every FILES entry in mod-manager.md; grepped all deployed `.reds` for `OnScannedObjectChanged|FocusModeTaggingSystem|scannerDetailsGameController|HUDManager|TagObject|OnActionWithOwner|ScannedObject` — **no installed mod hooks the wrapped method.** Details:

- **Toggle Sprint While Scanning** (wraps `AimWalkDecisions`, `SprintEvents`, `PlayerVisionModeController`): no overlap. Behavioral synergy only — sprint-scanning sweeps tag faster; harmless.
- **Disappearing Enemy Health Bar Fix** (`@replaceMethod(NameplateVisualsLogicController)`): no overlap; tagged enemies simply show nameplates more.
- **Preem Scanner + Clean Voiceovers** (raw `.archive` scanner cosmetics): no script surface; tag brackets render normally.
- **Custom Switch Speed / Custom XP mods**: wrap unrelated methods (equip transitions, `AddExperience`); no overlap.
- **Hacking Gets Tedious / Quickhacks sort by slot**: quickhack-side only; the focus-mode gate keeps auto-tag out of the quickhack panel path.
- **Restricted-scan trade-off:** hovering an entity while tagging is restricted (no cybereye, `GameplayRestriction.NoScanning`, quest lock) spends its single attempt without tagging — that entity won't auto-tag later. Accepted under "one attempt ever"; manual middle-click still tags it. (If undesired in play: move the `ArrayPush` behind a success check on a replicated `CanTag()`/`CanBeTagged()` test — one-line change, noted for follow-up.)
- **Already-tagged on first hover** (ping/aim-reveal/vanilla): attempt is a no-op, entity marked seen — a later manual untag is respected forever. Consistent with the rule.
- **Native tag expiry** (if the ScanningController times out NPC tags): expired tags are NOT re-applied by hover (attempt spent). Vanilla-feel note, not a correctness issue; manual re-tag works.
- Quest clue groups: cascade preserved via `ResolveFocusClues(true, target)` — same as vanilla tag.
- Save/load mid-session: seen-list survives (system persists across loads within the session); after load, previously hovered ids stay spent for still-spawned entities. Degrades gracefully.
- Vanilla input path completely untouched (no `OnActionWithOwner` wrap) — middle-click tag/untag behavior is byte-for-byte vanilla.

## Verification steps

1. **Compile:** with Steam running, `script/launch_modded.sh` — REDscript compiles all of `r6/scripts/` at launch; any signature drift vs the 2.3x macOS build surfaces as a compile error dialog immediately. (If a "backup corrupted" dialog appears: transient — stop workflow, clean serial `scc -compile`; never clear `r6/cache` or verify files.)
2. **In-game checklist:**
   - Enter scan mode, sweep over an untagged enemy → tag brackets appear without middle-click; scanner details panel unaffected.
   - Sweep over a device (camera/turret) and a loot container → tagged.
   - Middle-click a hovered auto-tagged target → untags (vanilla); sweep away and back → NOT re-tagged (once-per-entity works).
   - Middle-click the same target again → tags (manual always works); untag again → still no auto re-tag on hover.
   - Hover a NEW enemy twice (sweep away/back without touching it) → tagged on first hover only, second hover changes nothing.
   - Exit scan mode; open quickhack panel (Tab) and cycle targets → nothing gets tagged (focus gate works).
   - Scan during a quest scene with focus clues → clue group cascade-tags like vanilla middle-click.
   - Cutscene/restricted area with scanning disabled → no tags, no errors.
   - Save, reload same session → previously hovered targets stay spent (no re-tag on hover) while still spawned.
   - Flip `EnableAutoTagOnScan()` to `false`, relaunch → hover tags nothing anywhere; middle-click tag/untag fully vanilla; flip back to `true` for play.
3. **Log sanity:** no script errors in `r6/logs/redscript_rCURRENT.log` after a play session.
4. **Registry:** on install, add mod-manager.md entry (Gameplay: Custom Auto Tag On Scan, COMPAT ✅ locally authored pure wrap-based `.reds`, URL —, FILES `r6-scripts/custom-auto-tag-on-scan/AutoTagOnScan.reds`) per custom-mod house pattern.
