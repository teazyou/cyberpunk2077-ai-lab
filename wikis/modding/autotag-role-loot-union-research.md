# Auto-Tag Under-Tagging: Role-Loot Union (research, 2026-07-16)

Dynamic multi-agent workflow (opus/max investigate ×3 → fable/max plan → opus/max adversarial verify) into the report: *"some items like this one are not auto-tagged"* — screenshot of a small die/memento + flat shard-like device on a mattress at a Badlands dumpsite, in scan mode, receiving NO persistent loot tag while ordinary crates/corpses/floor weapons tag fine.

All vanilla APIs verified against the v2.3 decompile clone (`CDPR-Modding-Documentation/Cyberpunk-Scripts`). Every predicate below was re-greped in the adversarial verify pass (0 factual errors).

---

## Root cause — CLASSIFICATION MISS (medium-high confidence)

`ST_AutoTagCategory` admits loot ONLY via the class trio `IsContainer() || IsShardContainer() || IsItem()` (`ScannerSuite.reds:957`). **Those three predicates are CONTENT-CACHED, not structural:**

- `gameLootContainerBase.IsContainer()` = `!IsEmpty() && !IsDisabled()` (`lootContainers.script:618`); `IsEmpty()` is a native import (`:747`) that reads **true both pre-loot-generation and post-looting**.
- `ItemObject.IsContainer()` = `!HasTag('NoLootMappin') && IsConnectedWithDrop()` (`item.script:89`).
- `IsShardContainer()` — only `ShardCaseContainer` overrides true (`:60`).
- `IsItem()` = `((ItemObject)(this)) != NULL` (`gameObject.script:1811`, protected const, non-virtual, no overrides).

So a loot container seen by the 0.5 s sweep **before its inventory is generated** reads all-trio-false → classified `None`. The worker spends the entity's one attempt as a transient-None (re-checked), but the object shows the scan-focus circle with **no red loot bracket** — exactly the screenshot symptom.

**The fix vanilla already hands us:** `DeterminGameplayRole() == EGameplayRole.Loot` — vanilla's own, NON-content-cached loot signal. It is the very virtual that draws the loot mappin the user looks for. The auto-**pickup** path adopted this union on 2026-07-13 (`APS_IsCollectable`, `ScannerSuite.reds:1907`); the **tag** path never did.

### Over-tag is provably bounded
Exhaustive grep: exactly **5** `return EGameplayRole.Loot` sites in the whole 2.3 tree — all loot classes, no Device / VehicleObject / explodable:
- `gameLootBag` `lootContainers.script:309` (unconditional)
- `gameLootContainerBase` `lootContainers.script:709` (unconditional)
- `gameLootObject`/`gameItemDropObject` `inventoryComponent.script:374` (unconditional)
- `ItemObject` `item.script:173` (iff `IsContainer()`)
- `ScriptedPuppet` `scriptedPuppet.script:4520` (iff `IsContainer()` — **unreachable**: the puppet lane at `:930-941` returns for every `ScriptedPuppet` before the widened gate)

`CanBeTagged()` base = true, sole override `ScriptedPuppet` (`gameObject.script:1997` / `scriptedPuppet.script:2134`), so new admits are never permanently refused.

---

## Hypotheses REFUTED

- **Quality-floor failure** (bare item's `GetItemData()` null forever): refuted 3/3. For a live `ItemObject`, `GetItemData()` is reliably non-null — vanilla derefs it with no null guard (`item.script:91`, `:166`) — and the default Common floor passes tier-0 quality-less loot unconditionally (`ScannerSuite.reds:922`). Floor weapons demonstrably tag today.
- **Tagged-but-invisible render gap**: real but narrow — needs a DISCONNECTED bare `ItemObject` (no HUDActor: `ShouldRegisterToHUD = m_forceRegisterInHudManager` only, `item.script:155`; role None, `:169`). The hover channel redirects connected items to their always-registered drop (`ScannerSuite.reds:2225`). Residual ~15-20%; fix is a no-op on it (data-side limit).

---

## Residual: hard vanilla limit (~20%)

If the object is a non-loot-class scannable prop — `gameCpoPickableItem`/`HealthConsumable` (`healthConsumable.script:1`/`:11`), `InspectDummy` (`inspectableItem.script:1`), `VirtualItem_TEMP` — these extend `GameObject` with a bespoke PickUp/Inspect interaction, **no trio override, role Clue/None**. No vanilla loot predicate exists for them; the fix is a SAFE NO-OP (cannot tag, cannot mis-tag). Do **not** widen to Clue/None roles — that tags every scene prop. WONTFIX unless the user requests a per-class opt-in lane.

Corroborating signal: these classes are also invisible to auto-**pickup** (its `DeterminGameplayRole==Loot` union sees the same 5 sites). So "this cube never auto-tags" should correlate with "it never auto-loots either."

---

## Open questions (only the in-game probe resolves)

- **Exact runtime class of the screenshot object** — entity templates live in game archives, not the script decompile. `DebugProbeAutoTagSweep` (`:350`) prints class names + `cand=`/`tagged=` buckets.
- Native loot-generation timing (when `wasLootInitalized` flips) — engine-side, decides whether Edit 1 alone would suffice; Edits 2+3 cover the lazy case regardless.
- Whether the object was merely beyond the streamed entity list — `candMax` in the probe line exposes this.

See `plan-autotag-role-loot-union.md` for the implemented fix + mandatory probe protocol.
