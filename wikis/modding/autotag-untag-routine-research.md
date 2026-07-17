# Auto-Untag Routine: Gap Map + API (research, 2026-07-16)

Dynamic workflow (opus/max investigate ×3 → fable/max plan → opus/max adversarial verify) for the request: *"it tags some hackable device but after being hacked, could it untag it? Could we have a routine where everything tagged gets untagged if it's empty or not actionable anymore?"*

Verdict: **APPROVE, ready to implement, crash risk NONE, manual-tag risk effectively none.** All vanilla APIs re-greped against the v2.3 clone (0 errors).

---

## Untag API (verified)

- `GameObject.UntagObject(obj: weak<GameObject>)` — public static, `gameObject.script:1985`. Queues an **async** `UnTagObjectRequest` via `GetTaggingSystem().QueueRequest`.
- Private `FocusModeTaggingSystem.UntagObject(target)` — `focusModeTagging.script:157-165`. **Full teardown**: `ScanningController().UntagObject` + `SendForceRevealObjectEvent(false)` (kills the standing through-wall reveal) + `RefreshUI` + `NotifyNetworkSystem` + `NotifyHudManager(false)` + `UnRegisterObjectToBlackboard`. Mirror-superset of private `TagObject` (`:144`).
- `FocusModeTaggingSystem.IsTagged(target)` — private, null-guarded, `focusModeTagging.script:232`. Same native `ScanningController` registry (`scanningController.script:6/7/9`) as Tag/Untag → **synchronous readback authoritative**.

**Chosen call = private `this.UntagObject` (synchronous)**, not the static wrapper. Both give the complete teardown and both are idempotent (vanilla calls `UntagObject` unconditionally at `deviceBase:2353`, `lootContainers:249`). The wrapper is **async** → `IsTagged` lags the pump → an `IsTagged`-gated pass would double-issue across ticks, breaking the mod's deliberate sync-readback invariant. `@addMethod(FocusModeTaggingSystem)` calling private `IsTagged`/`UntagObject` is the exact pattern already compiled for `TagObject`/`IsTagged`.

---

## The gap map — what vanilla already untags vs the residual

| Mod tag category | Vanilla self-untag? | file:line | Gap? |
|---|---|---|---|
| Container / shard case / loot bag | YES — `OnInventoryEmptyEvent → UntagObject` (unconditional, drainer-agnostic → the mod's auto-pickup `TransferItem` drain triggers it too) | `lootContainers:249/:637`, `inventoryComponent:514` | **No — defer to vanilla** |
| Corpse (resolved quality) | YES | `scriptedPuppet:4718` | No |
| Corpse (quality-less loot only) | NO — vanilla untag is `HasValidLootQuality`-gated | `scriptedPuppet:4708/:4713` | **Yes (minor)** |
| Deactivated / force-disabled device | YES — `DeactivateDevice → UntagObject` | `deviceBase:2353` | No |
| **Breached access point** | **NO** — breach = one persistent flag write, zero `UntagObject`/`DeactivateDevice` in the whole file | `accessPointController:345-349`; `IsBreached` `:377` | **YES — the prime case** |
| Inert-but-powered quest device | NO — vanilla untags devices only via `DeactivateDevice` | `deviceBase:2347` | Yes (minor) |

**Prime gap = the breached access point** — the exact user report. APs are Devices, not one of the 4 `OnInventoryEmptyEvent` handler classes, and breaching fires neither empty nor deactivate. The `EnableAutoTagAccessPoints` lane (`ScannerSuite.reds`, gated `!IsBreached()`) therefore leaves its tag stuck forever. The breached AP entity stays spawned/valid (vanilla's scanner reads `IsBreached()` off it), so a next-sweep untag on the game thread is valid.

---

## Why the mod-owned ledger is mandatory (the correctness trap)

The native tag registry is **one bit per object, no provenance** — `UntagObject` strips *any* tag, mod- or player-applied. `m_autoTagSeen` is **NOT** a usable gate: it also spends an entry on the already-tagged branch (the player's hand, `AutoTagTryOnce`), so untagging by the seen-list would rip the player's manual tags. A separate **landed-tag ledger** (`m_autoTagged`) fed only from `AutoTagTryOnce`'s landed branch is required. The player's middle-click never routes through `AutoTagTryOnce` (`FocusModeTaggingSystem.OnActionWithOwner`, `focusModeTagging.script:265`), so a manual tag can never enter the ledger → provably never auto-untagged.

See `plan-autotag-untag-routine.md` for the implemented design + probe protocol.
