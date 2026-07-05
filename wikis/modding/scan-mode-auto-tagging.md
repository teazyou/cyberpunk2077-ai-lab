# Scan-Mode Auto-Tagging — Feasibility Research

Researched 2026-07-05. Game: Cyberpunk 2077 v2.3x, macOS Steam (REDscript + Input Loader + .archive + engine.ini ONLY; no CET/RED4ext/TweakXL/ArchiveXL/Codeware/Mod Settings).

## Feature

While in scan mode (focus vision), sweeping the crosshair over a taggable enemy/item tags it automatically — no middle-click needed. Bonus: if the user manually untags a target (middle-click on a tagged target), remember it and never auto-re-tag that entity on later hovers (session-scoped memory is acceptable).

**Verdict: no existing mod does exactly this, but every building block is VERIFIED present in pure REDscript.** Feasibility: HIGH.

## Existing mods

| Mod | Nexus id | Behavior | Frameworks | Version status | macOS-usable? |
|---|---|---|---|---|---|
| Auto Tag Enemies | [26670](https://www.nexusmods.com/cyberpunk2077/mods/26670) | Auto-tags enemies that turn hostile / start alerting; auto-untags when they lose track of player or leave combat. Configurable duration (default 300 s). | redscript (required); Mod Settings only for non-default duration | v1.0, updated 05 Jan 2026 (v2.3-era) | YES minus settings menu (defaults hardcoded) |
| Ping Tags Enemies | [9950](https://www.nexusmods.com/cyberpunk2077/mods/9950) | Ping quickhack auto-tags all revealed enemies/access points/cameras/turrets. Source verified (see pipeline below). | redscript + Mod Settings (settings class read via `new TagOnPingSettings()` — works without the menu, defaults apply) | v1.2, Oct 2023 (pre-2.x hooks still valid in 2.3 sources) | YES minus settings menu |
| Aim Reveals (Tags) Enemies | [14742](https://www.nexusmods.com/cyberpunk2077/mods/14742) | Aiming a weapon reveals or tags NPCs/devices in range (TargetingSystem query on `OnEnterAimState`). Source verified. | redscript mandatory; Mod Settings optional | v1.03a, updated 31 Aug 2025 | YES minus settings menu |
| Tag and Hack | [23654](https://www.nexusmods.com/cyberpunk2077/mods/23654) | Aim reveal + tag + quickhack tagged targets through walls until untagged. | redscript + RED4ext + Codeware + ArchiveXL + Mod Settings | v1.1.1, updated 02 Oct 2025 | NO (RED4ext/Codeware) — evidence only |
| Ping Tags Enemies — CET | [14256](https://www.nexusmods.com/cyberpunk2077/mods/14256) | CET/Lua port of 9950. | CET | Apr 2024 | NO — evidence only |

Notable: Ping Tags Enemies' known-issues section states some cameras "will be tagged just by hovering over them in scanning mode" via the game's own reveal path — vanilla already conflates hover-reveal and tag for certain devices, more evidence the hover→tag jump is natural to the engine.

No mod found (Nexus/Google, multiple query shapes) that tags on scanner hover specifically. This would be a novel but small mod.

## Vanilla tagging pipeline (VERIFIED from decompiled 2.x sources)

Source: local clone of `CDPR-Modding-Documentation/Cyberpunk-Scripts` (decompiled vanilla scripts; game's REDmod script dump not shipped in macOS build). Mod sources from `rfuzzo/cyberpunk-nexus-script-dump`.

### The tag system — `FocusModeTaggingSystem` (script class, `core/systems/focusModeTagging.swift`)

`FocusModeTaggingSystem extends ScriptableSystem` — pure script, fully hookable.

- **Middle-click handler (answers Q-b and Q-c):** `protected cb func OnActionWithOwner(action, consumer, owner)` listens for input action `n"TagButton"` (mapped to `Tag_Button` in `r6/config/inputContexts.xml` — verified in local game files). Only acts when `IsPlayerInFocusMode(owner)` (PlayerStateMachine blackboard `Vision == 1`). Target resolution order:
  1. `GameInstance.FindEntityByID(gi, this.GetScannerTargetID())` — scanner's current target,
  2. `TargetingSystem.GetLookAtObject(owner, true, true)`,
  3. `TargetingSystem.GetLookAtObject(owner, false)` (then only taggable if `target.IsObjectRevealed()`).
  Then: `if !this.IsTagged(target) → this.TagObject(target) + ResolveFocusClues(true)`; **`else → this.UntagObject(target) + ResolveFocusClues(false)`** — this else-branch is the ONLY player-initiated untag path → perfect detection point for the untag-memory blocklist.
- **`GetScannerTargetID()`**: reads blackboard `UI_Scanner.ScannedObject` (EntityID) — the scanner's hovered target.
- **`TagObject(target)`** (private): checks `CanTag()` (player has cybereye stat + no `GameplayRestriction.NoScanning`) and `target.CanBeTagged()`, then `VisionModeSystem.GetScanningController().TagObject(target)` (native), sends `RevealObjectEvent` (reason `n"tag"`), refreshes `UI_Scanner.LastTaggedTarget`, notifies HUDManager (`TagStatusNotification`), registers target in `TaggedObjectsList` blackboard.
- **`UntagObject(target)`** (private): mirror of the above via `ScanningController.UntagObject`.
- **Public entry points (answers Q-b, programmatic tag):** `GameObject.TagObject(obj)` / `GameObject.UntagObject(obj)` — public static wrappers (`core/entity/gameObject.swift:1527/1537`) that queue `TagObjectRequest`/`UnTagObjectRequest` to the system; requests are processed by `OnTagObjectRequest`/`OnUnTagObjectRequest`. Used by Ping Tags Enemies and Aim Tags Enemies mods — proven script-callable.
- **Tag state query:** `GameObject.IsTaggedinFocusMode()` (public const, `gameObject.swift:2090`) → `ScanningController.IsTagged(this)`.

### The hover event (answers Q-a)

The native scanning system publishes the hovered target to blackboard `UI_Scanner.ScannedObject`. Scripted listeners (all wrappable):

1. **`scannerDetailsGameController.OnScannedObjectChanged(value: EntityID)`** (`cyberpunk/UI/hud/scanner/scanner_details.swift:179`) — plain script class extending `inkHUDGameController`; fires exactly when the scanner details panel acquires/loses a target (the moment the target frame appears). Controller only lives while scan UI is up → implicit focus-mode gating. **Best hook.**
2. `scannerGameController.OnScannedObjectChanged(val: EntityID)` (`scanner.swift:264`) — native class but the callback is scripted; also wrappable.
3. `HUDManager.OnScannerTargetChanged(value: EntityID)` (`core/systems/hud/hudManager.swift:685`) — global listener on the same blackboard key; also fires for quickhack target changes outside scan mode (`quickHackChangeTarget` time dilation), so needs an explicit `Vision == 1` focus-mode check.

### Answers to the four questions

- (a) Hover event: `UI_Scanner.ScannedObject` blackboard change → `scannerDetailsGameController.OnScannedObjectChanged` / `HUDManager.OnScannerTargetChanged`. VERIFIED.
- (b) Programmatic tag: `GameObject.TagObject(obj)` (static, public, request-based; auto-enforces `CanTag`/`CanBeTagged`). VERIFIED (two shipped mods use it).
- (c) Untag detection: wrap `FocusModeTaggingSystem.OnActionWithOwner` — if in focus mode, `TagButton` just pressed, and resolved target `IsTaggedinFocusMode()` → vanilla is about to untag → record `GetEntityID()`. VERIFIED code path; wrap itself SPECULATED-but-standard (wrapping `protected cb func` on ScriptableSystems is routine REDscript practice).
- (d) Script reachability: the entire decision layer (input handling, tag/untag orchestration, blackboard, UI notify) is script-side. Only the underlying `gameScanningController.TagObject/UntagObject/IsTagged` and the scanner's hover detection are native, and both are already exposed to script exactly where needed. Pure REDscript is sufficient. VERIFIED.

## Candidate implementation approaches (ranked)

### 1. Wrap `scannerDetailsGameController.OnScannedObjectChanged` (RECOMMENDED — pure REDscript)

```reds
@wrapMethod(scannerDetailsGameController)
protected cb func OnScannedObjectChanged(value: EntityID) -> Bool {
  let result = wrappedMethod(value);
  if EntityID.IsDefined(value) {
    let target = GameInstance.FindEntityByID(this.m_player.GetGame(), value) as GameObject;
    let sys = GameInstance.GetScriptableSystemsContainer(this.m_player.GetGame())
        .Get(n"FocusModeTaggingSystem") as FocusModeTaggingSystem;
    if IsDefined(target) && target.CanBeTagged()
        && !target.IsTaggedinFocusMode() && !sys.AutoTag_IsBlocked(value) {
      GameObject.TagObject(target);   // request path: CanTag()/CanBeTagged() re-checked inside
    };
  };
  return result;
}
```
Plus on `FocusModeTaggingSystem`: `@addField` blocklist `array<EntityID>`, `@addMethod AutoTag_IsBlocked/AutoTag_Block/AutoTag_Unblock`, and the untag-capture wrap (below). Viability: HIGH. Fires exactly at frame-acquire; no polling; no per-frame cost.

### 2. Wrap `HUDManager.OnScannerTargetChanged`

Same body, but gate on focus mode via PlayerStateMachine blackboard (`Vision == 1`) since it also fires for quickhack targeting. Use if approach 1's controller lifecycle proves flaky. Viability: HIGH.

### 3. Wrap `ScanningComponent.OnRevealStateChanged` (Ping Tags Enemies pattern)

Tags on reveal events instead of hover; would tag things revealed by any means (ping, optics) unless reason-filtered, and hover-reveal reasons for NPCs are unverified. Viability: MEDIUM — wrong trigger semantics for this feature.

### 4. Polling loop (DelaySystem callback querying `TargetingSystem.GetLookAtObject` while scanning)

Works but inferior: per-tick cost, duplicated target resolution. Viability: MEDIUM. Fallback only.

All four are REDscript-only. None need CET/RED4ext/TweakXL/ArchiveXL/Codeware. No Input Loader xml needed (no new input action; we piggyback on existing events).

## Untag-memory design options

1. **`@addField(FocusModeTaggingSystem) let m_autoTagBlocklist: array<EntityID>` (RECOMMENDED).** ScriptableSystem lives for the whole game session → session-scoped memory for free; not written to saves (fine per spec). Capture:
```reds
@wrapMethod(FocusModeTaggingSystem)
protected cb func OnActionWithOwner(action: ListenerAction, consumer: ListenerActionConsumer, owner: wref<GameObject>) -> Bool {
  if IsDefined(owner) && this.IsPlayerInFocusMode(owner)
      && Equals(ListenerAction.GetName(action), n"TagButton")
      && ListenerAction.IsButtonJustPressed(action) {
    // replicate vanilla target resolution (private helpers accessible inside class wrap)
    let target = ... /* ScannedObject -> GetLookAtObject fallbacks */;
    if IsDefined(target) {
      if this.IsTagged(target) { this.AutoTag_Block(target.GetEntityID()); }   // about to be untagged
      else { this.AutoTag_Unblock(target.GetEntityID()); }                     // manual re-tag lifts the block
    };
  };
  return wrappedMethod(action, consumer, owner);
}
```
   Nice property: the hover hook fires on target *change* only, so the just-untagged, still-hovered target is not instantly re-tagged even before blocklist insertion resolves.
2. Blackboard-based list (mirror vanilla's `TaggedObjectsList` pattern with a custom key) — no custom-blackboard creation from script without Codeware; would have to abuse an existing board. Viability LOW on macOS. Rejected.
3. Persistent memory across saves — would need `persistent let` on a ScriptableSystem (redscript supports persistent fields on ScriptableSystems in principle, but behavior with `@addField` is UNVERIFIED). Out of scope; session memory satisfies the spec.

## Risks & unknowns

- **Over-tagging clutter (main design risk):** `ScannedObject` covers everything scannable — loot, quest clues, vehicles, civilians. `CanBeTagged()` defaults `true` on GameObject. Probably want filters (NPC via `target.IsNPC()`, devices via `IsSensor()/IsTurret()/IsAccessPoint()`, skip friendly attitude) mirroring Ping Tags Enemies' category checks. SPECULATED tuning need.
- **NPC tag expiry:** whether the native `ScanningController` expires NPC tags after a timeout is native-side and UNVERIFIED (Auto Tag Enemies implements its own 300 s duration, hinting vanilla tags on enemies may persist until death/untag; tags are known to survive walls and long ranges). Doesn't affect feasibility, only feel.
- **`ResolveFocusClues` skipped:** the request path (`GameObject.TagObject`) does not resolve linked focus clues (that extra step only runs in the middle-click handler). Quest-linked clue groups won't cascade-tag on hover. Minor; could be replicated inside a class wrap if wanted.
- **EntityID reuse:** blocklist keyed by EntityID; dynamic NPC ids are stable within a session but a despawned/respawned crowd NPC gets a fresh id → block lost. Acceptable (spec: session-scoped). VERIFIED-adjacent (standard engine behavior, not re-proven here).
- **v2.3x source drift:** pipeline read from the CDPR-Modding-Documentation dump (2.x); tiny signature drift possible vs the exact 2.3x macOS build. Mitigation: REDscript compile errors surface immediately at launch via `launch_modded.sh`. LOW risk — Auto Tag Enemies (Jan 2026) and Aim Reveals (Aug 2025) still ship against these same hooks.
- **`scannerDetailsGameController` lifecycle:** exact spawn/despawn timing of the details controller vs the moment of hover is inferred from its blackboard registrations; if it misses the earliest hover frames, fall back to approach 2 (HUDManager). SPECULATED.
- **macOS**: mod would be a single `.reds` file in `mods/enabled/r6-scripts/` — fits the platform constraints exactly; no Mod Settings menu, so thresholds/filters are hardcoded constants.

## Sources

- Vanilla decompiled scripts: https://github.com/CDPR-Modding-Documentation/Cyberpunk-Scripts — files `core/systems/focusModeTagging.swift`, `core/entity/gameObject.swift`, `core/systems/hud/hudManager.swift`, `cyberpunk/UI/hud/scanner/scanner_details.swift`, `cyberpunk/UI/hud/scanner/scanner.swift`, `core/components/scanningComponent.swift`, `cyberpunk/puppet/scriptedPuppet.swift`
- Nexus mod script dump (mod sources verified): https://github.com/rfuzzo/cyberpunk-nexus-script-dump — `mods/14377/.../TagOnPing.reds` (Ping Tags Enemies), `mods/14742/.../AimTagsEnemies.reds` (Aim Reveals)
- Local game files: `r6/config/inputContexts.xml` (`TagButton` → `Tag_Button` mapping)
- Nexus pages (via r.jina.ai): [Auto Tag Enemies 26670](https://www.nexusmods.com/cyberpunk2077/mods/26670), [Ping Tags Enemies 9950](https://www.nexusmods.com/cyberpunk2077/mods/9950), [Aim Reveals (Tags) Enemies 14742](https://www.nexusmods.com/cyberpunk2077/mods/14742), [Tag and Hack 23654](https://www.nexusmods.com/cyberpunk2077/mods/23654), [Ping Tags Enemies CET 14256](https://www.nexusmods.com/cyberpunk2077/mods/14256)
- Reference (not fetched, for follow-up): NativeDB https://nativedb.red4ext.com (class `gameScanningController`), CDPR modding wiki https://wiki.redmodding.org
