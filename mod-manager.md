# Cyberpunk 2077 — Mod Manager (macOS / Steam)

Procedure + current state for an AI to install / uninstall / enable / disable mods.
Standalone — everything needed is in this file; do NOT read other files.
Current state only. No logs, no history, no changelog.

## Wishlist
URLs to process. For each: fetch mod info (see Mod info), classify (compat rule), create entry in Mod Manager Data (STATE=NOT INSTALLED), remove URL from this list. Do not download or install unless asked.

## Env
- GAME = `~/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077`

## Compatibility rule (macOS)
- ✅ REDscript `.reds` · ✅ input `.xml` (Input Loader) · ✅ raw `.archive` (texture/mesh, no ArchiveXL) · ✅ engine-config `.ini` (Windows mods target `engine/config/platform/pc/`; on macOS the file goes to `platform/mac/` — no `pc/` dir exists on the Mac build)
- ❌ RED4ext (`.dll`/`.asi`) · ❌ CET · ❌ ArchiveXL · ❌ TweakXL · ❌ Codeware · ❌ anything requiring them
- Classify from Nexus "Requirements": any ❌ dep → ❌. Else → ✅.
- The macOS Input Loader is ALREADY installed (built into the game toolchain). Mods that "need input loader" only require their `.xml` dropped in `r6-input`; never install the Nexus "Input Loader" mod itself (it is Windows RED4ext).

## Mod info (one fetch, via markdown reader)
Nexus mod PAGES are Cloudflare-blocked to direct WebFetch/curl (→ HTTP 403). Fetch through the r.jina.ai markdown reader instead (not bot-blocked) — ONE call returns everything needed for an entry: Title, Category, Requirements, Description, and the download stats.
```bash
curl -s "https://r.jina.ai/https://www.nexusmods.com/cyberpunk2077/mods/<mod_id>"
```
- Title = the `Title:` header / `# <name>` heading → entry `<Title>`.
- Category = the breadcrumb link before the title (e.g. `User Interface`) → entry `<Category>`.
- Requirements = the `### Nexus requirements` table → drives the Compatibility rule (any ❌ dep → ❌, else ✅).
- Description = the mod's summary line under the title → entry `DESC`.
- TOTAL DLS = the `Total DLs` stat, comma-formatted (e.g. `238,992`). Sanity check: Total DLs ≥ Unique DLs. If the stat line is absent, set TOTAL DLS to `—`.

## Folders (`mods/`)
`<slug>` = kebab-case of the mod Title (used for zip + disabled folder names).
- `downloaded/` — original `<slug>.zip`. Audit only, never loaded.
- `enabled/` — fixed symlink portals INTO game drop dirs, one per mod TYPE (drop targets, NOT a disable mechanism). Writing here = writing into game:
  - `r6-scripts`  → `GAME/r6/scripts`      (REDscript `.reds`, each mod in its own kebab-case subfolder)
  - `r6-input`    → `GAME/r6/input`        (input `.xml`)
  - `archive-mod` → `GAME/archive/pc/mod`  (raw `.archive`)
  - `engine-config` → `GAME/engine/config/platform/mac` (engine-config `.ini` overrides; on Windows mods this path is `platform/pc` — redirect here)
- `disabled/` — real dirs (NOT symlinks). `disabled/<slug>/<portal>/…` mirrors `enabled/` layout. Deactivated files live here, out of game.

### Portal invariant
The 4 `enabled/` portals MUST always exist — this is how mods are piloted from here. If any is missing, recreate (run from this file's folder):
```bash
GAME="$HOME/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077"
mkdir -p "$GAME/archive/pc/mod"
ln -sfn "$GAME/r6/scripts"     mods/enabled/r6-scripts
ln -sfn "$GAME/r6/input"       mods/enabled/r6-input
ln -sfn "$GAME/archive/pc/mod" mods/enabled/archive-mod
ln -sfn "$GAME/engine/config/platform/mac" mods/enabled/engine-config
```

## State model
Every mod below is referenced in Mod Manager Data. STATE is exactly one of:
- NOT INSTALLED = referenced only; zip not downloaded, no files deployed.
- ENABLED = downloaded; files deployed under `enabled/` portals (in game).
- DISABLED = downloaded; files moved out to `disabled/<slug>/`.

Each entry carries current STATE + FILES manifest (exact `<portal>/<path>` owned). The manifest is the source of truth for enable / disable / uninstall.

## Procedures

INSTALL  (NOT INSTALLED → ENABLED)
1. Download the mod zip → `downloaded/<slug>.zip`, using ONLY the Claude-in-Chrome browser extension (mcp__claude-in-chrome tools; Nexus account is logged in there) — open the mod's Files tab, click "Manual Download" (never "Mod Manager Download"/Vortex — no mod manager on macOS), then "Slow download" (no paid subscription). Never use curl/WebFetch/wget for the actual file — Nexus blocks them and downloads require login (curl via r.jina.ai is for reading the page/metadata only, see ## Mod info — never for the file itself).
   - Claude-in-Chrome extension/tools not available or not connected → STOP. Do not install any mods this run; report back instead.
   - Download fails for any other reason (Cloudflare/CAPTCHA, login/paywall wall, no manual-download link found, network error, etc.) → SKIP this mod: keep STATE=NOT INSTALLED, add a NOTE with the failure reason, move on to the next mod.
   - Under NO circumstance write, invent, or reconstruct a mod's code yourself as a substitute for a real download, even partially. Only a file actually downloaded from Nexus counts as installed. (This happened once — an agent fabricated REDscript for 9 mods instead of downloading; all were reverted and deleted.)
2. Inspect zip; apply compat rule. ❌ → keep STATE=NOT INSTALLED, note reason, stop.
3. Extract files into matching portal(s), preserving internal layout (each mod's `.reds` in its own kebab-case subfolder under `r6-scripts/`, per the naming rule in Cautions).
4. Update entry: STATE=ENABLED, FILES=deployed `<portal>/<path>` list.

DISABLE  (ENABLED → DISABLED)
1. Move each FILES path: portal → `disabled/<slug>/<same-portal>/…`.
2. Set STATE=DISABLED.

ENABLE  (DISABLED → ENABLED)
1. Move `disabled/<slug>/<portal>/*` → matching portal.
2. Set STATE=ENABLED.

UNINSTALL  (delete the mod entirely)
1. Delete FILES from the portals and from `disabled/<slug>/`.
2. Delete `downloaded/<slug>.zip`.
3. Remove the entry from Mod Manager Data.

## Cautions
- Prevent `.reds` collisions: one subfolder per mod under `r6-scripts`.
- Never overwrite the toolchain's `input_loader.ini` via the `engine-config` portal; and only one mod may own `user.ini` at a time (collision = ❌ for the second).
- Name every `r6-scripts` per-mod subfolder in kebab-case (lowercase words joined by hyphens; keep it short and explicit). If a mod's zip ships a CamelCase / underscore / spaced namespace folder (e.g. `AdaptiveSliders`, `Locking_Fixes`, `Second Heart Fix`), rename it to kebab-case on install. Folder names are cosmetic to REDscript (it compiles all `.reds` recursively), so renaming is safe — just keep the entry's FILES manifest in sync.

## Entry format
```
### <Category>: <Title>
COMPAT: ✅/❌ <note>
STATE: ENABLED | DISABLED | NOT INSTALLED
URL: <nexus url>
TOTAL DLS: <nexus total downloads> | —
FILES: <portal/path>, … | —
NOTE: <mod-specific install detail: special step, chosen variant, load order, caveat> (omit line if none)
DESC: <one line>
```

## Mod Manager Data

### Gameplay: Better Fast Travel Map - Redscript
COMPAT: ✅ main file is REDscript only (input .xml + Input Loader only needed for the optional file, not installed)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/9214
TOTAL DLS: 25,770
FILES: r6-scripts/better-fast-travel-map-redscript/BetterFastTravelMap.reds
NOTE: Installed the main file "better fast travel map" v1.0.0.2 (ships only r6/scripts/BetterFastTravelMap.reds). Skipped the optional file "Disable exit with right click" (remaps right-click for waypoint tracking, needs Input Loader + its own .xml) — enable later if wanted.
DESC: Makes the Fast Travel menu behave more like the Map menu by disabling the info box and adding the filter menu and features to the fast traveling map.

### Gameplay: Reset Attributes always available - Redscript
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/9240
TOTAL DLS: 1,360,601
FILES: r6-scripts/reset-attributes-always-available-redscript/ResetAttributesAlwaysAvailable.reds
NOTE: Main file "reset attributes" v1.0.0.4 (single r6/scripts/ResetAttributesAlwaysAvailable.reds). This is the redscript version — NOT the separate REDmod version.
DESC: Lets you reset your character attributes as many times as you want, at any time.

### UI: Disappearing Enemy Health Bar Fix
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/19815
TOTAL DLS: 765,710
FILES: r6-scripts/disappearing-enemy-health-bar-fix/Z_BetterEnemyHealthBar.reds
NOTE: Installed main file #1 "Disappearing Enemy Health Bar Fix" (the non-LHUD version; user has no Limited HUD). Two other main/LHUD choices exist — #2 is for Limited HUD users. Skipped the optional "Show Player Health Bar When Scanning" add-on.
DESC: Keeps the enemy health bar visible whenever you look directly at an enemy, fixing the vanilla appear/disappear behavior.

### Gameplay: Disassemble As Looting Choice
COMPAT: ✅ REDscript + input .xml (Requirements: redscript only; input handled via bundled Input Loader xml)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/4648
TOTAL DLS: 199,680
FILES: r6-scripts/disassemble-loot/dalc_base.reds, r6-scripts/disassemble-loot/dalc_overrides.reds, r6-input/disassembleAsLootingChoice_input_loader.xml
NOTE: Main file v2.0 bundles both the REDscript (DALC/) AND the Input Loader keybind xml (disassembleAsLootingChoice_input_loader.xml) — so the separate optional "Input Loader XML"/"Input Helper XML" files are NOT needed. Keybind defaults to IK_Z (kbd) / IK_Pad_DigitLeft (pad). Settings (excludedQualities, sound) editable in r6/scripts/DALC/dalc_base.reds. Renamed the mod's DALC/ namespace subfolder to kebab-case disassemble-loot/.
DESC: Adds a disassemble option directly to the loot prompt so you can break items down while looting.

### Gameplay: Fast Travel from anywhere to everywhere - Redscript
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/9241
TOTAL DLS: 499,493
FILES: r6-scripts/fast-travel-from-anywhere-to-everywhere-redscript/FastTravelFromAnywhereToAnyMapPin.reds
NOTE: Two mutually-exclusive variants exist. Installed the "fast travel to any map pin" variant v1.0.0.5 (user chose it) — fast travel to ANY map pin incl. own waypoints. The alternative is "fast travel to any fast travel point" (FT points only). Caveat: some shop pins can leave you stuck behind the counter — the author suggests setting a nearby waypoint instead. To swap variants later, uninstall and install the other file.
DESC: Lets you fast travel from the map menu to any fast travel point or map pin, including your own markers.

### Gameplay: Hacking Gets Tedious - 2.3 redscript HOTFIX
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/15084
TOTAL DLS: 42,567
FILES: r6-scripts/hacking-gets-tedious/HackingGetsTedious.reds
NOTE: Single main file "HGT - 2.12a redscript v0.5.24 Hotfix" (ships r6/scripts/HackingGetsTedious.reds; page title now reads v2.31a). Author note: if the original "Hacking Gets Tedious" base mod is ever added, delete its r6/scripts/HackingGetsTedious.reds and keep only this hotfix — no base mod is present in this vault, so nothing to remove.
DESC: Pre-installs all quickhacks on the breach/hacking minigame so hacking is instant (redscript hotfix for newer redscript versions).

### Miscellaneous: No Intro Videos
COMPAT: ✅ REDscript or raw archive (macOS-compatible version)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/533
TOTAL DLS: 2,006,664
FILES: r6-scripts/no-intro-videos/NoIntroVideos.reds
NOTE: Installed the "redscript" main variant (v0.8); requires REDscript (provided by the macOS toolchain). Mutually exclusive with the "archive" main variant — use only one. Compiled at launch by launch_modded.sh.
DESC: Skips the startup logo/intro videos and news report for a faster launch to the main menu.

### Gameplay: Replace Weapon Mods
COMPAT: ✅ core is REDscript only (ArchiveXL/RED4ext/Mod Settings are OPTIONAL — only for the in-game settings menu, not macOS-compatible)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/15409
TOTAL DLS: 730,552
FILES: r6-scripts/replace-weapon-mods/ReplaceWeaponMods.reds
NOTE: Main file v1.3 bundles the core r6/scripts/ReplaceWeaponMods.reds PLUS an ArchiveXL settings pack (archive/pc/mod/ReplaceWeaponMods.archive + ReplaceWeaponMods.xl) — deployed the core .reds ONLY; skipped the .archive/.xl (they drive the Mod Settings menu which needs RED4ext+ArchiveXL, unavailable on macOS). Consequence: the "warning popup before destroying a mod" defaults ON and can't be turned off in-game (settings menu absent). Core replace/destroy functionality works fully (verified the .reds compiles standalone; ModSettings refs are inert @runtimeProperty annotations).
DESC: Restores pre-2.0 behavior letting you install a new weapon mod over an existing one (destroying the old one), with an optional warning popup.

### Gameplay: Rich Vendors and Drop points - Redscript
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/9273
TOTAL DLS: 16,168
FILES: r6-scripts/rich-vendors-and-drop-points-redscript/RichVendors.reds
NOTE: Single main file "rich vendors" v1.0.0.0 (ships r6/scripts/RichVendors.reds). Tops vendors/drop points to 500,000 eddies when they hit 0.
DESC: Tops up vendors and drop points with eddies whenever they run out so they never lack money to buy your loot.

### UI: Adaptive Sliders
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/5075
TOTAL DLS: 1,151,227
FILES: r6-scripts/adaptive-sliders/adaptiveSliders.reds
NOTE: Main file v2024-06-10 ships r6/scripts/AdaptiveSliders/adaptiveSliders.reds — renamed its AdaptiveSliders/ namespace subfolder to kebab-case adaptive-sliders/. This version also "Enabled Crafting by default" (max slider now applies to Crafting too, not just Drop/Stash/Sell). Download was a .7z (not .zip) — stored as downloaded/adaptive-sliders.7z; extracted with macOS bsdtar/libarchive (no 7z tool needed). Old builds used an r6/scripts/ImmersivePatches folder — not present here, nothing to delete.
DESC: Sets inventory transaction sliders to max by default for Drop, Stash, and Sell actions, keeping all other sliders at 1.

### Gameplay: Auto Unequip Weapon Mods And Attachments When Selling Or Disassembling
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/9604
TOTAL DLS: 343,078
FILES: r6-scripts/auto-unequip-weapon-mods-and-attachments-when-selling-or-disassembling/UnequipWeaponModsAndAttachements.reds
NOTE: Main file v1.1.0 (single r6/scripts/UnequipWeaponModsAndAttachements.reds — note the author's "Attachements" spelling). v1.1.0 added an in-script option to skip unequipping mods (editable in the .reds). Also works alongside bulk-sell mods like Mark To Sell.
DESC: Automatically unequips all weapon mods and attachments when selling or disassembling a weapon, returning them to your inventory.

### UI: Crafting Recipe Owned and Iconic Labels
COMPAT: ✅ REDscript only (Requirements: redscript; the TweakDBID refs are vanilla engine types, not a TweakXL dep — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/11261
TOTAL DLS: 972,302
FILES: r6-scripts/crafting-recipe-owned-and-iconic-labels/crafting_recipe_owned_labels.reds
NOTE: Installed the single main file "Crafting recipe owned and iconic labels" v1.1.1 (ships r6/scripts/crafting_recipe_owned_labels.reds) — placed in own r6-scripts/crafting-recipe-owned-and-iconic-labels/ per the collision rule. Downloaded via Claude-in-Chrome browser (Manual → Slow download).
DESC: Adds check marks to crafting-menu recipe icons for items you already own, plus the iconic background for iconic recipes.

### Miscellaneous: Bounty class stars bug fix
COMPAT: ✅ REDscript only (Requirements: redscript; .reds has no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/23211
TOTAL DLS: 339,712
FILES: r6-scripts/bounty-class-stars-bug-fix/BountyClassStarsFix.reds
NOTE: Installed the single main file "Bounty class stars fix" v1.0.0.2 (ships r6/scripts/BountyClassStarsFix.reds) — placed in own r6-scripts/bounty-class-stars-bug-fix/ per the collision rule. Downloaded via Claude-in-Chrome browser (Manual → Slow download).
DESC: Fixes the broken bounty class stars (wanted-level rating) that stopped displaying properly since patch 2.0.

### UI: Drink At The Counter - Use Consumables From Vendor Menu
COMPAT: ✅ REDscript only (Requirements: redscript; .reds has no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/8588
TOTAL DLS: 4,139
FILES: r6-scripts/drink-at-the-counter-use-consumables-from-vendor-menu/DrinkAtTheCounter.reds
NOTE: Installed the single main file "Drink At The Counter" v1.1 (ships r6/scripts/DrinkAtTheCounter.reds) — placed in own r6-scripts/drink-at-the-counter-use-consumables-from-vendor-menu/ per the collision rule. Downloaded via Claude-in-Chrome browser (Manual → Slow download).
DESC: Lets you use consumable items from your inventory while browsing a vendor's menu.

### Gameplay: Go Where You Want - Bypass Skill Checks
COMPAT: ✅ REDscript only (Requirements: redscript; .reds has no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/4095
TOTAL DLS: 5,526
FILES: r6-scripts/go-where-you-want/goWhereYouWant.reds
NOTE: Installed the single main file "GoWhereYouWant" v1.0 — download is a .7z (stored as go-where-you-want-bypass-skill-checks.7z; extracted with macOS bsdtar/libarchive). Ships r6/scripts/GoWhereYouWant/goWhereYouWant.reds — renamed its GoWhereYouWant/ namespace subfolder to kebab-case go-where-you-want/. Downloaded via Claude-in-Chrome browser (Manual → Slow download).
DESC: Bypasses attribute/skill checks on locked doors and gated dialogue/level routes so you can reach loot or shortcuts anywhere.

### Gameplay: Fighting Gangs Allowed - Reasonable Police
COMPAT: ✅ REDscript only (Requirements: redscript; .reds has no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/19189
TOTAL DLS: 799,598
FILES: r6-scripts/fighting-gangs-allowed-reasonable-police/FightingGangsAllowed.reds
NOTE: Installed the single main file "Fighting Gangs Allowed - Reasonable Police" v1.0 (zip ships bare r6/scripts/FightingGangsAllowed.reds with no subfolder — placed in its own r6-scripts/fighting-gangs-allowed-reasonable-police/ per the collision rule). Downloaded via Claude-in-Chrome browser (Manual → Slow download).
DESC: Lets you shoot, quickhack, and grenade gang enemies in the open world without the NCPD turning hostile (harming civilians or cops is still a crime).

### Gameplay: Fast Finishers
COMPAT: ✅ REDscript only (Requirements: redscript; .reds has no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/10314
TOTAL DLS: 16,875
FILES: r6-scripts/fast-finishers/FastFinishers.reds
NOTE: Two mutually-exclusive main variants: "Fast Finishers Always" (finishers always fast) and "Fast Finishers Sandevistan Berserk" (fast only when Sandevistan/Berserk active). Installed the SANDEVISTAN BERSERK variant v1.0.0 (user chose "Only Sandy/Berserk"). Download is a .7z (stored as fast-finishers.7z; extracted with macOS bsdtar/libarchive); ships r6/scripts/FastFinishers/FastFinishers.reds — renamed its FastFinishers/ namespace subfolder to kebab-case fast-finishers/. To swap to the Always variant later, uninstall and install "Fast Finishers Always". Downloaded via Claude-in-Chrome browser (Manual → Slow download).
DESC: Makes finisher animations use their quick version so they don't waste Sandevistan/Berserk uptime.

### Gameplay: Enhanced Monowire Quickhacks
COMPAT: ✅ REDscript only
STATE: DISABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/11289
TOTAL DLS: 10,749
FILES: r6-scripts/monowire-quickhacks/EnhancedMonowireQuickhacks.reds
NOTE: Main file v1.0 (skipped the optional "1 in 3 Proc Chance" variant). Ships r6/scripts/EnhancedMonowireQuickhacks/EnhancedMonowireQuickhacks.reds — renamed its EnhancedMonowireQuickhacks/ namespace subfolder to kebab-case monowire-quickhacks/. Verified at install: Nexus Requirements = redscript only, and the .reds is a clean @replaceMethod (no TweakXL/Codeware) — macOS-safe.
DESC: Lets the monowire apply quickhacks with normal and strong attacks, not just charged attacks.

### Gameplay: Disable Fall Damage And Deadly Fall On-Screen Grey Effect Filter
COMPAT: ✅ REDscript only
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/3161
TOTAL DLS: 26,405
FILES: r6-scripts/disable-fall-damage-and-deadly-fall-on-screen-grey-effect-filter/disableFallDamageAndFallOnScreenEffects.reds
NOTE: Installed the single main file "Disable Fall Damage And Deadly Fall On Screen Effects" v1.6 (ships r6/scripts/disableFallDamageAndFallOnScreenEffects.reds) — standalone REDscript, NOT the separate CET fall-damage mod (#9928); incompatible with other fall-damage mods. Requirements = redscript only; the .reds is @replaceMethod (macOS-safe). Download was a .rar (not .zip) — stored as downloaded/disable-fall-damage-and-deadly-fall-on-screen-grey-effect-filter.rar; extracted with macOS bsdtar/libarchive.
DESC: Disables all fall damage and removes the grey deadly-fall warning filter from the screen.

### Crafting: Item Level Scaled Upgrade Cost
COMPAT: ✅ REDscript only (Requirements: redscript req. version 0.3.4; .reds has no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/2873
TOTAL DLS: 163,012
FILES: r6-scripts/item-level-scaled-upgrade-cost/item_level_scaled_upgrade_cost.reds
NOTE: Three cost-scaling main variants (Linear/Exponential/Combination), each ships the same bare r6/scripts/item_level_scaled_upgrade_cost.reds. Installed the LINEAR variant v0.3 (user chose Linear) — placed in its own r6-scripts/item-level-scaled-upgrade-cost/ per the collision rule. Download is a .7z (stored as item-level-scaled-upgrade-cost.7z; extracted with macOS bsdtar/libarchive). To swap curve later, uninstall and install Exponential or Combination. Incompatible with other mods that modify GetItemFinalUpgradeCost. Downloaded via Claude-in-Chrome browser (Manual → Slow download).
DESC: Scales weapon/gear upgrade cost by item level instead of by upgrade count, making low-level legendaries cheaper to upgrade.

### UI: Inventory Sorting Improved
COMPAT: ✅ REDscript only
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/23628
TOTAL DLS: 278,052
FILES: r6-scripts/inventory-sorting/InventorySortingImproved.reds
NOTE: Installed the single main file v1.0 — ships r6/scripts/Inventory Sorting Improved/InventorySortingImproved.reds; renamed its "Inventory Sorting Improved" namespace subfolder to kebab-case inventory-sorting/. Requirements = redscript only. The ModSettings menu integration is an optional soft-dep: all ModSettings.* calls are inside @if(ModuleExists("ModSettingsModule")) guards and the rest are inert @runtimeProperty annotations (same graceful-degrade pattern as Replace Weapon Mods), so it compiles/runs standalone. Consequence on macOS with no ModSettings framework installed: the cyberware name/quality sort CONFIG menu is absent (baked-in defaults apply); core quality-based inventory sorting still works. The "Plus" tier icon overlay needs a separate complementary mod.
DESC: Improves quality-based inventory sorting (respects Iconic items and Plus-tier upgrades) and adds configurable cyberware sorting by name or quality.

### Gameplay: No carry weight - Disable encumbrance
COMPAT: ✅ REDscript only
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/2388
TOTAL DLS: 77,051
FILES: r6-scripts/no-carry-weight-disable-encumbrance/NoEncumbrance.reds
DESC: Disables over-encumbrance so the inventory weight stat has no gameplay effect.

### Gameplay: No Special Outfit Lock
COMPAT: ✅ REDscript only
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/3963
TOTAL DLS: 349,828
FILES: r6-scripts/no-special-outfit-lock/noSpecialOutfitLock.reds
NOTE: Installed main file v1.3 — ships r6/scripts/noSpecialOutfitLock.reds (the page's older "outfitUnlocker.reds" name is outdated). Pure REDscript, macOS-safe (Requirements: redscript only). Requires redscript v0.5.6+ on game v2.0+. Download was a .rar; stored as no-special-outfit-lock.rar.
DESC: Lets you modify other clothing slots while a special outfit is equipped, instead of the slot being locked.

### Vehicles: Vehicle Exit Fix for 2.3
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/22786
TOTAL DLS: 652,217
FILES: r6-scripts/vehicle-exit-fix/vehicleexitfix.reds
NOTE: Single main file "VehicleExitFix" v1.0 (ships r6/scripts/vehicleexitfix/vehicleexitfix.reds — renamed its vehicleexitfix/ namespace subfolder to kebab-case vehicle-exit-fix/). Pure REDscript, macOS-safe (Requirements: redscript only).
DESC: Fixes the slight kickback/roll after exiting a vehicle and the bike tilt/lean bug in 2.3 (and 2.31).

### User Interface: Track What You Want - Have Only One Map Marker
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/4110
TOTAL DLS: 98,374
FILES: r6-scripts/track-what-you-want/trackWhatYouWant.reds
NOTE: Installed main file "TrackWhatYouWant" v3.0 (updated for patch 2.3) — ships r6/scripts/TrackWhatYouWant/trackWhatYouWant.reds; renamed its TrackWhatYouWant/ namespace subfolder to kebab-case track-what-you-want/. Pure REDscript, macOS-safe. v3.0 download is a .zip (the earlier .7z note was for an older version). Right-click a marker to keep only one active pin; right-click empty ground to set/unset a Pinned Location for zero markers.
DESC: Putting a marker on the map hides all other markers and routes (including the main quest), and lets you have no markers at all if preferred.

### Gameplay: ThrowingWeaponBugFix2.3
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/25830
TOTAL DLS: 18,338
FILES: r6-scripts/throwing-weapon-bug-fix-2.3/FixThrowingWeapon.reds
NOTE: Single main file "FixThrowingWeaponBug" v1.0 (zip ships r6/scripts/FixThrowingWeapon.reds with no subfolder — placed in its own r6-scripts/throwing-weapon-bug-fix-2.3/ per the collision rule). Pure REDscript, macOS-safe (Requirements: redscript only).
DESC: Fixes the patch-2.3 throwing-knife bug where chaining throws while holding block caused an unintended melee swing, restoring smooth continuous knife throwing.

### Gameplay: Throwing Weapon Kerenzikov Fix
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/26327
TOTAL DLS: 120,351
FILES: r6-scripts/throwing-weapon-kerenzikov-fix/Throwing Weapon Kerenzikov Fix.reds
NOTE: Installed the MAIN file "Throwing Weapon Kerenzikov Fix" v1.0 ("For vanilla Kerenzikov"; ships r6/scripts/Throwing Weapon Kerenzikov Fix.reds with no subfolder — placed in its own r6-scripts/throwing-weapon-kerenzikov-fix/ per the collision rule). SKIPPED the optional "Enhanced (Modded) Kerenzikov Patch" — it is only for users of the separate Enhanced Kerenzikov mod (not installed here) and does not require the main file. Pure REDscript, macOS-safe.
DESC: Fixes Kerenzikov ending instantly when the throw button is pressed while still aiming, plus Air Kerenzikov accuracy while falling during the throw animation.

### Gameplay: Talk to Me
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/5534
TOTAL DLS: 550,351
FILES: r6-scripts/talk-to-me/TalkToMe.reds, r6-scripts/talk-to-me/TalkToMeConfig.reds
NOTE: Main file "Talk to Me" v1.3 — ships r6/scripts/TalkToMe.reds + TalkToMeConfig.reds (config editable in the .reds); both placed in own r6-scripts/talk-to-me/ subfolder. Verified at install: Requirements = redscript only. Pure REDscript, macOS-safe.
DESC: People casually interact with you as you walk near them, so the world's crowds are no longer silent.

### Gameplay: Reroll Cyberware Stats When Upgrading
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/17315
TOTAL DLS: 10,256
FILES: r6-scripts/reroll-cyberware-stats-when-upgrading/ReRollCWStatsWhenUpgrading.reds
NOTE: Main file v1.1 — single r6/scripts/ReRollCWStatsWhenUpgrading.reds, placed in own r6-scripts/reroll-cyberware-stats-when-upgrading/ subfolder. Verified at install: Requirements = redscript only (macOS-safe). Requires the in-game "Chipware Connoisseur" perk to be active — the mod does nothing without it. Reroll by backing out of the upgrade screen and re-entering.
DESC: Lets you reroll the offered cyberware upgrade stats by exiting and re-entering the upgrade screen, as many times as you like.

### User Interface: Real Vendor Names
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/4941
TOTAL DLS: 1,739,067
FILES: r6-scripts/real-vendor-names/realVendorNames.reds
NOTE: Main file v2.1.0 — ships a single r6/scripts/realVendorNames.reds, placed in own r6-scripts/real-vendor-names/ subfolder. Verified at install: Requirements = redscript only (macOS-safe).
DESC: Displays each vendor's real name on the world-map icons instead of the generic vendor-type labels.

### Gameplay: Street Vendors
COMPAT: ✅ redscript required (not a ❌ dep). CAVEAT: current v2.0.2 also needs off-site REDMod deployment, which the macOS REDscript toolchain (launch_modded.sh) does not run — re-verify at install; a pre-2.0 redscript-only build is the macOS-safe option.
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/2894
TOTAL DLS: 750,446
FILES: r6-scripts/street-vendors/street_vendors.reds, r6-scripts/street-vendors/InventoryGeneration/DefaultInventoryGeneration.reds
NOTE: Installed the pre-2.0 redscript-only build "Street Vendors v1.2.7b" (highest version that needs redscript only; REDMod is required only for v2.0.0+, and the macOS toolchain does not run REDMod deploy). Inspected zip: ships ONLY r6/scripts (Street Vendors/street_vendors.reds + Street Vendors/InventoryGeneration/DefaultInventoryGeneration.reds) — no mods/ REDMod packaging, no archive/, no ArchiveXL .xl, no RED4ext .dll → pure REDscript, macOS-safe. Deployed both .reds under r6-scripts/street-vendors/ keeping the InventoryGeneration/ subfolder. Did NOT install v2.0.x (needs REDMod deployment unavailable on macOS). To move to v2.0.x later you'd need a working REDMod deploy step.
DESC: Lets you trade with most of the street vendors around Night City.

### User Interface: Status Effect ReColor
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/26438
TOTAL DLS: 5,322
FILES: r6-scripts/debuff-color/DeBuffColor.reds
NOTE: 6 main-file variants exist (DeBuffColor-Full / DeBuffColor-Icon / E3DeBuffColor-Full / E3DeBuffColor-Icon / DeBuffColor-FullGreen / DeBuffColor-IconGreen). Installed "DeBuffColor-Full" v1.1 — the default that matches the mod's core description (whole debuff display red, positives stay blue; not icon-only, not E3, not buffs-green). Ships r6/scripts/DeBuffColor/DeBuffColor.reds; renamed its DeBuffColor/ namespace subfolder to kebab-case debuff-color/. Verified at install: Requirements = redscript only (macOS-safe). To switch variant later, uninstall and install a different file.
DESC: Colors negative status effects (debuffs) red next to the health bar while positive effects stay blue.

### Gameplay: Stamina Consumption Fix
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/23230
TOTAL DLS: 490,475
FILES: r6-scripts/stamina-consumption-fix/Stamina Consumption Fix.Global.reds
NOTE: Main file v1.0.0 — single global .reds ("Stamina Consumption Fix.Global.reds"); zip stores Windows backslash paths, extracted the real r6/scripts .reds into own r6-scripts/stamina-consumption-fix/ subfolder. Verified at install: Requirements = redscript only (macOS-safe).
DESC: Makes stamina consumption (e.g. crouch-sprinting) framerate-independent, fixing the vanilla bug where higher FPS drains stamina faster.

### Gameplay: Smart Gun Lock Speed Fixes
COMPAT: ✅ REDscript only (Requirements: redscript; .reds has no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/21798
TOTAL DLS: 510,786
FILES: r6-scripts/smart-gun-lock-fixes/lock_animation.reds
NOTE: Installed the single main file "Smart Gun Lock Speed Fixes" v1.0.0 — ships r6/scripts/Locking_Fixes/lock_animation.reds; renamed its Locking_Fixes/ namespace subfolder to kebab-case smart-gun-lock-fixes/. Downloaded via Claude-in-Chrome browser (Manual → Slow download).
DESC: Makes smart-gun lock-on animation properly accelerate against debuffed targets and fixes recon grenades so they actually apply their status effect on detonation.

### User Interface: Simple untrack quest
COMPAT: ✅ REDscript only (Requirements: redscript; .reds has no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/5177
TOTAL DLS: 192,173
FILES: r6-scripts/simple-untrack-quest/untrackQuestByRightClick.reds
NOTE: Installed the MAIN file "untrackQuestByRightClick" v2.31 (update for patch 2.31, "doesn't conflict with Delamain anymore"; zip ships bare r6/scripts/untrackQuestByRightClick.reds with no subfolder — placed in its own r6-scripts/simple-untrack-quest/ per the collision rule). SKIPPED the optional v1.1 file (that one is for old game patch 1.63). Downloaded via Claude-in-Chrome browser (Manual → Slow download).
DESC: Lets you untrack a quest by right-clicking its marker on the Map, the same way you track it.

### Gameplay: Monowire Perk Tree
COMPAT: ✅ no requirements listed on Nexus (per compat rule → ✅). CAVEAT: perk-tree mods that add NEW perks normally need TweakXL to register perk TweakDB records (❌ on macOS) — re-verify at install by inspecting the zip; if it ships a .xl / TweakXL yaml / RED4ext .dll / ArchiveXL-dependent archive → ❌.
STATE: NOT INSTALLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/31022
TOTAL DLS: 266
FILES: —
NOTE: v0.1.0 by IMES, uploaded 30 Jun 2026 (still ver 0.x, beta). Adds new Intelligence perks for the Monowire at INT 9/15/20 — range/stamina/attack-speed buffs, EMP combat utility (RAM recovery, mitigation), and Overclock synergy. Korean i18n included; custom per-perk refund buttons; no perk icons. Single main file "MonowirePerkTree" 19KB. Install attempted but NOT completed: Claude-in-Chrome browser tools were not connected this session, so the file could not be downloaded (Nexus blocks curl/WebFetch + requires login) — retry install once Chrome is connected, and at that point inspect the 19KB zip for TweakXL yaml / RED4ext .dll before deploying (adds NEW perks → likely needs TweakXL = ❌ on macOS).
DESC: Adds a custom Intelligence perk tree for the Monowire, giving it range/stamina/attack-speed buffs plus EMP and Overclock synergy for netrunners.

### Gameplay: Second Heart Fix
COMPAT: ✅ REDscript only (Requirements: redscript; .reds has no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/11100
TOTAL DLS: 841,195
FILES: r6-scripts/second-heart-fix/SecondHeartFix.reds
NOTE: Installed the single main file "Second Heart Fix" v1.0 — ships r6/scripts/Second Heart Fix/SecondHeartFix.reds; renamed its "Second Heart Fix"/ namespace subfolder to kebab-case second-heart-fix/. Removes black screen on death, extends timeframe until resurrection. May conflict with other mods that adjust death behavior/events. Downloaded via Claude-in-Chrome browser (Manual → Slow download).
DESC: Improves NPC reactions to Second Heart revival so enemies treat V as dead and stop attacking during the revive, with a distinct feign-death animation.

### Visuals and Graphics: Preem Scanner (Customization Options for a Clean Minimal Scanner)
COMPAT: ✅ raw .archive only (verified in zip: single archive/pc/mod/###-PreemScanner-Pure.archive, no .xl/ArchiveXL, no .dll — macOS-safe; Nexus Requirements: only "Clean Voiceovers", recommended-not-required)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/9215
TOTAL DLS: 712,134
FILES: archive-mod/###-PreemScanner-Pure.archive
NOTE: Installed file "Preem Scanner - Pure" v1.2.0p (user chose it; AIO minimal variant, updated for 2.2; 11 other files on page incl. Vanilla-Style/No-Vignette/Monochrome variants + Pure addons). Caveat: LUT Switcher overrides scanner LUT colors (not installed here). Pairs with Clean Voiceovers (mod 15285). Downloaded via Claude-in-Chrome browser (Manual → Slow download).
DESC: Removes the green tint and vignette from the scanner while providing a clean new look, with various options.

### Audio: Clean Voiceovers (while zoomed or scanning)
COMPAT: ✅ raw .archive only (verified in zip: single archive/pc/mod/ZoomVoSfxRemover.archive, no .xl/ArchiveXL, no .dll — macOS-safe; Nexus Requirements: only "Preem Scanner", recommended-not-required)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/15285
TOTAL DLS: 37,704
FILES: archive-mod/ZoomVoSfxRemover.archive
NOTE: Installed the single main file "Clean Voiceovers" r1. Pairs with Preem Scanner (mod 9215). Downloaded via Claude-in-Chrome browser (Manual → Slow download).
DESC: Makes voiceovers sound normal instead of robotic while zoomed or scanning.

### Gameplay: Quickhacks sort by slot
COMPAT: ✅ REDscript only (Requirements: redscript; .reds is a single @replaceMethod(RPGManager), no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/11425
TOTAL DLS: 819,478
FILES: r6-scripts/quickhacks-sort-by-slot/quickhacks_sort_by_slot.reds
NOTE: Installed the main file "Quickhacks sort by slot" v0.0.0.3 (v0.0.0.3 switched wrapMethod → replaceMethod for compatibility; tested on game v2.3). Ships r6/scripts/quickhacks_sort_by_slot/quickhacks_sort_by_slot.reds — renamed its underscore namespace subfolder to kebab-case quickhacks-sort-by-slot/. SKIPPED the separate Miscellaneous WIP file "keep_quickhacks_slots" v0.0.0.2 (keeps quickhack slots when unequipping cyberdeck — a different feature). Downloaded via Claude-in-Chrome browser (Manual → Slow download).
DESC: Quickhacks are displayed in slot order, not in reverse order of installation.

### Visuals and Graphics: Nova LUT 4.0 (AgX - New HDR)
COMPAT: ✅ raw .archive only (verified in zip: single archive/pc/mod/###-NovaLUT4.archive, no .xl/ArchiveXL, no .dll — macOS-safe; Nexus Requirements: none listed; author: "not a reshade")
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/11622
TOTAL DLS: 1,621,772
FILES: archive-mod/###-NovaLUT4.archive
NOTE: Installed the main file "Nova LUT 4" v4.0.0 (user chose it; "LUT ONLY. Contains both SDR and HDR LUTs"). Nova 4 has just one LUT (no variants yet); 3 optional LUT-Switcher packs on the page were skipped. NOT compatible with other LUT mods; compatible with weather/lighting mods that use their own LUTs if Nova LUT gets load priority (### filename prefix keeps it late in load order). Caveat: Preem Scanner (installed here) notes LUT Switcher overrides scanner LUT colors — plain Nova LUT is fine. Author recommends pairing with Nova City 2 (mod 12490) for the screenshot look. Downloaded via Claude-in-Chrome browser (Manual → Slow download).
DESC: Crisp visuals with a natural palette, using AgX tonemapping to bring lifelike luminance and color to Night City with a pop of contrast.

### Gameplay: Toggle Sprint While Scanning
COMPAT: ✅ REDscript only (Requirements: redscript; .reds is pure @wrapMethod, no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/14646
TOTAL DLS: 32,361
FILES: r6-scripts/toggle-sprint-while-scanning/EnableSprintingWhileScanning.reds
NOTE: Installed the single main file "Toggle Sprint While Scanning" v1.0 (download is named "Enable sprinting while scanning-14646-…zip"; ships bare r6/scripts/EnableSprintingWhileScanning.reds with no subfolder — placed in its own r6-scripts/toggle-sprint-while-scanning/ per the collision rule). Author: meant to be used in conjunction with mods that disable the scanner time-dilation effect, e.g. "Scanner Time Dilation Optional 2.01" (mod 9671) — not installed here; this mod works standalone regardless. Downloaded via Claude-in-Chrome browser (Manual → Slow download).
DESC: Scanning no longer restricts you to walking-only mode — you can walk, run, or sprint with full control over movement speed while scanning.

### Visuals and Graphics: Cyberpunk 2077 HD Reworked Project
COMPAT: ✅ raw .archive only (verified in zip: single archive/pc/mod/HD Reworked Project.archive, no .xl/ArchiveXL, no .dll; Nexus Requirements: none listed)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/7652
TOTAL DLS: 1,181,393
FILES: archive-mod/HD Reworked Project.archive
NOTE: Installed the ULTRA QUALITY main file v2.0 (user pre-downloaded it — 1.07 GB; the other main variant is Balanced Quality). Author install path is exactly archive/pc/mod/HD Reworked Project.archive. No performance hit if VRAM is sufficient; if VRAM runs short, uninstall = delete the one .archive. Zip kept as downloaded/cyberpunk-2077-hd-reworked-project.zip.
DESC: Improves the graphics by reworking game assets to better quality, preserving the original art style and good performance.

### Appearance: NPCs Gone Wild
COMPAT: ✅ raw .archive only (verified in zip: single archive/pc/mod/basegame_00NPC_GM.archive, no .xl/ArchiveXL, no .dll — macOS-safe; Nexus page lists no Requirements section)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/1436
TOTAL DLS: 1,940,308
FILES: archive-mod/basegame_00NPC_GM.archive
NOTE: Installed the MILD variant — main file #2 "NPCs Gone Mild (non-REDMOD)" v2.0 (62.6MB, uploaded 14 Jan 2022; mod page itself is v4.3.2 for the full Wild file). Mild = modifies only NPC base body texture files (base underwear/bra removed), affects only a small portion of female NPCs — the tame version. Adult-gated page: metadata unreadable via r.jina.ai, must use logged-in browser. Other main files (not installed): #1 "NPCs Gone Wild (non-REDMOD)" v4.3.2 full version, #3 "Strippers and Prostitutes Only", plus REDMOD variants and a low-res texture patch. Downloaded via Claude-in-Chrome browser (Manual → Slow download).
DESC: Modifies female NPC body textures to be more revealing (Mild variant: base underwear and bra removed from base body textures only).

### Gameplay: Custom Progression XP
COMPAT: ✅ REDscript only (locally authored, pure wrap-based .reds — macOS-safe)
STATE: ENABLED
URL: — (custom local mod, not from Nexus)
TOTAL DLS: —
FILES: r6-scripts/custom-progression-xp/CustomProgressionXP.reds
NOTE: CUSTOM MOD authored locally on user request (2026-07-03) — not a Nexus download, nothing in downloaded/. Wraps PlayerDevelopmentData.AddExperience via @wrapMethod (calls wrappedMethod exactly once): multiplies XP amount by 7.0x for the five patch-2.x progression skills only (CoolSkill/IntelligenceSkill/ReflexesSkill/StrengthSkill/TechnicalAbilitySkill = Headhunter/Netrunner/Shinobi/Solo/Engineer); character Level and StreetCred XP untouched. Stacking: sibling custom mod Custom Faster XP wraps the SAME method with a global 1.2x — wraps chain, so the five skills get ~8.4x total (multiplicative, intended); no interaction with other installed mods (none touch AddExperience). Multiplier editable in the .reds (ProgressionXpMultiplier). Plan + research archived in the session scratchpad at /private/tmp/claude-501/-Users-teazyou-dev-tmp-claude-cyberpunk/f2ab62a5-4fae-4475-9330-417377dfde38/scratchpad/custom-progression-xp/.
DESC: Multiplies skill-proficiency XP by 7x for the five progression skills — Headhunter, Netrunner, Shinobi, Solo, Engineer — leaving character level and street cred XP vanilla.

### Gameplay: Custom Faster XP
COMPAT: ✅ REDscript only (locally authored, pure wrap-based .reds — macOS-safe)
STATE: ENABLED
URL: — (custom local mod, not from Nexus)
TOTAL DLS: —
FILES: r6-scripts/custom-faster-xp/CustomFasterXP.reds
NOTE: CUSTOM MOD authored locally on user request (2026-07-03) — not a Nexus download, nothing in downloaded/. Wraps PlayerDevelopmentData.AddExperience via @wrapMethod (calls wrappedMethod exactly once): multiplies ALL organic XP awards by 1.2x (character Level, StreetCred, and every skill proficiency) — gated to telemetryGainReason == Gameplay && !isDebug so respec/build/debug level-sets stay vanilla; RoundF with a minimum +1 XP so tiny Int32 awards are never flattened. Stacking: sibling custom mod Custom Progression XP wraps the SAME method with 7.0x on the five progression skills — wraps chain, so those skills get ~8.4x total (multiplicative, intended); no interaction with other installed mods (none touch AddExperience). Multiplier editable in the .reds (the 1.20 literal). Plan + research archived in the session scratchpad at /private/tmp/claude-501/-Users-teazyou-dev-tmp-claude-cyberpunk/f2ab62a5-4fae-4475-9330-417377dfde38/scratchpad/custom-faster-xp/.
DESC: Boosts all organic XP gains by 20% (1.2x) — character level, street cred, and every skill proficiency — leaving respec and debug XP untouched.

### Gameplay: Custom Switch Speed
COMPAT: ✅ REDscript only (locally authored, pure wrap-based .reds — macOS-safe)
STATE: ENABLED
URL: — (custom local mod, not from Nexus)
TOTAL DLS: —
FILES: r6-scripts/custom-switch-speed/SwitchSpeed.reds
NOTE: CUSTOM MOD authored locally on user request (2026-07-03, extended 2026-07-04) — not a Nexus download, nothing in downloaded/. Wraps 8 methods via @wrapMethod (each calls wrappedMethod exactly once): EquipmentBaseTransition.HandleWeaponEquip / HandleWeaponUnequip / GetWeaponEquipDuration / GetWeaponUnEquipDuration (weapon-side, also covers the cyberware-arm dispatch path) + MeleeTargetingEvents.OnEnter (knife-aim injection site) + MeleeThrowReloadDecisions.ExitCondition (knife redraw floor) + FirstEquipSystem.HasPlayedFirstEquip (flourish suppression) + PlayerPuppet.OnGameAttached (player-side). Effect via transient stat Multiplier modifiers (never rescales return values): EquipDuration/UnequipDuration/EquipDuration_First on the weapon entity + UnequipDuration/WeaponSwapDuration on the player, each x0.2 (≈5x faster draw/holster/swap; WeaponSwapDuration is belt-and-suspenders — no 2.31 script reads it); for THROWABLE melee only (WeaponHasTag "Throwable" — throwing knives/axes) also AimInTime x0.2 (≈5x faster normal-stance→knife-held aim-raise; AimingStateEvents.UpdateAimAnimFeature feeds that weapon stat to AnimFeature_AimPlayer.aimInTime each aim frame); applied at most once per entity instance via @addField guards, not saved, cannot stack. Knife switch-in fixes (paths that never read EquipDuration; verified in 2.31 decompile): (1) MeleeThrowReload post-throw redraw keeps its ThrowRecovery pool-refill wait (throw cooldown untouched) but the ~2s TDB Items.MeleeWeapon.minimumReloadTime floor is scaled by Multiplier() once the pool is full; (2) automatic FirstEquip flourishes suppressed via HasPlayedFirstEquip→true — every draw uses the normal scaled equip cycle (vanilla recorded-weapon behavior; hold-key flourish requests behave as with an already-recorded weapon). Known residual: the plain melee draw clip itself is an anim-graph asset and may not fully honor the scaled duration (engine-side). Multipliers editable in the .reds (SwitchSpeed.Multiplier(), 0.2 literal = switch + redraw floor; SwitchSpeed.AimMultiplier(), 0.2 literal = knife aim raise). Stacking: sibling custom mods Custom Progression XP / Custom Faster XP wrap a DIFFERENT method (PlayerDevelopmentData.AddExperience) — no overlap; no other installed mod touches these equip/unequip/melee transitions or stats. Plan + research archived at /private/tmp/claude-501/-Users-teazyou-dev-tmp-claude-cyberpunk/f2ab62a5-4fae-4475-9330-417377dfde38/scratchpad/custom-switch-speed/ (original) and .../3c7f9102-27a9-45d9-99ac-c43acb3f666a/scratchpad/ (knife-aim + 2.31 melee/upperBody/firstEquip sources).
DESC: Makes weapon draw, holster, and swap ~5x faster for all weapon types (including cyberware arms) by scaling the per-weapon and player switch-duration stats to 1/5; also ~5x faster throwing-knife aim-raise, ~5x shorter post-throw knife redraw floor (throw cooldown untouched), and automatic first-draw flourishes suppressed.

### Gameplay: Custom Scanner Suite
COMPAT: ✅ REDscript only (locally authored, pure wrap-based .reds — macOS-safe)
STATE: ENABLED
URL: — (custom local mod, not from Nexus)
TOTAL DLS: —
FILES: r6-scripts/custom-scanner-suite/ScannerSuite.reds
NOTE: CUSTOM MOD authored locally on user request (2026-07-05; auto-tag reworked to visible-sweep 2026-07-06) — not a Nexus download, nothing in downloaded/. Three independent scan-mode features, each behind its own toggle in the ScannerSuiteConfig block at the top of the .reds (edit literal + relaunch): EnableLootWhileScanning (default true), EnableAutoTagOnScan (default true), EnableAutoPickupOnScan (default true); secondary knobs AutoTagSweepRange (50.0 m), AutoTagSweepInterval (0.35 s), AutoPickupMaxDistance (12.0 m), AutoPickupPlaySound (true). Wraps 5 methods via @wrapMethod (each calls wrappedMethod exactly once — check here for collisions before installing scanner/HUD mods): HUDManager.OnScannerUIVisibleChanged (loot-while-scanning restore→delegate→suppress + arms the auto-tag sweep loop on scanner-open) / OnQuickHackUIVisibleChanged / OnQuickHackUIKeepContextChanged (loot-while-scanning Path A: compensation keeps UIGameContext.Scanning OFF the UI context stack while preserving vanilla bookkeeping, state in @addField m_lwsScanningSuppressed) + HUDManager.OnLootDataChanged (debug probe only) + scannerDetailsGameController.OnScannedObjectChanged (SINGLE shared wrap dispatching auto-tag hover channel first, then auto-pickup, gated on ActiveMode.FOCUS). AUTO-TAG (reworked): while the scanner UI is up, a self-re-arming DelayCallback sweep loop (STSweepTickCallback + HUDManager.ST_ArmSweep/ST_SweepTick/ST_RunSweepOnce, 0.35 s cadence, armed-flag double-arm guard, self-terminates on scanner-close) runs TargetingSystem.GetTargetParts with TargetingSet.Frustum (through walls, NO LOS — occlusion sets Visible/ClearlyVisible deliberately unused) + camera-forward dot backstop (never behind player) + 50 m cap, deduped per tick; hover channel kept as complement (loot containers may lack TargetingComponents and be missed by the frustum query — settle via DebugProbeAutoTagSweep; in-file fallback if Frustum proves empty: TargetingSet.Complete + FOV cosine gate). BOTH channels feed a four-category whitelist (ST_IsAutoTagWhitelisted on GameObject; revised 2026-07-06) BEFORE the seen-list: (1) safe-to-attack enemies — CanBeTagged → IsHostile / IsCharacterCyberpsycho / DoNotTriggerPrevention-tag → crime-branch mirror of PreventionSystem.ShouldPreventionSystemReactToAttack (police/vendor/civilian/crowd/TriggerPrevention = never) → IsEnemy; (2) collectables — lootable corpses (puppet branch) + non-puppet loot objects gated TWICE: vanilla classification trio (IsContainer/IsShardContainer/IsItem — only loot classes override these; every Device inherits GameObject-base false, so doors/fridges/vending machines exit here) THEN non-empty TransactionSystem.GetItemList final gate (closes the empty-container hole; stash excluded); (3) access points un-breached (IsAccessPoint && !IsBreached; datamine-computers excluded); (4) security TURRETS only (IsTurret && !IsBroken — sole vanilla IsTurret override is SecurityTurret; disabled/unpowered still tagged). REMOVED 2026-07-06 — root cause of junk doors/fridges auto-tagging: the QUEST category ran FIRST, before any class gating — Device.IsQuest() reads persistent DeviceComponentPS.m_markAsQuest, which quests set on route/objective doors/appliances (Door/Fridge are InteractiveDevices) and often never clear, and GetAvailableClueIndex()≥0 fired on clue-flagged devices; whole QUEST category dropped (no IsQuest/clue tagging), CAMERAS also dropped per spec (IsSensor removed; turrets kept via exact-class IsTurret). Non-whitelisted targets spend NOTHING (no seen-list append). Once-per-entity semantics, all session-transient (never saved): auto-tag seen-list on FocusModeTaggingSystem (vanilla TagObject path; ResolveFocusClues removed from the auto-tag attempt 2026-07-06 — its TagLinkedCluekRequest cascade could tag non-whitelisted clue-group members such as quest doors; manual middle-click keeps the full vanilla cascade untouched; a manually untagged target is never re-tagged — its one attempt is spent); auto-pickup attempt ledger on PlayerPuppet with transient-vs-final semantics (alive NPC / locked / >12 m / no-LOS / empty do NOT spend the attempt) + per-item filters (quest-flagged, iconic, HMG, nameless-non-shard skipped; locked containers and player stash never touched; replacer/braindance guarded; animated crates play their open animation on loot). Path A known side effect (by design): HUD elements vanilla hides during scanning (minimap, quest tracker, healthbar…) stay visible while the scanner is up; Path B fallback (Choice1 listener + TransferAllItems, no tooltip) documented in the plan, not deployed. Debug probe flags DebugProbeLootWhileScanning / DebugProbeAutoPickup / DebugProbeAutoTagSweep (keep false for play). PENDING in-game tests: loot-prompt-while-scanning decisive test T1 (+probe if it fails), the auto-pickup blackboard probe (does UI_Scanner.ScannedObject carry plain loot objects?), and the sweep probe (what does Frustum return — containers? through-wall? behind-player?). Stacking: no other installed mod wraps or replaces any of these methods (grep-verified across all deployed .reds; the simple-untrack-quest/better-fast-travel @replaceMethod collision is WorldMapMenuGameController — unrelated). Plans + research dossiers archived at wikis/modding/ (rework spec: scanner-suite-refinements.md).
DESC: Scan-mode trio — keeps the vanilla loot prompt usable while scanning, auto-tags everything whitelisted in camera view while the scanner is up (periodic frustum sweep through walls within 50 m + hover fallback; no-NCPD-heat enemies, loot-bearing collectables, un-breached access points, working turrets; quest elements and cameras removed 2026-07-06; once per entity via the vanilla tag path), and auto-collects hovered lootables within 12 m and line of sight (quest/iconic/HMG filtered) — each feature independently toggleable in the .reds.
