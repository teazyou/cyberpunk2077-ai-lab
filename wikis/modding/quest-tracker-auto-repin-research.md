# Quest Tracker Auto-Repin to Main Quest — research dossier

**Goal (user request):** after finishing a side quest / gig / NCPD scanner / contract, the game auto-switches the tracked (pinned) objective back to a **main quest** (HUD tracker + minimap waypoint jump to main story). User wants to PREVENT this auto-switch — keep the tracker on whatever was pinned, or on nothing.

**Status:** ✅ SHIPPED 2026-07-15 as custom REDscript mod **No Main Quest Auto-Repin** (`r6-scripts/no-main-quest-auto-repin/NoMainQuestAutoRepin.reds`; registered in mod-manager.md, STATE=ENABLED, scc -compile clean). Approach A (reactive Tracked-listener counter) with the completed-non-main→main discriminator below. User decisions applied: go blank (no restore), leave Fixers'-Reward vanilla, apply everywhere, NCPD/contracts untouched. Feasibility was MEDIUM (no clean pre-emptive native seam; reactive counter). PENDING in-game verification (user runs the game) — see §5.

**Constraint honored:** every class/method/enum below grep-verified in game v2.3 sources — no predicted APIs. Source of truth: https://github.com/CDPR-Modding-Documentation/Cyberpunk-Scripts (fresh clone, session scratchpad).

---

## 1. Existing-mod verdict

**Exact-fit mod exists but is macOS-INCOMPATIBLE.**

- **Untrack Quest Ultimate - No Main Quest re-tracking - No leftovers** — https://www.nexusmods.com/cyberpunk2077/mods/6328
  - Has precisely the wanted feature: **"Main Quest re-tracking preventer"** (prevents the game auto-re-tracking the main quest after you untracked it; on by default since v3.4.0) + **"Fixers' Reward quests autotracking preventer"** (stops auto-switching tracking to incoming Fixer reward quests during gameplay).
  - **REQUIRES Cyber Engine Tweaks (CET)** (mod 107) → **❌ macOS** per the vault compat rule (CET is a Windows RED4ext-class scripting platform, not available in the mac REDscript toolchain). Appears in CET overlay as "QuestTrackingToggle."
  - Verdict: cannot install on macOS.

Other candidates examined (none prevent the auto-switch on macOS):
- **Untrack Quest or Job… (Disable Tracking)** (mod 2209) — manual button to fade the tracker; menus re-enable it. Not an auto-repin blocker.
- **Simple untrack quest** (mod 5177, Angelore) — REDscript, **already installed in this vault**. Manual right-click untrack only; users report the game still auto-tracks main after gigs. Does NOT block the auto-switch.
- **Track What You Want – Have Only One Map Marker** (mod 4110) — REDscript, **already installed**. Hides other map markers/routes incl. main quest and allows zero markers. Mitigates the MAP clutter but is marker-visibility, not the tracked journal entry — the HUD tracker objective still auto-repins.
- **Quest Untracker** (mod 3154) — obsolete since game 2.0.

Conclusion: **no macOS-compatible (REDscript/.archive/.xml/.ini) mod prevents the tracker auto-switch.** → custom REDscript feasibility below.

---

## 2. Vanilla mechanism (v2.3 sources, file:line)

### Tracking API (native, on JournalManager)
`scripts/core/systems/journalManager.script`:
- `GetTrackedEntry() : weak<JournalEntry>` — :418
- `IsEntryTracked(entry) : Bool` — :419
- `TrackEntry(entry)` — :420  (sets the tracked entry)
- `UntrackEntry()` — :422  (clears tracking → nothing tracked)
- `GetQuestType(entry) : gameJournalQuestType` — :432
- `GetParentEntry(childEntry) : weak<JournalEntry>` — :409  (tracked objective → its containing quest)
- `RegisterScriptCallback(obj, functionName, type : gameJournalListenerType)` — :437 / `UnregisterScriptCallback` — :438
- `enum gameJournalQuestType { MainQuest, … }` — :140-142; per-quest `JournalQuest.GetType()` — :157.

### Who decides the auto-repin
- **The decision is NATIVE.** Every script-side caller of `TrackEntry(` is UI/user-initiated, NOT an on-completion auto-switch:
  - `journal_wrapper.script:139` `SetTracking()` (menu), `questLog.script:599` (quest log UI), `worldMap.script:1010` (map click), `notificationActions.script:23/46` (`TrackQuestNotificationAction` = a user "Track" button), `messagePopup.script:485/490` (`TrackQuest()` = popup button).
  - There is **no** scripted `OnQuestCompleted → TrackEntry(mainQuest)` path. When the tracked quest completes, the native journal/quest system selects the next tracked entry itself and fires the listener.
- **The only script-visible reaction is a listener:** `quest_tracker.script:38` registers `OnTrackedEntryChanges` via `RegisterScriptCallback(this, 'OnTrackedEntryChanges', gameJournalListenerType.Tracked)`; the handler (`quest_tracker.script:103`) only re-renders the HUD from the already-changed tracked entry. It reacts to, it does not cause, the switch.

Implication: there is **no clean pre-emptive script method to wrap** that says "re-track main quest." The auto-repin happens in native code.

---

## 3. Feasibility + proposed approach

**Feasible via a REACTIVE COUNTER — the same net behavior the CET mod achieves, re-implemented in REDscript.** No pre-emptive native seam, so we let the native switch happen and immediately counter it.

### Approach A (recommended) — reactive Tracked-listener counter
1. A small ScriptableSystem (or a field on PlayerPuppet) registers its own `RegisterScriptCallback(self, 'OnCustomTrackedChange', gameJournalListenerType.Tracked)`, armed from the **player object (game thread)** — never from an arbitrary-entity `OnGameAttached` (worker-thread crash class, per vault memory).
2. Maintain a stored "user intent": the entry the user last manually tracked, or an explicit "user wants nothing tracked" flag. Capture manual intent by wrapping the user-initiated `TrackEntry`/`UntrackEntry` UI callers (`worldMap`, `journal_wrapper`, notification actions) to record "this track was user-driven."
3. In `OnCustomTrackedChange`: read `GetTrackedEntry()`. Resolve its quest via `GetParentEntry` then `GetQuestType(...)==gameJournalQuestType.MainQuest`. If the new tracked entry is a **main quest** AND the change was **not** user-initiated (our flag) AND it differs from the user's stored intent → reassert intent: `UntrackEntry()` (keep nothing) or `TrackEntry(storedIntent)` if still `Active` (state via `GetEntryState`).
4. Guard against loops: our reassert calls will themselves fire the listener — set a re-entrancy flag around them so we don't counter our own call.

### Approach B (needs verification, possibly cleaner) — wrap native TrackEntry
- `@wrapMethod(JournalManager) func TrackEntry(entry)`: if entry resolves to a `MainQuest` and an "unwanted auto-switch" flag is set, skip `wrappedMethod()`.
- **RISK/UNKNOWN:** hooking a native `import` method is not guaranteed to intercept native-INTERNAL callers (native C++ may call its own impl, bypassing the redscript hook). Must be validated in-game before relying on it. If native-internal calls bypass the hook, this approach silently fails and Approach A is required.

### Known edge cases to handle (why the CET mod has many toggles)
- **Prologue & Endings:** the reference mod disables its preventer there (forcing no main-quest guidance is confusing/blocking during linear story). Need equivalent gating.
- **Legitimate intra-quest objective advance** (same quest, next objective) must NOT be countered — compare containing quest, not raw entry.
- **"Blue" quests (NCPD hustles) / contracts:** must remain untouchable independently (the CET mod explicitly leaves blue quests alone).
- **Fixers' Reward auto-track** is a distinct trigger from generic completion repin — may need its own detection.

### Risk assessment
- MEDIUM. The reactive pattern is proven (CET mod does it) and uses only verified read/track APIs. Risks are behavioral (countering a legitimate switch, prologue/ending confusion, listener loops), all mitigable with the guards above. No crash-class risk if armed from the player object and only reading/tracking journal state.

---

## 4. Verified API inventory

| Symbol | Location | Role |
|---|---|---|
| `JournalManager.GetTrackedEntry` | journalManager.script:418 | read current tracked entry |
| `JournalManager.IsEntryTracked` | :419 | check tracked |
| `JournalManager.TrackEntry(entry)` | :420 | set tracked (native) |
| `JournalManager.UntrackEntry()` | :422 | clear tracking |
| `JournalManager.GetQuestType(entry)` | :432 | classify quest |
| `JournalManager.GetParentEntry(child)` | :409 | objective→quest |
| `JournalManager.RegisterScriptCallback / Unregister` | :437 / :438 | subscribe to Tracked changes |
| `gameJournalQuestType { MainQuest,… }` | :140-142 | main-vs-side |
| `JournalQuest.GetType()` | :157 | quest type |
| `quest_tracker.OnTrackedEntryChanges` (Tracked listener precedent) | quest_tracker.script:38,:103 | reactive seam pattern |
| `gameJournalEntryState` (Active/Succeeded/Failed) | journalManager (GetEntryState) | validate reassert target |

**REDscript constraints (vault memory):** no `continue`/`break`; arm listeners/loops from the PLAYER object only (never arbitrary-entity `OnGameAttached`); one `@wrapMethod` = one `wrappedMethod()` call; validate with serial `scc -compile`.

---

## 5. Recommendation

- No installable macOS mod exists (the exact-fit 6328 is CET-gated).
- A custom REDscript mod is **feasible** via Approach A (reactive Tracked-listener counter), mirroring the CET mod's logic with verified APIs; Approach B (native wrap) is cleaner but unverified and may not intercept native-internal calls.
- **Await user confirmation of scope** (keep-nothing vs keep-last-pinned; whether to also block Fixers' Reward auto-track; prologue/ending behavior) before authoring `.reds`. Plan: `plan-disable-quest-auto-repin.md`.
