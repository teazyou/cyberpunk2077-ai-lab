# Auto-Tag Investigation (2026-07-14)

Single-agent deep investigation (fable, max effort) into two reported symptoms of the Custom Scanner Suite auto-tag feature:
1. tagging appears to work only in scan mode;
2. it does not tag everything it should (notably: unbreached **access points** are not tagged).

All vanilla APIs below were verified against a fresh clone of `CDPR-Modding-Documentation/Cyberpunk-Scripts` (v2.3 decompile). Note: the repos `WolvenKit/Cyberpunk-Scripts` and `WolvenKit/CDPR-Modding-Documentation` are 404 — the correct repo is `CDPR-Modding-Documentation/Cyberpunk-Scripts`.

---

## 1. Symptom 1 — NOT a game limitation

Tagging is provably **mode-independent** in vanilla. Evidence:

- **The tag write path has no focus gate.** `FocusModeTaggingSystem.TagObject` (`core/systems/focusModeTagging.script:144-155`) checks only `CanTag()` (HasCybereye stat + no `GameplayRestriction.NoScanning`, `:254-263`) and `target.CanBeTagged()`. The only focus-mode check in the whole system is in the middle-click input handler `OnActionWithOwner` (`:269`, `IsPlayerInFocusMode`) — the **UI trigger** is focus-gated, the **system** is not.
- **Vanilla itself tags outside focus mode.** A friendly-hacked surveillance camera auto-tags aggressive enemies during normal gameplay: `surveillanceCamera.script:184-190` and `sensorDevice.script:1271-1273` call `GameObject.TagObject(...)` (`gameObject.script:1973-1983`) with no vision-mode condition. The engine also re-tags streamed-in entities at `OnPostInitialize` (`gameObject.script:470-479`).
- **Markers render and persist outside focus, by design.** `iconsModule.script:8` keeps a tagged actor's icons on in EVERY mode (`mode == FOCUS || IsPulseActive() || IsRevealed() || IsTagged()`). The through-wall outline persists because `TagObject` sends `RevealObjectEvent(reveal=true, reason='tag', lifetime=0 → permanent)` (`focusModeTagging.script:151, 208-215`) → `VisionModeComponent.OnRevealObject` standing reveal (`visionModeComponent.script:1058-1102`); `highlightModule.script:39-52` keeps the highlight on outside FOCUS for revealed actors.
- **Nothing tears tags down on focus exit.** Zero script callers of `UntagAll`/`RequestUntagAll` in the entire dump. Tag lifetime = until manually untagged or entity despawn.

**The mod's architecture is already correct**: both sweep channels are armed once per load from the `PlayerPuppet.OnGameAttached` wrap (`ScannerSuite.reds:1901-1922` → `ST_ArmSweep` → self-re-arming `DelaySystem` loop `ST_SweepTick`). Only the *hover* channel is deliberately FOCUS-gated (`:2363`), because it depends on `UI_Scanner.ScannedObject`, which only the scanner publishes.

**Why it still looks scan-only** (ranked):
1. **Stale build** — the always-on rework was only `scc -compile`-validated; all in-game tests are still PENDING. REDscript edits take effect only after a `launch_modded.sh` relaunch.
2. **Perception artifact** — in FOCUS mode the HUD turns icons on for every processed actor regardless of tags (first disjunct of `iconsModule.script:8`), and the hover channel tags instantly. So scan mode always "works"; outside focus only what the sweeps actually landed shows, and the sweeps under-deliver (§2), so normal mode looks dead.
3. **Visual-less subset** — an object that is not a registered HUD actor (`ShouldRegisterToHUD`, `gameObject.script:517-524`; the loot override needs a template `vision` component, `lootContainers.script:611-616`) gets a state-only tag: no icon in ANY mode.

---

## 2. Symptom 2 — under-tagging root causes, ranked

1. **The uniform LOS gate eats a permanent class of candidates.** All three channels require `TargetingSystem.IsVisibleTarget` (`ScannerSuite.reds:1404, :1525, :2388`). The file itself documents this call's FALSE NEGATIVES (ragdolled-corpse probes clipping into floor/cover, tiny floor-item volumes, closed container lids). The **pickup** path absorbs them with a no-LOS inner bubble; the **tag** path has no equivalent, so a false-negative candidate is re-refused every sweep, forever, at any distance.
2. **Vanilla refuses tags on crowd/civilian corpses.** `ScriptedPuppet.CanBeTagged()` (`scriptedPuppet.script:2134-2153`): `IsCrowd() || IsCharacterCivilian()` → false (plus friendly and Cerberus). Every lootable civilian/crowd corpse passes our filters, then is refused by vanilla forever. Hard constraint, not a mod bug.
3. **The forward-hemisphere gate halves the "360" entity-list pass.** Both channels require `Vector4.Dot(camFwd, targetPos − camPos) > 0` (`:1383`, `:1518`). Nothing behind the camera ever tags until faced.
4. **Content-cached class gates + async loot resolution.** The corpse lane needs `ScriptedPuppet.IsContainer()` (cached `m_lootQuality`, `scriptedPuppet.script:4687-4697`); the container lane needs native `!IsEmpty()` behind a lazy `wasLootInitalized` (`lootContainers.script:505, 748`). Mostly latency, but a container whose native loot init defers until interaction never tags at range.
5. **Spec-narrowed categories.** Alive enemies removed (`:1000-1009`); Defense sensors tag only in combat and untag at combat exit; breached access points skipped. User spec, not defect — but they read as "should tag but doesn't".
6. **`m_autoTagSeen` has no FIFO cap** (pushes at `:739`/`:746`). EntityID recycling — the exact bug class capped at 4096 for `m_apsAttempted` (`:1582-1589`) — will falsely mark fresh entities as seen in long sessions.
7. **Streaming envelope ≪ 100 m sweep range.** Both channels only see spawned entities; the configured range promises more than streaming delivers, especially in interiors.
8. **`TargetingSet.Frustum` semantics unverified** — the enum exists (`targetingSearchFilter.script:44`) but has zero vanilla callers. Low residual impact (the entity-list pass masks it).

---

## 3. Recommended fixes

**Symptom 1**
- Relaunch via `launch_modded.sh` to guarantee the always-on build is what runs, then one session with `DebugProbeAutoTagSweep=true` in NORMAL mode. Non-zero `parts=`/`entities=` proves the loops run outside the scanner; the bucket split (`losRej` / `refused` / `tagged`) identifies which §2 cause dominates.
- For instant tagging outside the scanner (parity with the hover feel): add a cursor-tag step to the EXISTING always-on loot loop via `GetLookAtObject` (`targetingSystem.script:93`, LOS form precedented at `focusModeTagging.script:281`) feeding `AutoTagTryOnce`. No new hooks, no new loops.

**Symptom 2** (impact order)
- Mirror the pickup path's two-tier LOS on the tag path (small no-LOS radius absorbing the documented false negatives), **or** drop the tag-side LOS gate entirely for collectables (restoring the "information through walls is the scanner fantasy" asymmetry that was the standing verdict before 2026-07-13). Either removes the dominant silent under-tagger.
- Decide the civilian-corpse question: spend the seen entry on `CanBeTagged()==false` puppets (stops infinite futile retries — they can NEVER tag) or accept and document. Do **not** try to bypass `CanBeTagged`; vanilla re-checks it inside `TagObject`.
- Drop (or widen to a cosine) the forward-dot gate on the ENTITY-LIST pass only; keep it on the frustum channel.
- FIFO-cap `m_autoTagSeen` (mirror the 4096 pattern).
- Category scope (enemies / out-of-combat sensors / breached APs) is user spec — re-widen deliberately if wanted. Vanilla precedent exists for alive-enemy tagging (the hacked-camera path).

**Hard rules / risks** — all changes stay inside the two existing game-thread `DelayCallback` loops and the FOCUS hover wrap. NEVER reintroduce a per-arbitrary-entity `GameObject.OnGameAttached` (or any streaming/attach) hook: redDispatcher worker threads + shared REDscript array mutation = the confirmed heap-corruption crash (see `scanner-suite-crash-analysis.md`, commit `cbf1dd9`). Removing LOS raycasts only ever reduces per-tick cost.

---

## 4. Open questions / not verified

- **Native synchronous readback**: whether `ScanningController.TagObject` → `IsTagged` reflects immediately (`scanningController.script:6,9` are import signatures only). If deferred, tags never spend (benign — retries) and the probe's `refused` bucket over-counts.
- **Native tag expiry**: whether the registry times NPC tags out is native-side. (The Auto Tag Enemies mod ships its own 300 s timer, suggesting vanilla persists indefinitely.)
- **Which loot-container templates carry a `vision` component / register as HUD actors** — determines whether a tagged crate displays ANY marker. Data-side; needs WolvenKit template inspection or in-game observation.
- **Native lazy loot-init timing** (`wasLootInitalized`) for distant containers.
- **Whether the game was relaunched after the 2026-07-13/14 edits** — the stale-build hypothesis for symptom 1 is only resolvable by the user.
- **`TargetingSet.Frustum` runtime behavior and any `GetEntityList` size cap** — both answerable in one probe session.
