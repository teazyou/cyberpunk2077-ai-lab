# No-LOS Aggro Bug — Findings & Fix Directions

**Mod:** custom-enemy-overhaul · **Date:** 2026-07-17 · **Status:** diagnosis complete — awaiting your fix-direction decisions (no code changed yet)

---

## 1. TL;DR

Two features of the mod independently start combat against a player no enemy has seen, and both are confirmed against the vanilla game sources. The **aggro-range feature** widened the "react to a heard gunshot" distance from vanilla's 12m to 35m; that check is pure straight-line distance (walls ignored), and for regular gang enemies the game never checks sight on this path — so one indoor shot now aggros everyone within the 25m indoor gunshot broadcast, through walls. The **duplication feature** is the bigger surprise: it needs no player action at all — every half-second it may clone any hostile human within 50m (walls ignored, awareness never checked), and each clone is hard-wired to attack you the instant it spawns; a coupling with the aggro feature then drags the clone's whole unaware squad in. The "aggro distance increase" you suspected is real and confirmed, but duplication is the only confirmed path that starts combat while you do nothing. All fixes are local; the recommended direction keeps both features and gates them on genuine detection.

**Findings at a glance**

| # | Feature | What goes wrong | Confidence | Recommended fix |
|---|---------|-----------------|------------|-----------------|
| 1 | Duplication | Every clone is force-ordered to attack the player on spawn | High | Only force the attack when the clone's source already fights the player |
| 2 | Duplication | Clone sources picked with zero awareness check (50m sphere, 0.5s) | High | Only clone enemies already in combat |
| 3 | Aggro range | Heard-gunshot danger distance 12m → 35m, no sight test | High | Keep 35m, but only for a detected player; undetected = vanilla 12m |
| 4 | Aggro range | Explosion reactions lose their distance cap entirely | High | Same detection gate as #3 |
| 5 | Coupling | One clone recruits its whole unaware squad via ally-help | Medium | Fix the seeds (#1–#4); optional extra gate on ally-help |

---

## 2. The bug

You are alone in a locked room inside a building. Enemies elsewhere in the building — behind walls, in other rooms, with no possible line of sight — enter combat against you. Expected behavior: the mod's extended aggro distances should only apply to enemies that have legitimately detected you; combat must never start through walls with zero detection.

Useful vanilla context: even the unmodded game lets a gang enemy react to a gunshot *heard* through a wall — gunfire is treated as sound and sound travels through walls by design. Vanilla's entire protection against absurd through-wall aggro is **distance, not sight**: a tight 12m "close enough to matter" radius, modest broadcast ranges, and a deliberately muffled 25m radius when you fire indoors. Only police get an actual visibility check on this path. The mod widened or removed the distance brakes without adding any sight check — and separately added a spawn path that skips detection entirely.

Which player action triggers what: doing **nothing** → Findings 1+2 (duplication); **firing a gun** → Finding 3; **grenade / explosion nearby** → Finding 4. Finding 5 multiplies whichever fired.

---

## 3. Confirmed findings

Six hypotheses survived an adversarial verification pass against the vanilla sources. Two of them describe the same danger-radius mechanism, so they are merged below — five findings total.

### Feature: Duplication — `EnemyOverhaul.Duplication.reds`

#### Finding 1 — Every clone is force-started into combat with the player

*(hypothesis: clone-force-combat-threat)*

**What the mod does:** When a clone is wired up (`EODup_WireClone`), it is set hostile toward the player and then sent the game's "attack this target now" command (`AIInjectCombatThreatCommand` aimed at the player, 120 seconds). This is the exact recipe vanilla uses to make scripted police/MaxTac reinforcements spawn straight into a fight. It runs unconditionally for every clone.

**Why combat starts through walls:** That command writes the player — at their exact current position — directly onto the clone's threat list. Verified end to end: there is no perception, sight, or detection check anywhere in that command's handling, and the player's own combat state deliberately counts threats it cannot see. Since the clone spawns at its source enemy's position (±3m) and sources are gathered through walls (Finding 2), the clone materializes in the room behind the wall already fighting you.

**Confidence:** High. Note: "clones fight immediately" is deliberate per the file's own header — the defect is that it fires for clones minted off enemies who never noticed you.

**Where:** `EnemyOverhaul.Duplication.reds` lines 626–646 (hostile attitude at 631, attack command at 637–642).

#### Finding 2 — Clone sources are chosen with no awareness check

*(hypothesis: los-independent-ungated-source-selection)*

**What the mod does:** A sweep re-arms every 0.5s and collects **all** NPCs within 50m of the player — a pure sphere query that ignores walls. The only filters: not already a clone, once per source, and "eligible combat human" = human + alive + hostile-type attitude. There is **no** requirement that you are in combat, that the source is in combat, or that the source has ever seen or heard you. Each new source gets a 20% clone roll.

**Why combat starts through walls:** An idle gang member two locked rooms away qualifies as a clone source while completely unaware of you. The clone then appears next to them and Finding 1 forces the fight. With a fully passive player, this is the only confirmed mechanism that can start combat entirely on its own.

**One honest caveat:** the underlying spawn call is the mod's experimental part (your in-game probe is still pending). If spawns silently fail, this path never fires and Finding 3 is what you experienced. Quick tell during a repro: if a duplicated enemy is present when combat starts, this path is live.

**Confidence:** High for the code path itself; whether it fired in your session depends on that pending spawn probe.

**Where:** `EnemyOverhaul.Duplication.reds` lines 264–329 (sweep at 266, candidate gates 288–316; the eligibility helper is `EnemyOverhaul.Common.reds` 73–90).

### Feature: Aggro range — `EnemyOverhaul.AggroRange.reds`

#### Finding 3 — Heard-gunshot danger distance nearly tripled: 12m → 35m, with no sight test

*(merged: hypotheses D1-danger-radius-35m + aggro-d1-danger-range — same mechanism, same replaced routine)*

**What the mod does:** The mod replaces the game's "should I ignore this combat noise?" routine. Inside it, the "is this gunshot close enough that I must react?" test now uses 35m (`DangerRange()`, config line 61) instead of vanilla's hard-coded 12m.

**Why combat starts through walls:** When you fire indoors, the game deliberately broadcasts a muffled "gunshot heard" event to everything within 25m — through walls, because it's sound. Each receiving NPC then runs the danger-distance test, which is pure straight-line distance with no wall or sight check. Vanilla: an NPC 20m away behind a wall ignores the shot (20 > 12). Modded: 35m swallows the **entire** 25m indoor broadcast, so every gang NPC that hears the shot reacts, turns hostile, and enters combat — and on this path the game only ever checks visibility for police, never for gangs. Net effect indoors: through-wall aggro radius grows 12m → 25m, roughly four times the floor area, which exactly reproduces "adjacent-room enemies attack from behind walls." (The mod's separate broadcast-radius widening is *not* involved here — the indoor 25m broadcast is a fixed value it never touches.)

**Confidence:** High. Requires a gunshot — it cannot start combat while you are silent.

**Where:** `EnemyOverhaul.AggroRange.reds` lines 217–246 (value swap at 217–223, gunshot branch 237–246; the 35.0 lives at line 61).

#### Finding 4 — Explosion reactions lose their distance cap entirely

*(hypothesis: aggro-d2-explosion-ungated)*

**What the mod does:** Vanilla reacts to an explosion only inside that same 12m danger distance. The mod drops the distance term altogether: any explosion event is "never ignorable," at any range within its broadcast.

**Why combat starts through walls:** Your grenade or ground-slam indoors is broadcast as sound through walls; every NPC receiving it now reacts regardless of distance and reaches combat via the AI decision path — which, verified, contains no sight test either. Even an enemy dying nearby (the game emits a 30m explosion-type event on some deaths) can set this off.

**Confidence:** High.

**Where:** `EnemyOverhaul.AggroRange.reds` lines 227–235.

### Feature coupling

#### Finding 5 — One clone drags the whole unaware squad in

*(hypothesis: attitude-group-aggrorange-cascade)*

**What the mod does:** Two things combine. Duplication copies the source's squad/attitude group onto the clone (line 623), so the clone counts as a squadmate of enemies that never saw you. Separately, the aggro feature's ally-help rule removes vanilla's "…but not when the target is the player" exemption (D6, AggroRange lines 342–353).

**Why combat starts through walls:** When the forced clone enters combat it emits the vanilla 10m "I'm fighting!" alarm — gated only on having a target, not on anyone seeing anything. The same-squad source hears it through the wall (sound again), and with the player exemption removed it joins the fight against you; its own alarm then recruits the next squadmate, and so on. Verification confirmed this chain but corrected the details: the carrier is this combat-entry alarm — **not** the widened gunshot radius or the 35m danger gate originally suspected here (clone-sourced noise exits that check early). This is an amplifier, not a seed: it turns one illegitimate fight into a room-full.

**Confidence:** Medium (chain confirmed in essence, two originally-cited amplifiers were mis-attributed; it cannot start combat on its own).

**Where:** `EnemyOverhaul.Duplication.reds` lines 616–651 (group copy at 623) + `EnemyOverhaul.AggroRange.reds` lines 342–353.

---

## 4. How it would be solved

A shared principle first: the engine already exposes honest "have I actually seen / detected this target?" checks, and they are callable from exactly the routines the mod replaces. The feature's original acceptance criteria never mentioned detection — that missing requirement is the root gap. Every option below is a small, local change.

### Finding 1 — forced combat on spawn

- **Fix direction (recommended):** make the clone inherit real awareness — only send the "attack now" command when the clone's source already has the player as its combat target; otherwise spawn the clone unaware and let its own senses find you.
- **Alternative:** leave the wiring unconditional and rely solely on gating clone creation (Finding 2). One gate instead of two — but any future path that mints a clone bypasses it.
- **Recommended:** inherit awareness, ideally combined with the Finding 2 gate (belt and braces). Rationale: this line is the actual combat trigger; gate the trigger itself.
- **Feature kept:** "reinforcements join the fight instantly" fully intact whenever the fight is real — lost only for enemies who never detected you, which is the bug.

### Finding 2 — ungated source selection

- **Fix direction (recommended):** only accept a source that is **already in combat with the player** before rolling/spawning a clone. Duplication becomes what it reads as: mid-fight reinforcement. Also stops wasted spawns for idle enemies.
- **Alternatives:** (a) gate on *player* in combat — weaker: during a real fight it would still clone unaware enemies in distant rooms, and Finding 1's wiring would drag them in; (b) gate on the source having *detected* the player (perception meter) — nearly equivalent to source-in-combat, slightly more permissive.
- **Recommended:** source-in-combat-with-player. Rationale: simplest honest signal, matches the feature's intent exactly.
- **Feature kept:** duplication fully intact during genuine fights; only ambient cloning of oblivious enemies disappears.

### Finding 3 — 35m gunshot danger distance

- **Fix direction (recommended):** keep 35m **only for a detected player**: inside 12m behave exactly like vanilla; in the 12–35m band, react only if this NPC has actually seen/detected you. Undetected through-wall behavior returns to the vanilla envelope while "enemies converge from farther once you're spotted" survives.
- **Alternative:** revert the value to vanilla 12m — zero-risk, but deletes this part of the feature everywhere, including legitimate open-air fights.
- **A middle number does not work:** the indoor broadcast is 25m, so *any* value above 12 widens through-wall aggro indoors. The only numeric-only fix is a full revert.
- **Recommended:** detection-gated 35m. Rationale: keeps the feature and restores exactly the expected "extended range only after legitimate detection."
- **Feature kept:** full extended reaction range against a player the enemy has actually noticed.

### Finding 4 — uncapped explosion reactions

- **Fix direction (recommended):** apply the **same detection gate** as Finding 3 — undetected player: vanilla 12m behavior; detected: react at any range.
- **Alternative:** restore the vanilla 12m distance requirement outright.
- **Recommended:** the shared gate. Rationale: one consistent rule across the feature ("extended reactions require detection") instead of two different repair styles.
- **Feature kept:** dramatic long-range explosion responses whenever you've been spotted.

### Finding 5 — squad cascade

- **Fix direction (recommended):** fix the seeds (Findings 1–4) and leave this alone. Allies piling onto a *genuine* fight is the feature working as intended; the cascade only misbehaves when the seed itself was illegitimate, and verification showed it cannot originate combat by itself.
- **Alternative (defense in depth):** additionally gate the ally-help rule on the helper having detected the player — slightly dampens the intended squad pile-on.
- **Do not** remove the clone's squad-group copy (line 623): clones need their squad's group or they would misbehave against their own side.
- **Feature kept:** full squad-alarm behavior in legitimate combat either way.

**Interim mitigation (no code):** both features have master switches — `EnableAggroRange()` and `DuplicationEnabled()` — a one-value flip each reverts them to vanilla behavior entirely. Full feature loss until the fix lands, so this is a stopgap, not the fix.

**Verification aid for the fix work:** the aggro file's debug notify lines (231–233, 242–244, 263–265) fire *exactly* when a reaction was accepted only because of the widened range, and the presence/absence of a duplicated enemy distinguishes Findings 1/2 from Finding 3. One locked-room repro before coding would tell us which path(s) actually fired in your session.

---

## 5. What stays intact

Untouched by every recommended fix above:

- **Tier uprank** — the entire feature; verified stat-only (health/power/level), no perception or combat triggers.
- **Duplication core** — spawn mechanics, 20% roll, once-per-source ledger, clone HP bonus, clone visuals, and "clones fight immediately" for legitimately engaged sources.
- **Aggro range, everything not named above** — the broadcast-radius widening (50m fallbacks, district gunshot ranges), the illegal-action and null-instigator tweaks (D3/D4), the affiliation half of ally-help (D5), the config block and master toggle.
- **Vanilla stealth values** — silenced-gunshot radius (8m) and the 25m indoor muffling were never modified.
- **Common.reds** — verified fully passive (HUD notices, bookkeeping); contributes nothing to the bug.

---

## 6. Ruled out

Each of these was suspected and cleared by the verification pass:

- **Broadcast-radius widening as the indoor culprit** — the indoor gunshot uses a fixed 25m radius the wraps never touch (they only fill in zero-radius events); Finding 3 is what bites indoors.
- **Ally-help rewrite (D5/D6) as a combat starter** — it is a yes/no "join in" filter that can only amplify an existing fight, never originate one (it appears only as the amplifier in Finding 5).
- **Illegal-action leg (D3)** — an untouched detection gate upstream still blocks that path when the enemy hasn't seen you.
- **Null-instigator guard (D4)** — a filter-level change with no through-wall combat attributable to it.
- **Dormant CombatHit fallback (Duplication 644–646)** — compiled off by config, and even switched on it would not create a no-sight combat start.
- **Early version of the explosion claim** — refuted on its cited pathway (explosions aren't in the "direct combat" event list); the confirmed Finding 4 reaches combat via the AI decision path instead.

---

## 7. Coverage note

22 hypotheses were raised across the diagnosis; **12 were deep-verified** in an adversarial pass against the vanilla sources — **6 confirmed** (merged into the five findings above) and **6 refuted** (section 6). The remaining **10 were raised but not deep-verified** — all lower priority, and most restate already-verified mechanisms from another angle. They can be checked later if you want:

1. `aggro-broadcast-radius-wraps` (AggroRange 371–406) — 50m fallback radii; cleared for the indoor case, *outdoor* implications unexamined.
2. `aggro-d6-ally-help-cascade` (AggroRange 301–361) — D6 standalone; overlaps Finding 5 / refuted-as-starter.
3. `aggro-d3-illegal-cone` (AggroRange 259–267) — direction-only illegal leg; overlaps refuted D3.
4. `aggro-d4-null-instigator` (AggroRange 169–185) — instigator guard; overlaps refuted D4.
5. `dup-forced-combat-command` (Duplication 606–646) — restates confirmed Finding 1.
6. `d1-danger-range-35m` (AggroRange 217–267) — restates confirmed Finding 3.
7. `d6-help-vs-player-no-los` (AggroRange 342–353) — restates the D6 half of Finding 5.
8. `d3-illegal-cone-no-distance-cap` (AggroRange 259–267) — restates refuted D3.
9. `d2-explosion-never-ignorable` (AggroRange 227–235) — restates confirmed Finding 4.
10. `halfb-broadcast-radius-50m` (AggroRange 371–430) — Half B incl. district gunshot-range widening; outdoor-range behavior unchecked.

---

## 8. Decisions needed

Your calls before the fix plan is written:

1. **Finding 3 (gunshot 35m):** keep 35m gated on detection *(recommended)*, or revert to vanilla 12m?
2. **Finding 4 (explosions):** same detection gate *(recommended)*, or restore the vanilla 12m cap?
3. **Duplication gate placement:** at the sweep (only clone sources already fighting you), at the wiring (clone inherits source awareness), or both *(recommended: both)*?
4. **The "legitimate" signal:** source-in-combat-with-player *(recommended)*, source-has-detected-player, or player-in-combat?
5. **Finding 5 (ally-help):** leave as-is once seeds are fixed *(recommended)*, or add a detection gate there too?
6. **Dormant CombatHit fallback** (Duplication 644–646): delete, or keep switched off?
7. **Interim:** flip either feature's master toggle off while the fix is written, or live with it?
8. **Optional pre-fix repro:** run the locked-room scenario once with the existing debug lines to confirm which finding fired in your session?
9. **The 10 unverified hypotheses:** park them *(recommended — mostly duplicates)*, or verify before fixing?
