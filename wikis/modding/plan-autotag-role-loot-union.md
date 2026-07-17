# Plan: Auto-Tag Role-Loot Union (2026-07-16)

Give the auto-TAG classifier the same `DeterminGameplayRole()==EGameplayRole.Loot` union the auto-PICKUP gate has had since 2026-07-13, so not-yet-generated / content-cache-false loot objects reach the quality floor at all. Root-cause + verification: `autotag-role-loot-union-research.md`.

Status: **edits applied to `ScannerSuite.reds`** (2026-07-16). **NOT yet compiled** (game was running — `scc` deferred per the backup-corrupted rule). In-game probe **pending**.

Verify verdict: APPROVE-WITH-CHANGES, over-tag LOW/bounded. The one refinement (disabled guard on the gate) is folded in.

---

## The three edits (all applied)

**Edit 1 — gate, `ST_AutoTagCategory` (`~:957`).** Widen the collectable-lane gate with the role-Loot union + a PS-disabled guard:
```reds
let lootRole: Bool = Equals(this.DeterminGameplayRole(), EGameplayRole.Loot);
if lootRole {
  let lcGuard: ref<gameLootContainerBase> = this as gameLootContainerBase;
  if IsDefined(lcGuard) && lcGuard.IsDisabled() { lootRole = false; };
};
if this.IsContainer() || this.IsShardContainer() || this.IsItem() || lootRole { ... }
```
Disabled guard (verify Correction #1, preemptive): `DeterminGameplayRole` ignores the PS-disabled flag, so a disabled-but-stocked container would slip the gate via role where `IsContainer()` (`= !IsEmpty() && !IsDisabled()`) excludes it. Guarded cast mirrors the pickup path (`:2054`).

**Edit 2 — private-field shim (`~:892`, above `ST_LootMeetsQualityFloor`).**
```reds
@addMethod(gameLootContainerBase)
public final func ST_WasLootInitialized() -> Bool { return this.wasLootInitalized; }
```
`wasLootInitalized` (sic) is a `private import var` (`lootContainers.script:505`): false until loot generates (set true in `OnInventoryFilledEvent :684`), never reset. **Private-field-via-@addMethod compiles** — in-file precedent `APS_EnsureOpened` reads private `wasOpened` (`:1836-1841`).

**Edit 3 — rescue inside `ST_LootMeetsQualityFloor` (before the final `if !hasLoot`).**
```reds
if !hasLoot && Equals(this.DeterminGameplayRole(), EGameplayRole.Loot) {
  let lc: ref<gameLootContainerBase> = this as gameLootContainerBase;
  if IsDefined(lc) && !lc.ST_WasLootInitialized() && !lc.IsDisabled() { hasLoot = true; };
}
```
Never-generated container: `GetItemList=[]`, not `ItemObject` → `hasLoot` false → role rescues it ONLY while `wasLootInitalized` false and not disabled. `bestTier` stays 0 → passes Common floor only (raised floor still drops it, same as quality-less junk). Non-container Loot-role classes (bag/drop) cast-fail → unchanged transient-empty behavior.

---

## Invariants preserved (verified)
- Collectable-lane-first + `IsShardContainer()` unconditional (`:60`) keeps the `ShardCaseContainerPS m_markAsQuest` landmine consumed before the quest lane.
- Puppet lane returns before the widened gate → no alive-NPC tag; `ScriptedPuppet` `DeterminGameplayRole==Loot` site unreachable, and Edit-3 cast fails on puppets anyway.
- No `OnGameAttached`/streaming hook added (worker-crash memory). No LOS reintroduction. Changes stay inside the existing game-thread `DelayCallback` sweeps. Transient-None re-check untouched.

## REDscript constraints respected
Enum compare via `Equals()` (file convention `:1909`); no `continue`/`break`; guarded casts only; private-member `@addMethod` precedented (`wasOpened :1838`, protected `GetPS() :1830`). `EGameplayRole`/`gameLootContainerBase` already referenced in-file (`:1909`, `:2045`).

---

## Validation — REQUIRED, not optional

1. **Close the game first**, then clean serial compile (do NOT clear r6/cache):
   ```
   gd="/Users/teazyou/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077"
   "$gd/engine/tools/scc" -compile "$gd/r6/scripts"
   ```
   Expect 0 errors. If Edit 2 is rejected (private-field access), fall back to Edit 1 alone — the fix still lands whenever loot generates before the player leaves (transient-None re-check), just not on lazily-generated containers.

2. **In-game probe (MANDATORY — the fix is a genuine ~60% bet on THIS object).** Set `DebugProbeAutoTagSweep -> true` (`:350`), relaunch via `launch_modded.sh`, revisit the dumpsite, focus the cube. Decision tree:
   - (a) `cand=` + `tagged=` and marker visible → **fixed**; revert probe to false.
   - (b) `cand=` + `tagged=` but NO marker → render gap → disconnected bare `ItemObject` → data-side limit.
   - (c) still never `cand=` → read its class from the `|classes` list → non-loot-class prop (`gameCpoPickableItem`/`InspectDummy`/role-None Device) → hard vanilla limit, WONTFIX.

3. **Regression sniff (same session):** shard cases still tag; an emptied crate does NOT newly tag; alive NPCs / quest vehicles / vending machines / doors / explodables / breached access points never tag.

## Residual risks (all disclosed, bounded)
- Zero-yield generation: container tagged pre-generation whose loot generates empty keeps its tag (mod never untags). Rare for `ContainerObjectSingleItem` (fixed `itemTDBID :1049`). Accepted.
- Tag-then-vacuum flicker inside pickup range (dispatch is tag-first `:2196`). Cosmetic, pre-existing for trio-admitted crates.
