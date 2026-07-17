# Unlootable-Weapon Auto-Pickup Filter — Research Dossier (2026-07-14)

Scope: FEATURE 3 (auto-pickup) of the locally-authored **Custom Scanner Suite**
(`/Users/teazyou/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077/r6/scripts/custom-scanner-suite/ScannerSuite.reds`),
specifically the per-item filter chain inside the shared worker `GameObject.APS_TryAutoPickup`
(ScannerSuite.reds:1291-1449, filter loop at 1393-1418). Pure REDscript only, game v2.3 macOS Steam.

**The bug:** with the 360° radius channel (`EnableConstantAutoLoot`) on, some enemy-dropped weapons
get auto-looted into the player inventory, then are force-dropped back to the world the moment the
player re-equips their own weapon — and the radius channel immediately re-loots the same weapon,
producing an infinite drop → pickup → drop loop the player cannot escape by normal play (only by
disabling the mod or the weapon slot).

Evidence tier **[V]** = read directly in the local decompiled v2.3 vanilla sources
(`/private/tmp/claude-501/-Users-teazyou-dev-tmp-claude-cyberpunk/8dbf7d7b-2cd7-4203-ba6b-d76fe702851c/scratchpad/vanilla-scripts/scripts/`,
`.script`). Every citation is `file:line` in that tree. **[W]** = web source (URL given).

---

## Verdict up front

A **reliable, vanilla-sourced, per-item flag** exists and should be the primary filter:

> **`itemData.HasTag(n"NPCMeleeware")`** — skip the item if true.

This is not a guess: it is the exact tag CD Projekt Red's own code checks when it forcibly **strips
these items back out of the player's inventory** as a one-time save-migration fixup
(`EquipmentSystem.RemoveNPCMeleeware`, [V] `cyberpunk/systems/equipmentSystem.script:5547-5566`,
called from the version-gated migration block at `:5193-5199`). If CDPR's own retrofix logic treats
"has this tag → does not belong in the player's inventory, remove it," a pre-emptive skip in
auto-pickup is the mod-side mirror of the exact same rule, using the exact same API our own
`APS_IsQuestItem` already calls (`itemData.HasTag(n"Quest")`, ScannerSuite.reds:1279) — zero new API
surface, same cost as the existing quest-tag filter.

It is **not a complete fix for every conceivable unlootable weapon** — it is confirmed for the
*NPC-only melee prop* class only (see "Residual risk" below). No broader "NPC-only weapon" or
"cannot-be-held" tag/flag/ItemType exists anywhere in the decompiled script corpus (verified by
enumerating **every** `HasTag(...)` literal and **every** `gamedataItemType.*` value referenced in
~2,077 vanilla `.script` files — full lists in Appendix A/B). Ranking of everything found, most to
least reliable, follows.

| # | Predicate | Reliability | Cost | Verdict |
|---|---|---|---|---|
| 1 | `itemData.HasTag(n"NPCMeleeware")` | **High** (CDPR's own removal criterion) | Trivial (1 HasTag call, existing pattern) | **Adopt as primary filter** |
| 2 | Weapon-category item with no `EquipArea()` record | Medium — plausible, **unverified correlation** with #1 | Low-moderate (1 TweakDBInterface lookup + 1 record accessor) | Optional backstop only |
| 3 | Hardcoded TDBID/tag blacklist (named iconics/bosses) | As good as the list, i.e. **incomplete by construction** | High (manual discovery + maintenance per patch) | Fallback for named exceptions only, CDPR itself does this |
| — | `EquipmentSystem.IsEquippable(itemData)` | **Wrong tool** — over-broad | — | **Rejected** (see below) |
| — | `RPGManager.CanItemBeDropped` | **Wrong question** — inverse concept | — | **Rejected** (see below) |
| — | `GameObject.IsQuest()` | Already proven wrong in this file's own history | — | **Rejected** (shard-case false positive, documented) |
| — | `Item_Record.DropSettings()` (`ItemDropSettings_Record`) | Dead end | — | **Rejected** (physics params only, no gate) |

---

## 1. How the bug happens (confirmed from the mod's own source)

Read `ScannerSuite.reds` in full (1519 lines). The auto-pickup worker `APS_TryAutoPickup`
(GameObject, ScannerSuite.reds:1291-1449) already has a real per-item filter chain
(:1393-1418), evaluated once per `itemData` in the corpse/container's `GetItemList`:

```
nameless internal placeholder (name == "" && != Gen_Readable)  -> always skip (structural)
APS_IsQuestItem: HasTag('Quest') || HasTag('UnequipBlocked')   -> hard rule, never taken
!AutoPickupTakeHeavyWeapons && Wea_HeavyMachineGun             -> skip (config knob)
!AutoPickupTakeIconic && RPGManager.IsItemIconic(itemData)     -> skip (config knob)
else                                                            -> ArrayPush(lootIDs, …); TransferItem later
```

Nothing in this chain inspects whether the item can actually be *held* by the player long-term. A
dead NPC's `GetItemList` (read via `TransactionSystem.GetItemList`, called at ScannerSuite.reds:1367)
includes whatever weapon that NPC had equipped, tag warts and all. If that weapon is an NPC-only
melee prop, it sails through every existing filter, gets
`transSys.TransferItem(this, player, lootIDs[li], lootQtys[li])`'d (ScannerSuite.reds:1437) into the
player's inventory exactly like any normal drop — and the shared one-attempt-per-entity ledger
(`m_apsAttempted`, ScannerSuite.reds:884-906) marks the corpse done, so the mod itself never re-loots
*that corpse*. The infinite loop the user sees is therefore **not** the auto-tag/auto-pickup ledger
re-firing on the same corpse; it is the weapon **re-entering the world as a fresh loot entity** (a
force-drop respawns it as a new `gameItemDropObject`/`ItemObject` pair with a new `EntityID`), which
the always-on 360° radius pass (`APS_RunSurroundingsPickup`, ScannerSuite.reds:1032-1074) then treats
as a brand-new, never-attempted piece of loot and vacuums again — repeat forever.

This means the fix belongs entirely in the **pre-transfer filter**, not in the ledger: never let the
item enter the inventory in the first place, and the force-drop/re-spawn/re-loot cycle has nothing to
attach to.

## 2. What actually force-drops the weapon on re-equip — **SOLVED 2026-07-14 (review pass)**

> **This section's original conclusion ("honest gap — no reactive hook, no verified force-drop
> branch") was WRONG, and the plan built on it (`plan-unlootable-weapon-filter.md`) inherited the
> error.** The force-drop is fully present in the decompile. It was missed because the greps covered
> `equipmentSystem.script` / `itemActionsHelper.script` / `scriptedPuppet.script` /
> `tweakAISubActions.script` but **not the player state machine**, and searched for the names
> `ForceDrop` / `DropItem` while the vanilla function is called **`DropActiveWeapon`**. The original
> text is kept below the fold for the record.

**The exact trigger** — [V] `cyberpunk/player/psm/equipment.script:1362`, in the weapon-unequip state
exit (right-hand logic, item category `Weapon`):

```
if( ( GetEquipAreaFromItemID( item ) == gamedataEquipmentArea.WeaponHeavy
      || ( ( ItemObject )( itemObject ) ).GetItemData().HasTag( 'DiscardOnEmpty' ) )
    && ( upperBodyState != ( ( Int32 )( gamePSMUpperBodyStates.ForceEmptyHands ) ) ) )
{
    DropActiveWeapon( scriptInterface, stateContext, stateMachineInstanceData );
}
```

`DropActiveWeapon` ([V] `equipment.script:363-377`) calls
`GameInstance.GetLootManager(...).SpawnItemDrop( owner, weaponID, worldPosition, dropRotation )` with
`worldPosition = Transform.TransformPoint( cameraWorldTransform, Vector4(0.4, -0.6, -0.5, 0) )` — a
**brand-new ground-drop entity ~0.9 m from the camera, at V's feet**.

The same condition appears again in [V] `cyberpunk/player/psm/weaponTransitions.script:1881`
(`NoAmmoEvents.OnEnter` force-swaps away from such a weapon when its magazine runs dry).

**This is the user's bug, verbatim**: "when I equip my normal weapon back, that weapon is dropped
again" == V unequips → PSM sees `EquipArea == WeaponHeavy` → `DropActiveWeapon` → fresh drop entity
(new `EntityID`, so the mod's one-attempt ledger `m_apsAttempted` is blind to it) → the 360° pass
re-vacuums it 0.5 s later → forever.

**Therefore the reliable programmatic identifier EXISTS and needs no blacklist:**

| Signal | Where | Meaning |
|---|---|---|
| `EquipmentSystem.GetEquipAreaType( itemID ) == gamedataEquipmentArea.WeaponHeavy` | [V] `equipmentSystem.script:5748` (static; `TweakDBInterface.GetItemRecord(...).EquipArea().Type()`), enum [V] `tweakDBEnums.script:3130` | HMG / turret class. `WeaponObject.IsHeavyWeapon()` is *defined* as exactly this ([V] `weapon.script:159`). Carry-only: vanilla force-drops it on unequip. |
| `itemData.HasTag( 'DiscardOnEmpty' )` | [V] `equipment.script:1362`, `weaponTransitions.script:1881` | Same force-drop branch. (Ironically this tag was already sitting in this dossier's own Appendix A tag dump — enumerated, never connected.) |
| `itemData.HasTag( 'NPCMeleeware' )` | [V] `equipmentSystem.script:5562` | CDPR's own strip-from-player-inventory retrofix. Cheap superset, keep. |

Corollary: candidate #2 below (§4, "weapon with no `EquipArea()`", rejected as an *unverified
correlation*) was pointing at the right record field for the wrong reason. The signal is not a
**missing** `EquipArea()` — it is `EquipArea() == WeaponHeavy`, and it is not a correlation at all: it
is literally the `if` that guards the drop.

Refusing to auto-collect this class is not a restriction, it is the vanilla contract: heavy weapons
are *meant* to be taken by hand (the Take prompt puts V into the carry state properly — [V]
`scriptedConditions.script:403` even refuses the pickup interaction on a `WeaponHeavy` weapon while V
is already carrying something) and dropped again when done. They are not inventory items.

<details>
<summary>Original (incorrect) §2 text, kept for the record</summary>

Grepped exhaustively for `ForceDrop`, `DropItem`, `UnequipItem`, `CanTransferItem`, `IsItemDroppable`,
`EquipmentArea.Invalid`, and the full equip/holster pipeline in `equipmentSystem.script`,
`itemActionsHelper.script`, `scriptedPuppet.script`, `tweakAISubActions.script`. **No single vanilla
function was found whose job is explicitly "eject any inventory item that fails an equip-slot
validity check."** What was found instead is indirect but consistent:

- `ScriptedPuppet.DropItemFromSlot` ([V] `cyberpunk/puppet/scriptedPuppet.script:3121`) and
  `AISubActionThrowItem`/`AIActionHelper.SetItemsUnequipData` ([V]
  `core/ai/actions/tweakAISubActions.script:1000,1181,1352`) are the NPC-side "make this AI drop its
  weapon" primitives — they run on the *NPC*, not the player, and are how the corpse got the weapon
  onto the ground/into its loot list to begin with.
- `EquipmentSystem.RemoveNPCMeleeware` ([V] `cyberpunk/systems/equipmentSystem.script:5547-5566`,
  quoted in full below) is CDPR's own admission that these items ending up in the *player's*
  inventory is an anomaly serious enough to need a forced, silent `TS.RemoveItemByTDBID` cleanup —
  run once per save on first load after patch 2.0 (`gameGameVersion.Current >= 2099`, `saveVersion <=
  257`, gated by fact `NPCMeleewareRemoved`, [V] `equipmentSystem.script:5193-5199`). It does not
  drop the item into the world — it deletes it outright.

Given (a) CDPR's own fixup only *removes*, it does not describe a live "keeps getting dropped" loop,
and (b) our mod's transfer path (`TransactionSystem.TransferItem`, a raw inventory-to-inventory move)
completely bypasses the picked-up-weapon vetting that the normal player-loot UI or auto-equip-on-pickup
path would otherwise run, the most defensible conclusion is: **the force-drop the user is seeing is an
emergent side effect of an item that was never supposed to be able to reach the player's equip
pipeline getting there anyway** (no valid equip slot / appearance data for the player skeleton), not
one single documented "reject" branch we can call directly. This is exactly why the fix has to be
prophylactic (never transfer it) rather than reactive (catch the force-drop) — there is no verified
reactive hook to catch.

</details>

*(The "prophylactic, not reactive" conclusion above survives — and is now much stronger, because the
prophylactic predicate is exact rather than inferred. Everything else in the original §2 is
superseded.)*

## 3. Candidate #1 (DEMOTED to a cheap superset — see §2): `itemData.HasTag(n"NPCMeleeware")`

> **2026-07-14 review:** this is a real "V must not hold this" signal and is kept in the shipped
> predicate, but it is **melee-cyberware-scoped and is almost certainly NOT the user's weapon**. The
> primary signal is the `WeaponHeavy` equip area / `DiscardOnEmpty` tag from §2.

**Full text of the vanilla function that defines this tag's meaning:**

```
// [V] cyberpunk/systems/equipmentSystem.script:5547-5566
private function RemoveNPCMeleeware()
{
	var i : Int32;
	var itemList : array< weak< gameItemData > >;
	var TS : TransactionSystem;
	var player : weak< PlayerPuppet >;
	var itemData : ItemID;
	player = GetMainPlayer( GetGameInstance() );
	if( player )
	{
		TS = GameInstance.GetTransactionSystem( GetGameInstance() );
		TS.GetItemList( player, itemList );
	}
	for( i = 0; i < itemList.Size(); i += 1 )
	{
		if( itemList[ i ].HasTag( 'NPCMeleeware' ) )
		{
			itemData = itemList[ i ].GetID();
			TS.RemoveItemByTDBID( player, ItemID.GetTDBID( itemData ), 1 );
		}
	}
}
```

Called from the save-migration dispatcher:

```
// [V] cyberpunk/systems/equipmentSystem.script:5193-5199
factVal = GetFact( GetGameInstance(), 'NPCMeleewareRemoved' );
if( ( ( factVal <= 0 ) && ( ( ( Int32 )( gameGameVersion.Current ) ) >= 2099 ) ) && ( saveVersion <= 257 ) )
{
	RemoveNPCMeleeware();
	SetFactValue( GetGameInstance(), 'NPCMeleewareRemoved', 1 );
}
```

**Why this is the right predicate, not a coincidence:**

- It is walking the **player's own inventory** (`TS.GetItemList(player, itemList)`) — i.e. this is
  CDPR's own statement that an `NPCMeleeware`-tagged item showing up in *player* possession is wrong
  and must be corrected, unconditionally, no exceptions, no config.
- It is gated to fire once per save on the first load after patch 2.0 — a real migration for a real
  historical leak, meaning real save files really did contain these items in player inventory before
  this existed. That is the exact failure mode our auto-pickup risks re-creating live, every session,
  via a different door (our mod's raw `TransferItem`, instead of whatever pre-2.0 bug originally
  leaked them).
- **The API is already in production in this exact mod file.** `GameObject.APS_IsQuestItem`
  (ScannerSuite.reds:1277-1280) already calls `itemData.HasTag(n"Quest") ||
  itemData.HasTag(n"UnequipBlocked")` on the identical `wref<gameItemData>` type flowing through
  `APS_TryAutoPickup`'s filter loop. The base signature:

  ```
  // [V] core/data/itemData.script:9
  public import const function HasTag( tag : CName ) : Bool;
  ```

  Adding `itemData.HasTag(n"NPCMeleeware")` as one more `else if` arm is a same-pattern, same-cost,
  zero-new-API addition.

**Reliability:** High for the class it targets (NPC-only melee "prop" weapons — the tag name itself
says so, and CDPR's own removal logic confirms the semantics). Not proven to cover every possible
unlootable weapon in the game (see Residual risk).

**Cost:** One `HasTag` call per item, same call already paid twice per item for the quest check.

## 4. Candidate #2 (SECONDARY backstop, unverified correlation): weapon with no `EquipArea()`

`Item_Record` exposes:

```
// [V] core/data/tweakDBRecords.script:5076  (class Item_Record, opened :5067)
public import function EquipArea() : weak< EquipmentArea_Record >;
```

reachable from a live item via:

```
// [V] core/data/tweakDB.script:517
public import static function GetItemRecord( path : TweakDBID ) : Item_Record;
// combined with the already-used-in-this-mod pattern:
// ItemID.GetTDBID(itemData.GetID())  — ScannerSuite.reds:1398 already calls this exact chain
//   for UIItemsHelper.GetItemName(ItemID.GetTDBID(itemData.GetID()), itemData)
```

and the category gate:

```
// [V] core/data/tweakDBRecords.script:5094 (Item_Record.ItemCategory)
public import function ItemCategory() : weak< ItemCategory_Record >;
```

(`ItemCategory().Type() == gamedataItemCategory.Weapon` is the exact test `equipmentSystem.script`
itself uses at its private `IsItemAWeapon`, [V] `equipmentSystem.script:1990-1995`.)

Vanilla's own loot-list UI treats a missing `EquipArea()` as a real, load-bearing sentinel, not an
edge case it papers over:

```
// [V] cyberpunk/UI/interactions/looting.script:578-584
equipRecord = itemRecord.EquipArea();
if( equipRecord )
{
	equipmentArea = equipRecord.Type();
}
else
{
	equipmentArea = gamedataEquipmentArea.Invalid;
}
```

**Reasoning for the candidate:** a weapon `Item_Record` with no `EquipArea()` at all has, structurally,
nowhere in the player's weapon-wheel/paperdoll it could ever be placed — which is a plausible root
cause of "keeps getting force-dropped": vanilla equip/holster bookkeeping has no slot to reconcile it
into. **What is NOT verified:** whether `NPCMeleeware`-tagged records actually lack `EquipArea()`
(the correlation is architecturally plausible but the truth lives in TweakDB `.yaml`/archive data, not
in decompiled `.script` logic — out of reach for a script-only grep). Also unverified: whether any
*legitimate* player-lootable weapon type ever lacks `EquipArea()` (a false positive here would
silently refuse a normal weapon forever via the worker's existing "final refusal" semantics — a
regression class this file has been bitten by before, see `APS_IsCollectable`'s commentary on
content-cached vs. structural gates, ScannerSuite.reds:1230-1238).

**Recommendation:** keep this as an optional, config-gated backstop at most, restricted to
`ItemCategory().Type() == gamedataItemCategory.Weapon` items only (never widen it to clothing/
cyberware/consumables, which legitimately use different equip plumbing) — not a required part of the
fix. Candidate #1 alone should resolve the reported bug.

**Reliability:** Medium (plausible mechanism, unconfirmed data correlation). **Cost:** one
`TweakDBInterface.GetItemRecord` + one `EquipArea()` accessor call per item — more indirection than
#1's single `HasTag`, still cheap (both are `import` native calls, no allocation).

## 5. Candidate #3: hardcoded TDBID/tag blacklist — feasibility

**Is a blanket wildcard enumerable (e.g. "all `Items.Preset_*_NPC` records")?** No such naming
convention appears anywhere in the ~2,077-file decompiled script corpus — TweakDB record path
strings (`T"Items.XXX"`) are opaque literals baked into compiled script bytecode; script code never
enumerates "every record under a prefix," it only ever references specific, individually-named paths.
Discovering the full set would require a TweakDB dump/browser tool (e.g. WolvenKit) working on the
actual `.tweak`/archive data, which is outside this project's redscript-only, no-CET/no-RED4ext scope
(project CLAUDE.md: mod is pure REDscript).

**Does CDPR itself hardcode individual exceptions? Yes — right next to `RemoveNPCMeleeware`,** in the
very same save-migration dispatcher in `equipmentSystem.script`, confirming that even CDPR, with full
internal data access, resorts to naming individual problem items one at a time for anything narrower
than the generic `NPCMeleeware` class:

```
// [V] equipmentSystem.script:5540-5545 — single hardcoded TDBID, no tag involved
ts.RemoveItemByTDBID( player, T"Items.NeoFiberLegendary", 1 );
```

```
// [V] equipmentSystem.script:5602+ (ProcessMaskCWRestoration) — per-tag cleanup, single named item
if( itemList[ i ].HasTag( 'MaskCWPlus' ) ) { … TS.RemoveItemByTDBID(...) }
… itemData = ItemID.FromTDBID( T"Items.MaskCWPlus" ); TS.GiveItem( player, itemData, 1 );
```

Enumerating every `HasTag('...')` literal in the corpus (Appendix A) turns up a cluster of similar
**single-character/single-quest identifiers** used the same way — each is presumably a past leak that
needed its own fact-gated retrofix, exactly like `NPCMeleeware` and `NeoFiberLegendary`:
`'Sasquatch_Hammer'`, `'Rasetsu'`, `'BountyHunterIconicKnife'`, `'KurtIconicKnife'`, `'Gog_Katana'`,
`'Nekomata_Breakthrough'`, `'Nue_Jackie'`, `'Grad_Panam'`, `'Buck_Grad'`, `'Clouds_VIP'`,
`'Competition_Lexington'`, `'Ozob'`. These were **not individually traced** (out of scope / low
expected value: each is a one-off named item, several plausibly clothing/cyberware rather than
weapons — e.g. `'Clouds_VIP'` reads as an outfit tag), but their existence is the evidence for the
answer to the ground-truth question this dossier was asked to resolve:

> **Must we hardcode a blacklist of TweakDB record names?** For the *general* NPC-melee-prop class,
> no — `NPCMeleeware` covers it as a tag, not a per-record list. For genuinely unique/boss/iconic
> weapons that misbehave the same way, **CDPR's own precedent says yes**, a small hardcoded list is
> the realistic fallback, because no broader flag for "this specific unique item is unsafe to hold"
> exists — only ad hoc per-item tags CDPR invented one at a time as bugs were reported. Any such list
> we author will, like CDPR's, always be reactive (added after a specific weapon is reported) and
> incomplete by construction — this is a cost to accept, not a solvable gap.

**Reliability:** bounded by list completeness — degrades over time / with new content, never
self-updating. **Cost:** high relative to #1 — needs a real specimen (TDBID or tag) reported by the
user before it can be added, then a manual `ArrayContains`-style check + array literal to maintain.

**Recommendation:** do not build this preemptively. Ship #1 now; if the user hits a *specific* named
weapon that still loops (i.e. not melee, or melee but somehow untagged), capture its TDBID from the
`DebugProbeAutoPickup` log line (`APS surround: …` / `APS cursor: lookAt -> ` +
`NameToString(target.GetClassName())`, ScannerSuite.reds:1070-1073, 1143-1146) or add a one-line probe
printing `ItemID.GetTDBID(itemData.GetID())` in the filter loop, and add that single ID to a small
`AutoPickupBlockedItemIDs` array as a targeted, evidence-based patch — exactly CDPR's own pattern.

## 6. Rejected candidates (documented so the next pass doesn't re-walk this path)

**`EquipmentSystem.IsEquippable(itemData)`** — looks tempting (name matches the ask) but answers a
different question:

```
// [V] cyberpunk/systems/equipmentSystem.script:2018-2032
public const function IsEquippable( itemData : weak< gameItemData > ) : Bool
{
	if( itemData == NULL ) { return false; }
	if( RPGManager.IsItemBroken( itemData ) ) { return false; }
	if( !( CheckEquipPrereqs( itemData.GetID(), itemData.GetVariant() ) ) ) { return false; }
	statsSys = GameInstance.GetStatsSystem( m_owner.GetGame() );
	ownerLevel = statsSys.GetStatValue( m_owner.GetEntityID(), gamedataStatType.Level );
	itemLevel = ( ( Float )( FloorF( itemData.GetStatValueByType( gamedataStatType.Level ) ) ) );
	return ownerLevel >= itemLevel;
}
```

This is "can the player equip this **right now**" — broken-quality items and items above the player's
current level both legitimately return `false` here, and both are completely normal, storable loot
the mod is explicitly designed to keep vacuuming (broken/quality-less loot is the entire subject of
`ST_LootMeetsQualityFloor`'s quality-less carve-out, ScannerSuite.reds:554-562). Wiring this in as a
skip-filter would silently stop looting most low-level trash and any weapon above the player's current
level — a severe regression, not a fix. **Rejected: conflates "equippable now" with "storable at
all."**

**`RPGManager.CanItemBeDropped`** — already documented in
`wikis/modding/interaction-based-autoloot-research.md` (its full body, [V]
`cyberpunk/managers/rpgManager.script:2963-2973`, refuses `IconicWeapon`/`Quest`/`UnequipBlocked` +
requires `ItemActionsHelper.GetDropAction(itemID)` to be non-null). This answers "can the player
**voluntarily eject** this item from inventory" (protects iconics/quest items from an accidental manual
drop) — the inverse of our question, and our mod's policy explicitly **wants** to auto-collect iconics
by default (`AutoPickupTakeIconic`, default true). Gating pickup on this would wrongly block every
iconic weapon pickup. **Rejected: opposite-facing check.**

**`GameObject.IsQuest()`** — already proven unusable as any kind of loot gate by this codebase's own
prior research (`ShardCaseContainerPS.m_markAsQuest = true` for every shard case in the game,
[V] `cyberpunk/containers/shardCaseContainer.script:1-4`, fully documented in
`interaction-based-autoloot-research.md`). Not re-litigated here beyond citing it as precedent for
"whole-object flags on this class of question are the wrong altitude — item tags are the right
altitude," which is exactly why `NPCMeleeware` (an item tag) is trusted here and a hypothetical
whole-object "this corpse carries unsafe loot" flag would not be.

**`Item_Record.DropSettings()` → `ItemDropSettings_Record`** — dead end:

```
// [V] core/data/tweakDBRecords.script:5308-5312
importonly class ItemDropSettings_Record extends TweakDBRecord
{
	public import function DesiredAngularVelocity() : Float;
	public import function DesiredInitialRotation() : Float;
}
```

Purely the tumble physics for the dropped-item visual (how it spins/settles on the ground). No
boolean "can be dropped/held" gate anywhere on `Item_Record` or its base `BaseObject_Record`
([V] `tweakDBRecords.script:3193-3223`, no `Tags()`/drop-eligibility member). **Rejected.**

## 7. Web research — community precedent

- **[W]** [Autoloot (Nexus 5202)](https://www.nexusmods.com/cyberpunk2077/mods/5202) — per search
  summary, this mod explicitly **excludes Turrets and Heavy Machine Guns** ("weapons that cannot be
  equipped in normal gameplay") from its auto-loot, and leaves "protected" items (quest, heavy
  weapons) for manual pickup. This mirrors exactly the HMG carve-out our mod already has
  (`AutoPickupTakeHeavyWeapons`, ScannerSuite.reds:314-316) — no new information, but independent
  confirmation that HMG-class exclusion is a known, standard auto-loot concern, not unique to us.
- **[W]** ["Pick-up and equip weapon restrictions fix"](https://www.cyberpunk2077mod.com/pick-up-and-equip-weapon-restrictions-fix/)
  — mod description only: *"Fix pick-up and equip weapon glitch during fists fights – no more
  equipping dropped weapons when it's not allowed."* WebFetch of the page yielded no technical detail
  (no TweakDB records, no tag names, no code). This is almost certainly a **different mechanism** —
  the scripted "forced fists" fight state (`StatusEffectSystem.ObjectHasStatusEffectWithTag(player,
  'FirearmsNoSwitch')`, [V] `cyberpunk/UI/inventory/inventoryItemData.script:973,993` — a **context**
  gate on the player, unrelated to any per-item tag) rather than a property of the weapon itself. Not
  applicable to our bug (our repro has no fist-fight context implied) but noted so it isn't
  re-investigated as if it were the same bug.
- **[W]** General search for "NPCMeleeware" (exact string) returned **zero results** anywhere on the
  public web — this tag is undocumented outside CDPR's own shipped script bytecode. No modder-authored
  auto-loot mod on Nexus/GitHub was found to already special-case it; this dossier's finding appears
  to be new, not a rediscovery of known modder folklore.
- No forum/wiki report of the exact "weapon keeps getting re-dropped in an infinite loop" symptom was
  found in the general Cyberpunk bug-report corpus — the closest hits were about loot **visually
  clipping into geometry and being unreachable** (a different, well-known bug — see
  [GameRevolution guide](https://www.gamerevolution.com/guides/670092-cyberpunk-2077-cant-pick-up-loot-fix-pc-ps5-ps4-xbox),
  [GOG forum thread](https://www.gog.com/forum/cyberpunk_2077/unable_to_pick_up_items)), not our
  reported failure mode. This is consistent with the loop being specific to *auto-pickup bypassing the
  normal loot-take UI's implicit vetting* — i.e., largely self-inflicted by this mod's own
  `TransactionSystem.TransferItem` shortcut, not a base-game-vanilla-play bug ordinary players would
  ever hit (they'd simply never be offered a "Take" prompt for the NPC-only prop in the first place).

## 8. Suggested implementation (illustrative — not applied; this is a research note only)

Same shape as the existing `APS_IsQuestItem` rule (ScannerSuite.reds:1277-1280), added as one more
hard rule (not a config knob, matching the project's treatment of the other structural/vanilla-defined
skip in this same loop):

```redscript
// Mirrors APS_IsQuestItem exactly. 'NPCMeleeware' is the tag CDPR's own
// EquipmentSystem.RemoveNPCMeleeware (equipmentSystem.script:5547-5566) forcibly strips from
// player inventory as a save-migration fixup — i.e. vanilla's own definition of "must not be
// held by the player." Never auto-collected; player can still hand-pick it if they really want to
// (mirrors the quest-item policy: the object stays interactable, only the vacuum skips it).
@addMethod(GameObject)
public final func APS_IsNPCOnlyWeapon(itemData: wref<gameItemData>) -> Bool {
  return itemData.HasTag(n"NPCMeleeware");
}
```

and one more `else if` arm in `APS_TryAutoPickup`'s filter loop (ScannerSuite.reds:1401, right after
the existing `APS_IsQuestItem` arm):

```redscript
} else if this.APS_IsQuestItem(itemData) {
  // existing quest rule …
} else if this.APS_IsNPCOnlyWeapon(itemData) {
  // NPC-only melee prop (vanilla RemoveNPCMeleeware precedent) — never auto-collected;
  // still hand-lootable via the normal Take prompt.
} else if !takeHeavy && Equals(itemType, gamedataItemType.Wea_HeavyMachineGun) {
  // existing HMG rule …
```

This is a **TRANSIENT-safe** skip exactly like the quest rule: the object's other items (if any) are
still vacuumed, the corpse/container is not burned, and the NPC-only weapon simply stays on the
ground/corpse for the player to manually inspect if they ever want to.

## 9. Residual risk / open questions for a future pass

1. **Ranged NPC-only weapons.** `NPCMeleeware` is, per its name and CDPR's own function name, scoped
   to melee. No sibling `NPCRangedware`/`NPCFirearm`-style tag was found anywhere in the corpus
   (Appendix A is the complete `HasTag` literal set found). Most thug/ganger ranged weapons in
   Cyberpunk appear to be ordinary player-lootable records (shared armory), which is consistent with
   ranged weapons not needing this carve-out — but this is an absence-of-evidence, not a proof the
   user's specific repro was melee. **If the user's next repro is a ranged weapon, candidate #2
   (missing `EquipArea()`) becomes the more relevant fallback to actually implement**, or capture its
   TDBID (see §5's probe suggestion) for a targeted blacklist entry.
   *(Correction after the note above was drafted: `NPCMeleeware`'s own name and the AI-melee-prop
   context strongly suggest this covers melee only by design, not by an incomplete search — treat the
   "ranged" gap as expected, not as a research shortfall.)*
2. **Exact force-drop trigger is still unidentified** (§2). If `NPCMeleeware` fully resolves the
   user's repro, this gap is moot. If the loop recurs on a *different* weapon after shipping candidate
   #1, the next step should be a live repro with `DebugProbeAutoPickup` on to capture the offending
   item's tags/type/TDBID directly, rather than more static grepping — the remaining unknown is a data
   question (what tags does *that specific* record carry), not a code-path question.
3. Candidate #2 was deliberately **not shipped** pending confirmation that #1 alone fixes the reported
   case — adding an unverified structural gate risks a false-positive "final refusal" on some
   legitimate weapon type this research did not have game-data access to check (TweakDB `.yaml` /
   archive contents are outside this REDscript-only research's reach).

---

## Appendix A — every `HasTag('...')` / `HasTag(n"...")` literal found in the vanilla script corpus

(Full enumeration; source of the "no broader NPC-weapon tag exists" claim in the Verdict.)

```
AdvancedSubdermalCoProcessor_Regina, Alcohol, AllowProgramLink, Ammo, AnimCycleRound, ArmorMod,
AutoScalingItem, base_fists, Body, BossExo, BountyHunterIconicKnife, Buck_Grad, bullet_no_destroy,
Buzz, CapacityBooster, ChemResMod, ChimeraMod, Clothing, Clouds_VIP, Competition_Lexington,
Consumable, Cool, CraftingPart, Currency, CWCapacity_Shard, Cyberdeck, Cyberware, CyberwareUpgrade,
DeprecatedWeaponMod, DiscardOnEmpty, DLCAdded, DLCStashItem, Dreads, Drink, DummyPart,
DummyWeaponMod, Food, ForceRevealConsumable, Fragment, Gog_Katana, Grad_Panam, Grenade, Grit,
HideInUI, HideProgramDuration, IconicRecipe, IconicWeapon, ignore_player_bullets, IllegalFood,
IllegalItem, Important, Intelligence, inventoryDoubleSlot, itemPart, jammer, Jewellery, Junk,
JurijProjectile, KeepRenderPlane, KurtIconicKnife, LargeSkillbook, Left_Hand, Left_Hand_Retrofix,
Long, LongLasting, Looting, MantisBlades, MaskCWPlus, MeatBag, Melee, MeleeDmgRedMod, MoneyShard,
MustBeWearableToPurchase, Nekomata_Breakthrough, NoLootMappin, NPCMeleeware, Nue_Jackie, Ozob,
PerkSkillbook, PermanentFood, PermanentHealthFood, PermanentMemoryFood, PermanentStaminaFood,
q005_saburo_dogtag, Quest, QuickhackCraftingPart, QuickhackDmgRedMod, QuickhackUploadMod, Rasetsu,
Recipe, Reflex, ReloadMod, RescalePL, Ripperdoc, Sasquatch_Hammer, Shard, Short, ShowStackPrice,
skillbook, SkillbookReward_Body, SkillbookReward_Cool, SkillbookReward_Int, SkillbookReward_Ref,
SkillbookReward_Tech, SkipActivityLog, SkipActivityLogOnLoot, SkipActivityLogOnRemove, Slaughtomatic,
SmartWeapon, SoftwareShard, StashScaling_Iconic, StrongArms, Tactician_Headsman, TakeAndEquip, Tech,
TechWeapon, Throwable, TppHead, TransmogBlocked, UnequipBlocked, VendorIconicItem, VisibilityMod,
Wardrobe, WorkspotSyncAnimated, ZoomMod
```

## Appendix B — every `gamedataItemType.*` value referenced in the vanilla script corpus

```
Clo_Face, Clo_Feet, Clo_Head, Clo_InnerChest, Clo_Legs, Clo_OuterChest, Clo_Outfit, Con_Ammo,
Con_Edible, Con_Inhaler, Con_Injector, Con_LongLasting, Con_Skillbook, Count, Cyb_Ability,
Cyb_HealingAbility, Cyb_Launcher, Cyb_MantisBlades, Cyb_NanoWires, Cyb_StrongArms, Cyberware,
CyberwareStatsShard, CyberwareUpgradeShard, Fla_Launcher, Fla_Rifle, Fla_Shock, Fla_Support,
Gad_Grenade, Gen_CraftingMaterial, Gen_DataBank, Gen_Jewellery, Gen_Junk, Gen_Keycard, Gen_Misc,
Gen_MoneyShard, Gen_Readable, Gen_Tarot, Grenade_Core, GrenadeDelivery, Invalid,
Prt_AR_SMG_LMGMod, Prt_BladeMod, Prt_BluntMod, Prt_BootsFabricEnhancer, Prt_Capacitor,
Prt_FabricEnhancer, Prt_FaceFabricEnhancer, Prt_Fragment, Prt_HandgunMod, Prt_HandgunMuzzle,
Prt_HeadFabricEnhancer, Prt_LongScope, Prt_Magazine, Prt_MeleeMod, Prt_Mod, Prt_Muzzle,
Prt_OuterTorsoFabricEnhancer, Prt_PantsFabricEnhancer, Prt_PowerMod, Prt_PowerSniperScope,
Prt_Precision_Sniper_RifleMod, Prt_Program, Prt_RangedMod, Prt_Receiver, Prt_RifleMuzzle,
Prt_Scope, Prt_ScopeRail, Prt_ShortScope, Prt_ShotgunMod, Prt_SmartMod, Prt_Stock,
Prt_TargetingSystem, Prt_TechMod, Prt_TechSniperScope, Prt_ThrowableMod, Prt_TorsoFabricEnhancer,
Wea_AssaultRifle, Wea_Axe, Wea_Chainsword, Wea_Fists, Wea_GrenadeLauncher, Wea_Hammer, Wea_Handgun,
Wea_HeavyMachineGun, Wea_Katana, Wea_Knife, Wea_LightMachineGun, Wea_LongBlade, Wea_Machete,
Wea_Melee, Wea_OneHandedClub, Wea_PrecisionRifle, Wea_Revolver, Wea_Rifle, Wea_ShortBlade,
Wea_Shotgun, Wea_ShotgunDual, Wea_SniperRifle, Wea_SubmachineGun, Wea_Sword, Wea_TwoHandedClub,
Wea_VehicleMissileLauncher, Wea_VehiclePowerWeapon
```

No `Wea_*` value reads as an NPC-exclusive category (e.g. no `Wea_NPCOnly`/`Wea_Prop`) — the
distinction between a player-safe and an NPC-only weapon of the same nominal type (e.g. two different
`Wea_Melee` records) lives entirely in the **tag**, not the **type**. This is further confirmation
that `HasTag(n"NPCMeleeware")` (a tag test) is the right altitude, and no `ItemType`-based filter could
ever substitute for it.

## Appendix C — files/APIs read for this dossier (no vanilla file was edited; read-only throughout)

- `ScannerSuite.reds` (full, 1519 lines) — current mod source, auto-pickup filter chain.
- `wikis/modding/interaction-based-autoloot-research.md` — prior art on the quest-tag rule and
  `IsQuest()` rejection (not re-derived, cited).
- `wikis/modding/constant-auto-loot-research.md`, `plan-unified-auto-loot.md`,
  `scan-mode-auto-pickup.md`, `scanner-suite-refinements.md`, `scan-mode-auto-tagging.md`,
  `plan-auto-pickup-on-scan.md`, `plan-auto-tag-on-scan.md` — grepped for prior mentions of this bug
  (force-drop / infinite loop / NPCMeleeware / fists / EquipArea); none found — this is new ground.
- `cyberpunk/systems/equipmentSystem.script` — `IsEquippable` (x2 overloads), `RemoveNPCMeleeware`,
  `ProcessMaskCWRestoration`, `IsItemAWeapon`, save-migration dispatcher, holstered-arms/fists swap
  logic (`base_fists` context).
- `cyberpunk/managers/rpgManager.script` — `CanItemBeDropped`, `CanPartBeUnequipped`, `GetItemRecord`.
- `cyberpunk/UI/interactions/looting.script` — loot-list `EquipArea`/`Invalid` UI fallback.
- `cyberpunk/UI/inventory/inventoryItemRequirements.script`, `inventoryItemData.script` — UI-side
  `IsEquippable` wiring, `FirearmsNoSwitch` context gate.
- `cyberpunk/items/actions/itemActionsHelper.script` — `DropItem`, `GetDropAction`.
- `core/data/itemData.script`, `core/data/tweakDBRecords.script`, `core/data/tweakDB.script`,
  `core/data/tweakDBEnums.script` — `HasTag` base signature, `Item_Record`/`BaseObject_Record`/
  `ItemDropSettings_Record`/`EquipmentArea_Record` class shapes, `gamedataItemCategory` enum format.
- `core/ai/actions/tweakAISubActions.script`, `cyberpunk/puppet/scriptedPuppet.script` — NPC-side
  `DropItem`/`DropItemFromSlot` (ruled out as the player-side mechanism).
- Web: Nexus Autoloot (5202) mod page summary, cyberpunk2077mod.com fist-fight weapon-restriction
  mod page (fetched, no technical detail), GameRevolution/GOG loot-clipping bug guides (ruled out as
  a different bug), general search for `NPCMeleeware` (zero public hits).
