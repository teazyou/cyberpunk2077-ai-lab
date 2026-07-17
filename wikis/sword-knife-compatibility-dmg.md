# Sword + Knife Damage — Compatibility & Ranking (Cyberpunk 2077 2.0–2.2 / Phantom Liberty)

> Research dossier for a **hybrid sword + knife build** (swords/katanas + knife melee + throwing knives).
> Version: game Update **2.0–2.2 + Phantom Liberty** — pre-2.0 perk trees are obsolete and excluded.
> Compiled 2026-07-07. Wiki-verified (primary: cyberpunk.fandom.com; cross-checked Game8 / Fextralife / patch notes). Unverified magnitudes are flagged.

---

## Damage model (read this first)

This build is a **crit-multiplication engine**:

- **Crit Chance × Crit Damage** = the multiplicative spine (the #1 mechanic).
- **Attack Speed** = near-linear secondary.
- **Bleed/DoT + stealth-openers** = tertiary.

Key consequence: **Crit Chance saturates.** This build stacks crit chance to its effective cap from many sources (Sandevistan, From the Shadows, Handle Wrap, Vulnerability Analytics 100%, Scalpel +50%, Style Over Substance guaranteed). Once near cap, extra crit chance is wasted — while **Crit Damage is uncapped, so that's where marginal damage actually lives.** That single fact drives most of the ordering below.

### Coverage tags (the weighting rule made explicit)
- **[ALL]** = boosts sword + knife-melee + throwing → most universal
- **[MELEE]** = boosts sword + knife-melee (both weapons, melee modes; not throw)
- **[SWORD]** / **[KNIFE]** / **[THROW]** = single weapon type

Per the build rule, **[ALL] ≥ [MELEE]** (both boost *both* sword and knife) rank above **[SWORD]/[KNIFE]/[THROW]** at comparable magnitude. Within a coverage class: sort by magnitude → uptime → multiplicative-vs-additive.

---

## STAT RANKING — which raw stat is worth the most (per point / per %)

Ranked by **marginal** value **for this build** (i.e. accounting for what the build already oversupplies). This is different from a generic tier list — crit chance would be #1 on a fresh character, but this build floods it, so its marginal value collapses.

| # | Stat | Type | Marginal value here | Why |
|---|------|------|---------------------|-----|
| 1 | **Crit Damage** | Multiplicative, **uncapped** | ★★★★★ | Every point converts fully because crit chance is already near-cap → crits land constantly. Never diminishes. **Stack this above everything.** Sources: Cool +25%, Sleight of Hand +100% (throw), BioDyne +100%, Blades +10%, Apogee +15–20%, iconics. |
| 2 | **Crit Chance** | Multiplicative, **saturates** | ★★★★☆ → ★☆ | Enormous **until** the effective cap, then near-worthless. Front-load to ~cap, then stop investing and pivot everything to Crit Damage. High raw value, low *marginal* value once flooded. |
| 3 | **Attack Speed** | Near-linear DPS | ★★★★☆ | Multiplies swings/throws per second; converts almost 1:1 until the **~2.0 attacks/s engine cap** (2.11). Dead once capped (e.g. Stinger already 3.08 → Microrotors do nothing). Great on slower katanas. |
| 4 | **Headshot / Weakspot damage mult** | Conditional multiplier | ★★★★☆ (throw) / ★★★☆ (melee) | Huge on **throws** (Headhunter +200–250%, base knife +200%, Nehan/Stinger +150%) since throws hit heads reliably; smaller on sword combo swings. Conditional on landing the precision hit. |
| 5 | **Stealth / first-strike mult** | Burst multiplier | ★★★★☆ opener / ★☆ sustained | Near one-shots the first target (Cool +200% @20 stealth dmg + From the Shadows +25% crit). One hit per encounter → burst, not sustained DPS. Exact "opener %" unverified (the +100% figure is pre-2.0). |
| 6 | **Bleed / DoT** | Sustained, mostly additive | ★★★☆ | Consistent extra damage + dismember/finisher setup, but **tick magnitude is unverified** and it doesn't multiply your hits. Great as a finisher/heal enabler (Slaughterhouse, Satori+Nehan Hemorrhage). |
| 7 | **Armor penetration** | Conditional | ★★★☆ | Matters vs armored/high-level/bosses; wasted on soft targets. Vulnerability Analytics +25% + weakspot mark. Scales your *existing* damage through mitigation. |
| 8 | **Elite / Boss damage %** | Conditional additive | ★★☆ | Narrow (Jinchu-maru / Errata +10% vs Elites/Bosses). Useful for the fights that matter, irrelevant to trash. |
| 9 | **Raw / base weapon DPS %** | Flat additive | ★★☆ | Smallest marginal value — additive base that everything else multiplies, so a % of base is dwarfed by crit/AS multipliers. |
| 10 | **Damage Reduction / survivability / stamina** | Utility (no damage) | ★☆ | Enables **uptime** (stay alive, keep swinging: Adrenaline Booster, DR from Berserk) but adds zero direct damage. Real, but not a damage stat. |

**One-line takeaway:** push **Crit Chance to cap first**, then dump everything into **Crit Damage**, keep **Attack Speed** climbing until the 2.0/s cap, and treat **headshot/stealth** multipliers as your burst/opener layer.

---

## TOP 5 elements — with comparative justification

### 1. Cool attribute → 20  **[ALL]**
+1.25% **Crit Damage**/pt (**+25% @20**, universal to every crit on all 3 profiles) · gates the **entire throwing-knife perk line** (Juggler / Sleight of Hand / Style Over Substance) · +10% **stealth damage**/pt (**+200% @20** on openers). Always-on, 100% uptime, multiplicative.
- **Why #1 (beats Reflexes below):** both are always-on tri-profile attributes, but Cool pays out in **uncapped Crit Damage** while Reflexes pays out in **saturating Crit Chance** — and this build already floods crit chance to near-cap. So Cool's marginal damage never diminishes while Reflexes' does. Cool additionally **gates a whole weapon profile** (throwing doesn't exist without it) and adds the stealth-opener multiplier. Nothing else touches all three levers at once.

### 2. Reflexes attribute → 20  **[ALL] + melee gate**
+0.5% **Crit Chance**/pt (+10% @20, universal) · governs the **Blades skill** · **gates every blade perk** (Bladerunner, Slaughterhouse, Flash & Thunderclap…). Always-on.
- **Why below #1:** its per-point payout (crit chance) **saturates** on this build → lower effective magnitude than Cool's uncapped crit damage; and it gates *only* the two melee profiles, not the throw line.
- **Why above #3 (beats Apogee):** it is **always-on (100% uptime)** and **foundational** — 2 of 3 profiles (sword + knife-melee) literally cannot be built without it, and its crit chance covers all 3. Sandevistan is a single, mutually-exclusive cyberware living in ~5–6s windows. A permanent, build-defining attribute outranks a limited-uptime item.

### 3. Militech "Apogee" Sandevistan (OS)  **[ALL]**
+15–20% Crit Chance / +15–20% Crit Damage / +15–20% Headshot · **85% time-slow** (~5–6s, 25–30s cd, kills extend). Works with **throwing** (unlike Berserk); enables Scalpel's +50% crit.
- **Why below #2:** one equippable, mutually-exclusive item with limited uptime vs an always-on foundational attribute.
- **Why above #4 (beats Blades skill):** it's the **only top element besides the attributes that boosts all three profiles** — crit/headshot bonuses apply to sword, knife-melee **and** throws, and 85% slow-mo is a massive **effective-DPS + survivability** multiplier across the whole kit. Blades skill is always-on but **melee-only** (throw benefit unverified → excluded conservatively). Tri-profile meta OS > dual-profile passive. *(Mutually exclusive with #5 — this is the OS a hybrid build actually runs.)*

### 4. Blades skill, maxed  **[MELEE]**
Net **+30% Attack Speed, +5% Crit Chance, +10% Crit Damage, +5% DPS** (levels resolved to Fandom/Game8/Fextralife values, not cyberpunkcentral's 15%/2% outliers). Near-free, passive, 100% uptime on both melee weapons.
- **Why below #3:** dual-profile only (no throw), and its individual magnitudes are smaller than Apogee's crit stack + slow-mo; no survivability component.
- **Why above #5 (beats BioDyne Berserk):** **100% uptime and no downside** — it covers both melee weapons continuously and, critically, **does not disable throwing**, whereas BioDyne is a short-window active (~20–25% uptime) that **locks out the entire throw profile** while running. For a build that explicitly wants its throwing knives, an always-on both-melee engine (its +30% attack speed alone is a near-linear DPS multiplier) beats a bursty melee-only cooldown — even though BioDyne's peak crit-damage number is far larger.

### 5. BioDyne Berserk (OS)  **[MELEE]**
**+100% Crit Damage** (the single largest melee multiplier in the game — doubles every sword & knife-melee crit) · +5–20% Crit Chance · +15–30% Attack Speed · +30–50% DR. Melee-only, ~8–11s / 35–60s cd.
- **Why below #4:** bursty vs always-on, and it **disables throwing** (a third of this kit) while active; also mutually exclusive with the #3 OS you'd rather run.
- **Why still top 5 (beats #6 From the Shadows):** +100% Crit Damage covers **both** melee weapons at a magnitude an order larger than anything in A-tier, and it's **uncapped/multiplicative** — always converts to damage. From the Shadows' +25% Crit *Chance* is largely **overcap** on this build (saturation), so its effective magnitude is small despite tri-profile coverage. BioDyne is the "drop-throwing-for-max-melee" alternative OS.

---

## FULL RANKING BY TIER

### S — Universal spine (both/all weapons, high magnitude, high uptime, multiplicative)
1. **Cool 20** **[ALL]** — +25% Crit Damage (uncapped) + gates throw line + +200% stealth-opener.
2. **Reflexes 20** **[ALL]** — +10% Crit Chance + governs Blades + gates all blade perks.
3. **Apogee Sandevistan** **[ALL]** — crit/headshot stack + 85% slow; the OS that works with throws.
4. **Blades skill (maxed)** **[MELEE]** — +30% AS / +5% CC / +10% CD / +5% DPS, always-on.
5. **BioDyne Berserk** **[MELEE]** — +100% Crit Damage (biggest melee multiplier); throw-disabling caveat.

### A — Major
- **From the Shadows** (Cool) **[ALL]** — +25% Crit Chance 7s after entering combat; broad opener burst (value dampened by crit-cap saturation).
- **Vulnerability Analytics + Machine Learning** (Relic) **[ALL]** — 100% crit vs marked weakspot + 25% armor-pen + up to +25–50% Crit Damage stacks; **only** Relic node that helps held swords *and* throws. Conditional on the mark + PL Relic points.
- **Militech "Falcon" Sandevistan** **[ALL]** — budget tri-profile slow + crit; longer window, weaker multipliers (Apogee alternative).
- **Kerenzikov** **[ALL]** — ~60% slow on dodge/slide attack; sharpens melee bursts + throw accuracy; triggers Bullet Time.
- **Bladerunner** (Reflexes 15) **[MELEE]** — +20% blade Attack Speed + 25% HP finisher.
- **Flash of Steel** (Reflexes) **[MELEE]** — +25% Attack Speed & move 6s after a Finisher; chains with Bladerunner.
- **Flash & Thunderclap** (Reflexes 9) **[MELEE]** — strong-attack leap, **+50%** distance-scaled — biggest single melee hit multiplier.
- **Slaughterhouse** (Reflexes 20) **[MELEE]** — all melee attacks apply Bleed + dismember; universal DoT/finisher enabler.
- **Attack Speed (aggregate mechanic)** **[MELEE]** — Blades +30% / Bladerunner +20% / Flash of Steel +25% stack near-linearly (subject to 2.0/s engine cap).
- **Militech Berserk** **[MELEE]** — +25–30% AS, invuln, −100% stamina, up to +50% low-HP damage; alt melee OS (also throw-disabling).
- **Handle Wrap** (cyberware) **[THROW]** — +8–27% throw Crit Chance (only source of throw crit chance); near-guarantees crits with Style Over Substance.
- **Juggler L3 (+L2)** (Cool 15) **[THROW]** — resets throw cd on kill = infinite-throw DPS engine; L2 +20% headshot/weakspot. *S-tier for the throw sub-build; placed here by the dual-weapon rule.*
- **Sleight of Hand** (Cool 15) **[THROW]** — up to **+100% Crit Damage** (×5 stacks). Throw-only, so capped at A despite magnitude.
- **Style Over Substance** (Cool 20) **[THROW]** — guaranteed crits while moving; the reliable stealth-crit lever for throws.
- **Headhunter** (iconic) **[THROW]** — mark → +200% (guides cite ≈250% headshot) + instant recall; standout throw iconic.
- **Satori** (iconic) **[SWORD]** — top raw crit-damage katana; guaranteed-Bleed Quickdraw; Hemorrhage combo with Nehan.
- **Scalpel** (iconic) **[SWORD]** — with Sandevistan (S-tier): **+50% Crit Chance + all hits Bleed** → near-guaranteed crits.
- **Jinchu-maru** (iconic) **[SWORD]** — last combo hit ×2 dmg + guaranteed crits under Optical Camo + **+10% Elite/Boss**.
- **Stinger** (iconic) **[KNIFE]** — +150% headshot + self-sustaining **+25% Bleed / +25% Poison** cross-cycle; standout melee knife (also throwable).

### B — Moderate
- **Focus** (Cool 9) **[ALL]** — +10% headshot/weakspot damage; small but universal.
- **Stealth opener (mechanic)** **[ALL]** — near-one-shot first strike; verified parts = Cool +10%/pt stealth + From the Shadows +25% crit. **Exact opener % unverified** ("+100%" is pre-2.0) → ranked conservatively.
- **Opportunist** (Reflexes 15) **[MELEE]** — Bleed/Stagger enemies more Finisher-susceptible; combos with Slaughterhouse.
- **Blade weapon mods** **[MELEE]** — Bleedout (+20–100% crit chance for bleed DoT), Haemocide (+bleed dur, +5–13% CC, −base dmg), Slice 'Em Up (+finisher susceptibility), **Severance** (dismember/instakill <50% HP). 2.1 = 2 mods on crafted. *(Gun mods Penetrator/Pulverize/Crunch/Pacifier do NOT apply.)*
- **Bleed (mechanic)** **[MELEE]** (+ Stinger/Nehan on knife) — sustained DoT + dismember/finisher setup; **tick magnitude UNVERIFIED** → conservative.
- **Byakko** (iconic) **[SWORD]** — on-kill +17.5% AS 10s snowball + **+10% Bleed** (Fandom, not TheGamer's 15%) + range.
- **Errata / Gwynbleidd** (iconics) **[SWORD]** — conditional guaranteed-crit states (vs Burning / after 2 kills or <25% HP; +10% boss).
- **Nehan** (throwable tanto) **[KNIFE]** — +150% headshot throw + always-Bleed + **Hemorrhage-heal with Satori** (genuine sword↔knife synergy).
- **Butcher's Cleaver** (iconic) **[KNIFE]** — bleed synergy: +AS / −stamina vs bleeding targets.
- **Killer Instinct** (Cool 4) **[KNIFE]** — +25% dmg with knives out of combat (melee + throw). **Does NOT help katanas.**
- **Pay It Forward** (Cool 15) **[THROW→KNIFE]** — +200% first melee after retrieving a thrown knife; throw→melee hybrid finisher.
- **Scorpion Sting / Act of Mercy / Pounce** (Cool) **[THROW]** — Poison DoT + faster cycle / Juggler-proc finisher heal / finisher setup.
- **Base Knife / Punknife** (iconics) **[THROW]** — +200% headshot mult / fastest recall (throw cadence).
- **Newton Module / Axolotl** (cyberware) **[THROW]** — cooldown reduction → throw cadence (effective DPS).
- **Microrotors** **[MELEE]** — +10–25% melee AS, **but 2.11 cap = no effect >2.0/s**; dead on fast blades/knives (Stinger 3.08), useful only on slower katanas.
- **Tsumetogi / Black Unicorn** (iconics) **[SWORD]** — very high base AS (voids Microrotors) / AS ignores stamina depletion.

### C — Minor (utility, sustain, situational, enablers, low magnitude)
- **Emergency Cloaking / Optical Camo** (Relic) **[ALL]** — stealth uptime → guaranteed sneak crits + powers Jinchu-maru/Scalpel camo-crit. Indirect.
- **Adrenaline Booster** **[MELEE]** — stamina on melee kill (swing uptime, no damage).
- **Lead and Steel / Going the Distance / Bullet Deflect / Bullet Time / Seeing Double** (Reflexes) **[MELEE]** — stamina/deflect/counter/finisher-range enablers; Bullet Time auto-crits deflections (situational).
- **Rangeguard** **[THROW]** — +headshot damage (single-source ⚠).
- **Parasite** (Cool 9) **[THROW]** — +15 HP on crit-throw (sustain, no dmg).
- **Blue Fang / Cocktail Stick / Agaou** (iconics) — stun / low-base bleed / electric (Agaou isn't a knife).
- **Ninjutsu** (Cool) — mobility only + prereq for Style Over Substance (the pre-2.0 "+100% crouch crit" is obsolete).
- **Technical Ability / Body** — indirect only: cyberware capacity (enables damage chrome) / Adrenaline survivability. No blade-damage multiplier.

---

## THROWING KNIVES — dedicated deep-dive

**The one thing to know:** throwing knives run off the **Cool** attribute, **not** Reflexes/Blades. There is **no dedicated throwing skill** in 2.0+; the entire profile is powered by the Cool perk line + the two universal crit stats. ✅ (rpgsite, gamerant, game8)

### What "headshot" means here
- **Headshot** = your knife lands on the enemy's **head** hitbox. The big multipliers below (base knife +200%, Nehan/Stinger +150%) **only pay out when you actually hit the head** — a body hit gets base damage.
- **Weakspot** = a highlighted weak point (heads count, plus tagged/marked spots or exposed cyberware). Perks reading "headshot **and** weakspot" cover both.
- Consequence: throwing is a **precision** profile — the whole damage stack is conditional on landing head/weakspot hits. Time-slow cyberware (Sandevistan/Kerenzikov) is valued precisely because it makes those head throws easy to land.

### Attributes
- **Cool** — primary. +1.25% **Crit Damage**/pt (**+25% @20**) **and** unlocks the entire throwing perk line (tiers 9/15/20). Invest here first. ✅
- **Reflexes** — secondary only, for its universal +0.5% **Crit Chance**/pt (applies to throws). Does **not** scale base throw damage. ✅
- ❌ Blades skill / Reflexes do **not** raise base thrown-knife numbers (whether thrown kills even level Blades is unverified).

### Perks (all Cool tree)
- **Juggler L3** (Cool 15) — kill via headshot/crit/poison → **instantly resets throw cooldown** = infinite-throw engine. L2 = **+20% headshot/weakspot dmg**. ✅ *(biggest single lever)*
- **Sleight of Hand** (Cool 15) — **+20% Crit Damage per Juggler proc, ×5 = +100% Crit Damage**. ✅
- **Style Over Substance** (Cool 20) — **guaranteed crits** while crouch-sprint/slide/dodge/dash. ✅ *(needs Ninjutsu 3 + Juggler 3)*
- **Scorpion Sting** (Cool 9) — −15% throwable recovery + applies **Poison** on crit/headshot/weakspot. ✅
- **Pay It Forward** (Cool 15) — first **melee** hit with a retrieved knife **+200%** (throw→melee hybrid). ✅
- **Act of Mercy** (Cool 15) — throwable Finisher, auto-procs Juggler + restores 25% HP. ✅
- **Parasite** (Cool 9) — +15 HP on crit/headshot throw (sustain, no dmg). ✅
- **Ninjutsu** (Cool center) — crouch-sprint/stealth mobility; prereq for Style Over Substance. ✅

### Cyberware
- **Handle Wrap** (Hands) — **+8–27% throw Crit Chance** by tier (only source of throw crit chance); ~+23–27% top tier, 6s after throwing. ✅ *(pairs with Style Over Substance to lock in crits)*
- **Sandevistan / Kerenzikov** (OS / Nervous) — time-slow → more accurate headshot throws + more throws per beat (effective DPS). ➕
- **Newton Module / Axolotl** (Frontal Cortex) — cooldown reduction → faster throw cadence. ➕
- **Rangeguard** (Integumentary) — +headshot damage (single-source ⚠).
- ❌ **Berserk (either OS)** — **disables throwing entirely** while active (locks out ranged/items). Mutually exclusive with a throw build. ✅

### Iconic throwing knives
- **Headhunter** (iconic Punknife) — thrown hit **marks** enemy → **+200%** (guides cite ≈**250% headshot**) on next hit, then **returns instantly**. Standout throw iconic; West Wind Estate melee vendor. ✅➕
- **Base Knife** — **+200% headshot mult** (highest of throwables) + mod slots. ➕
- **Punknife** — **shortest return time** → highest throw cadence. ➕
- **Nehan** (iconic Tanto, throwable) — +150% headshot + applies **Bleed** + **Hemorrhage-heal combo with Satori**; from Saburo's body during *The Heist*. ➕
- **Stinger** (iconic knife, also throwable) — +150% headshot + **+25% Bleed / +25% Poison** cross-cycle (better as melee). ✅
- **Blue Fang** — stun/utility, low dmg. ⚠️
- ❌ **Tinker Bell / Cottonmouth** are blunt **clubs**, not knives; **"Blades of Namaqua"** does not exist.

### Stats & mechanics (throw damage model)
The whole model is a **crit stack**:
> guaranteed crit (Style Over Substance / Handle Wrap crit chance) × Cool **Crit Damage** (+25%) × **Sleight of Hand** (+100%) × **headshot mult** (base knife 200% / Nehan-Stinger 150%) × **Juggler L2** (+20% headshot/weakspot)

- **Headshots/weakspots** = the primary damage lever (conditional on landing head hits).
- **Recall / cooldown** reduction (Scorpion Sting −15%, Juggler L1 −15%, **Juggler L3 = zero on kills**) = effective DPS.
- **Bleed + Poison** DoT via Scorpion Sting / Stinger / Nehan.
- ❌ **No inherent distance scaling** on base throws (verified-absent) — Headhunter's bonus is the *mark*, not range.
- **Stealth first-strike** — throwing is the premier stealth one-shot-headshot tool; exact sneak multiplier ❓ unverified. Style Over Substance's guaranteed crit is the reliable stealth lever.

### Most impactful — throwing knife (ranked)
1. **Juggler L3** (Cool 15) — infinite throws on kill = the DPS engine
2. **Sleight of Hand** (Cool 15) — up to **+100% Crit Damage**
3. **Style Over Substance** (Cool 20) — **guaranteed crits** while moving
4. **Headhunter** iconic — **+200%/≈250%** mark execute + instant recall
5. **Handle Wrap** cyberware — up to **+27% throw Crit Chance**
6. **Cool crit damage** (+25% @20) + **base knife 200% headshot** + **Juggler L2** (+20% headshot/weakspot)

*Sources: rpgsite, gamerant, game8 (Cool perks), cyberpunk.fandom.com (Juggler / Handle Wrap / Headhunter / Berserk), fextralife (Stinger), gamestegy (throwing-knife build/tier list). ❓ residual unverified: exact stealth-throw multiplier; whether thrown kills grant Blades-skill milestones.*

---

## Conflicts, unverified values, and conservative calls
- **"Dragon Strike":** Dossier 1 calls it the current Blades L20 ultimate; Dossier 2 lists it as a **pre-2.0 removed perk**. Direct conflict, **not spot-checked** — it doesn't affect any tier (Blades skill ranks on its progression bonuses, not the capstone). **Did not rank Dragon Strike as a damage source** (conservative).
- **Blades skill → throws:** whether thrown kills level Blades / whether its +5% CC & +10% CD milestones apply to throws is **unverified**. Ranked Blades as **[MELEE]** (dual), not **[ALL]** — the conservative choice. If it *did* buff throws it would edge toward #3.
- **Bleed tick magnitude:** unpublished by Fandom/Fextralife → Bleed and bleed-mods (Bleedout/Haemocide) kept in **B**, not higher.
- **Stealth-opener multiplier:** the widely-quoted "+100% + guaranteed crit" is **pre-2.0**; only Cool +10%/pt stealth and From the Shadows +25% crit are current-verified → stealth mechanic ranked **B** despite likely one-shot power.
- **Strong/charged-attack multiplier** and **per-tier Berserk crit splits:** unverified → not used as ranking drivers (Strong attacks sit low-B/C).
- **Resolved numbers used:** Blades L6/L7 = **+10% CD / +5% CC**; Byakko Bleed = **+10%**; Apogee duration ≈ **5–6s**; Militech Berserk low-HP dmg up to **+50%**.
- **BioDyne (#5) vs From the Shadows (#6):** ranked on **effective** magnitude — BioDyne's +100% uncapped Crit Damage beats +25% Crit Chance that this build largely wastes to saturation, even though From the Shadows has broader coverage. Flagged as a judgment call.

## Do-NOT-chase (non-applicable to this build)
**Gorilla Arms, Mantis-Blade Relic perks (Jailbreak/Spatial Mapping/Limiter Removal), Bioconductor (quickhacks), gun mods (Penetrator/Pulverize/Crunch/Pacifier), and pre-2.0 perks (Blessed Blade/Deflection/Cutthroat/Roaring Waters) do nothing for this build.**
**Killer Instinct helps knives but NOT swords. Berserk (either) disables throwing.**
Non-weapons flagged: **Tinker Bell / Cottonmouth are blunt clubs; "Blades of Namaqua" does not exist.**

## Cross-weapon synergy worth building around
- **Satori (sword) + Nehan (throwable knife)** → Bleed → **Hemorrhage that heals V** — the one true sword↔knife combo.
- **Scalpel / Jinchu-maru + Apogee Sandevistan** → the S-tier OS directly arms your sword iconic's crit condition.
- **Slaughterhouse (melee bleed) + Opportunist + Bladerunner finisher** → bleed-to-finisher-to-heal melee loop covering both blades.

## Bottom line
Max **Cool + Reflexes** (both to 20), run **Apogee Sandevistan** as the hybrid OS (or **BioDyne Berserk** if you drop throwing for pure melee), max **Blades skill**. That's the S-tier spine before any iconic. Stat priority: **Crit Chance to cap → then dump into Crit Damage → keep Attack Speed rising to the 2.0/s cap → headshot/stealth as the burst layer.**

---

*Sources: cyberpunk.fandom.com (primary), cross-checked against Game8, Fextralife, and official 2.0/2.1 patch notes. Per-element verification URLs are recorded in the underlying research dossiers. Numbers flagged "unverified" could not be confirmed against a maintained wiki at compile time.*
