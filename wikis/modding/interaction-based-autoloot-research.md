# Interaction-Based Auto-Loot Detection — Feasibility Research (2026-07-13)

Scope: FEATURE 3 (auto-pickup) of the locally-authored **Custom Scanner Suite**
(`mods/enabled/r6-scripts/custom-scanner-suite/ScannerSuite.reds`), specifically the 360°
surroundings pass `APS_RunSurroundingsPickup` (PlayerPuppet) and the shared worker
`APS_TryAutoPickup` (GameObject). Pure REDscript only, game v2.3 macOS Steam. NO CET / RED4ext /
TweakXL / ArchiveXL / Codeware.

**The user spec:** replace the class whitelist (`IsContainer() || IsShardContainer() || IsItem()`
plus puppet-corpse handling) with a detection that is **agnostic of item/object type** — *"can it
detect if an item is collectable, and if yes → pick it. It just checks whether an interaction
'collect' (pick up / take / loot) is AVAILABLE on the entity. However it must NOT pick up anything
quest-related."*

Evidence tier **[V]** = read directly in the local decompiled v2.3 vanilla sources
(`…/scratchpad/vanilla/scripts/`, `.script`). Every citation below is `file:line` in that tree.

---

## Verdict up front

**The literal ask — "is a collect interaction currently available on this arbitrary entity" — is
NOT answerable from script. It is outcome (b).** Two independent walls, both structural:

1. **`InteractionComponent` has no choice getter.** [V] `core/components/interactionComponent.script:24-31`
   — the class is `importonly final`, and its entire script surface is
   `SetSingleChoice` / `SetChoices` / `ResetChoices` / `GetActiveInputLayers` /
   `GetActivatorsForLayer`. Choices go **in**; nothing comes **out**. There is no
   `GetChoices()`, no `HasChoice()`, no `IsChoiceAvailable()`.
2. **The choice data that carries the quest flag is FOCUS-SCOPED, singular, and lives on a
   blackboard, not on the entity.** [V] `core/blackboard/blackboardDefinitions.script:662-679`
   (`UIInteractionsDef`) holds **one** `InteractionChoiceHub`, **one** `ActiveChoiceHubID`, **one**
   `LootData`. That is the interaction the player is *currently focusing*. A 360° radius sweep needs
   N entities answered simultaneously; the blackboard can answer exactly 1.

So the interaction system cannot be queried per-entity. **What replaced it** is the closest thing
vanilla actually exposes and uses for the same purpose — the gameplay **ROLE** (`EGameplayRole.Loot`)
— plus a per-**item** quest tag. Details in "What was implemented".

---

## Wall 1 — the interaction component is write-only

[V] `core/components/interactionComponent.script:24-31`

```
importonly final class InteractionComponent extends IPlacedComponent
{
	public import function SetSingleChoice( choice : InteractionChoice, optional layer : CName );
	public import function SetChoices( choices : array< InteractionChoice >, optional layer : CName );
	public import function ResetChoices( optional layer : CName, optional deactivate : Bool );
	public import const function GetActiveInputLayers( out activeInputLayers : array< gameinteractionsActiveLayerData > ) : Bool;
	public import const function GetActivatorsForLayer( layerName : CName, out activeInputLayers : array< gameinteractionsActiveLayerData > ) : Bool;
}
```

`GetActiveInputLayers` is the only thing that smells like a query, and it is not the one we need:

* It returns `gameinteractionsActiveLayerData` = `{ activator, linkedLayersName, layerName }`
  ([V] `core/gameplay/interactions.script:19-24`) — **layer names, not choices**. No caption, no
  `ChoiceTypeWrapper`, no quest flag.
* Its one vanilla consumer proves the semantics: `VehicleComponent.DetermineInteractionState`
  ([V] `core/components/scriptComponents/vehicleComponent.script:1957-1973`) uses it to find out
  *which activators are currently inside which interaction hot-spot layers* so it can then **push**
  choices into them. It is an input to choice *generation*, not a readout of choice *availability*.
* For loot containers the layers are not even collect-related: they are
  `QualityRange_Short/Medium/Max` icon-visibility bands
  ([V] `core/components/lootContainers.script:938-1019`).

### …and you cannot get the component anyway

Even a read-only getter would be unreachable on an arbitrary entity:

* There is **no component enumeration API**. `Entity` exposes exactly one component accessor:
  `protected import const final function FindComponentByName( componentName : CName ) : IComponent`
  ([V] `core/entity/entity.script:17`). By **name** — so you must already know the name.
* The name is per-archetype and lives in `.ent` files, not in scripts. Vanilla alone uses at least
  six different ones: `'interaction'` ([V] `devices/core/interactiveDevice.script:41`), `'Interaction'`
  ([V] `puppet/scriptedPuppet.script:618`), `'interactions'` ([V] `items/healthConsumable.script:30`),
  `'InteractionComp'` ([V] `devices/wireRepairable.script:20`), `'choice'`
  ([V] `core/gameplay/weakspot.script:195`), `'entrances'` ([V] `devices/ladders/slidingLadder.script:22`).
* For the **native** loot classes (`gameLootContainerBase`, `gameLootObject`, `gameLootBag`) the
  component name appears **nowhere** in the script tree. Guessing it would violate the project's
  no-invented-API rule outright.

---

## Wall 2 — the choice/quest data is focus-only

The quest signal the task hoped for is real, and it is genuinely how vanilla colours quest
interactions:

* [V] `core/gameplay/choice.script:1-16` — `enum gameinteractionsChoiceType { QuestImportant, AlreadyRead,
  Inactive, CheckSuccess, CheckFailed, InnerDialog, PossessedDialog, TimedDialog, Blueline, Pay,
  Selected, Illegal, Glowline }`
* [V] `core/gameplay/choice.script:18-23` — `ChoiceTypeWrapper.IsType( context, type ) : Bool`
* [V] `UI/interactions/dialogUI.script:752` — `if( ChoiceTypeWrapper.IsType( m_type, gameinteractionsChoiceType.QuestImportant ) )`

But `ChoiceTypeWrapper` only ever appears inside an `InteractionChoiceData.type` /
`InteractionChoice.choiceMetaData.type`, and those structs only reach script through:

* `InteractionChoiceHubData` ([V] `UI/interactions/interactionData.script:28-36`) — read from the
  blackboard var `UIInteractions.InteractionChoiceHub`
  ([V] `UI/interactions/interactionsUI.script:41,55`; `cyberpunk/player/player.script:975`). **Singular.**
* `LootData` ([V] `UI/interactions/lootingData.script:1-12`) — `{ isActive, isListOpen, currentIndex,
  title, choices, itemIDs, ownerId, isLocked }`. Note `ownerId : EntityID` — **one** owner. This is the
  loot popup for the container you are looking at. **Singular.**
* `InteractionAttemptedChoice` ([V] `core/gameplay/choice.script:43-49`) — the choice the player just
  pressed. Past tense, singular.

`UIInteractionsDef.ActiveInteractions` ([V] `blackboardDefinitions.script:670`) is the one name that
sounds plural — it is **declared and never read or written by any script in the tree** (grep returns
that single declaration line). Dead / native-internal. Not usable.

**Conclusion:** interaction/choice data is materialised for the player's *current* focus target only.
A 360° pass over ~N streamed entities gets nothing from it. This is exactly the failure mode the task
brief anticipated, and it is confirmed.

### The loot "Take" choice is native and write-only from script

For completeness — loot never declares its collect choice in script at all. The container side only
*pushes* control operations into the native loot visualiser:

* [V] `core/components/inventoryComponent.script:63` —
  `LootVisualiserControlWrapper.Wrap( wrapper ) : InteractionSetChoicesEvent`
* [V] `core/components/lootContainers.script:1008-1013` — `RefereshInteraction` builds a
  `Locked` operation and `QueueEvent( setChoices )`.
* [V] `UI/interactions/interactionData.script:1-7` — `enum EVisualizerType { Device, Dialog, Loot, Invalid }`

The "Take / Take All" choices themselves are generated by the native `Loot` visualiser. Nothing
queryable per entity survives.

### `InteractionManager` doesn't help either

[V] `core/gameplay/interactions.script:26-31` — the whole system surface is
`IsInteractionLookAtTarget( activatorOwner, hotSpotOwner ) : Bool`, `SetBlockAllInteractions`,
`AreSceneInteractionsBlocked`. The first is a **look-at** test (its only caller is a scripted
interaction *condition*, [V] `cyberpunk/interactions/scriptedConditions.script:352`) — i.e. it answers
"is the player pointing at this?", which is the crosshair channel we already have and the opposite of
what a 360° sweep needs. No per-entity choice query.

---

## What DOES exist: `DeterminGameplayRole() == EGameplayRole.Loot`

The nearest per-entity, **virtual**, type-agnostic "the game considers this collectable" predicate —
and it is vanilla's own, the one that drives the loot mappin and the loot highlight
([V] `core/components/scriptComponents/gameplayRoleComponent.script:820`;
[V] `UI/mappins/minimapMappins.script:891`).

* [V] `core/entity/gameObject.script:2504` — `public const virtual function DeterminGameplayRole() : EGameplayRole`
* [V] `core/components/scriptComponents/gameplayRoleComponent.script:172` — `Loot = 16`

Overrides that return `Loot`:

| class | file:line | condition |
|---|---|---|
| `gameLootObject` (and `gameItemDropObject`) | `core/components/inventoryComponent.script:372-375` | always |
| `gameLootBag` | `core/components/lootContainers.script:307-310` | always |
| `gameLootContainerBase` (every container subclass) | `core/components/lootContainers.script:707-710` | always |
| `ItemObject` | `cyberpunk/items/item.script:169-176` | iff `IsContainer()` |
| `ScriptedPuppet` | `cyberpunk/puppet/scriptedPuppet.script:4516-4520` | iff `IsContainer()` |

Because it is **virtual**, this asks the object what it is *for* rather than what class it *is* — an
unknown or modded object that declares itself loot is collected with the mod knowing nothing about
its type. That is the agnostic property the user asked for, delivered by the only mechanism that
actually exists.

### Bonus: the old class trio was content-cached, and that was a latent bug

The whitelist it replaces is not as structural as it looks:

* [V] `core/components/lootContainers.script:618-621` — `gameLootContainerBase.IsContainer()` =
  `!IsEmpty() && !IsDisabled()`, off `m_isEmpty`, which is only computed inside `EvaluateLootQuality`
  on an inventory callback ([V] same file, `:783-850`).
* [V] `core/components/lootContainers.script:229-232` (`gameLootBag`) and
  [V] `core/components/inventoryComponent.script:382-385` (`gameLootObject`) — same `!IsEmpty()` shape.
* [V] `cyberpunk/puppet/scriptedPuppet.script:4687-4696` — `ScriptedPuppet.IsContainer()` is off
  `m_lootQuality`.

The worker returns **FINAL** (spends the entity's single attempt, forever) when the gate fails. So a
container the 0.5 s pass reached *before* its loot had been evaluated was **burned permanently** =
"this crate never loots". Role-`Loot` is not content-cached for the container classes, so such a
container now falls through to the item-list read and takes a **TRANSIENT** empty refusal instead.
Real fix, not a rename.

---

## The quest exclusion: item tag, NOT `IsQuest()`

### `GameObject.IsQuest()` is provably unusable as a loot gate

* Base: [V] `core/entity/gameObject.script:2699-2702` — `return m_markAsQuest;`
* Loot classes OR their content in:
  [V] `core/components/lootContainers.script:312-315` (`gameLootBag`) and
  [V] `core/components/inventoryComponent.script:377-380` (`gameLootObject`) —
  `return m_hasQuestItems || m_markAsQuest;`
  [V] `core/components/lootContainers.script:712-721` (`gameLootContainerBase`) —
  `return !ps.IsDisabled() && ( ps.IsMarkedAsQuest() || m_hasQuestItems );`
  [V] `cyberpunk/puppet/scriptedPuppet.script:3775` — `return super.IsQuest() || m_hasQuestItems;`
  [V] `cyberpunk/items/item.script:165-168` — `return super.IsQuest() || GetItemData().HasTag( 'Quest' );`
* The mark is **persistent**: [V] `core/components/lootContainers.script:33` —
  `protected instanceeditable persistent var m_markAsQuest : Bool;` (read back via
  `IsMarkedAsQuest()`, [V] same file `:58-61`).

**The killer:** [V] `cyberpunk/containers/shardCaseContainer.script:1-4`

```
class ShardCaseContainerPS extends gameLootContainerBasePS
{
	default m_markAsQuest = true;
}
```

**Every shard case in the game is `m_markAsQuest = true`, therefore `IsQuest() == true`.** Gating
auto-pickup on `IsQuest()` would silently stop the vacuum from ever collecting a single shard — on top
of the doors/fridges stuck-flag over-skip the mod file already documented from play. This is the
verifiable, decisive reason the whole-object quest gate stays out.

### The precise signal is the item tag

`itemData.HasTag(n"Quest")` ([V] `core/data/itemData.script:9` for the signature) is exactly what every
loot class uses to compute its own `m_hasQuestItems`:

* [V] `core/components/lootContainers.script:364` (`gameLootBag`)
* [V] `core/components/lootContainers.script:792` (`gameLootContainerBase`)
* [V] `core/components/inventoryComponent.script:318` (`gameLootObject`)
* [V] `cyberpunk/puppet/scriptedPuppet.script:4650` (`ScriptedPuppet`)

Vanilla's UI additionally folds in `UnequipBlocked` as "quest item":

* [V] `cyberpunk/UI/inventory/InventoryItem.script:413` —
  `IsQuestItem = m_realItemData.HasTag( 'Quest' ) || m_realItemData.HasTag( 'UnequipBlocked' );`
* [V] `cyberpunk/managers/rpgManager.script:2973` — `CanItemBeDropped` refuses `IconicWeapon`, `Quest`
  and `UnequipBlocked`.

So the hard rule shipped is `HasTag(n"Quest") || HasTag(n"UnequipBlocked")` — vanilla's own definition,
per item, no config knob. Because it is per-**item**, a mixed container is handled precisely: the quest
item stays on the ground (with its normal interaction and quest highlight intact, ready for a manual
pickup), everything around it is still vacuumed. The `m_hasQuestItems` half of `IsQuest()` **is** this
tag, so nothing precise is lost by dropping the whole-object test.

---

## What was implemented (2026-07-13)

In `ScannerSuite.reds`:

* **`GameObject.APS_IsCollectable()`** — `DeterminGameplayRole() == EGameplayRole.Loot`, UNIONed with
  the legacy `IsContainer() || IsShardContainer() || IsItem()` trio as a never-narrower backstop (an
  `ItemObject` tagged `NoLootMappin` has `IsContainer() == false` → role `None`,
  [V] `cyberpunk/items/item.script:89-99`, but `IsItem()` still passes it, exactly as before). This is
  the new gate in `APS_TryAutoPickup`.
* **`GameObject.APS_IsQuestItem(itemData)`** — the hard quest rule above. Not a knob.
* **Explicit `IsPlayer()` FINAL reject** ([V] `core/entity/gameObject.script:1721`) — the player is in
  the `GetEntityList` the 360° pass walks, and `PlayerPuppet` is a `ScriptedPuppet`, so the alive-puppet
  branch was refusing them *transiently* (re-evaluated every pass, forever). Now they land in the
  ledger once.
* **Explicit `IsDisabled()` TRANSIENT reject for containers** ([V] `core/components/lootContainers.script:733-742`)
  — vanilla's own `IsContainer()` refuses a disabled container as a side effect of its
  `!IsEmpty() && !IsDisabled()` shape; the role gate does not, so the check had to become explicit.
  Transient (not final) because `OnResetContainerEvent` can re-enable one
  ([V] `core/components/lootContainers.script:1060-1083`).
* **Config split:** `AutoPickupTakeQuestAndIconic` (one flag, default true, which also *took quest
  items*) → `AutoPickupTakeIconic` (default true) + `AutoPickupTakeHeavyWeapons` (default true), with
  quest promoted out of the config entirely into the hard rule.

Preserved unchanged: game-thread-only execution (DelaySystem callback), cheap distance reject before
any cast, no per-entity streaming hooks, no writes to vanilla state fields, the shared `m_apsAttempted`
ledger, and the transient-vs-final return contract.

---

## Known gaps (stated plainly)

1. **A quest-*marked* object whose items carry no `Quest` tag is still vacuumed.** E.g. a container a
   quest script flagged via `SetAsQuestImportantEvent` ([V] `core/entity/gameObject.script:2704-2716`)
   but whose contents are ordinary loot. Closing this gap requires the whole-object `IsQuest()` test,
   which — per the `ShardCaseContainerPS` proof above — would kill all shard looting and re-open the
   junk-container over-skip. Not worth it. The user's stated risk (taking a quest *item*) is fully
   covered.
2. **Auto-looting a container never fires its interaction.** `TransactionSystem.TransferItem` moves the
   items; it does not raise the `InteractionChoiceEvent` a manual "Take" would. Any quest objective
   phrased as *"interact with / open the container"* rather than *"acquire the item"* could therefore
   fail to tick. This is **pre-existing** (true of every auto-loot build of this mod, and of the
   take-everything default), not introduced here — and the new quest rule makes it strictly less
   likely, since quest-tagged loot is now left for a manual pickup.
3. **Quest-only objects are on a transient treadmill.** An object whose entire contents are quest loot
   never passes the filters, so it returns TRANSIENT and is re-read once per 0.5 s pass for as long as
   it sits inside the 10 m bubble. Deliberate: the quest item can be taken by hand at any moment and
   the object must become auto-lootable again the instant it is. Cost is one `GetItemList` per pass —
   the same treadmill an already-empty container in range has always been on, and negligible next to
   the `GetEntityList` walk the pass does anyway.
4. **Role-`Loot` is wider than the class trio, so empty/already-looted containers in range now re-check
   every pass** instead of being burned FINAL on the first sighting. That is the intended trade (it is
   what fixes the "crate never loots" bug), but it does mean marginally more `GetItemList` calls per
   pass in a room you have already cleared.
