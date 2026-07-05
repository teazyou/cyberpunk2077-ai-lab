# "Melee Damage" stat (Dégâts au corps-à-corps) — what it affects

Stat: `BaseStats.MeleeDamagePercentBonus`. Seen as teal "+X% Melee Damage" random cyberware modifier roll (`Modifiers.MeleeDamagePercentBonusRandom`), fixed rolls on some cyberware (Dense Marrow etc.), food buff, Body-tree block buff. Berserk uses its own separate stat (`BerserkMeleeDamageBonus`).

## Rule (from decompiled game code, patch 2.x)

`damageSystem.script → ProcessCyberwareModifiers()`:

```
if( AttackData.IsMelee( attackType ) )
    tempDamage += MeleeDamagePercentBonus
```

`AttackData.IsMelee` = attackType is `Melee`, `QuickMelee`, or `StrongMelee` — nothing else. Bonus is additive with other %-bonuses (AllDamageDone, vs-burning, etc.), then multiplies the hit.

## Boosted ✅

- Blades: katana, knife/axe MELEE swings, machete, chainsword (Slash/StrongSlash records)
- Blunt: bats, hammers, batons, fists (Impact/StrongImpact)
- Gorilla arms (Fists/Impact family), mantis blades (Slash family)
- Monowire whip attacks (Lash/StrongLash → Melee/StrongMelee)
- Gun-bash quick melee (QuickMelee)

## NOT boosted ❌

- THROWN knife/axe hits — `ThrownPiercing` record → `AttackType.Thrown` (excluded). Thrown dmg scales via Cool throwing perks, headshot (knife 200% HS mult), crit. Melee stab with same knife IS boosted.
- Quickhacks, incl. uploaded via monowire (Hack damage)
- DoT ticks (bleed/poison/burn) — use `DamageOverTimePercentBonus` instead
- Explosions / Projectile Launch System — use `ExplosionDamagePercentBonus`
- Smart/Tech guns have own stats (`SmartWeaponDamagePercentBonus`, `TechWeaponDamagePercentBonus`)

FR→EN: "Dégâts au corps-à-corps" = "Melee Damage".

Sources: [Cyberpunk-Scripts](https://github.com/CDPR-Modding-Documentation/Cyberpunk-Scripts) (damageSystem.script ~L2938, attackData.script IsMelee), [Cyberpunk-Tweaks](https://github.com/CDPR-Modding-Documentation/Cyberpunk-Tweaks) (attack/melee/*.tweak, items/cyberware/variants/modifiers.tweak).
