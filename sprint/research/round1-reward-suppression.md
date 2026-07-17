# R1 — F2: kill-XP, loot and corpse-lootability suppression (reward-suppression)

## Verdict

**FEASIBLE, and stronger than the brief hoped for.** All four reward surfaces (kill-XP, corpse
loot container, dropped weapon, plus a bonus telemetry-only kill-reward flag) resolve to a
**single family of `ScriptedPuppet`/`GameObject` members**, and the two highest-value levers are
**public, non-final, zero-wrap, directly-callable functions**: `GameObject.DisableKillReward(Bool)`
(`gameObject.script:1682`) and `TransactionSystem.RemoveAllItems(obj)` +
`ScriptedPuppet.EvaluateLootQualityByTask(self)` (`transactionSystem.script:49`,
`scriptedPuppet.script:440`). The decisive fact: **corpse lootability, the loot mappin/highlight,
and the interaction-range layer all key off one field, `ScriptedPuppet.m_lootQuality`**
(`scriptedPuppet.script:373-374`, default `Invalid`), which is set from
`TransactionSystem.GetItemList` — clear the inventory and the corpse structurally stops being
`EGameplayRole.Loot`. The one genuinely uncertain piece is the dropped weapon
(`ScriptedPuppet.DropHeldItems()`, `scriptedPuppet.script:3092`) — it is `private`, so wrapping it
has no exact local precedent (ScannerSuite.reds never wraps a `private` or `const` method) and
needs a compile check; a redundant fallback exists regardless (see Findings §4 and the ladder
below), so minimum bar is not at risk even if that one wrap fails.

**Cross-mission note:** this dossier assumes a live `ref<NPCPuppet>` handle to the marked clone
already exists at spawn time and at death time. `sprint/research/round1-runtime-npc-spawning.md`
(sibling R1) found the *spawn* mechanism itself currently BLOCKED for a clean pure-REDscript path
— an orthogonal problem. Everything below applies to any `ref<ScriptedPuppet>` handle regardless
of how/whether that blocker resolves, so this research remains valid investment either way.

## Findings

### 1. Kill-XP: `AwardsExperience()` is the real choke point; `DisableKillReward` is a confirmed-real but telemetry-only bonus

1a. **The actual XP-per-kill mechanic is *per-hit proficiency XP*, not a lump kill reward.**
`RPGManager.AwardExperienceFromDamage(hitEvent, damagePercentage)`
(`sprint/vanilla-scripts/scripts/cyberpunk/managers/rpgManager.script:2091-2263`) computes weapon
skill XP (`gamedataProficiencyType.StrengthSkill/ReflexesSkill/CoolSkill/IntelligenceSkill/
TechnicalAbilitySkill`) scaled by `damagePercentage` (fraction of the target's health pool drained
by that hit) and is invoked from `StatPoolsManager.DrainStatPool` on every hit that drains the
Health pool, **including the killing blow**:
   ```
   scripts/cyberpunk/damage/statPoolsManager.script:400-403
       if( dmgExpPercent > 0.0 )
       {
           RPGManager.AwardExperienceFromDamage( hitEvent, dmgExpPercent );
       }
   ```
   Its very first gate (`rpgManager.script:2116`) is:
   ```
   if( ( ( ( !( targetPuppet ) || !( targetPuppet.IsActive() ) ) || !( targetPuppet.AwardsExperience() ) )
         || !( attackData.GetInstigator().IsPlayer() ) ) || hitEvent.target.IsPlayer() )
   {
       return;
   }
   ```
   `targetPuppet.AwardsExperience() == false` short-circuits the ENTIRE function before any XP is
   computed — for every hit against that entity, for the whole fight, not just the kill.

1b. **`AwardsExperience()` is a single-definition, non-final, `public const function` on
`ScriptedPuppet`** (`scriptedPuppet.script:1835-1838`):
   ```
   public const function AwardsExperience() : Bool
   {
       return !( IsCrowd() ) && !( IsPrevention() );
   }
   ```
   Repo-wide grep confirms exactly one declaration site (`grep -rn "AwardsExperience" scripts/`) —
   no subclass override exists, so wrapping it on `ScriptedPuppet` covers `NPCPuppet` (and every
   other puppet subclass) uniformly. It is already used by vanilla as a categorical
   "does this entity give rewards at all" gate for **three separate reward systems**, not just XP:
   - `rpgManager.script:2116` — proficiency XP (finding 1a)
   - `bountyManager.script:230` — bounty completion reward
   - `executorGivePlayerReward.script:19` (`EffectExecutor_GivePlayerReward.Process`) — status-effect-triggered rewards (e.g. utility-grenade kill bonus)

   A `@wrapMethod(ScriptedPuppet) AwardsExperience()` that returns `false` for a marked clone
   (checked before falling through to `wrappedMethod()`) suppresses **all three** at once, for the
   clone's entire lifetime from the moment it is marked (spawn time) — correctly covering
   progressive per-hit XP, not just a death-instant.

1c. **`GameObject.DisableKillReward(Bool)` is public, non-final, and needs no wrap at all** —
just call it once on the marked clone:
   ```
   scripts/core/entity/gameObject.script:1649-1685
       protected virtual function RewardKiller( killer : weak< GameObject >, killType : gameKillType, isAnyDamageNonlethal : Bool )
       {
           var killRewardEvt : KillRewardEvent;
           if( m_killRewardDisabled ) { return; }
           ...
           killer.QueueEvent( killRewardEvt );
       }
       public function DisableKillReward( value : Bool ) { m_killRewardDisabled = value; }
   ```
   `RewardKiller` is called from `FindAndRewardKiller` (`gameObject.script:1581`), itself called
   from `ScriptedPuppet.HandleDeath` (`scriptedPuppet.script:414`) and `HandleDefeated`
   (`scriptedPuppet.script:430`) — i.e. every kill/defeat path. **Vanilla itself uses this exact
   flag for a "no normal kill reward" scenario**, which is strong precedent it is safe and
   intended for scripted suppression:
   ```
   scripts/cyberpunk/devices/disposal/disposalDevice.script:302-313  (body-disposal feature)
       protected event OnNPCKillDelayEvent( evt : NPCKillDelayEvent )
       {
           ...
           rewardSettingsEvent = new ChangeRewardSettingsEvent;
           rewardSettingsEvent.forceDefeatReward = !( evt.isLethalTakedown );
           rewardSettingsEvent.disableKillReward = evt.disableKillReward;
           m_npcBody.QueueEvent( rewardSettingsEvent );
   ```

1d. **CAVEAT on 1c: confirmed to exist and to suppress `KillRewardEvent`, but that event's only
found consumer is telemetry.** Repo-wide grep for `OnKillRewardEvent` finds exactly one handler,
`scriptedPuppet.script:2981-2995`, which only calls `LogEnemyDown` (telemetry / analytics logging)
— no XP or money grant is visible in decompiled script at that consumption point. `PlayerPuppet`
(`player.script:435 class PlayerPuppet extends ScriptedPuppet`) does not override it. So
`DisableKillReward(true)` is **zero-risk and vanilla-precedented, but its confirmed effect is
telemetry-suppression only** — it should be called as a free bonus alongside 1b, not relied on as
the actual XP blocker. (`Event` is a native class; a purely-native, non-script subscriber cannot be
ruled out from decompiled sources alone — marked UNVERIFIED, harmless either way.)

### 2 & 3. Loot container + corpse lootability collapse to one field: `m_lootQuality`

2a. **The moment-of-death loot fill and the drop-flag are BOTH native and `final`** — cannot be
hooked internally, only bracketed:
   ```
   scripts/core/gameplay/puppet.script:86   public import const final function GenerateLoot();
   scripts/core/gameplay/puppet.script:105  public import final function ProcessLoot();
   scripts/core/gameplay/puppet.script:88   public import const final function DropWeapons();
   ```
   `ProcessLoot()` is called exactly once for a fresh death, from the override that handles BOTH
   the lethal and non-lethal (takedown) paths:
   ```
   scripts/cyberpunk/NPC/NPCPuppet.script:3935-3987
       protected override function OnIncapacitated()
       {
           ...
           super.OnIncapacitated();
           ProcessLoot();
           ...
       }
   ```
   `NPCPuppet.OnIncapacitated` is `protected override` (not final) — a valid `@wrapMethod` target.
   Both death routes funnel here: `ScriptedPuppet.HandleDeath` (`:408-416`, lethal) →
   `OnDied()` (`:2712`) → `OnIncapacitated()`; and `ScriptedPuppet.HandleDefeated` (`:428-438`,
   non-lethal takedown) → `OnIncapacitated()` directly. Wrapping this ONE method, calling
   `wrappedMethod()` first (so `ProcessLoot()` still runs, preserving all vanilla ragdoll/quickhack
   bookkeeping), then acting for marked clones, covers both death types with one hook.

2b. **`TransactionSystem` exposes a direct, public, native "clear everything" call** —
already-verified-existing sibling APIs to the `GetItemList` call ScannerSuite.reds already uses in
production (`ScannerSuite.reds:1036`):
   ```
   scripts/core/systems/transactionSystem.script:16   RemoveItem( obj, itemID, amount ) : Bool
   scripts/core/systems/transactionSystem.script:44   GetItemList( obj, out itemList ) : Bool
   scripts/core/systems/transactionSystem.script:49   RemoveAllItems( obj ) : Bool
   ```
   Called via `GameInstance.GetTransactionSystem(game)` — itself already locally precedented
   (`ScannerSuite.reds:1036`, `:2027` etc.).

2c. **Corpse lootability is 100% derived from one field, with an explicit `Invalid` default and a
vanilla auto-reset-on-empty listener already wired up** — no wrap needed for this half either,
just the `RemoveAllItems` call plus one more public helper:
   ```
   scripts/cyberpunk/puppet/scriptedPuppet.script:373-374
       private var m_lootQuality : gamedataQuality;
       default m_lootQuality = gamedataQuality.Invalid;

   scripts/cyberpunk/puppet/scriptedPuppet.script:4687-4697   (IsContainer)
       public const override function IsContainer() : Bool
       {
           if( m_lootQuality != gamedataQuality.Invalid && m_lootQuality != gamedataQuality.Random )
           { return true; } else { return false; }
       }

   scripts/cyberpunk/puppet/scriptedPuppet.script:4516-4530   (DeterminGameplayRole)
       public const override function DeterminGameplayRole() : EGameplayRole
       {
           if( IsContainer() ) { return EGameplayRole.Loot; }
           else if( ( !( IsCrowd() ) || ... ) ) { return EGameplayRole.NPC; }
           ...
       }

   scripts/cyberpunk/puppet/scriptedPuppet.script:4713-4733   (OnInventoryEmptyEvent — VANILLA auto-reset)
       protected event OnInventoryEmptyEvent( evt : OnInventoryEmptyEvent )
       {
           if( HasValidLootQuality() )
           {
               m_lootQuality = gamedataQuality.Invalid;
               UntagObject( this );
               ...
           }
           ...
       }
   ```
   `IsContainer()` is exactly the virtual ScannerSuite.reds' own doc comments cite as "the same
   virtual that drives the vanilla loot mappin/highlight" via `DeterminGameplayRole()`
   (`gameObject.script:2504` base; overridden here). `OnInventoryEmptyEvent` is a native-fired
   event (`importonly final class OnInventoryEmptyEvent extends Event`,
   `scripts/core/events/inventoryEvents.script:1`) that vanilla already wires to reset
   `m_lootQuality` to `Invalid` and untag the object the moment its `TransactionSystem` inventory
   empties — it is independently handled the same way in `lootContainers.script:244,633` and
   `inventoryComponent.script:508`, so this is an established, repeated vanilla pattern, not a one-off.
   `ResolveQualityRangeInteractionLayer()` (`scriptedPuppet.script:4532-4580`), which sets up the
   'QualityRange_Short/Medium/Max' interaction layer that governs the loot prompt's activation
   range, is *also* gated on `m_lootQuality != Invalid` — so an emptied corpse loses that layer too.

2d. **Belt-and-suspenders public re-evaluation call, in case `RemoveAllItems` does not itself fire
`OnInventoryEmptyEvent`** (native internals opaque — see Open Questions):
   ```
   scripts/cyberpunk/puppet/scriptedPuppet.script:440-456
       public static function EvaluateLootQualityByTask( self : weak< GameObject > )
       {
           if( self != NULL )
           {
               GameInstance.GetDelaySystem( self.GetGame() ).QueueTask( self, NULL, 'EvaluateLootQualityTask', gameScriptTaskExecutionStage.Any );
           }
       }
       protected function EvaluateLootQualityTask( data : ScriptTaskData ) { EvaluateLootQuality(); }
   ```
   `EvaluateLootQualityByTask` is `public static`, callable directly as
   `ScriptedPuppet.EvaluateLootQualityByTask(cloneEntity)` — **no wrap needed**. It queues a
   `DelaySystem` task (vanilla's own deferred-mutation idiom, matching this project's rule 3
   guidance) that calls the private `EvaluateLootQuality()`
   (`scriptedPuppet.script:4617-4675`), which reads `TransactionSystem.GetItemList` fresh and, on
   an empty list, leaves `m_lootQuality` at its `Invalid` default. Calling `RemoveAllItems` then
   this, back to back, is a fully public, zero-wrap, two-call recipe that independently guarantees
   the m_lootQuality reset regardless of whether `OnInventoryEmptyEvent` also fires.

2e. **Minor residual uncertainty, not a blocker.** `UpdateLootInteraction()`
(`scriptedPuppet.script:4587-4590`) toggles a *generic* `'Loot'` interaction layer via
`EnableInteraction('Loot', !(IsActive()) && m_inventoryComponent.IsAccessible())`, where
`IsAccessible()` is `public import` (native, opaque body,
`scripts/core/components/inventoryComponent.script:68`) and does not obviously depend on item
count. This layer may remain nominally "enabled" on an empty corpse even though
`DeterminGameplayRole`/mappin/highlight/quality-range-layer all correctly stop presenting it as
loot — matching real observed vanilla behavior for already-looted/empty corpses (no floating loot
icon, but the generic body-interaction slot itself is a separate, item-count-independent concept).
Worst case this is cosmetic (an empty backpack UI is still "no lootable items").

### 4. Dropped weapon: found, but the wrap target is `private` — one genuine open risk, with a built-in fallback

4a. **The gate and the drop are two different functions; only the gate is script-visible and
non-final.**
   ```
   scripts/cyberpunk/puppet/scriptedPuppet.script:3092-3119
       private function DropHeldItems() : Bool
       {
           var canDrop : Bool;
           ...
           canDrop = TweakDBInterface.GetCharacterRecord( GetRecordID() ).DropsWeaponOnDeath();
           if( canDrop )
           {
               slot = T"AttachmentSlots.WeaponRight"; rightItem = GetItemInSlot(...);
               canRightItemDrop = rightItem && IsNameValid( ...DropObject() );
               slot = T"AttachmentSlots.WeaponLeft"; leftItem = GetItemInSlot(...);
               canLeftItemDrop = ...;
               if( canLeftItemDrop || canRightItemDrop )
               {
                   DropWeapons();                     // native, final — spawns the standalone world item
                   if( RPGManager.IsItemWeapon(...) || RPGManager.IsItemWeapon(...) ) { m_droppedWeapons = true; }
               }
           }
           return m_droppedWeapons;
       }
   ```
   `TweakDBInterface.GetCharacterRecord(...).DropsWeaponOnDeath()`
   (`scripts/core/data/tweakDBRecords.script:3555`) is a **TweakDB record read** — cannot be
   changed at runtime (read-only rule) — so the gate itself cannot be flipped per-record; only the
   function call that acts on it can be intercepted.

4b. **Trigger path is a status-effect tag, independent of the `OnIncapacitated` timing used for
loot** — does not change the recommendation, but explains why this needs its own hook:
   ```
   scripts/cyberpunk/puppet/scriptedPuppet.script:2420   protected event OnStatusEffectApplied( evt : ApplyStatusEffectEvent )
       ...
       scripts/cyberpunk/puppet/scriptedPuppet.script:2501-2504
           if( tags.Contains( 'DropHeldItems' ) ) { DropHeldItems(); }
   ```
   Since our wrap targets `DropHeldItems()` itself (not the whole `OnStatusEffectApplied` switch,
   which handles many unrelated tags and cannot be sliced), interception is correct regardless of
   exactly when this status effect lands relative to `OnIncapacitated` — as long as the clone was
   marked at spawn time (well before any of this), the wrap catches the call whenever it fires.

4c. **UNVERIFIED: whether `@wrapMethod` compiles on a `private function`.** `DropHeldItems` is
`private`, not `final` — per this project's rule 5 (`@addMethod(Class)` gets private/protected
member access) and general REDscript convention (`@wrapMethod`/`@addMethod` patch the class as a
member, independent of the `virtual` keyword; only `final` blocks it), this is expected to work,
but **ScannerSuite.reds has no direct precedent of `@wrapMethod` on a `private` method** — every
wrap in that file targets a `protected`/public-visibility `cb func`/`event` (see API inventory).
The closest local precedent is `@addMethod(AudioSystem)` *calling* the private
`PlayItemLootedSound` from a public shim (`ScannerSuite.reds:2041-2044`) — proof private members
are member-reachable, but not proof `@wrapMethod` itself accepts a private target. Flag for a
first-order compile check; **redundant fallback if it fails to compile or to intercept in time**:
the weapon, until `DropWeapons()` actually runs, is still sitting in the corpse's ordinary
`TransactionSystem` inventory/equip slot exactly like any other lootable item — the *same*
`RemoveAllItems` call from §2b/§3 will strip it from the corpse right along with everything else.
The only failure window is if `DropWeapons()` (native) has *already* ejected it as a standalone
world entity (a different `EntityID`, outside the corpse's own inventory) by the time our
post-`OnIncapacitated` clear runs — in that one case the wrap is load-bearing for the minimum bar.

### 5. No cheaper spawn-time shortcut found

Checked whether choosing a specific `CharacterRecord`/spawn spec could pre-empt all of the above:
- `DynamicEntitySpec`/`DynamicEntitySystem` — **zero hits anywhere in `sprint/vanilla-scripts/`**
  (confirms sibling dossier `round1-runtime-npc-spawning.md`'s finding; this is a Codeware-only
  surface, not reachable here regardless).
- TweakDB record flags (`DropsWeaponOnDeath()`, the NPC's base loot table reference) are read-only
  at runtime — cannot be forced off for an arbitrary chosen record even if we wanted to filter by
  them (a curated same-faction pool *could* prefer records that already read
  `DropsWeaponOnDeath()==false`, but that is a filtering nicety, not a control lever, and the
  brief's stated FALLBACK is "exact clone of source," which offers no such choice).
- `IsCrowd()==true` records (background crowd NPCs) already read `AwardsExperience()==false`
  structurally — but crowd NPCs are not properly-combat-capable hostile archetypes, so this does
  not satisfy "hostile like the source... fights immediately."
- **Conclusion: no spawn-time shortcut avoids the per-entity post-spawn/post-death hooks above.**
  They are necessary regardless of which identity-selection strategy F2's spawn round settles on.

## API inventory

| API / member | Signature | Evidence (file:line) | Verified? |
|---|---|---|---|
| `ScriptedPuppet.AwardsExperience` | `public const function() : Bool` | `scriptedPuppet.script:1835-1838` | VERIFIED exists/behavior. Wrap-on-`const` has no local precedent — UNVERIFIED compile |
| `RPGManager.AwardExperienceFromDamage` | `static function(hitEvent:gameHitEvent, damagePercentage:Float)` | `rpgManager.script:2091-2263`, gate at `:2116` | VERIFIED (full body read) |
| `StatPoolsManager.DrainStatPool` | `static function(hitEvent, statPoolType, value:Float)` | `statPoolsManager.script:359-404`, calls XP at `:400-403` | VERIFIED |
| `GameObject.DisableKillReward` | `public function(value:Bool)` | `gameObject.script:1682-1685` | VERIFIED, public, no wrap needed; vanilla precedent `disposalDevice.script:302-313` |
| `GameObject.ForceDefeatReward` | `public function(value:Bool)` | `gameObject.script:1677-1680` | VERIFIED, adjacent API, not needed for this mission |
| `GameObject.m_killRewardDisabled` | `protected var : Bool` (`default false`) | `gameObject.script:245-246` | VERIFIED (private-ish field; use the public setter, not direct access) |
| `GameObject.RewardKiller` | `protected virtual function(killer, killType, isAnyDamageNonlethal)` | `gameObject.script:1649-1675` | VERIFIED; alternative wrap target, redundant with `DisableKillReward` |
| `GameObject.FindAndRewardKiller` | `public function(killType:gameKillType, optional instigator)` | `gameObject.script:1581-1647` | VERIFIED; called from `scriptedPuppet.script:414,430` |
| `KillRewardEvent` | `importonly final class extends Event { victim, killType }` | `scripts/core/events/hitEvents.script:114` | VERIFIED; only script consumer is telemetry (`scriptedPuppet.script:2981-3004`) |
| `TransactionSystem.RemoveAllItems` | `public import function(obj:GameObject) : Bool` | `transactionSystem.script:49` | VERIFIED (declaration); not yet locally precedented in a shipped mod |
| `TransactionSystem.RemoveItem` | `public import function(obj, itemID:ItemID, amount:Int32) : Bool` | `transactionSystem.script:16` | VERIFIED |
| `TransactionSystem.GetItemList` | `public import function(obj, out itemList:array<weak<gameItemData>>) : Bool` | `transactionSystem.script:44` | VERIFIED + locally precedented, `ScannerSuite.reds:1036` |
| `GameInstance.GetTransactionSystem` | `static function(gameInstance) : TransactionSystem` | used throughout; locally precedented `ScannerSuite.reds:1036,2027` | VERIFIED |
| `ScriptedPuppet.m_lootQuality` | `private var : gamedataQuality` (`default Invalid`) | `scriptedPuppet.script:373-374` | VERIFIED |
| `ScriptedPuppet.IsContainer` | `public const override function() : Bool` | `scriptedPuppet.script:4687-4697` | VERIFIED |
| `ScriptedPuppet.DeterminGameplayRole` | `public const override function() : EGameplayRole` | `scriptedPuppet.script:4516-4530` (base virtual `gameObject.script:2504`) | VERIFIED |
| `ScriptedPuppet.EvaluateLootQuality` | `private function() : Bool` | `scriptedPuppet.script:4617-4675` | VERIFIED; not directly called by mod (use the task wrapper instead) |
| `ScriptedPuppet.EvaluateLootQualityByTask` | `public static function(self:weak<GameObject>)` | `scriptedPuppet.script:440-446` | VERIFIED, public, no wrap needed |
| `ScriptedPuppet.HasValidLootQuality` | `protected const function() : Bool` | `scriptedPuppet.script:4708-4711` | VERIFIED |
| `ScriptedPuppet.OnInventoryEmptyEvent` (handler) | `protected event(evt:OnInventoryEmptyEvent)` | `scriptedPuppet.script:4713-4733` | VERIFIED; auto-resets `m_lootQuality`, calls `UntagObject` |
| `OnInventoryEmptyEvent` (class) | `importonly final class extends Event` | `scripts/core/events/inventoryEvents.script:1` | VERIFIED; native-fired, same pattern repeated `lootContainers.script:244,633`, `inventoryComponent.script:508` |
| `ScriptedPuppet.ResolveQualityRangeInteractionLayer` | `private function()` | `scriptedPuppet.script:4532-4580` | VERIFIED |
| `ScriptedPuppet.UpdateLootInteraction` | `protected function()` | `scriptedPuppet.script:4587-4590` | VERIFIED; calls `IsAccessible()` (native, opaque) — minor residual uncertainty, see Findings 2e |
| `InventoryComponent.IsAccessible` | `public import function() : Bool` | `scripts/core/components/inventoryComponent.script:68` | VERIFIED (declaration); body opaque |
| `Puppet.GenerateLoot` | `public import const final function()` | `scripts/core/gameplay/puppet.script:86` | VERIFIED; native+final, cannot be wrapped/hooked internally |
| `Puppet.ProcessLoot` | `public import final function()` | `scripts/core/gameplay/puppet.script:105` | VERIFIED; native+final; call site `NPCPuppet.script:3981` is the bracket target |
| `Puppet.DropWeapons` | `public import const final function()` | `scripts/core/gameplay/puppet.script:88` | VERIFIED; native+final, cannot be wrapped |
| `NPCPuppet.OnIncapacitated` | `protected override function()` (base `scriptedPuppet.script:2805` `protected virtual`) | `NPCPuppet.script:3935-3987` | VERIFIED; non-final, standard `@wrapMethod` shape (protected, not const) |
| `ScriptedPuppet.HandleDeath` | `protected override function(instigator:weak<GameObject>)` | `scriptedPuppet.script:408-416` | VERIFIED; lethal path, calls `FindAndRewardKiller`+`OnDied` |
| `ScriptedPuppet.HandleDefeated` | `protected function()` | `scriptedPuppet.script:428-438` | VERIFIED; non-lethal/takedown path, calls `FindAndRewardKiller`+`OnIncapacitated` directly |
| `ScriptedPuppet.DropHeldItems` | `private function() : Bool` | `scriptedPuppet.script:3092-3119` | VERIFIED exists/behavior. Wrap-on-`private` UNVERIFIED compile — no local precedent |
| `Character_Record.DropsWeaponOnDeath` | `public import function() : Bool` | `scripts/core/data/tweakDBRecords.script:3555` | VERIFIED; TweakDB read-only, cannot be changed at runtime |
| `ScriptedPuppet.IsCrowd` / `IsPrevention` | `public const function()` / `public const override function()` | `scriptedPuppet.script:1815-1818`, `:1976` | VERIFIED existence (composed into `AwardsExperience`) |
| Class hierarchy | `NPCPuppet : ScriptedPuppet : gamePuppet : gamePuppetBase : TimeDilatable : GameObject : GameEntity : Entity : IScriptable` | `NPCPuppet.script:119`; `scriptedPuppet.script:323`; `puppet.script:71,11`; `timeSystem.script:38`; `gameObject.script:218`; `gameEntity.script:1`; `entity.script:1` | VERIFIED — confirms `GameObject`-declared APIs (`DisableKillReward` etc.) are inherited by `NPCPuppet` |

## Precedents & inspiration

- **`ScannerSuite.reds`** (`mods/enabled/r6-scripts/custom-scanner-suite/ScannerSuite.reds`) —
  proves the exact same subsystem (`TransactionSystem.GetItemList`, `IsContainer`-adjacent
  `DeterminGameplayRole()==Loot`, `ScriptedPuppet`/`gameLootContainerBase` member shims) is already
  read successfully at runtime by an in-game-proven mod. Direct precedent for `GetItemList`
  (`:1036`) and for the "member shim exposes a private/protected field" pattern
  (`ST_WasLootInitialized` on `gameLootContainerBase` reading private `wasLootInitalized`,
  `:1025-1028`; `APS_IsLootLocked` reading protected `GetPS()`, `:2024-2028`;
  `APS_PlayLootedSound` *calling* private `PlayItemLootedSound`, `:2041-2044`) — none of these are
  `@wrapMethod` on a private/const function specifically (all are `@addMethod` shims), which is
  exactly the gap flagged in Findings §4c/§1b as needing a first compile check.
- **`disposalDevice.script`** (vanilla) — the body-disposal feature is vanilla's own use of
  `ChangeRewardSettingsEvent`/`DisableKillReward` to suppress a normal kill reward on a specific
  NPC body under specific conditions (`:302-313`) — direct proof this exact mechanism is
  intentionally reusable for "this particular corpse should not pay out the usual way," matching
  our use case closely even though its confirmed effect is telemetry-only (Findings §1d).
- **`sprint/research/round1-runtime-npc-spawning.md`** (sibling dossier, this sprint) — establishes
  the spawn-mechanism blocker context this dossier's findings sit downstream of; no overlap in
  claims, cross-referenced in the Verdict.

## Dead ends

- **Hooking inside `GenerateLoot()`/`ProcessLoot()`/`DropWeapons()` directly** — all three are
  `public import const final` / `public import final` on `Puppet` (`puppet.script:86,88,105`).
  `final` blocks `@wrapMethod` outright; `import` means there is no script body to `@replaceMethod`
  either. Only bracketing (before/after via a non-final caller) works.
- **Changing `DropsWeaponOnDeath()` or any other TweakDB record flag per-entity at runtime** —
  confirmed read-only accessor (`tweakDBRecords.script:3555`); consistent with the project's
  hard TweakDB-read-only constraint. Not a lever, full stop.
- **A direct "IsLootable"/"SetLootable"/"CanBeLooted" style flag** — searched, does not exist
  anywhere in the decompiled tree. `m_lootQuality`/`IsContainer()` (Findings §2c) is the real and
  only mechanism; there is no shortcut being missed.
- **`DynamicEntitySpec` record-level "no inventory" spawn flag (Q5)** — zero hits in
  `sprint/vanilla-scripts/`; this whole system is Codeware-only per the sibling spawn dossier. No
  cheaper spawn-time alternative to the per-entity hooks in this dossier exists.
- **Relying on `KillRewardEvent`/`DisableKillReward` as the actual XP suppressor** — it is not;
  its only found consumer is telemetry (`scriptedPuppet.script:2981-3004`). Use `AwardsExperience()`
  for XP; keep `DisableKillReward` only as a free, zero-risk bonus.

## Ranked ladder (full suppression → minimum bar)

| Tier | Mechanism | Hook type | Guarantees |
|---|---|---|---|
| **Full (all 4 pillars)** | 1. `@wrapMethod(ScriptedPuppet) AwardsExperience()` → `false` for marked clone · 2. `TransactionSystem.RemoveAllItems` + `ScriptedPuppet.EvaluateLootQualityByTask` after `NPCPuppet.OnIncapacitated` · 3. `@wrapMethod(ScriptedPuppet) DropHeldItems()` → skip `wrappedMethod()` for marked clone · 4. `GameObject.DisableKillReward(true)` (bonus) | 1 wrap (const, UNVERIFIED-compile) · 2 public calls (no wrap) · 1 wrap (private, UNVERIFIED-compile) · 1 public call (no wrap) | No proficiency/bounty/status-reward XP; corpse not `EGameplayRole.Loot`, no mappin/highlight/prompt range; no separate dropped-weapon world entity; kill-reward telemetry suppressed |
| **If the `DropHeldItems` private-wrap fails to compile** | Drop tier-1 mechanism 3 only; keep 1/2/4 | — | Same as Full **provided** `DropWeapons()` has not already fired before mechanism-2's `RemoveAllItems` runs — the still-equipped weapon is stripped from the corpse's own inventory either way (Findings §4c). Narrow residual risk window only. |
| **If the `AwardsExperience` const-wrap also fails to compile** | Keep 2/4 only (both wrap-free, near-certain to work) | 2 public calls + 1 public call | **Minimum bar still met**: "no lootable items" holds via inventory-clear + loot-quality reset. XP suppression is lost (kill-XP not suppressed) — this is the one tier where the brief's "best-effort ladder" language actually bites. |
| **Absolute floor** | Mechanism 2 alone (`RemoveAllItems` + `EvaluateLootQualityByTask`) | 2 public calls, zero `@wrapMethod` anywhere | Still satisfies "minimum bar = no lootable items" by itself. Lowest implementation risk in this entire dossier — could ship first, independent of whether either wrap compiles. |

**What is explicitly NOT achievable:**
- Cannot prevent XP with zero `@wrapMethod` risk — the only wrap-free lever (`DisableKillReward`)
  is confirmed telemetry-only, not an XP blocker.
- Cannot touch TweakDB record flags at runtime (`DropsWeaponOnDeath`, base loot table) — read-only,
  categorically.
- Cannot hook inside the native `GenerateLoot`/`ProcessLoot`/`DropWeapons` bodies — final+import.
- Cannot 100%-prove (from decompiled script alone) that `TransactionSystem.RemoveAllItems` fires
  `OnInventoryEmptyEvent` — mitigated by the redundant `EvaluateLootQualityByTask` call.
- Cannot fully rule out a native-only (non-script) consumer of `KillRewardEvent` beyond the
  telemetry handler found — irrelevant to the recommended design since `AwardsExperience()` is the
  actual XP lever, not `KillRewardEvent`.
- Cannot guarantee (without a compile check) that `@wrapMethod` accepts `private`/`const` targets
  in this specific toolchain — no local precedent either way; general REDscript convention says
  yes, ScannerSuite.reds simply never needed to test it.

## Open questions

1. **Does `@wrapMethod` compile on a `private` function (`ScriptedPuppet.DropHeldItems`) and on a
   `const` function (`ScriptedPuppet.AwardsExperience`) in this toolchain?** No local precedent
   either way (Findings §1b, §4c). Planner-relevant because it decides which ladder tier
   (Full vs. the two degraded tiers above) is actually reachable — recommend the implementer try
   both wraps first via `sprint/bin/scc-serial.sh` and fall back per the ladder if either fails.
2. **Does `TransactionSystem.RemoveAllItems` synchronously fire `OnInventoryEmptyEvent`, or is a
   deferred re-check via `EvaluateLootQualityByTask` load-bearing?** Native internals opaque
   (Findings §2d). Does not block planning (the belt-and-suspenders call is cheap and already
   recommended either way) but affects exact call-ordering/timing the implementer should use
   relative to `wrappedMethod()` inside the `OnIncapacitated` wrap (immediate vs. next-frame via
   `DelaySystem.DelayCallbackNextFrame`, per this project's rule-3 deferred-mutation guidance).
