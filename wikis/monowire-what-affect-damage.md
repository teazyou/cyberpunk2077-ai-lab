# Monowire — Everything That Affects Its Damage

**Patch version researched:** Cyberpunk 2077 current patch line **2.0 / 2.1 / 2.2 + Phantom Liberty** (researched 2026-07). All pre-2.0 (1.x) perk/attribute data is disregarded or explicitly flagged as outdated.

---

## How Monowire Damage Is Calculated (summary)

- **What it is:** The Monowire is an **Arm cyberware weapon** (occupies the Arms slot, costs **8 Cyberware Capacity**). It has a light attack (swing arc), a **charged/heavy attack** (hold), and a block/parry — moveset like Mantis Blades / Gorilla Arms.
- **Base damage** comes from the cyberware's **quality tier**, which auto-upgrades roughly every 10 character levels up to Tier 5. Fextralife per-hit base values: **T2 ≈ 29.7 · T3 ≈ 42.7 · T4 ≈ 58.2 · T5 ≈ 83.5 DPH**. Tier is the single largest raw-damage driver — always run the highest-tier Monowire you can.
- **Damage type:** **Physical** by default with a **20% Bleed chance** (base Monowire). Elemental **cable mods / variants** change the type (Thermal→Burn, Electrifying→Shock, Toxic→Poison).
- **Attribute scaling is small and variant-specific.** In 2.0+ each Monowire variant is "**Attuned**" to one attribute and gains only **+0.5% damage per point** of that attribute:
  - Base **Monowire → Intelligence** attuned (Fextralife-confirmed)
  - **Thermal Monowire → Cool** · **Electrifying Monowire → Reflexes** · **Toxic Monowire → Technical Ability**
  - ⚠️ **FLAGGED / OUTDATED:** Many guides (ggrecon, GamesLearningSociety, some Fandom user comments) still say "Monowire scales with Reflexes, +3 damage per Reflexes level, counts as a Blade." That is **pre-2.0 (patch-1.5-era) info** and is **not** how the current game works. See disputes below.
- **Charge mechanic:** Holding attack builds a charge; the **fully-charged heavy attack** unleashes a large single hit and is the trigger for the **quickhack-upload** interaction. A **Monowire Battery mod** boosts charged-attack damage (High-Capacity = **+50%**).
- **Physical vs. quickhack damage:** The Monowire deals **physical melee damage**, but in the current meta its biggest "damage" comes indirectly through **netrunner / quickhack synergy** — the base weapon itself is comparatively weak, and builds amplify it with cyberdeck bonuses, quickhack uploads (Jailbreak/Data Tunneling), and quickhack-damage perks rather than raw melee multipliers.

### Key disputes / things sources disagree on
| Claim | Current-patch verdict | Notes |
|---|---|---|
| "Scales with Reflexes, +3/Reflexes level" | **Outdated (pre-2.0).** Base variant is Intelligence-attuned at +0.5%/pt. | Only the **Electrifying** variant is Reflexes-attuned. |
| "Monowire counts as a Blade → gets Blades perks" | **Largely FALSE in 2.0+.** It is its own weapon class; the "Only affects Blades" perks do **not** apply. | gamestegy & TheGamer (current) confirm: "no longer considered a blade or bludgeoning weapon"; "gets no boosts except a few Intelligence perks." ggrecon (recycled) disagrees. |
| Main damage source | **Cyberdeck + quickhack synergy + weapon tier**, not melee perks. | Consensus of current build guides. |

---

## SECTION 1 — Cyberequipment / Cyberware (ranked by damage impact)

| Rank | Item / System | Effect & magnitude | Source | Interaction with Monowire |
|---|---|---|---|---|
| 1 | **Monowire quality Tier (T1→T5)** | Base per-hit ~29.7 → **83.5** (T5), plus higher mod-slot count. ~**+180%** raw over the usable range. | Fextralife Monowire | The single biggest damage lever — tier drives base damage; upgrade at ripperdoc / via components. |
| 2 | **Militech Paraline Mk.4/5 (cyberdeck OS)** | **+2% Monowire damage per RAM unit spent, cap +30%** (T3+); under **Overclock** adds bonus **Electrical dmg = 25% / 40% / 60%** of attack dmg (T5 / T5+ / T5++); +10% quickhack dmg (T2+). | Fextralife Militech Paraline Mk 4; RPG Site | Best raw-damage cyberdeck for Monowire — turns spent RAM into a flat +30% and stacks an Overclock electrical rider on every swing. |
| 3 | **Biotech Σ Mk.4 (cyberdeck OS)** | **+25% Monowire damage vs. enemies affected by a DoT** (from quickhacks). | Fextralife Biotech MK 4; TheNerdStash | Pairs Contagion/Overheat/Thermal Monowire DoT with a conditional +25%; strong in a contagion netrunner loop. |
| 4 | **Berserk OS (Militech / BioDyne / Zetatech / MooreTech)** | Removes stamina cost (−100%), **+20–30% attack speed** (DPS multiplier), invuln windows; **Militech = +50% damage below 20% HP**; **BioDyne = +20% Crit Chance / +100% Crit Damage** (Tier 5). 2.1 added damage-reduction to non-Militech models. | RPG Site; gamestegy Berserk build; Fandom Berserk | The classic Monowire pairing. No flat "melee dmg %" line, but attack-speed + crit (BioDyne) + low-HP dmg (Militech) massively raise effective DPS. Choose BioDyne for crit-Monowire, Militech for glass-cannon. |
| 5 | **Dense Marrow (Skeleton)** | **+15% / 18% / 21% / +24% melee damage** (T2→T5); +armor; downside +15% melee stamina cost; Reflexes-attuned +0.1% crit/pt. | Fextralife Dense Marrow | One of the few cyberware pieces that flatly boosts **melee** damage and applies to the Monowire's physical hits. |
| 6 | **COX-2 Cybersomatic Optimizer (Frontal Cortex, iconic)** | Guarantees **critical hits** (with quickhacks / under conditions), major crit uptime. | VULKK catalog; gamestegy Monowire | Feeds crit-damage stacking; strong in hybrid quickhack+Monowire crit builds. |
| 7 | **Microrotors (Hands)** | **+melee attack speed** (caps ~2 attacks/sec). | VULKK catalog | Pure DPS multiplier via faster swings — more hits = more Bleed/quickhack procs. |
| 8 | **Kerenzikov (Nervous System)** | Time-slow on dodge/aim while moving; sets up guaranteed charged/heavy hits. | VULKK catalog | Not a flat multiplier; buys time to land fully-charged heavy hits and quickhack uploads. |
| 9 | **Cyberware Capacity / quality tier of all slots** (Technical Ability chrome: License to Chrome, Extended Warranty, Cyborg, etc.) | More/higher-tier capacity → run the best cyberdeck + Dense Marrow + Berserk simultaneously. | TheNerdStash; Siliconera perk list | Indirect but foundational — Capacity is what lets the above stack; TechAbility is the enabling attribute. |
| 10 | **RAM-boosting Frontal Cortex chrome (Memory Boost, Ex-Disk, RAM Upgrades)** | More RAM → more RAM spent → more Paraline "%-per-RAM" damage + more quickhack uploads. | gamestegy Monowire | Scales the Militech Paraline bonus and sustains the Jailbreak/quickhack loop. |

**Cyberware mods (on the Monowire itself) — see Section 3, they slot into the weapon.**

---

## SECTION 2 — Perks / Skills / Talents (current 2.0+ trees, ranked)

**Where Monowire perks live:** primarily **Intelligence** (quickhack/netrunner synergy — the Monowire's real damage engine) and the **Relic** tree (Phantom Liberty). A handful of **Body/Reflexes** melee perks help the physical hits. **Blades-tree perks mostly do NOT apply** (Monowire is not a Blade in 2.0+).

| Rank | Perk (tree) | Effect & magnitude | Source | Interaction with Monowire |
|---|---|---|---|---|
| 1 | **Jailbreak** (Relic — Phantom Liberty) | Lets you slot a **Control quickhack into the Monowire**; a **fully-charged heavy attack uploads it** to the target. | gamestegy; TheGamer; multiple | Core of the modern Monowire build — turns each charged hit into a free control quickhack + its damage/debuff. |
| 2 | **Data Tunneling** (Relic) | Spreads the uploaded control quickhack to **nearby enemies hit by swipe attacks**. | AttackOfTheFanboy; gamestegy | Multiplies Jailbreak across groups — AoE quickhack application via Monowire swings. |
| 3 | **Embedded Exploit** (Intelligence) | **+60% quickhack damage** and **+10% RAM recovery** vs. enemies affected by a **Control** quickhack. | AttackOfTheFanboy; PCGamer | Since Jailbreak keeps a Control quickhack on targets, this +60% is near-permanent on your Monowire kills. Top damage perk. |
| 4 | **Overclock** (Intelligence, capstone) | Lets you cast/keep quickhacks by spending Health as RAM → more RAM spent. | gamestegy; TheNerdStash | Triggers Militech Paraline's Overclock electrical rider (+25–60%) and enables constant uploads. |
| 5 | **Blades skill progression passives (Level milestones)** | Skill-level rewards: crit-chance/attack-speed milestones (e.g. attack speed at Blades L2/11/13, crit around L6–7). | cyberpunkcentral Blades | ⚠️ **Contested** — these are labeled for "Katanas/Blades/Mantis"; whether they tag the Monowire in 2.0+ is disputed. Treat as *possible* minor bonus, not guaranteed. |
| 6 | **Siphon / Finisher: Live Wire** (Intelligence) | Siphon: restore **0.5 RAM per Monowire hit (1 RAM if target quickhacked)**; Live Wire: big RAM regen + invuln on finisher. | PCGamer; gamestegy | Sustains RAM so Paraline %-per-RAM and uploads never stall — indirect DPS uptime. |
| 7 | **Dense Marrow-supporting melee perks — Body: Adrenaline Rush, Army of One; Reflexes: Slaughterhouse** | Health/stamina/attack sustain enabling continuous swinging; Slaughterhouse = +25 stamina on dismember. | AttackOfTheFanboy | Keep you attacking (Monowire eats stamina); more uptime = more DPS. Not direct multipliers. |
| 8 | **Crit-support perks (Cool: Crit chance nodes; Reflexes attack-speed)** | Cool gives ~1.25% crit chance/point-tier nodes; Reflexes finisher attack-speed. | AttackOfTheFanboy | Amplify a crit-Monowire (esp. with BioDyne Berserk +100% Crit Dmg). Secondary. |
| — | ⛔ **Blades-only perks** (Roaring Waters +10–30% strong-attack dmg, Sting Like a Bee +10–30% attack speed, Blessed Blade +10% crit, Dragon Strike +40% crit dmg, Flash & Thunderclap, Bullet Deflect) | Powerful **but "Only affects Blades"** | cyberpunkcentral; Siliconera | **Do NOT apply to Monowire** in 2.0+. Listed here only to warn: do not invest expecting Monowire gains. |

---

## SECTION 3 — Stats / Modifiers on Gear (Monowire mods, clothing, consumables — ranked)

Legendary Monowires have up to **3 mod slots**: a **Battery**, a **Cable**, and a **Sensory Amplifier** slot.

| Rank | Modifier | Effect & magnitude | Source | Interaction with Monowire |
|---|---|---|---|---|
| 1 | **Monowire Battery — High-Capacity** | **+50% charged-attack damage** (best battery). | TheGamer; ggrecon | Biggest single mod multiplier; only benefits the fully-charged heavy hit — pair with a charge-heavy playstyle + Jailbreak. |
| 2 | **Militech Paraline "%-per-RAM"** (repeated here as a gear-side multiplier) | **+2% dmg per RAM used, cap +30%**; +25–60% electrical under Overclock. | Fextralife | See Section 1 #2 — functionally a gear stat on the weapon's damage. |
| 3 | **Cripple Movement (Control quickhack) via Jailbreak** | **Tier-4 grants +15% melee damage** to the afflicted target. | Reddit/community via search; AttackOfTheFanboy | Slot it as the Jailbreak upload → guarantees a +15% melee debuff on every charged hit. |
| 4 | **Cyberware Malfunction (Control quickhack) stacking** | Stacks up to **8×**, disabling enemy cyberware and **increasing damage the target takes**. | PCGamer | Excellent Jailbreak payload — ramps incoming (incl. Monowire) damage on a target. |
| 5 | **Cable mods (elemental)** | Convert damage type (Thermal/Electrical/Chemical) → enable Burn/Shock/Poison DoTs; exploit enemy weakness for effectively higher damage. | ggrecon; TheGamer | Turn the Monowire into a DoT applier → also satisfies Biotech Σ's "+25% vs DoT" condition. |
| 6 | **Sensory Amplifier mod** | **+2% Crit Chance** *or* **+20% Crit Damage** (variant depends on ripperdoc). | ggrecon | Only crit-stat slot on the weapon; +20% crit dmg version scales hard with BioDyne Berserk's +100% crit dmg. |
| 7 | **Clothing/armor mods — melee & crit rolls** | Mod slots roll **+% melee damage**, **+Crit Chance**, **+Crit Damage**, **+% damage**; armor mods (e.g. crit-focused) stack additively. | General 2.0 gear system (Siliconera/guides) | Stack crit chance/damage and any +melee% on outfit mods; there is no clothing tier system in 2.0, only mod slots. |
| 8 | **Attack speed as a DPS multiplier** (from Berserk +20–30%, Microrotors, Sting-like-a-Bee if it applied) | Each +% attack speed ≈ proportional +% DPS. | RPG Site; VULKK | More swings/sec = more Bleed procs, more quickhack uploads, higher sustained DPS. |
| 9 | **Attribute "Attuned" bonus on the weapon** | **+0.5% damage per point** of the attuned attribute (Int base / Cool Thermal / Reflexes Electrifying / TechAbility Toxic). | Fextralife; TheGamer | Real but minor — at 20 Int that's only +10%; do not build around it. |
| 10 | **Consumables / boosters** | Combat stims and boosters granting temporary **+% damage / +crit / +attack speed** (e.g. damage boosters, MaxDoc/health for sustain). | 2.0 consumable system | Short-duration multiplicative/additive buffs during fights; niche top-up, not a build pillar. |

---

## Bottom line / build-shaping takeaways
- The Monowire's damage is **carried by the netrunner package**, not by melee perks: **weapon Tier → Militech Paraline (%-per-RAM + Overclock electrical) → Jailbreak/Data Tunneling uploads → Embedded Exploit +60% → crit stacking (BioDyne Berserk / Sensory Amplifier / COX-2)**.
- Attributes: **Intelligence** (quickhacks) + **Technical Ability** (capacity) are the backbone; **Body/Reflexes** only for sustain and minor melee/crit; **Cool** optional for crit chance.
- Do **not** invest Blades perks expecting Monowire scaling — most are hard-gated to Blades.

---

## Sources
- Fextralife — Monowire: https://cyberpunk2077.wiki.fextralife.com/Monowire
- Fextralife — Militech Paraline Mk 4: https://cyberpunk2077.wiki.fextralife.com/Militech+Paraline+Mk+4
- Fextralife — Biotech MK 4: https://cyberpunk2077.wiki.fextralife.com/Biotech+MK+4
- Fextralife — Dense Marrow: https://cyberpunk2077.wiki.fextralife.com/Dense+Marrow
- Cyberpunk Fandom — Monowire: https://cyberpunk.fandom.com/wiki/Monowire
- Cyberpunk Fandom — Berserk: https://cyberpunk.fandom.com/wiki/Berserk
- Cyberpunk Fandom — Militech Paraline: https://cyberpunk.fandom.com/wiki/Militech_Paraline
- TheGamer — Everything About The Monowire: https://www.thegamer.com/cyberpunk-2077-monowire-upgrades/
- gamestegy — Best Monowire Build: https://gamestegy.com/post/cyberpunk-2077/676/monowire-build
- gamestegy — Savage Berserk build: https://gamestegy.com/post/cyberpunk-2077/1038/berserk-build
- TheNerdStash — Best Monowire Build (2.0): https://thenerdstash.com/best-monowire-build-in-cyberpunk-2077-2-0/
- AttackOfTheFanboy — Best Monowire Build (2.0): https://attackofthefanboy.com/guides/best-monowire-build-in-cyberpunk-2077/
- PC Gamer — Monowire best skills/cyberware: https://www.pcgamer.com/cyberpunk-monowire-best-legendary-build/
- ggrecon — Monowire: How To Get, Best Stats And Perks: https://www.ggrecon.com/guides/cyberpunk-2077-monowire/
- RPG Site — Best Berserk in 2.0: https://www.rpgsite.net/guide/15222-the-best-berserk-in-cyberpunk-2077-20-lets-you-hulk-out
- RPG Site — Best Cyberdecks in 2.0: https://www.rpgsite.net/feature/15004-the-best-cyberdecks-in-cyberpunk-2077-20-are-all-about-your-netrunning-build
- VULKK — Full Cyberware Catalog (2.0/PL): https://vulkk.com/2023/09/30/full-cyberware-catalog-for-cyberpunk-2077-update-2-0-and-phantom-liberty/
- CyberpunkCentral — Blades Skill Tree & Perks: https://cyberpunkcentral.com/blades/
- Siliconera — All 2.0 Skill Tree Perks: https://www.siliconera.com/all-cyberpunk-2077-2-0-skill-tree-perks/
- Steam Community — "Are monowires still blades for perks?": https://steamcommunity.com/app/1091500/discussions/0/3875968426425601760/
- Game8 — Best Monowire Build (Phantom Liberty): https://game8.co/games/Cyberpunk-2077/archives/Builds-Monowire

*Flagged as outdated / pre-2.0 (used only for the disputes table, NOT as current): GamesLearningSociety "+3 per Reflexes level / Blade since 1.5" articles; ggrecon's "affected by Blades perks" line; older Fandom user comments claiming Monowire is a Blade.*
