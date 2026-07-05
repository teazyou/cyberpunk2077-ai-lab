# Custom Scanner Suite — crash analysis (2026-07-06)

Diagnosis only. No code was changed, no game was launched, `r6/cache` was not touched.
Target file: `mods/enabled/r6-scripts/custom-scanner-suite/ScannerSuite.reds` (918 lines, compiles clean under scc).

## Symptom

Cyberpunk 2077 v2.3.1 (macOS Steam) began hard-crashing (process termination, no error dialog)
this session, immediately after two commits to the Scanner Suite mod:

- `e638160` — auto-tag whitelist fix (quest + camera categories removed, `GetItemList` gate added, `IsSensor`→`IsTurret`).
- `1659845` — two-channel auto-pickup (cursor 20 m + radius 10 m) + enemy LOS/any-range tag. File grew 659→918 lines. **Added a new always-on `@wrapMethod(GameObject) OnGameAttached` hook.**

The mod compiles clean, so this is a **runtime** crash, not a compile error.

## Log evidence

### REDscript log — clean, and only compile-time
`r6/logs/redscript_rCURRENT.log` (and the rotated 02:48 / 02:56 logs) show only a successful
compile: "Compilation complete" → "Output successfully saved to …/final.redscripts". The only
diagnostics are pre-existing WARNINGs from *other* mods (untrack-quest / better-fast-travel
`@replaceMethod` collision, disassemble-loot redundant cast, drink-at-the-counter type compare).
**No Scanner Suite warning, no runtime script error.** This log is written by the compiler at
launch and does not capture in-game runtime faults, so its silence neither implicates nor clears
the mod — the native crash reports are the real evidence.

### macOS native crash reports — the decisive evidence
`~/Library/Logs/DiagnosticReports/`:

| File | Time | Exception | Fault address | Faulting thread |
|---|---|---|---|---|
| `Cyberpunk2077-2026-07-06-025742.ips` | 02:57:42 | EXC_BAD_ACCESS / SIGSEGV / KERN_INVALID_ADDRESS | **0xaa60e3b215796770** | t7 = **redDispatcher3** |
| `Cyberpunk2077-2026-07-06-025759.ips` | 02:57:59 | EXC_BAD_ACCESS / SIGSEGV / KERN_INVALID_ADDRESS | **0xaa60e3b215796770** | t4 = **redDispatcher1** |

Both post-date commit `1659845` (02:49). Key facts:

1. **Both crashes fault at the *identical* wild address `0xaa60e3b215796770`** — `vmRegionInfo`
   confirms it "is not in any region" (a dangling/garbage pointer, not a small null-offset). Two
   independent launches producing the exact same bad pointer = **deterministic heap/pool
   corruption**, not a random null deref. (A deterministic world-load stream order producing the
   same corrupt value each run is exactly what a data race on a load-path structure looks like.)
2. **Both faulting threads are RED job-dispatch workers** (`redDispatcher1/3`), **not** `GameThread`
   (t0). The crash surfaces on the engine's parallel entity-streaming / render worker pool.
3. **The crash is inside the memory allocator / streaming path.** Report `…025759` frame 5 is
   symbolicated as `red::memory::PoolStorageProxy<rend::PoolRenderProxyInternals_Mesh>::Allocate(...)`
   — a crash *inside* a pool `Allocate` walking a free-list = textbook allocator/free-list
   corruption. Report `…025742` is a different job but shares the **identical top frames**
   (`Cyberpunk2077 +0xb130, +0xb0c0, +0xa2dc, +0xa908, +0xf904 …`) and the identical worker
   dispatch tail (`+0xca61c8, +0xc99460, +0xcfac90, +0x9d8e7c…` → `_pthread_start`). Two *different*
   consumer jobs tripping over the *same* corrupt pointer ⇒ a shared heap structure was scribbled.
4. **Distinct from the pre-existing fault.** The earlier `…2026-07-04-222109.ips` (before both
   commits) is also EXC_BAD_ACCESS on a redDispatcher, but at a **different** address
   (`0xf006925290`) with a **different** stack. So the 07-06 pair is a **new, repeatable
   signature** that appeared with the commits — while noting ~45 other REDscript mods are loaded,
   so the bisection below still ends in a "100% vanilla suite" control.

Timeline: launch → compile (02:57:44) → crash within ~15 s (during load/streaming) and again at
~69 s after the prior compile (early gameplay streaming). The unifying factor across "still
loading" and "just started playing" is code that runs on **every entity stream-in** — of which the
mod has exactly one new instance.

## Ranked suspects

### 1. (PRIME) `OnGameAttached` always-on registry mutation on the multithreaded streaming path
**Confidence: HIGH.**

**Mechanism.** Commit `1659845` added `@wrapMethod(GameObject) OnGameAttached` (`ScannerSuite.reds:726-741`).
This is the **only** new code that runs unconditionally — it fires for **every entity that streams
into the world**, during load and continuously as you move. On each qualifying entity it resolves
`GetPlayer(this.GetGame())` (`:735`) and calls `player.APS_RadiusRegister(this)` (`:738`), which does
`ArrayPush(this.m_apsRadiusRegistry, obj)` (`:662-665`) — mutating one shared dynamic array
(`@addField(PlayerPuppet) m_apsRadiusRegistry`, `:658`) on the single player instance.

Entity attach/streaming in the RED engine is driven by the `redDispatcher` job pool — exactly the
threads that faulted. Multiple worker threads streaming entities concurrently each call the wrap
and each `ArrayPush` into the **same** `m_apsRadiusRegistry`. A `DynArray` push is a
read-capacity → maybe-realloc → write-element → bump-count sequence with no lock; run it from two
threads at once and you get a torn element write and/or a double/racing realloc that frees a buffer
another thread is still using → **allocator free-list corruption**. That corruption then kills an
unrelated consumer (mesh render proxy allocation) on whichever worker next draws from the poisoned
pool — precisely the observed stacks and the identical corrupt pointer.

Contributing amplifier: even single-threaded, the registry is **unbounded and never compacted while
the scanner is closed** — `APS_RunRadiusPickup` (the only place nulls are dropped, `:686-706`) runs
only when the scanner is open in FOCUS. During a normal load with the scanner down, the array grows
by every puppet + loot + item that ever streamed in (thousands), so reallocs are frequent and large,
widening the race window and the blast radius.

**Code ref.** `ScannerSuite.reds:726-741` (wrap), `:657-665` (field + push), `:673-714` (walk/compaction), refinements doc line 303 ("`OnGameAttached` fires per entity stream-in").

**Why the toggle cleanly isolates it.** The wrap calls `wrappedMethod()` FIRST and unconditionally
(`:728`), and `ScannerSuiteConfig.EnableAutoPickupRadius()` is the **first** condition of the guard
(`:729`) — ahead of every cast, `GetPlayer`, and the `ArrayPush`. So `EnableAutoPickupRadius()=false`
turns `OnGameAttached` into a pure passthrough (only `wrappedMethod` runs). The toggle is correctly
placed; the always-on hook is genuinely neutralized when the radius channel is off. This is the
fastest, cleanest single-flip test.

**Proposed fix (not applied), in order of preference:**
- **Immediate / safe:** set `EnableAutoPickupRadius()` → `false` (`:134-136`). Removes the entire
  streaming-path work and the radius pass; cursor pickup + auto-tag + loot-while-scanning keep
  working. If a permanent removal is wanted, delete the `OnGameAttached` wrap and the radius channel.
- **Proper redesign:** never mutate shared script state inline on the attach callback. Either
  (a) gate registration to only while the scanner is actually up (gate the body on
  `m_uiScannerVisible`), so load-time streaming is a pure passthrough and the array stays small; and/or
  (b) defer the `ArrayPush` off the attach thread — queue the entity to a `ScriptableSystem` /
  0-delay `DelayCallback` processed on the game thread, so all mutation of `m_apsRadiusRegistry`
  happens single-threaded on the game tick. Also compact the registry every sweep tick regardless of
  channel, and cap its size.
- Note: the doc cites CNML (Nexus 16040) as precedent for a global `OnGameAttached` registry, but the
  precedent does not make cross-thread mutation of a *shared player-field* array safe here; if CNML
  is stable it likely registers on a single-threaded path or into per-thread/locked storage.

### 2. Unbounded `m_apsRadiusRegistry` growth + `wref`-to-every-entity accumulation
**Confidence: MEDIUM (same root as #1; listed separately as the non-race half of the mechanism).**

Even absent a race, storing a `wref<GameObject>` to every streamed puppet/loot/item and never
pruning while the scanner is closed means huge, frequently-reallocating script arrays on the hot
load path. Large churny reallocs are the ideal trigger to expose any latent allocator weakness and
are the same object being blamed in #1. Fix folds into #1 (scanner-gated registration + capped,
per-tick-compacted registry).

### 3. Mutation-during-iteration in `APS_TryAutoPickup` (use-after-free of `gameItemData`)
**Confidence: MEDIUM as a real bug, LOW as the cause of *these* crashes (timing mismatch).**

`APS_TryAutoPickup` reads a snapshot `itemList: array<wref<gameItemData>>` from
`transSys.GetItemList(this, itemList)` (`:810-811`) then loops `for itemData in itemList { …
transSys.TransferItem(this, player, itemData.GetID(), itemData.GetQuantity()); … }` (`:818-836`).
`TransferItem` mutates the source container's inventory — the very collection those `wref`s point
into — while the loop is still iterating and dereferencing later `itemData` handles. That is a
mutation-during-iteration / use-after-free pattern that can also throw EXC_BAD_ACCESS.

However: this path runs **only when actively looting** (scanner open, target hovered or within the
10 m radius, in FOCUS) — it cannot run during the load/streaming window where the observed crashes
occur, and it executes on the game thread, not a redDispatcher. It is a genuine latent bug worth
fixing (iterate a copied array of `ItemID`s, or transfer after collecting IDs), but it does not
match the load-time, worker-thread, allocator-corruption signature and is **not** the regression.

**Proposed fix:** collect `ItemID`s (and needed data) into a local array first, close the
`GetItemList` iteration, then perform the `TransferItem` calls.

### 4. `GetItemList` whitelist gate added to the sweep (commit e638160)
**Confidence: LOW.**

`ST_AutoTagCategory` now calls `GetTransactionSystem(...).GetItemList(this, itemList)` (`:409-411`)
for collectable candidates during the frustum sweep. On a valid `GameObject` this native call is
safe; it runs only while scanning (not at load) and on the game thread. Not consistent with the
crash signature. Keep as a low-probability item to clear via bisection Test 2.

### 5. Enemy sweep (500 m puppet query + per-enemy `IsVisibleTarget` raycast every 0.35 s)
**Confidence: LOW — classify as performance/hitching, not a true crash.**

`ST_RunEnemySweepOnce` (`:575-618`) adds a second `GetTargetParts` pass with a per-enemy occlusion
raycast. Worst case this is a frame-time / hitch cost, and it runs only while scanning in FOCUS. It
does not explain a load-time worker-thread segfault. Monitor for stutter, not crashes.

### Cleared
- **DelayCallback lifecycle** (`STSweepTickCallback` holds `wref<HUDManager>`, checks `IsDefined`
  `:433`; `m_stSweepArmed` double-arm guard `:445-454`): correctly guarded; not a suspect.
- **REDscript compile/link**: clean; not a suspect.

## User bisection steps

Flip one literal, relaunch, load the same save, reproduce the same action. Each test isolates one
layer. (Only you can run the game.)

1. **Test A — neutralize the prime suspect (do this first).**
   `ScannerSuite.reds:135` `EnableAutoPickupRadius()` → `return false;`
   This makes `OnGameAttached` a pure passthrough (confirmed: `wrappedMethod` runs first, toggle is
   the first gate) and disables the radius pass.
   - **Crash STOPS** ⇒ confirmed suspects #1/#2 (the `OnGameAttached` registry). Stop here; that is
     the culprit. Apply the redesign or leave the radius channel off.
   - **Crash PERSISTS** ⇒ rule out the attach hook; go to Test B.

2. **Test B — disable auto-tag sweeps** (keep A's change too).
   `:84` `EnableAutoTagOnScan()` → `return false;`
   With both `EnableAutoTagOnScan` and `EnableAutoPickupRadius` false, no sweep loop is armed
   (`OnScannerUIVisibleChanged` arms on `tagOn || radiusOn`, `:241`; `ST_SweepTick` early-outs,
   `:464`). Kills `ST_RunSweepOnce` + `ST_RunEnemySweepOnce` + the `GetItemList` whitelist gate.
   - Crash stops ⇒ a sweep pass (suspect #4/#5) is implicated.

3. **Test C — disable cursor pickup** (keep A + B).
   `:125` `EnableAutoPickupOnScan()` → `return false;`
   Removes the hover→`APS_TryAutoPickup` path (suspect #3, the `TransferItem`-in-loop).
   - Crash stops ⇒ cursor pickup / item-transfer path implicated.

4. **Test D — full vanilla control** (also set `:78` `EnableLootWhileScanning()` → `false`).
   All four features off = 100% passthrough.
   - Crash stops ⇒ definitively the Scanner Suite (which layer already localized by A–C).
   - **Crash STILL happens** ⇒ it is **not** this mod — look to another of the ~45 loaded REDscript
     mods or the engine (matches the pre-existing 07-04 redDispatcher fault). Next step then is to
     bisect other mods, not this file.

Fastest single decisive test: **Test A**. It is one boolean and it targets the highest-probability
cause.

## Recommended next action

Have the user run **Test A** first: set `EnableAutoPickupRadius()` to `return false;`
(`ScannerSuite.reds:135`), recompile via the normal launcher, load the same save, and play the ~1–2
minutes that previously crashed. Because the crash is deterministic (identical fault address across
runs), a clean run after this one flip is strong confirmation.

If Test A stops the crash (expected): the durable fix is to stop mutating the shared
`m_apsRadiusRegistry` on the multithreaded attach path — gate `OnGameAttached` registration to
scanner-active only and/or defer the `ArrayPush` to the game thread via a ScriptableSystem/
DelayCallback queue, plus cap and per-tick-compact the registry. Until that redesign lands, shipping
with `EnableAutoPickupRadius=false` keeps cursor pickup, auto-tag, and loot-while-scanning fully
working with zero streaming-path cost.

Separately (independent of this crash), fix suspect #3's mutation-during-iteration in
`APS_TryAutoPickup` by collecting item IDs before transferring.

---

## 2026-07-06 — FIX APPLIED (compiles clean; CONFIRMED crash-free in-game by the user)

Applied directly (a first fix agent was killed mid-edit having only rewritten header
comments to *claim* the hook was removed while the crash code stayed intact — the relaunch
crashed again on the identical bug).

**1. Root cause removed.** Deleted the `@wrapMethod(GameObject) OnGameAttached` wrap, the
`@addField(PlayerPuppet) m_apsRadiusRegistry` array, and `APS_RadiusRegister`. Nothing hooks
the entity-attach lifecycle anymore, so no custom code runs on the redDispatcher worker
threads — the unsynchronized shared-array mutation that corrupted the heap is gone. The suite
is scanner-scoped again (no always-on per-entity hook).

**2. Radius pickup re-derived on the game thread.** `APS_RunRadiusPickup` now enumerates via
`GameObject.GetEntitiesAroundObject(AutoPickupRadius, TSF_Any(TSFMV.Obj_Puppet))` — a vanilla
`TargetingSet.Complete` 360° proximity query (`gameObject.swift:686`; used by
`GetNPCsAroundObject` and `settingsMain.swift:646`), run from the existing DelaySystem sweep
tick (game thread). It returns entities through `TargetingComponent`, which only puppets/
devices carry, so radius pickup is **corpses-only** by construction; world containers/drops/
shards were never reachable by any targeting query and remain with the cursor (hover) channel.
10 m stays the binding gate (the query distance-filters; the shared worker's 20 m cursor cap
then always passes). Live puppets in range are a cheap transient reject each tick (spend
nothing) and are looted once dead.

**3. Secondary use-after-free fixed.** `APS_TryAutoPickup` now snapshots `{ItemID, quantity}`
into value arrays in a first read-only pass over the item list (playing the loot sound while
the `wref<gameItemData>` is still valid), then transfers purely from the snapshot in a second
pass — `TransferItem` no longer mutates a list being iterated. Applies to both pickup channels.

**Compile:** `scc -compile` → *Compilation complete*, zero `custom-scanner-suite` warnings
(906 lines). Game not launched; `r6/cache` untouched.

**Left for the user:** load the save that crashed and play a streaming-heavy stretch (driving,
fast-travel, district transitions) with the radius channel ON — the worker-thread crash should
be gone. Then confirm radius still auto-loots dead bodies within 10 m + LOS, and cursor/tag/
loot-while-scanning are unaffected.
