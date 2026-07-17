# Plan — Prevent Quest Tracker Auto-Repin to Main Quest

Companion to `quest-tracker-auto-repin-research.md`. **✅ SHIPPED 2026-07-15** as custom mod **No Main Quest Auto-Repin** (`r6-scripts/no-main-quest-auto-repin/NoMainQuestAutoRepin.reds`, STATE=ENABLED, scc clean). Scope answers below were all confirmed and applied: (1) go BLANK on unwanted main repin, no restore; (2) Fixers'-Reward left vanilla; (3) apply everywhere; (4) NCPD/contracts untouched. Approach A implemented as designed. This plan is retained as the design record; remaining work is in-game verification (user-run).

## Situation
- User wants: after finishing a side quest / gig / NCPD scanner / contract, the tracker must NOT auto-jump to a main quest — keep the last-pinned objective, or nothing.
- Exact-fit mod **Untrack Quest Ultimate** (Nexus 6328) has this ("Main Quest re-tracking preventer") but **requires CET → ❌ macOS**. No macOS-compatible mod does it.
- Custom REDscript is **feasible** (reactive counter; APIs verified in research §4). The native auto-repin can't be pre-empted cleanly, but it can be countered the instant it fires.

## Questions for the user before authoring
1. **Desired end state when a tracked side activity completes:**
   - (a) keep NOTHING tracked (blank tracker), or
   - (b) restore the LAST manually-pinned quest/objective if still active, else nothing?
2. **Fixers' Reward auto-track:** also suppress the auto-switch to incoming Fixer reward quests? (the CET mod treats this as a separate toggle)
3. **Prologue / Endings:** leave vanilla auto-tracking there (recommended — avoids confusing/blocking linear story), or apply everywhere?
4. **NCPD "blue" hustles / contracts:** confirm these should stay independently trackable (leave untouched) — matches the CET mod's safe default.

## Proposed implementation (Approach A — recommended)
Only after answers above. Sketch (all APIs verified in research §4):
1. Own tracked-change listener: `JournalManager.RegisterScriptCallback(self, 'OnCustomTrackedChange', gameJournalListenerType.Tracked)`, armed from the PLAYER object (game thread; no arbitrary-entity `OnGameAttached`).
2. Store "user intent": wrap the user-initiated UI track callers (`worldMap` map-click, `journal_wrapper.SetTracking`, notification `TrackQuestNotificationAction`) to flag manual tracks and record the intended entry / a "wants-nothing" flag.
3. In `OnCustomTrackedChange`: resolve new tracked entry → `GetParentEntry` → `GetQuestType == MainQuest`; if main AND not user-initiated AND ≠ stored intent → reassert via `UntrackEntry()` (option a) or `TrackEntry(storedIntent)` if `GetEntryState==Active` (option b).
4. Re-entrancy flag around reassert calls (they refire the listener). Prologue/ending + blue-quest guards per answers.
5. Config toggles in the `.reds` (master enable, block-fixers-reward, prologue-exempt), debug probe. `scc -compile` clean, then in-game test: finish a gig → confirm tracker stays put; verify intra-quest objective advances still work; verify NCPD hustle tracking unaffected.

### Fallback (Approach B) — only if A proves insufficient
`@wrapMethod(JournalManager) TrackEntry`: skip `wrappedMethod()` for unwanted main-quest auto-tracks. **Must first verify in-game that the native auto-repin routes through the script hook** (native-internal calls may bypass it). If it bypasses, discard B.

## Explicitly NOT in scope
- Hiding/altering map markers (already covered by installed Track What You Want 4110).
- Touching NCPD/contract "blue" quest tracking.
- Any CET dependency.

## Recommendation
Confirm answers to Q1-Q4, then I author Approach A, `scc -compile`, and report before deploying. No install of 6328 (CET-incompatible). No `.reds` written yet.
