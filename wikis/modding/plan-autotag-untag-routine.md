# Plan: Auto-Untag Routine (2026-07-16)

Untag the mod's OWN stale tags once the target is no longer a candidate — **breached access points** (default) and, opt-in, confirmed-inert objects — without duplicating vanilla self-untag and without ever touching the player's manual tags. Root-cause + API + gap map: `autotag-untag-routine-research.md`.

Status: **edits applied to `ScannerSuite.reds`** (2026-07-16). **NOT compiled** (game running — `scc` deferred per the backup-corrupted rule). In-game probe **pending**.

Verify verdict: **APPROVE, ready, crash risk NONE, manual-tag risk none by construction.**

---

## Mechanism

- **Landed-tag ledger** `@addField(FocusModeTaggingSystem) m_autoTagged: array<EntityID>` — fed ONLY from `AutoTagTryOnce`'s landed branch (after `TagObject` + a synchronous `IsTagged` proof), via `AutoTagMarkTagged` (FIFO-capped 4096, mirrors `APS_MarkAttempted`). The already-tagged branch is untouched → player-first tags never enter.
- **Untag pass** `AutoUntagSweepOnce(game)` — walks `m_autoTagged`; per id: resolve via `FindEntityByID` (null → keep, skip; never deref); if `!IsTagged` → drop the id (tag gone by player toggle / vanilla); **Lane A** `IsAccessPoint() && IsBreached()` → `UntagObject` + drop; **Lane B** (opt-in) `ST_AutoTagCategory()==None` on two consecutive passes (`m_autoUntagPending` debounce) → `UntagObject` + drop. Destreamed (unresolvable) entries are **kept** — world devices keep their EntityID, so tag-AP → walk away → return → breach still untags; the FIFO cap bounds the ledger.
- **Cadence** — `m_stUntagAccum` sub-gates the pass onto the 0.5 s sweep tick at `AutoUntagInterval` (3 s), inside `ST_SweepTick`'s self-re-arming `DelayCallback` (game thread).
- **Untag call** — synchronous private `this.UntagObject` (full teardown: tag + reveal + HUD + blackboard), mirroring `AutoTagTryOnce`'s private `this.TagObject`. `m_autoTagSeen` is **never** rolled back → nothing is ever re-tagged (breached APs also classify `None` → double block).

## Config knobs (3, split by confidence)
| Knob | Default | Why |
|---|---|---|
| `EnableAutoUntagBreachedAccessPoints()` | **ON** | The reported bug; `IsBreached` persistent/monotonic → zero flicker |
| `EnableAutoUntagInert()` | **OFF** | Mostly redundant with vanilla empty-untags; `None` is transient for streaming loot → a wrong untag is permanent. Ships WITH the two-pass debounce so ON is safe |
| `AutoUntagInterval()` | 3.0 s | Bounds ledger walk + debounce spacing |

## Edits applied (6, all text-anchored)
1. Config block — 3 knobs after `EnableAutoTagAccessPoints`.
2. Ledger — `m_autoTagged` + `m_autoUntagPending` fields + `AutoTagMarkTagged` helper.
3. `AutoTagTryOnce` landed branch — `AutoTagMarkTagged(id)` after the seen push.
4. `AutoUntagSweepOnce` method (+ supersede-note on the removed-combat-exit comment).
5. `@addField(HUDManager) m_stUntagAccum`.
6. `ST_SweepTick` — the accumulator-gated untag call.

## Safety (verified)
- **Manual tags never untagged** — ledger fed only from `AutoTagTryOnce` landed branch; player middle-click (`focusModeTagging.script:265`) bypasses it; `!IsTagged` GC erases an entry the instant its mod tag is gone. Sole residual = a ≤3 s same-interval untag+re-tag-while-breached race (one recoverable marker).
- **Crash-safe** — all shared mutation on the game thread inside the existing `DelayCallback`; re-arm scheduled FIRST so an untag fault can't kill the loop; NO attach/streaming hook; not inside any entity listener; async notifications engine-queued. Respects both the worker-crash and re-entrant-mutation memories.
- **No duplication** — vanilla's empty-container/corpse/deactivate untags are deferred to, not re-run (`!IsTagged` GC skips them).
- **Invariants** — lane A is orthogonal to the loot classifier (only READS `ST_AutoTagCategory`) → the shard-case landmine + the role-Loot union stay intact.

## REDscript constraints respected
No `continue`/`break` (drop-flag + if-wrapper); `ArrayErase` by index only (drain-to-local avoids remove-by-value); `Equals()` enum compare; `@addField`×2 / `@addMethod` private access precedented; system resolution matches the file idiom.

---

## Validation — REQUIRED (game must be CLOSED first)
1. Quit game; confirm `pgrep -f Cyberpunk2077` empty.
2. `"$gd/engine/tools/scc" -compile "$gd/r6/scripts"` (`$gd` = game dir) — expect 0 errors. This compile also validates the **pending role-Loot tag fix** (both changes are unvalidated in the same file).
3. **Primary probe:** tag an unbreached access point (mod marker appears) → breach it (jack-in / remote / HGT instant breach) → within ~3.5 s the tag + outline + HUD marker all vanish.
4. **Counter-probes:** (a) manual-tag an already-breached AP → must stay tagged forever (mod never owned it); (b) tag a loot container then loot it → untags **instantly** via vanilla's empty event (not the 3 s cadence), no flicker; (c) save after auto-untag → reload → stays untagged.

## Risks (disclosed, bounded)
- Session-transient ledger: tags landed before a save/load (and all pre-feature stale tags) are orphaned — one manual middle-click clears each.
- EntityID recycling: bounded by the 4096 FIFO; harmless severity (one marker).
- Quest un-breach (`OnResetNetworkBreachState`): an auto-untagged AP later un-breached is not re-tagged (seen spent) — deliberate.
- Lane B (if enabled): a streaming-transient `None` could permanently drop a tag — mitigated by the two-pass debounce + default OFF.
