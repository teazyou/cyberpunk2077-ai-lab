# R1 — Runtime rarity mutation + per-tier stat anatomy (tier-uprank-mechanism)

## Verdict
**Literal rarity/record mutation: BLOCKED, structurally.** `GetNPCRarity()`/`GetNPCRarityRecord()`/`GetRecordID()` on `gamePuppet` are `public import const final` — native getters, zero setter/record-swap counterpart anywhere in the decompile (grep for `SetNPCRarity`/`SetRecordID`/`SwapRecord`/`ReplaceRecord` across all of `sprint/vanilla-scripts` returns nothing rarity-related); TweakDB itself has no write surface either (`tweakDB.script`, 1156 lines, zero `Set*`/`CreateRecord`). Not a "couldn't find it" gap — the getter-only signature IS the proof.

**Stat-emulation fallback: feasible, and unusually well-justified.** CDPR's own per-tier data (fetched from the community TweakDB dump, cross-checked against the locally-verified `StatModifier_Record` shape and the locally-verified `RPGManager.StatRecordToModifier()`/`StatsSystem.AddModifier(s)` pipeline — the SAME pipeline vanilla code uses for Device stat init) gives an exact, non-guessed recipe for reproducing a one-tier jump in Health/Armor/Accuracy/DPS. Decisive risk to flag to the planner: `DamageSystem.ScalePlayerDamage()` auto-compensates player-sourced damage against a PowerLevel+rarity-predicted "expected health," so a Health-only stat bump (no PowerLevel change) is largely self-cancelling for TTK — the emulation should ride on the same PowerLevel-curve machinery vanilla uses for NPC scaling, not a bare Health multiplier.

**UI tier badge/healthbar/XP-reward tier will NOT visibly update** under stat-emulation — those all read `GetNPCRarity()` fresh but that getter is frozen (see above). Only the numeric toughness (Health/Armor/Accuracy/DPS) actually shifts. Plan/acceptance-criteria wording should account for this: "visible tier/power jump" will read as bigger healthbar + harder fight, NOT a new nameplate badge.

**Fallback ladder (mechanism selection, most- to least-preferred):**
1. ~~Literal record/rarity swap~~ — BLOCKED, no API exists (Findings 1-2). Do not attempt.
2. **Per-tier `StatModifier_Record` replay (RECOMMENDED primary)** — read the target tier's `NPCRarity_Record.StatModifiers()` via `TweakDBInterface.GetNPCRarityRecord(T"NPCRarity.<TargetTier>")`, convert each via `RPGManager.StatRecordToModifier()`, apply via `StatsSystem.AddModifiers()` — the exact device-init pipeline (Finding 8), using CDPR's own per-tier numbers (Finding 7). Delivers Health/Armor/Accuracy/(sometimes)DPS deltas that are genuinely data-justified.
3. **PowerLevel/Level Additive bump, `NPCManager.ScaleToPlayer()` pattern (complementary or fallback-of-fallback)** — coarser, cascades via the shared PowerLevel curves (Finding 9-10); most useful paired with #2 to avoid the `ScalePlayerDamage` auto-compensation trap (Finding 11) if a Health-only application of #2 turns out (empirically, Open Question 1) to get fought by that same compensation.
4. **Hand-picked flat percentage bump (last resort only)** — not data-justified, contradicts the brief's "multipliers justified from game data" instruction; fall back to this only if #2/#3 fail to compile or produce unusable results in testing.

## Findings

### 1. No setter exists for NPC rarity — verified by absence, not just by search
```
public import const final function GetNPCRarity() : gamedataNPCRarity;       // core/gameplay/puppet.script:95
public import const final function GetNPCRarityRecord() : NPCRarity_Record;  // core/gameplay/puppet.script:96
public import const final function GetRecordID() : TweakDBID;                // core/gameplay/puppet.script:13
```
All three are `import const final` on `gamePuppet` — native, read-only, non-overridable. `ScriptedPuppet.GetRecord()` (`cyberpunk/puppet/scriptedPuppet.script:1414`) is a thin wrapper — `return TweakDBInterface.GetCharacterRecord( GetRecordID() )` — re-resolved fresh from the same unwritable `GetRecordID()` every call, no cached/mutable field to overwrite. Exhaustive grep for `SetNPCRarity`, `SetRarity`, `SetRecordID`, `SwapRecord`, `ReplaceRecord`, `RespawnPuppet`, `TransformInto` across the whole decompile: the only `SetRarity` hits are unrelated UI item-tooltip-quality widgets (`cyberpunk/UI/inventory/inventoryItemPartDisplay.script:47`, `InventoryItemDisplay.script:74`) — nothing touching `gamedataNPCRarity`.

### 2. TweakDB has no write path either (confirms context-environment.md's rule from the API side)
`tweakDB.script` (1156 lines total) defines `TweakDBInterface` (line 1) and its subclass `TDB` (line 1022) — every member across both is `public import [static] function Get*`. Grep for `Set`/`CreateRecord`/`SetFlat` returns zero hits. So even the "swap the character record wholesale" idea is doubly blocked: no record-assignment setter on the puppet, AND no way to mutate/clone a TweakDB record at runtime to point it at.

### 3. Rarity manifestations: which are live, which are dead ends for us
- **Nameplate/healthbar badge — architecturally LIVE, practically frozen.** `NameplateVisualsLogicController.SetNPCType()` (`cyberpunk/UI/widgets/healthbar/nameplateVisuals.script:252-281`) reads `puppet.GetNPCRarity()` fresh every single call, and is itself called on every `SetVisualData()` refresh (`:109`, fired on nameplate (re)acquisition — not a spawn-time-only snapshot). Since the getter is unwritable (Finding 1), this channel will show the ORIGINAL tier forever no matter what we do.
  - Only 3 of 8 tiers get a distinct badge at all: `Rare`→`m_isRare`, `Elite`→`m_isElite`, `Boss`+`MaxTac`→shared `m_isBoss` (`:264-278`). `Trash`/`Weak`/`Normal`/`Officer` hit no `case` at all → no badge, same as the explicit `Weak: break;` no-op. So even a literal-record change on a Trash→Weak rung would be invisible in the nameplate specifically.
- **Boss healthbar** — same live-read, same frozen-in-practice conclusion: `BossHealthBarGameController` gates on `puppet.IsBoss() || puppet.GetNPCRarity()==MaxTac`, re-read per update (`healthbar/bossHealthBar.script:126,137,189,258,273,300`).
- **XP/kill reward tier** — `BountyManager.CompleteBounty()` switches on `target.GetNPCRarity()` at kill-time (`cyberpunk/managers/bountyManager.script:233-256`) to pick `T"RPGActionRewards.Neutralize<Tier>Enemy"`. Frozen at spawn tier under emulation — matches the brief's "rewards: natural, no reward-tampering code" instruction anyway, so this is not a problem, just a fact to log.
- **Player damage-vs-rarity bonuses** (`BonusDamageAgainstElites/Rares/Bosses`) — `cyberpunk/damage/damageManager.script:248-298` (`CalculateSourceModifiers`) — also keyed on the frozen getter; a stat-emulated "fake Elite" will never trigger the player's anti-Elite perks.
- **Actual combat toughness (Health/Armor/Accuracy/DPS) is NOT sourced from `GetNPCRarity()` at all** — it's baked in at spawn as ordinary `StatsSystem` stat modifiers (Additive/Multiplier/Curve) that exist independently of the rarity getter. This is the only lever stat-emulation can pull, and Findings 7-9 show exactly how.

### 4. `gamedataStatType.NPCRarity` is a real, readable/writable STAT — but a dead end for cascading toughness
`tweakDBEnums.script:1395` lists `NPCRarity` inside the (huge) `gamedataStatType` enum (distinct from the `gamedataNPCRarity` type enum at `:3396`). It's read live in vanilla: `targetRarity = statSystem.GetStatValue( target.GetEntityID(), gamedataStatType.NPCRarity )` (`cyberpunk/player/psm/locomotionTakedown.script:276`, feeds a grapple-duration formula). Its value is the tier's `RarityValue()` float (Finding 7). It IS writable via `StatsSystem.AddModifier` in principle — but Finding 9 shows Health/Armor/DPS curve modifiers key off `BaseStats.PowerLevel`, never `BaseStats.NPCRarity` — so writing this stat alone changes nothing downstream except whatever else explicitly reads `gamedataStatType.NPCRarity` (the takedown-grapple formula being the only vanilla-script reader found). Do not treat it as "the lever."

### 5. `gamedataNPCRarity` enum order is alphabetical, NOT power order — never do ordinal math
Decompiled order (`tweakDBEnums.script:3396-3408`): `Boss, Elite, MaxTac, Normal, Officer, Rare, Trash, Weak, Count, Invalid`. Every vanilla use is an explicit `switch`/`==` chain — `RPGManager.GetRarityMultiplier` (`rpgManager.script:265-292`), `BountyManager.CompleteBounty` (`bountyManager.script:233-256`), `NameplateVisualsLogicController.SetNPCType` (`nameplateVisuals.script:264-278`), `DamageManager.CalculateSourceModifiers` (`damageManager.script:263-288`) — **never** `(Int32)rarity+1` or similar. Confirms: any "next tier" lookup in our mod must be an explicit ladder table, never enum-ordinal arithmetic. The *actual* power-ordered scalar is `NPCRarity_Record.RarityValue()` (Finding 7) — Trash=1.0 through Boss=7.0, monotonic with the brief's ladder.

### 6. The record shape that carries per-tier data — locally verified, confirms the web data's structure
```
importonly class NPCRarity_Record extends TweakDBRecord {
  public import function EnumComment() : String;
  public import function StatModifiers( out outList : array< weak< StatModifier_Record > > );
  public import function GetStatModifiersCount() : Int32;
  public import function GetStatModifiersItem( index : Int32 ) : weak< StatModifier_Record >;
  public import function GetStatModifiersItemHandle( index : Int32 ) : StatModifier_Record;
  public import function StatModifiersContains( item : weak< StatModifier_Record > ) : Bool;
  public import function EnumName() : CName;
  public import function RarityValue() : Float;
  public import function NotAvailableDynamically() : Bool;
  public import function Type() : gamedataNPCRarity;
}                                                             // core/data/tweakDBRecords.script:6222-6232
```
`Character_Record.Rarity() : weak<NPCRarity_Record>` / `.RarityHandle()` (`tweakDBRecords.script:3456-3457`) is how a character record points at its tier. `TweakDBInterface.GetNPCRarityRecord(path:TweakDBID):NPCRarity_Record` (also on `TDB`, `core/data/tweakDB.script:605`) is how to fetch an ARBITRARY tier's record by path — this is the call that lets us read the NEXT tier's data, not just the puppet's current one.

### 7. Per-tier data, verbatim from CDPR's own TweakDB (WEB source — not in `sprint/vanilla-scripts`, see caveat below)
`sprint/vanilla-scripts` contains only compiled *scripts*; TweakDB *data* (the actual per-record numbers) is not part of that decompile. Fetched verbatim via `curl` (not summarized) from `CDPR-Modding-Documentation/Cyberpunk-Tweaks` (GitHub, community-maintained decompiled TweakDB — same community org as the user's own trusted `Cyberpunk-Scripts` source per project memory), file `tweaks/base/gameplay/static_data/database/characters/npcs/records/gameplay/npcrarities.tweak` (526 lines, `package NPCRarity`). Corroborated independently by `gh search code` hits for the `"NPCRarity.Elite"` / `"NPCRarity.Boss"` / `"NPCRarity.Trash"` / `"NPCRarity.Officer"` / `"NPCRarity.Rare"` / `"NPCRarity.Weak"` string convention across ~10 unrelated mod repos (incl. official `CDPR-Modding-Documentation/Cyberpunk-Tweaks` quest files, `wiki.redmodding.org`'s own tweaks-tutorial page using Jackie's `rarity: NPCRarity.Elite` as its example).

| Tier | `rarityValue` | Health modifier (Multiplier, curve set `puppet_powerLevelToHealth`, keyed on `BaseStats.PowerLevel`) | Armor: `HitShapeArmor` flat ×(`BaseStats.Armor`) | DPS modifier | Accuracy curve column | Other |
|---|---|---|---|---|---|---|
| Trash | 1.0 | col `puppet_powerLevelToRarityHealthMultiplier_trash` | ×1.00 | Multiplier curve, id `puppet_preset_trash_mods`, col `power_level_to_dps_mod` | `trash_puppet_accuracy` | `HasSubdermalArmor`=0 |
| Weak | 2.0 | col `..._weak` | ×1.05 | Multiplier curve, id `puppet_preset_weak_mods` | `weak_puppet_accuracy` | `HasSubdermalArmor`=0 |
| Normal | 3.0 | *(none — baseline, ×1.0 implicit)* | ×1.10 | *(none — baseline)* | `normal_puppet_accuracy` | `HasSubdermalArmor`=0 |
| Rare | 4.0 | col `..._rare` | ×1.15 | *(none — baseline)* | `rare_puppet_accuracy` | + `LootLevel` curve |
| **Officer** | 4.5 | **= Rare (no override — `Officer : Rare` inherits Rare's ENTIRE `statModifiers` block wholesale)** | **= Rare, ×1.15** | **= Rare (none)** | **= Rare** | `notAvailableDynamically=true` |
| Elite | 5.0 | col `..._elite` | ×1.20 | *(none — baseline)* | `elite_puppet_accuracy` | `DamageReductionExplosion`+0.35, `HackingResistance`+1, extended hit-recovery timers (2.5-4.33s) |
| MaxTac *(excluded)* | 6.0 | col `..._boss` (shares Boss's column) | ×1.25 | AdditiveMultiplier curve, id `puppet_preset_boss_mods` | `elite_puppet_accuracy` (shares Elite's) | Knockdown/Wounded-immune, all 10 Wound/Dismemberment thresholds zeroed, `DamageReductionExplosion`+0.6, `HackingResistance`+3, `notAvailableDynamically=true` |
| Boss *(excluded)* | 7.0 | col `..._boss` | ×1.25 | AdditiveMultiplier curve, id `puppet_preset_boss_mods` | `boss_puppet_accuracy` | Same immunity kit as MaxTac + `Stamina`×1.25, `DamageReductionExplosion`+0.35, `notAvailableDynamically=true` |

Baseline every NPC gets regardless of rarity (`NPC_Base_Curves` `StatModifierGroup`, same file family, `.../characters/npcs/stats/primary_stats.tweak:4-84`, applied to every archetype via `ArchetypeData_Record.StatModifierGroups()` → `RPGManager.ApplyStatModifierGroups()`, locally verified at `cyberpunk/managers/npcManager.script:81-105`):
- `BaseStats.Level` ← Additive curve `puppet_power_level_to_level`, keyed on `BaseStats.PowerLevel`.
- `BaseStats.Health` ← Additive curve `puppet_powerLevelToHealth`/col `puppet_powerLevelToHealth_base`, keyed on PowerLevel — this is the number the per-tier Multiplier above scales.
- `BaseStats.DPS` ← Multiplier curve `puppet_powerLevelToDPS`/col `puppet_intrinsic_levelToDPS`, keyed on PowerLevel — the number Trash/Weak/Boss/MaxTac's own DPS modifiers scale (Normal/Rare/Elite/Officer take this baseline unmodified — **an Elite does not out-damage a Normal in vanilla; the whole Normal→Elite toughness gap is Health×Armor×Accuracy, not raw damage**, a genuinely load-bearing nuance for tuning).
- `BaseStats.Armor` ← Combined `AdditiveMultiplier`, `refStat=BaseStats.ArmorMultBonus`, ×1 (separate from the rarity's own `HitShapeArmor` flat multiplier above).

**Caveat on this whole Finding**: the numbers are WEB-sourced (community TweakDB dump), not from `sprint/vanilla-scripts`. The *API shapes* they rely on (`StatModifier_Record` subtypes, `RPGManager.StatRecordToModifier`, curve modifier fields) ARE locally verified (Finding 6, 9). Treat the exact floats as high-confidence, not vanilla-grep-certain — see Open Questions §3 for a cheap in-game verification path.

### 8. The exact vanilla pipeline for turning `StatModifier_Record` lists into applied stats — directly reusable
```
protected function InitializeStats() {
  ...
  record.StatModifiers( statList );                                    // NPCRarity_Record.StatModifiers() is this same shape
  statModifiers.Resize( statList.Size() );
  for( i = 0; i < statList.Size(); i += 1 ) {
    statModifiers[ i ] = RPGManager.StatRecordToModifier( statList[ i ] );
  }
  statSystem.AddModifiers( GetMyEntityID(), statModifiers );
}                                                    // cyberpunk/devices/core/scriptableDeviceBasePS.script:535-554
```
`RPGManager.StatRecordToModifier(statRecord:StatModifier_Record):gameStatModifierData` (`cyberpunk/managers/rpgManager.script:1659-1696`) branches on the record's concrete subtype — `ConstantStatModifier_Record`→`CreateStatModifier`, `CurveStatModifier_Record`→`CreateCurveModifier`, `CombinedStatModifier_Record`→`CreateCombinedStatModifier` — the exact 3 subtypes the web-sourced tweak file uses (Finding 7's table: `ConstantStatModifier`/`CurveStatModifier`/`CombinedStatModifier`). **This device-init pattern is the template**: swap `TweakDBInterface.GetDeviceRecord(...)` for `TweakDBInterface.GetNPCRarityRecord(T"NPCRarity.<TargetTier>")`, everything else lines up 1:1.

### 9. PowerLevel is the master curve key — proof Health-only bumps are the wrong lever
Finding 7's table shows every tier's Health modifier is a `CurveStatModifier` with `refStat="BaseStats.PowerLevel"` — never `BaseStats.NPCRarity`. Combined with Finding 4 (writing the NPCRarity stat cascades nowhere), this proves: **an NPC's toughness is fundamentally `f(PowerLevel) × g(PowerLevel, tierColumn)`** — both factors keyed on the SAME PowerLevel stat, just different curve columns. This is confirmed independently from the runtime-damage side too:
```
baseNPCHealth = GameInstance.GetStatsDataSystem(...).GetValueFromCurve( 'puppet_powerLevelToHealth', 1.0, 'puppet_powerLevelToHealth' );
baseNPCHealth *= RPGManager.GetRarityMultiplier( targetPuppet, 'power_level_to_health_mod' );   // itself PowerLevel-keyed, rpgManager.script:255-294
```
— `cyberpunk/damage/damageSystem.script:3483-3484`, inside `ScalePlayerDamage` (Finding 10).

### 10. Vanilla precedent for "make this NPC act like a different power level" — `NPCManager.ScaleToPlayer()`
```
private function ScaleToPlayer() {
  statSys = GameInstance.GetStatsSystem( m_owner.GetGame() );
  statSys.RemoveAllModifiers( m_owner.GetEntityID(), gamedataStatType.PowerLevel );
  playerPL = statSys.GetStatValue( GameInstance.GetPlayerSystem( m_owner.GetGame() ).GetLocalPlayerControlledGameObject().GetEntityID(), gamedataStatType.PowerLevel );
  playerLevel = statSys.GetStatValue( GameInstance.GetPlayerSystem( m_owner.GetGame() ).GetLocalPlayerControlledGameObject().GetEntityID(), gamedataStatType.Level );
  modifier = RPGManager.CreateStatModifier( gamedataStatType.PowerLevel, gameStatModifierType.Additive, playerPL );
  statSys.AddModifier( m_owner.GetEntityID(), modifier );
  modifier = RPGManager.CreateStatModifier( gamedataStatType.Level, gameStatModifierType.Additive, playerLevel );
  statSys.AddModifier( m_owner.GetEntityID(), modifier );
}                                                              // cyberpunk/managers/npcManager.script:107-121 (private — pattern only, not directly callable)
```
Because Health/Level/DPS are all PowerLevel-curve-driven (Finding 9), bumping PowerLevel this way cascades automatically — this is CDPR's own "rescale this NPC" lever, and the cleanest precedent for a fallback mechanism.

### 11. Damage auto-compensation — the sharpest gotcha in this whole investigation
```
private function ScalePlayerDamage( const hitEvent : gameHitEvent ) {
  targetHealth = GameInstance.GetStatsSystem(...).GetStatValue( target.GetEntityID(), gamedataStatType.Health );      // ACTUAL current Health stat
  if target not Boss/MaxTac:
    baseNPCHealth = GetValueFromCurve('puppet_powerLevelToHealth', 1.0, 'puppet_powerLevelToHealth');
    baseNPCHealth *= RPGManager.GetRarityMultiplier( targetPuppet, 'power_level_to_health_mod' );                     // PREDICTED health from frozen rarity + CURRENT PowerLevel
    multiplier = targetHealth / baseNPCHealth;
    ...
    hitEvent.attackComputed.MultAttackValue( multiplier );                                                            // scales incoming PLAYER damage by that ratio
}                                                              // cyberpunk/damage/damageSystem.script:3468-3502
```
If we bump `gamedataStatType.Health` directly (Additive/Multiplier, no PowerLevel change), `targetHealth` rises while `baseNPCHealth` (still anchored to the frozen `GetNPCRarity()` + unchanged PowerLevel) does not — so `multiplier>1` and the game scales the PLAYER's outgoing damage up by roughly the same ratio, **largely canceling the intended tankiness for player-sourced hits** (TTK ~unchanged; only the number on the healthbar is bigger). Bumping `PowerLevel` instead (Finding 10) raises BOTH sides of that ratio together (`GetRarityMultiplier` re-reads live PowerLevel each call), avoiding self-cancellation — assuming the target tier's own curve column diverges meaningfully from the source tier's at the same PowerLevel input, which Finding 7's per-tier distinct columns are explicitly designed to do. Non-player damage sources (environment, other NPCs) are untouched by this compensation either way.

### 12. Health stat-pool re-sync — explicit call is the vanilla pattern
```
public import function GetStatPoolMaxPointValue( objID : StatsObjectID, statPoolType : gamedataStatPoolType ) : Float;
public import function RequestSettingStatPoolMaxValue( objID : StatsObjectID, statPoolType : gamedataStatPoolType, instigator : weak< GameObject > );
public import function RequestSettingStatPoolValue( objID : StatsObjectID, statPoolType : gamedataStatPoolType, newValue : Float, instigator : weak< GameObject >, optional perc : Bool, optional ignoreCustomLimit : Bool );
public import function RequestChangingStatPoolValue( objID : StatsObjectID, statPoolType : gamedataStatPoolType, diff : Float, instigator : weak< GameObject >, forceChunkTransfering : Bool, optional perc : Bool, optional ignoreCustomLimit : Bool );
```
— `core/systems/statPoolsSystem.script:39,50,51,54`. Every vanilla site that intentionally wants a Health pool's cached max to reflect an updated underlying stat calls `RequestSettingStatPoolMaxValue` explicitly right after: `scriptableDeviceBasePS.script:5676` (`OnQuestResetDeviceToInitialState`, right after re-enabling the device), `vehicleComponent.script:4627` (`RepairVehicle`). `StatPoolsManager.DrainStatPool()` (`cyberpunk/damage/statPoolsManager.script:359-404`) operates in PERCENTAGE space internally (`GetStatPoolValue(...,perc=true)` → `ToPoints`), which suggests current-HP-as-%-of-max would scale proportionally if max changes — but the fact that CDPR's own code still calls `RequestSettingStatPoolMaxValue` explicitly at every intentional-max-change site (rather than relying on silent auto-refresh) is the strongest available signal: **treat the resync call as required**, issued immediately after the `AddModifier`/`AddModifiers` call that touches `gamedataStatType.Health`. If the NPC's current HP should visibly jump too (not just max), follow with `RequestSettingStatPoolValue(objID, gamedataStatPoolType.Health, 1.0, instigator, true)` (percentage mode, top off to 100%) or `RequestChangingStatPoolValue` for a delta.

### 13. `AddSavedModifier` vs `AddModifier` — a real stacking hazard for this specific feature
```
public import function AddModifier( objID : StatsObjectID, modifierData : gameStatModifierData ) : Bool;        // statsSystem.script:38
public import function AddModifiers( objID : StatsObjectID, modifierData : array< gameStatModifierData > ) : Bool; // statsSystem.script:39
public import function AddSavedModifier( objID : StatsObjectID, modifierData : gameStatModifierData ) : Bool;   // statsSystem.script:40
```
Grepped every `AddSavedModifier` call site in the decompile (~70 hits): **100% of them are either item Quality/upgrade-tier persistence** (`core/systems/craftingSystem.script`, `cyberpunk/devices/stash/stash.script`, `cyberpunk/systems/marketSystem/vendor.script`, `cyberpunk/player/player.script` item-scaling blocks) **or permanent player buffs** (`player.script:5201-5236`, var literally named `permaMod`). Never once used for a transient per-session NPC combat buff. Since the brief's design is explicitly session-scoped (in-memory seen-set, "save/reload may re-roll — accepted"), using `AddSavedModifier` risks the OLD modifier surviving into a reloaded save (persisted) while the reset seen-set causes a FRESH roll to add a SECOND modifier on top — direct stacking, violating "single-tier bump only, never stacking." **Recommend plain `AddModifier`/`AddModifiers`**, consistent with the session-only design.

### 14. Rarity/Boss/MaxTac reading — the exact predicates for this mission's Q5
```
public const function IsOfficer() : Bool { return GetNPCRarity() == gamedataNPCRarity.Officer; }        // scriptedPuppet.script:1533-1536
public static function IsBoss( obj : weak<GameObject> ) : Bool                                            // scriptedPuppet.script:1640-1647
public const function IsBoss() : Bool { return GetNPCRarity() == gamedataNPCRarity.Boss; }                // scriptedPuppet.script:1649-1652
public static function IsMaxTac( obj : weak<GameObject> ) : Bool                                          // scriptedPuppet.script:1654-1661
public const function IsMaxTac() : Bool { return GetNPCRarity() == gamedataNPCRarity.MaxTac; }            // scriptedPuppet.script:1663-1666
public const function IsElite() : Bool { return GetNPCRarity() == gamedataNPCRarity.Elite; }              // scriptedPuppet.script:1673-1676
```
No named wrapper exists for Trash/Weak/Normal/Rare — check `GetNPCRarity() == gamedataNPCRarity.X` directly (equally verified, just no shorthand). Vanilla ALWAYS pairs Boss+MaxTac as one combined exclusion (10+ sites, e.g. `NPCPuppet.script:448,840,2655`; `hitReactionComponent.script:331,2375,2492,2874`) — mirror that, never treat them as separately-optional. Adjacent (not this mission's job — owned by the shared eligibility helper — but co-located for completeness): `IsCharacterPolice()`/`IsPrevention()` (`scriptedPuppet.script:1780-1794,1976-1979`), `IsCharacterCivilian()` (`:1775-1778`), `IsCrowd()` (`:1815-1818`), `GetNPCType()==Human` (`:1419-1422`).

## API inventory

| API / member | Signature | Evidence (file:line) | Verified? |
|---|---|---|---|
| `gamePuppet.GetNPCRarity()` | `: gamedataNPCRarity`, import const final | `core/gameplay/puppet.script:95` | VERIFIED |
| `gamePuppet.GetNPCRarityRecord()` | `: NPCRarity_Record`, import const final | `core/gameplay/puppet.script:96` | VERIFIED |
| `gamePuppet.GetRecordID()` | `: TweakDBID`, import const final | `core/gameplay/puppet.script:13` | VERIFIED |
| `ScriptedPuppet.IsBoss()` / static `IsBoss(obj)` | `: Bool` | `scriptedPuppet.script:1640-1652` | VERIFIED |
| `ScriptedPuppet.IsMaxTac()` / static `IsMaxTac(obj)` | `: Bool` | `scriptedPuppet.script:1654-1666` | VERIFIED |
| `ScriptedPuppet.IsElite()` / `IsOfficer()` | `: Bool` | `scriptedPuppet.script:1673-1676` / `1533-1536` | VERIFIED |
| `NPCRarity_Record.RarityValue()` | `: Float` | `core/data/tweakDBRecords.script:6231` | VERIFIED (member; values 1.0-7.0 are WEB-sourced, Finding 7) |
| `NPCRarity_Record.StatModifiers(out array<weak<StatModifier_Record>>)` + `GetStatModifiersCount/Item(Handle)` | — | `tweakDBRecords.script:6224-6227` | VERIFIED |
| `NPCRarity_Record.NotAvailableDynamically()` | `: Bool` | `tweakDBRecords.script:6230` | VERIFIED (member; semantics inferred from data, Finding 7) |
| `Character_Record.Rarity()` / `.RarityHandle()` | `: weak<NPCRarity_Record>` / `NPCRarity_Record` | `tweakDBRecords.script:3456-3457` | VERIFIED |
| `TweakDBInterface.GetNPCRarityRecord(path)` (also on `TDB`) | `static (TweakDBID) : NPCRarity_Record` | `core/data/tweakDB.script:605` | VERIFIED |
| `TweakDBInterface.GetCharacterRecord(path)` | `static (TweakDBID) : Character_Record` | `tweakDB.script:371` | VERIFIED |
| `GameInstance.GetStatsSystem(self)` | `static : StatsSystem` | `core/systems/gameInstance.script:43` | VERIFIED |
| `GameInstance.GetStatPoolsSystem(self)` | `static : StatPoolsSystem` | `gameInstance.script:42` | VERIFIED |
| `GameInstance.GetStatsDataSystem(self)` | `static : StatsDataSystem` | `gameInstance.script:44` | VERIFIED |
| `StatsSystem.GetStatValue(objID,statType)` | `: Float` | `core/systems/statsSystem.script:34` | VERIFIED |
| `StatsSystem.AddModifier(objID,modifierData)` | `: Bool` | `statsSystem.script:38` | VERIFIED |
| `StatsSystem.AddModifiers(objID,array<modifierData>)` | `: Bool` | `statsSystem.script:39` | VERIFIED |
| `StatsSystem.AddSavedModifier(objID,modifierData)` | `: Bool` | `statsSystem.script:40` | VERIFIED to exist; NOT RECOMMENDED here (Finding 13) |
| `StatsSystem.RemoveAllModifiers(objID,statType,optional removeSaved)` | `: Bool` | `statsSystem.script:44` | VERIFIED |
| `StatsDataSystem.GetValueFromCurve(curveSetName,argumentValue,optional columnName,optional difficulty)` | `: Float` | `core/systems/statsDataSystem.script:25` | VERIFIED |
| `RPGManager.CreateStatModifier(statType,modType,value)` | `: gameStatModifierData` | `cyberpunk/managers/rpgManager.script:1612` | VERIFIED |
| `RPGManager.CreateStatModifierUsingCurve(statType,modType,refStat,curveName,columnName)` | `: gameStatModifierData` | `rpgManager.script:1622` | VERIFIED |
| `RPGManager.CreateCombinedStatModifier(statType,modType,refStat,opSymbol,value,refObject)` | `: gameStatModifierData` | `rpgManager.script:1634` | VERIFIED |
| `RPGManager.StatRecordToModifier(statRecord)` | `(StatModifier_Record) : gameStatModifierData` | `rpgManager.script:1659-1696` | VERIFIED |
| `RPGManager.GetRarityMultiplier(puppet,curveName)` | `(NPCPuppet,CName) : Float` | `rpgManager.script:255-294` | VERIFIED — but locked to the puppet's OWN current rarity (reads `puppet.GetNPCRarity()` internally, `:262`); can't query a hypothetical tier directly — call `GetValueFromCurve` yourself with the target tier's preset name for that |
| `StatPoolsSystem.GetStatPoolValue(objID,poolType,optional perc)` | `: Float` | `core/systems/statPoolsSystem.script:40` | VERIFIED |
| `StatPoolsSystem.GetStatPoolMaxPointValue(objID,poolType)` | `: Float` | `statPoolsSystem.script:39` | VERIFIED |
| `StatPoolsSystem.RequestSettingStatPoolMaxValue(objID,poolType,instigator)` | — | `statPoolsSystem.script:50` | VERIFIED |
| `StatPoolsSystem.RequestSettingStatPoolValue(objID,poolType,newValue,instigator,optional perc,optional ignoreCustomLimit)` | — | `statPoolsSystem.script:51` | VERIFIED |
| `StatPoolsSystem.RequestChangingStatPoolValue(objID,poolType,diff,instigator,forceChunkTransfering,optional perc,optional ignoreCustomLimit)` | — | `statPoolsSystem.script:54` | VERIFIED |
| `gameStatModifierType` enum | `{Additive, AdditiveMultiplier, Multiplier, Count, Invalid}` | `core/data/statsData.script:9-16` | VERIFIED |
| `gameConstantStatModifierData` / `gameCurveStatModifierData` / `gameCombinedStatModifierData` | field shapes | `statsData.script:55-73` | VERIFIED |
| `NPCManager.ScaleToPlayer()` | pattern only — `private`, not directly callable cross-class | `cyberpunk/managers/npcManager.script:107-121` | VERIFIED (as precedent pattern) |
| `StatsObjectID` param | accepts `EntityID` directly, no explicit cast, at every call site | e.g. `npcManager.script:118`, `damageSystem.script:3479` | VERIFIED BY USAGE (no explicit typedef found; dozens of direct-pass call sites) |
| `gamedataStatType.NPCRarity` | stat enum member | `core/data/tweakDBEnums.script:1395`; read usage `locomotionTakedown.script:276` | VERIFIED to exist; VERIFIED USELESS for cascading Health/Armor/DPS (Findings 4, 9) |
| TweakDBID paths `"NPCRarity.Trash/Weak/Normal/Rare/Officer/Elite/Boss/MaxTac"` | string convention | WEB: `CDPR-Modding-Documentation/Cyberpunk-Tweaks` `npcrarities.tweak` (fetched verbatim) + corroborated across ~10 independent mod repos via `gh search code` | UNVERIFIED against `sprint/vanilla-scripts` (no TweakDB data there); high-confidence web-verified — see Open Questions §3 |

## Precedents & inspiration
- **Device stat-init pipeline** (`scriptableDeviceBasePS.script:535-554`) — the direct template: `record.StatModifiers()` → `RPGManager.StatRecordToModifier()` per entry → `StatsSystem.AddModifiers()` once. Swap the device record for `TweakDBInterface.GetNPCRarityRecord(T"NPCRarity.<TargetTier>")` and this is a straight copy.
- **`NPCManager.ScaleToPlayer()`** (`npcManager.script:107-121`) — canonical "rescale this NPC" via PowerLevel+Level `Additive` bump only; the fallback-ladder's rung 2 (below).
- **ScannerSuite.reds `STSweepTickCallback`** (`mods/enabled/r6-scripts/custom-scanner-suite/ScannerSuite.reds:1303-1501`) — in-game-proven self-rearming `DelaySystem.DelayCallback` sweep matching the brief's "~0.5-1s periodic sweep" ask; `ST_RunSweepOnce` (`:1426-1501`) shows `GameInstance.GetTargetingSystem(game).GetTargetParts(...)` frustum enumeration. Not this mission's question, but directly reusable shape for whichever file owns the sweep loop. (No `StatsSystem`/`NPCRarity` usage anywhere in ScannerSuite.reds itself — confirmed by grep, this mission is genuinely new ground for this codebase.)
- **`sprint/reference-aggro`** — grepped for `StatsSystem`/`NPCRarity`/`StatPoolsSystem`: zero hits. Not a precedent for this mission (different domain, and appears to target TweakXL/ArchiveXL tweak-file editing rather than runtime REDscript stat mutation — NOT AVAILABLE on this macOS setup per context-environment.md anyway).
- **GitHub (inspiration only, NOT vanilla-verified, modern `.reds` dialect confirmation)**: `djkovrik/CP77Mods` "Limited HUD" `hudNoEnemyRedHighlight.reds` — `this.IsAggressive() || this.IsBoss() || Equals(this.GetNPCRarity(), gamedataNPCRarity.MaxTac)` — confirms the same APIs we verified in legacy `.script` dialect translate directly into modern `.reds` syntax (`Equals()` in place of `==` for enum compare). `SaganoKei/Better-Netrunning-Fix` `ProgressionSystem.reds` — `switch`/`case gamedataNPCRarity.Trash:` etc. in modern dialect, consistent with our "explicit ladder, no ordinal math" finding.

## Dead ends
- **Literal rarity/record mutation in any form** — no setter, no record-swap, no TweakDB write path. Not worth re-attempting; the getter-only signatures on `gamePuppet` are the proof, not a search-coverage gap.
- **Bumping `gamedataStatType.NPCRarity` alone** — writable, but nothing downstream reads it to derive Health/Armor/DPS (those key off `BaseStats.PowerLevel` exclusively per the web-sourced curve data). Cosmetic only.
- **A bare `gamedataStatType.Health` Additive/Multiplier bump with no PowerLevel change** — algebraically fought by `DamageSystem.ScalePlayerDamage`'s auto-compensation (Finding 11) for player-sourced damage specifically. Bigger healthbar number, ~same TTK. Will not satisfy "visible tier/power jump" alone.
- **`RPGManager.GetRarityMultiplier(puppet, curveName)` for a hypothetical/target tier** — hard-locked to `puppet.GetNPCRarity()` internally; cannot be redirected to a different tier by any parameter. Call `StatsDataSystem.GetValueFromCurve` directly with the target tier's own curve/column (Finding 7's table) instead.
- **`gibbed/Cyberpunk-TweakDB-Schema` raw-path guess** — 404'd; abandoned after one attempt in favor of the `CDPR-Modding-Documentation/Cyberpunk-Tweaks` fetch, which succeeded and yielded actual values (schema shape alone would have been lower-value anyway).

## Open questions
1. **Exact compounding arithmetic for stacked `Multiplier`/`AdditiveMultiplier`/`Additive` stat modifiers on the same stat** (e.g., a synthetic Health-delta modifier stacking against the vanilla tier's own Multiplier + the PowerLevel base Additive curve) lives in native C++, invisible to any decompiled script. Recommend the implementer treat computed HP numbers as approximate and verify empirically in-game rather than assume exact math — not planner-blocking, but should inform how tight the tuning constants are set.
2. **Whether `StatPoolsSystem` silently auto-refreshes a pool's cached max the instant the underlying stat changes**, vs. staying stale until `RequestSettingStatPoolMaxValue` is explicitly called, couldn't be settled with 100% certainty from static script reading (the mutation is native). Finding 12's recommendation (call it explicitly, always) is the conservative default and matches every vanilla call site that cares — treat as required, not optional.
3. **TweakDBID literal paths and the `npcrarities.tweak`/`primary_stats.tweak` numbers are WEB-sourced**, not from `sprint/vanilla-scripts` (which has no TweakDB data at all, by design of what got decompiled into this repo). High confidence given multi-repo corroboration, but if the planner wants zero-doubt certainty before committing tuning constants to the plan, the cheapest resolution is a one-line runtime probe in the first compile/test pass: `FTLog(ToString(TweakDBInterface.GetNPCRarityRecord(T"NPCRarity.Elite").RarityValue()))` (expect `5.00`) — not planner-blocking, just the fastest way to convert "high-confidence" into "vanilla-proven" if desired.
