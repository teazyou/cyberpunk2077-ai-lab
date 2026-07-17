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

## 2026-07-06 — auto-tag narrowed to collectables + Epic quality floor

Scope cut applied in the single classifier `GameObject.ST_AutoTagCategory` (both the sweep and the hover channel inherit it):

- **ENEMY category removed entirely.** The whole alive safe-to-attack puppet branch (IsHostile / IsCharacterCyberpsycho / DoNotTriggerPrevention / prevention-mirror / IsEnemy / CanBeTagged) is gone, along with the separate LOS/any-range enemy sweep `ST_RunEnemySweepOnce`, its `ST_SweepTick` call, and the `AutoTagEnemyRange` config. No NPC/enemy is auto-tagged anymore. The enum collapses to `STAutoTagCategory { None, Other }`.
- **ACCESS-POINT and TURRET categories removed.** The `IsAccessPoint` and `IsTurret` branches are deleted. Only lootable corpses and loot-bearing world objects (containers/shards/items) can classify `Other`.
- **Epic quality floor added.** Both collectable cases are now gated so they tag only when their MAX item quality is ≥ `AutoTagQualityFloor` (default `gamedataQuality.Epic` = Tier 4). Helpers `ST_LootMeetsQualityFloor` (max over `GetItemList`, plus a bare-`ItemObject.GetItemData` fallback) + `ST_QualityTier` (explicit quality→tier switch, NOT `EnumInt`: `gamedataQuality` raw ints are non-monotonic — Epic=2, Rare=9, Invalid=14 — and NOT `RPGManager.ItemQualityEnumToValue`, which collapses EpicPlus/LegendaryPlus/Iconic to 0). EpicPlus/LegendaryPlus/LegendaryPlusPlus/Iconic all pass; Rare/Uncommon/Common/Invalid do not.
- **Side effect (intended):** shards and Common/Uncommon/Rare junk corpses/containers below Epic no longer auto-tag. Below-floor / empty-now stays transient (no seen-list append), so a container that streams its loot in later is re-checked. Floor is user-editable via `AutoTagQualityFloor` (lower to `gamedataQuality.Rare` for Tier 3+).

## 2026-07-11 — entity-list pass: tag enemy-dropped floor weapons

Enemy weapon drops were never auto-tagged because they are invisible to BOTH existing channels (all VERIFIED against a fresh `CDPR-Modding-Documentation/Cyberpunk-Scripts` clone):

- A dropped weapon spawns as a visual `ItemObject` + connected `gameItemDropObject` holding the actual inventory (`cyberpunk/items/item.script:16-17`). Neither carries a TargetingComponent → the frustum sweep (`GetTargetParts`) never returns them.
- Neither publishes `UI_Scanner.ScannedObject` (plain loot never "focuses") → the hover channel never sees them either.
- Classification needed NO change: `gameItemDropObject extends gameLootObject extends GameObject` (`inventoryComponent.script:147/238`), its `IsContainer()` returns `!IsEmpty()` (`inventoryComponent.script:382`) → a loot-bearing drop already passes the collectables whitelist; `CanBeTagged()` defaults true (`gameObject.script:1997`, no loot-class override).

Fix: `ST_RunEntityListSweepOnce` on `HUDManager` — a `GameInstance.GetEntityList` pass (same crash-safe game-thread pattern as the F2 auto-loot channel) sub-gated onto the 0.35 s sweep tick by an accumulator (`m_stEntityListAccum`, cadence `AutoTagEntityListInterval` = 1.0 s, F2's safe envelope). Per entity: cheap distance-reject to `AutoTagSweepRange` (50 m) → `APS_ResolveLootTarget` folds the bare `ItemObject` into its drop (one tag per weapon, no double) → seen-check FIRST (skips the classifier's `GetItemList` on already-tagged ids) → camera-forward dot backstop (same "in front, not behind" semantics as the frustum sweep) → shared `ST_AutoTagCategory` whitelist → `AutoTagTryOnce`. Bonus coverage: standalone containers/shard cases without TargetingComponents in the 50 m sphere now tag too (previously hover-only). Probe extended: `DebugProbeAutoTagSweep` also logs `ST entity-list: entities=N tagged=M`. Validated with serial `scc -compile` (clean).

## 2026-07-12 — quality-less loot (materials / junk / broken weapons) now tags

**Bug (user report):** enemy drops that are crafting **materials** or a **broken weapon** never got a tag marker, while normal weapon/gear drops did.

**Root cause:** `ST_LootMeetsQualityFloor` ended in `bestTier >= floorTier`. Quality-less items carry no usable Quality stat, so `RPGManager.GetItemDataQuality` returns `Random`/`Invalid` and `ST_QualityTier` maps them to the `default` → **tier 0**, which is BELOW the Common floor (tier 1). This was already noted (and accepted as "sensibly not tagged") in the 2026-07-07 refinements entry — it is exactly the class of loot the user wants tagged. `CanBeTagged()` is NOT the culprit: it defaults true on `GameObject` (`gameObject.script:1997`) and only `ScriptedPuppet` overrides it, so the vanilla tag path never rejected these drops.

**Fix:** `ST_LootMeetsQualityFloor` now separates "**has loot**" from "**loot is good enough**":
- Track `hasLoot` while scanning `GetItemList` (defined entries only), with the unchanged bare-`ItemObject.GetItemData()` fallback when the list is empty.
- No loot at all → `false`, still **transient** (no seen-list append; a container that streams loot in later is re-checked).
- `floorTier <= 1` (the default Common floor) → `true` for ANY loot-bearing target, **tier 0 included** → materials, junk and broken/quality-less weapons tag.
- The `bestTier >= floorTier` compare only bites when the user raises `AutoTagQualityFloor` above Common (there, dropping unresolved-quality junk is the intent).

Reach was already fine: enemy floor drops are picked up by the entity-list pass (2026-07-11) — they were being classified and then rejected by the quality gate. Validated with serial `scc -compile` (clean).

## 2026-07-13 — Auto-tag: normal-mode (always-on) + LOS-gated

Two user asks, both implemented: (1) auto-tag now works in NORMAL gameplay, not only while the scanner is up; (2) a tag is applied ONLY when the player has line of sight to the target.

**Always-on arming (scanner gate retired):**
- The sweep loop is now armed once per load from the `PlayerPuppet.OnGameAttached` wrap — the exact pattern the always-on auto-loot loop already uses (player object attaching = game thread, once per load; `m_stSweepArmed` double-arm guard keeps replacer re-attaches idempotent). `HUDManager` is a `ScriptableSystem` (`hudManager.script:162,174`) resolved via `GameObject.GetHudManager()` (`gameObject.script:3183`); the ScriptableSystemsContainer is live during this very event (vanilla queues `PlayerAttachRequest` to it there, `player.script:1170`), so the handle is valid at arm time (IsDefined-guarded anyway).
- The `OnScannerUIVisibleChanged` wrap no longer arms anything — it is a pure Feature-1 (loot-while-scanning) hook again. RETIRED, not kept as a fallback: with the attach-arming reliable, a second arm site is redundant (the guard would make it harmless but dead code).
- `ST_SweepTick` lifecycle reworked: the `!m_uiScannerVisible` stop and the `ActiveMode.FOCUS` gate are GONE (the loop never stops except the static config toggle, and sweeps run in normal mode, scan mode and with the QH panel up alike). Two hardenings ported from `APS_LootLoopTick`: FAULT-PROOF RE-ARM (successor tick scheduled FIRST, before any sweep work — with the scanner-open re-arm gone, a mid-tick fault would otherwise kill the feature for the session) and replacer/braindance tick skip (`GetPlayer()`/`IsReplacer`/`IsBraindanceActive`, loop stays alive).
- `AutoTagFirstTickDelay` (0.1 s) survives as the settle delay between player attach and the first sweep; its old scanner-open FOCUS-race rationale died with the FOCUS gate.

**LOS gate (uniform, all tag channels):**
- `GameInstance.GetTargetingSystem(game).IsVisibleTarget(player, target)` (native import, `targetingSystem.script:119`; same call the auto-pickup worker already runs on these exact loot classes — containers/drops/corpses return sane results, see scanner-suite-refinements.md) is now required before `AutoTagTryOnce` in ALL THREE channels: the frustum sweep (`ST_RunSweepOnce`), the entity-list pass (`ST_RunEntityListSweepOnce`), and the `OnScannedObjectChanged` hover complement. The frustum query itself still enumerates through walls (`TargetingSet.Frustum` does no occlusion test) — occlusion is enforced per candidate at tag time.
- Gate ordering keeps the raycast cheap: classify + seen-check first (they reject almost everything), `IsVisibleTarget` last, only for real candidates. An occluded candidate spends NOTHING (no seen-list append) — it stays eligible and tags on a later tick the moment LOS clears.
- This SUPERSEDES the removed 2026-07-06 enemy category's old LOS special case — the LOS rule is uniform across every tagged class now.
- Known accepted limitation (user spec: LOS-only regardless): `IsVisibleTarget` has documented FALSE NEGATIVES (ragdolled-corpse body-part probes clipping into floor/cover, tiny floor-item volumes, closed container lids — the same ones the auto-loot two-tier design absorbs with its 4 m bubble). Such a target may tag late or only from another angle/up close. No tagged class is structurally LOS-incapable: everything the whitelist can pass (corpses = ScriptedPuppet; containers/shard cases; gameItemDropObject via APS_ResolveLootTarget) goes through the same IsVisibleTarget call the pickup worker already uses successfully on them.

**Config truth after this change:**
- `EnableAutoTag` = true (RENAMED from `EnableAutoTagOnScan` — the old name lied about an always-on loop)
- `AutoTagSweepRange` = 100.0 m, `AutoTagSweepInterval` = 1.0 s, `AutoTagFirstTickDelay` = 0.1 s (after attach), `AutoTagEntityListInterval` = 1.0 s, `AutoTagQualityFloor` = Common, `DebugProbeAutoTagSweep` = false — all unchanged in value.

**Pending in-game tests:** loot tags in normal mode without ever opening the scanner (walk into a loot room and look around); loot behind a wall does NOT tag until LOS clears (then tags automatically); scan mode still tags as before (always-on covers it); hover-tag in scanner still works; a clipped visible corpse tagging late = the known false negative, accepted; replacer (Johnny) and braindance sections tag nothing; long-session stability (loop survives faults thanks to re-arm-first); no worker-thread crash regression (driving / fast-travel / district transitions).

Validated with serial `scc -compile`: "Compilation complete", no new warnings (only the known pre-existing ones from other mods).
