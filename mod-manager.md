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
- ADULT-TAGGED MODS: a mod tagged Sexualised/adult returns an EMPTY digest — r.jina.ai is logged-out and Nexus hides adult content from anonymous visitors, so the saved page is nav chrome only ("Adult content disabled"). The failure is SILENT (the tool exits 0 and writes a file with no mod in it). Do not retry; read the page in the logged-in Claude-in-Chrome browser instead — it is the only source for that mod's metadata, DL counts and incompatibility banners. Confirmed on mods 1436, 4843, 10150, 9887, 1699, 1823.

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
   - Files >500MB: after "Slow download" Nexus inserts an EXTRA modal ("Download this large file without losing progress") — click **"Standard download"** (NOT "Resumable download (Beta)", which does not drop a plain file in `~/Downloads`). Nothing downloads until one is clicked; skipping this modal makes `mod-tool.sh grab` poll an empty dir and time out with no explanation. Always confirm a `*.crdownload` appears before trusting the download. `grab`'s wait is hardcoded to 180s — far too short for GB-scale files at the free tier's 1.5–3MB/s, so wrap it: poll until no `*.crdownload` remains, then `exec script/mod-tool.sh grab <slug> "<glob>"`.
   - Claude-in-Chrome extension/tools not available or not connected → STOP. Do not install any mods this run; report back instead.
   - Download fails for any other reason (Cloudflare/CAPTCHA, login/paywall wall, no manual-download link found, network error, etc.) → SKIP this mod: keep STATE=NOT INSTALLED, add a NOTE with the failure reason, move on to the next mod.
   - Under NO circumstance write, invent, or reconstruct a mod's code yourself as a substitute for a real download, even partially. Only a file actually downloaded from Nexus counts as installed. (This happened once — an agent fabricated REDscript for 9 mods instead of downloading; all were reverted and deleted.)
   - VARIANT CHOICE (standing user rules, do NOT ask): pick the file with the **highest Total DLs** on the Files tab. The ONE exception is resolution — **always take 2K over 4K, even if the 4K file has more DLs**. Record the chosen variant AND its DL count in the entry's `NOTE:`, plus which variants were rejected. Still stop and report (do not guess): a ❌ compat fork, a mutually-exclusive conflict with an already-installed mod, or an unresolved hard Nexus dependency.
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
- `.archive` load order is INVERTED vs intuition: the game loads `archive/pc/mod/*.archive` in alpha-numerical order (numbers before letters), and the archive whose name comes **FIRST alphabetically is loaded LAST — so it overwrites everything after it**. First = winner. This is why `###-NovaLUT4` / `###-PreemScanner-Pure` win (`###` sorts first), and why the MonstrrMagic packs ship a `zz-` prefix on purpose: so other mods beat them. To make an archive win a texture conflict, prefix `00-`/`###-`; to make it lose, prefix `zz-`. PREFER OMISSION over load-order tricks when a pack ships one archive per target (e.g. mod 14999 ships 42 separate `zz-NPCs-<Name>.archive` — protecting a dedicated Judy mod is just "don't deploy `zz-NPCs-Judy.archive`", which needs no load-order reasoning at all).
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
NOTE: Main file "better fast travel map" v1.0.0.2 (ships only r6/scripts/BetterFastTravelMap.reds). The optional file "Disable exit with right click" is not installed (remaps right-click for waypoint tracking, needs its own input .xml).
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
NOTE: Main file #1 "Disappearing Enemy Health Bar Fix" — the non-LHUD version (#2 is for Limited HUD users, not installed here). The optional "Show Player Health Bar When Scanning" add-on is not installed.
DESC: Keeps the enemy health bar visible whenever you look directly at an enemy, fixing the vanilla appear/disappear behavior.

### Gameplay: Disassemble As Looting Choice
COMPAT: ✅ REDscript + input .xml (Requirements: redscript only; input handled via bundled Input Loader xml)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/4648
TOTAL DLS: 199,680
FILES: r6-scripts/disassemble-loot/dalc_base.reds, r6-scripts/disassemble-loot/dalc_overrides.reds, r6-input/disassembleAsLootingChoice_input_loader.xml
NOTE: Main file v2.0 bundles both the REDscript (DALC/) AND the Input Loader keybind xml (disassembleAsLootingChoice_input_loader.xml) — the separate optional "Input Loader XML"/"Input Helper XML" files are NOT needed. Keybind defaults to IK_Z (kbd) / IK_Pad_DigitLeft (pad). Settings (excludedQualities, sound) editable in r6-scripts/disassemble-loot/dalc_base.reds. The mod's DALC/ namespace subfolder is renamed to kebab-case disassemble-loot/.
DESC: Adds a disassemble option directly to the loot prompt so you can break items down while looting.

### Gameplay: Fast Travel from anywhere to everywhere - Redscript
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/9241
TOTAL DLS: 499,493
FILES: r6-scripts/fast-travel-from-anywhere-to-everywhere-redscript/FastTravelFromAnywhereToAnyMapPin.reds
NOTE: Installed the "fast travel to any map pin" variant v1.0.0.5 — fast travel to ANY map pin incl. own waypoints. Mutually exclusive with the "fast travel to any fast travel point" variant (FT points only); swap = uninstall + install the other file. Caveat: some shop pins can leave you stuck behind the counter — the author suggests setting a nearby waypoint instead.
DESC: Lets you fast travel from the map menu to any fast travel point or map pin, including your own markers.

### Gameplay: Hacking Gets Tedious - 2.3 redscript HOTFIX
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/15084
TOTAL DLS: 42,567
FILES: r6-scripts/hacking-gets-tedious/HackingGetsTedious.reds
NOTE: Main file "HGT - 2.12a redscript v0.5.24 Hotfix" (ships r6/scripts/HackingGetsTedious.reds; page title reads v2.31a). If the original "Hacking Gets Tedious" base mod is ever added, delete its r6/scripts/HackingGetsTedious.reds and keep only this hotfix — no base mod is present in this vault. LOCALLY MODIFIED — the deployed file no longer matches the Nexus zip; re-installing from downloaded/ would drop the INSTANT BREACH extension: device breaches (access-point jack-in + device remote breach) succeed INSTANTLY on connect, no breach screen, with the daemons the board would have offered applied through the untouched vanilla completion path (datamine rewards, network quickhacks exposed, hacking XP, personal-link auto-disconnect). NOT skipped (a pre-solved one-click board still opens): quest-designed minigames (any Minigame_Def with GridSymbols or OverrideProgramsList — VR netrunning tutorial, Kab08 FindAnna), NPC officer + suicide breach (puppet AccessBreach path), shard/item breach (Militech datashard), and devices vanilla already auto-skips. Config block HGTInstantBreachConfig at the top of the .reds: EnableInstantBreach (default true; false = pure Nexus one-click behavior), DebugProbeInstantBreach (default false). COLLISION: wraps ScriptableDeviceComponentPS.OnToggleNetrunnerDive (calls wrappedMethod on every non-hijacked branch) and adds 3 methods on that class (HGT_ShouldInstantBreach / HGT_CollectBoardPrograms / HGT_InstantBreach) — check here before installing breach/netrunning mods; no other deployed mod touches it. Research dossier: wikis/modding/instant-breach-device-dive.md.
DESC: Breach protocol without the minigame: connecting to a device hacks it instantly with every daemon applied (local instant-breach extension); any minigame that still opens (quest boards, NPC/shard breach) is pre-solved and completes with one click (Nexus hotfix base).

### Miscellaneous: No Intro Videos
COMPAT: ✅ REDscript or raw archive (macOS-compatible version)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/533
TOTAL DLS: 2,006,664
FILES: r6-scripts/no-intro-videos/NoIntroVideos.reds
NOTE: Installed the "redscript" main variant v0.8; requires REDscript (provided by the macOS toolchain). Mutually exclusive with the "archive" main variant — use only one.
DESC: Skips the startup logo/intro videos and news report for a faster launch to the main menu.

### Gameplay: Replace Weapon Mods
COMPAT: ✅ core is REDscript only (ArchiveXL/RED4ext/Mod Settings are OPTIONAL — only for the in-game settings menu, not macOS-compatible)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/15409
TOTAL DLS: 730,552
FILES: r6-scripts/replace-weapon-mods/ReplaceWeaponMods.reds
NOTE: Main file v1.3 — deployed the core r6/scripts/ReplaceWeaponMods.reds ONLY; the bundled ArchiveXL settings pack (ReplaceWeaponMods.archive + .xl) is skipped, as it drives the Mod Settings menu which needs RED4ext+ArchiveXL (unavailable on macOS). Consequence: the "warning popup before destroying a mod" defaults ON and can't be turned off in-game. Core replace/destroy works fully — the ModSettings refs are inert @runtimeProperty annotations.
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
NOTE: Main file v2024-06-10 — ships r6/scripts/AdaptiveSliders/adaptiveSliders.reds; namespace subfolder renamed to kebab-case adaptive-sliders/. Max slider applies to Crafting as well as Drop/Stash/Sell. Download is a .7z (downloaded/adaptive-sliders.7z), extracted with macOS bsdtar/libarchive.
DESC: Sets inventory transaction sliders to max by default for Drop, Stash, and Sell actions, keeping all other sliders at 1.

### Gameplay: Auto Unequip Weapon Mods And Attachments When Selling Or Disassembling
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/9604
TOTAL DLS: 343,078
FILES: r6-scripts/auto-unequip-weapon-mods-and-attachments-when-selling-or-disassembling/UnequipWeaponModsAndAttachements.reds
NOTE: Main file v1.1.0 (single r6/scripts/UnequipWeaponModsAndAttachements.reds — note the author's "Attachements" spelling). In-script option to skip unequipping mods, editable in the .reds. Works alongside bulk-sell mods like Mark To Sell.
DESC: Automatically unequips all weapon mods and attachments when selling or disassembling a weapon, returning them to your inventory.

### UI: Crafting Recipe Owned and Iconic Labels
COMPAT: ✅ REDscript only (Requirements: redscript; the TweakDBID refs are vanilla engine types, not a TweakXL dep — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/11261
TOTAL DLS: 972,302
FILES: r6-scripts/crafting-recipe-owned-and-iconic-labels/crafting_recipe_owned_labels.reds
NOTE: Single main file v1.1.1 (ships r6/scripts/crafting_recipe_owned_labels.reds) — placed in its own subfolder per the collision rule.
DESC: Adds check marks to crafting-menu recipe icons for items you already own, plus the iconic background for iconic recipes.

### Miscellaneous: Bounty class stars bug fix
COMPAT: ✅ REDscript only (Requirements: redscript; .reds has no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/23211
TOTAL DLS: 339,712
FILES: r6-scripts/bounty-class-stars-bug-fix/BountyClassStarsFix.reds
NOTE: Single main file "Bounty class stars fix" v1.0.0.2 (ships r6/scripts/BountyClassStarsFix.reds) — placed in its own subfolder per the collision rule.
DESC: Fixes the broken bounty class stars (wanted-level rating) that stopped displaying properly since patch 2.0.

### UI: Drink At The Counter - Use Consumables From Vendor Menu
COMPAT: ✅ REDscript only (Requirements: redscript; .reds has no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/8588
TOTAL DLS: 4,139
FILES: r6-scripts/drink-at-the-counter-use-consumables-from-vendor-menu/DrinkAtTheCounter.reds
NOTE: Single main file "Drink At The Counter" v1.1 (ships r6/scripts/DrinkAtTheCounter.reds) — placed in its own subfolder per the collision rule.
DESC: Lets you use consumable items from your inventory while browsing a vendor's menu.

### Gameplay: Go Where You Want - Bypass Skill Checks
COMPAT: ✅ REDscript only (Requirements: redscript; .reds has no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/4095
TOTAL DLS: 5,526
FILES: r6-scripts/go-where-you-want/goWhereYouWant.reds
NOTE: Single main file "GoWhereYouWant" v1.0 — ships r6/scripts/GoWhereYouWant/goWhereYouWant.reds; namespace subfolder renamed to kebab-case go-where-you-want/. Download is a .7z (go-where-you-want-bypass-skill-checks.7z), extracted with macOS bsdtar/libarchive.
DESC: Bypasses attribute/skill checks on locked doors and gated dialogue/level routes so you can reach loot or shortcuts anywhere.

### Gameplay: Fighting Gangs Allowed - Reasonable Police
COMPAT: ✅ REDscript only (Requirements: redscript; .reds has no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/19189
TOTAL DLS: 799,598
FILES: r6-scripts/fighting-gangs-allowed-reasonable-police/FightingGangsAllowed.reds
NOTE: Single main file "Fighting Gangs Allowed - Reasonable Police" v1.0 (zip ships bare r6/scripts/FightingGangsAllowed.reds with no subfolder — placed in its own subfolder per the collision rule).
DESC: Lets you shoot, quickhack, and grenade gang enemies in the open world without the NCPD turning hostile (harming civilians or cops is still a crime).

### Gameplay: Fast Finishers
COMPAT: ✅ REDscript only (Requirements: redscript; .reds has no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/10314
TOTAL DLS: 16,875
FILES: r6-scripts/fast-finishers/FastFinishers.reds
NOTE: Installed the SANDEVISTAN BERSERK variant v1.0.0 (fast finishers only while Sandevistan/Berserk is active). Mutually exclusive with the "Fast Finishers Always" variant; swap = uninstall + install the other file. Download is a .7z (fast-finishers.7z); ships r6/scripts/FastFinishers/FastFinishers.reds — namespace subfolder renamed to kebab-case fast-finishers/.
DESC: Makes finisher animations use their quick version so they don't waste Sandevistan/Berserk uptime.

### Gameplay: Enhanced Monowire Quickhacks
COMPAT: ✅ REDscript only
STATE: DISABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/11289
TOTAL DLS: 10,749
FILES: r6-scripts/monowire-quickhacks/EnhancedMonowireQuickhacks.reds
NOTE: Main file v1.0; the optional "1 in 3 Proc Chance" variant is not installed. Ships r6/scripts/EnhancedMonowireQuickhacks/EnhancedMonowireQuickhacks.reds — namespace subfolder renamed to kebab-case monowire-quickhacks/. The .reds is a clean @replaceMethod (no TweakXL/Codeware) — macOS-safe.
DESC: Lets the monowire apply quickhacks with normal and strong attacks, not just charged attacks.

### Gameplay: Disable Fall Damage And Deadly Fall On-Screen Grey Effect Filter
COMPAT: ✅ REDscript only
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/3161
TOTAL DLS: 26,405
FILES: r6-scripts/disable-fall-damage-and-deadly-fall-on-screen-grey-effect-filter/disableFallDamageAndFallOnScreenEffects.reds
NOTE: Single main file "Disable Fall Damage And Deadly Fall On Screen Effects" v1.6 (ships r6/scripts/disableFallDamageAndFallOnScreenEffects.reds) — standalone REDscript, NOT the separate CET fall-damage mod (#9928); incompatible with other fall-damage mods. Download is a .rar (downloaded/disable-fall-damage-and-deadly-fall-on-screen-grey-effect-filter.rar), extracted with macOS bsdtar/libarchive.
DESC: Disables all fall damage and removes the grey deadly-fall warning filter from the screen.

### Crafting: Item Level Scaled Upgrade Cost
COMPAT: ✅ REDscript only (Requirements: redscript req. version 0.3.4; .reds has no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/2873
TOTAL DLS: 163,012
FILES: r6-scripts/item-level-scaled-upgrade-cost/item_level_scaled_upgrade_cost.reds
NOTE: Installed the LINEAR variant v0.3 — placed in its own subfolder per the collision rule. Three mutually-exclusive cost curves exist (Linear/Exponential/Combination), each shipping the same bare r6/scripts/item_level_scaled_upgrade_cost.reds; swap = uninstall + install another. Download is a .7z. Incompatible with other mods that modify GetItemFinalUpgradeCost.
DESC: Scales weapon/gear upgrade cost by item level instead of by upgrade count, making low-level legendaries cheaper to upgrade.

### UI: Inventory Sorting Improved
COMPAT: ✅ REDscript only
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/23628
TOTAL DLS: 278,052
FILES: r6-scripts/inventory-sorting/InventorySortingImproved.reds
NOTE: Single main file v1.0 — ships r6/scripts/Inventory Sorting Improved/InventorySortingImproved.reds; namespace subfolder renamed to kebab-case inventory-sorting/. The ModSettings menu integration is an optional soft-dep (all ModSettings.* calls sit inside @if(ModuleExists("ModSettingsModule")) guards, the rest are inert @runtimeProperty annotations — same graceful-degrade pattern as Replace Weapon Mods), so it compiles/runs standalone. Consequence on macOS with no ModSettings framework: the cyberware name/quality sort CONFIG menu is absent (baked-in defaults apply); core quality-based sorting works. The "Plus" tier icon overlay needs a separate complementary mod.
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
NOTE: Main file v1.3 — ships r6/scripts/noSpecialOutfitLock.reds (the page's older "outfitUnlocker.reds" name is outdated). Requires redscript v0.5.6+ on game v2.0+. Download is a .rar (no-special-outfit-lock.rar).
DESC: Lets you modify other clothing slots while a special outfit is equipped, instead of the slot being locked.

### Vehicles: Vehicle Exit Fix for 2.3
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/22786
TOTAL DLS: 652,217
FILES: r6-scripts/vehicle-exit-fix/vehicleexitfix.reds
NOTE: Single main file "VehicleExitFix" v1.0 — ships r6/scripts/vehicleexitfix/vehicleexitfix.reds; namespace subfolder renamed to kebab-case vehicle-exit-fix/.
DESC: Fixes the slight kickback/roll after exiting a vehicle and the bike tilt/lean bug in 2.3 (and 2.31).

### User Interface: Track What You Want - Have Only One Map Marker
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/4110
TOTAL DLS: 98,374
FILES: r6-scripts/track-what-you-want/trackWhatYouWant.reds
NOTE: Main file "TrackWhatYouWant" v3.0 (updated for patch 2.3) — ships r6/scripts/TrackWhatYouWant/trackWhatYouWant.reds; namespace subfolder renamed to kebab-case track-what-you-want/. Download is a .zip. Right-click a marker to keep only one active pin; right-click empty ground to set/unset a Pinned Location for zero markers.
DESC: Putting a marker on the map hides all other markers and routes (including the main quest), and lets you have no markers at all if preferred.

### Gameplay: ThrowingWeaponBugFix2.3
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/25830
TOTAL DLS: 18,338
FILES: r6-scripts/throwing-weapon-bug-fix-2.3/FixThrowingWeapon.reds
NOTE: Single main file "FixThrowingWeaponBug" v1.0 (zip ships bare r6/scripts/FixThrowingWeapon.reds with no subfolder — placed in its own subfolder per the collision rule).
DESC: Fixes the patch-2.3 throwing-knife bug where chaining throws while holding block caused an unintended melee swing, restoring smooth continuous knife throwing.

### Gameplay: Throwing Weapon Kerenzikov Fix
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/26327
TOTAL DLS: 120,351
FILES: r6-scripts/throwing-weapon-kerenzikov-fix/Throwing Weapon Kerenzikov Fix.reds
NOTE: MAIN file "Throwing Weapon Kerenzikov Fix" v1.0 ("For vanilla Kerenzikov"; ships a bare .reds with no subfolder — placed in its own subfolder per the collision rule). The optional "Enhanced (Modded) Kerenzikov Patch" is not installed — it is only for users of the separate Enhanced Kerenzikov mod (not in this vault) and does not require the main file.
DESC: Fixes Kerenzikov ending instantly when the throw button is pressed while still aiming, plus Air Kerenzikov accuracy while falling during the throw animation.

### Gameplay: Talk to Me
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/5534
TOTAL DLS: 550,351
FILES: r6-scripts/talk-to-me/TalkToMe.reds, r6-scripts/talk-to-me/TalkToMeConfig.reds
NOTE: Main file "Talk to Me" v1.3 — ships r6/scripts/TalkToMe.reds + TalkToMeConfig.reds; config editable in TalkToMeConfig.reds. Both placed in r6-scripts/talk-to-me/.
DESC: People casually interact with you as you walk near them, so the world's crowds are no longer silent.

### Gameplay: Reroll Cyberware Stats When Upgrading
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/17315
TOTAL DLS: 10,256
FILES: r6-scripts/reroll-cyberware-stats-when-upgrading/ReRollCWStatsWhenUpgrading.reds
NOTE: Main file v1.1 — single r6/scripts/ReRollCWStatsWhenUpgrading.reds in its own subfolder. Requires the in-game "Chipware Connoisseur" perk to be active — the mod does nothing without it. Reroll by backing out of the upgrade screen and re-entering.
DESC: Lets you reroll the offered cyberware upgrade stats by exiting and re-entering the upgrade screen, as many times as you like.

### User Interface: Real Vendor Names
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/4941
TOTAL DLS: 1,739,067
FILES: r6-scripts/real-vendor-names/realVendorNames.reds
NOTE: Main file v2.1.0 — single r6/scripts/realVendorNames.reds in its own subfolder.
DESC: Displays each vendor's real name on the world-map icons instead of the generic vendor-type labels.

### Gameplay: Street Vendors
COMPAT: ✅ redscript required (not a ❌ dep). CAVEAT: current v2.0.2 also needs off-site REDMod deployment, which the macOS REDscript toolchain (launch_modded.sh) does not run — re-verify at install; a pre-2.0 redscript-only build is the macOS-safe option.
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/2894
TOTAL DLS: 750,446
FILES: r6-scripts/street-vendors/street_vendors.reds, r6-scripts/street-vendors/InventoryGeneration/DefaultInventoryGeneration.reds
NOTE: Installed the pre-2.0 redscript-only build "Street Vendors v1.2.7b" — the highest version that needs redscript only; v2.0.0+ requires REDMod deployment, which the macOS toolchain (launch_modded.sh) does not run, so moving to v2.0.x would need a working REDMod deploy step. Ships ONLY r6/scripts (Street Vendors/street_vendors.reds + Street Vendors/InventoryGeneration/DefaultInventoryGeneration.reds) — no REDMod packaging, no archive/, no .xl, no .dll. Both .reds deployed under r6-scripts/street-vendors/ keeping the InventoryGeneration/ subfolder.
DESC: Lets you trade with most of the street vendors around Night City.

### User Interface: Status Effect ReColor
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/26438
TOTAL DLS: 5,322
FILES: r6-scripts/debuff-color/DeBuffColor.reds
NOTE: Installed "DeBuffColor-Full" v1.1 — the variant matching the mod's core description (whole debuff display red, positives stay blue; not icon-only, not E3, not buffs-green). Five other mutually-exclusive variants exist (DeBuffColor-Icon / E3DeBuffColor-Full / E3DeBuffColor-Icon / DeBuffColor-FullGreen / DeBuffColor-IconGreen); swap = uninstall + install another. Ships r6/scripts/DeBuffColor/DeBuffColor.reds — namespace subfolder renamed to kebab-case debuff-color/.
DESC: Colors negative status effects (debuffs) red next to the health bar while positive effects stay blue.

### Gameplay: Stamina Consumption Fix
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/23230
TOTAL DLS: 490,475
FILES: r6-scripts/stamina-consumption-fix/Stamina Consumption Fix.Global.reds
NOTE: Main file v1.0.0 — single global .reds ("Stamina Consumption Fix.Global.reds"). The zip stores Windows backslash paths, so the real r6/scripts .reds was extracted by hand into its own subfolder.
DESC: Makes stamina consumption (e.g. crouch-sprinting) framerate-independent, fixing the vanilla bug where higher FPS drains stamina faster.

### Gameplay: Smart Gun Lock Speed Fixes
COMPAT: ✅ REDscript only (Requirements: redscript; .reds has no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/21798
TOTAL DLS: 510,786
FILES: r6-scripts/smart-gun-lock-fixes/lock_animation.reds
NOTE: Single main file "Smart Gun Lock Speed Fixes" v1.0.0 — ships r6/scripts/Locking_Fixes/lock_animation.reds; namespace subfolder renamed to kebab-case smart-gun-lock-fixes/.
DESC: Makes smart-gun lock-on animation properly accelerate against debuffed targets and fixes recon grenades so they actually apply their status effect on detonation.

### User Interface: Simple untrack quest
COMPAT: ✅ REDscript only (Requirements: redscript; .reds has no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/5177
TOTAL DLS: 192,173
FILES: r6-scripts/simple-untrack-quest/untrackQuestByRightClick.reds
NOTE: MAIN file "untrackQuestByRightClick" v2.31 (update for patch 2.31, "doesn't conflict with Delamain anymore"; zip ships a bare .reds with no subfolder — placed in its own subfolder per the collision rule). The optional v1.1 file is not installed — it is for old game patch 1.63.
DESC: Lets you untrack a quest by right-clicking its marker on the Map, the same way you track it.

### Gameplay: Monowire Perk Tree
COMPAT: ✅ no requirements listed on Nexus (per compat rule → ✅). CAVEAT: perk-tree mods that add NEW perks normally need TweakXL to register perk TweakDB records (❌ on macOS) — re-verify at install by inspecting the zip; if it ships a .xl / TweakXL yaml / RED4ext .dll / ArchiveXL-dependent archive → ❌.
STATE: NOT INSTALLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/31022
TOTAL DLS: 266
FILES: —
NOTE: v0.1.0 by IMES (still 0.x, beta). Single main file "MonowirePerkTree" (19KB). Adds new Intelligence perks for the Monowire at INT 9/15/20 — range/stamina/attack-speed buffs, EMP combat utility (RAM recovery, mitigation), Overclock synergy; Korean i18n included, custom per-perk refund buttons, no perk icons. BEFORE DEPLOYING: inspect the zip for TweakXL yaml / RED4ext .dll / ArchiveXL-dependent archive — adding NEW perks normally needs TweakXL to register perk TweakDB records (❌ on macOS).
DESC: Adds a custom Intelligence perk tree for the Monowire, giving it range/stamina/attack-speed buffs plus EMP and Overclock synergy for netrunners.

### Gameplay: Second Heart Fix
COMPAT: ✅ REDscript only (Requirements: redscript; .reds has no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: DISABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/11100
TOTAL DLS: 841,195
FILES: r6-scripts/second-heart-fix/SecondHeartFix.reds
NOTE: Single main file "Second Heart Fix" v1.0 — ships r6/scripts/Second Heart Fix/SecondHeartFix.reds; namespace subfolder renamed to kebab-case second-heart-fix/. Removes the black screen on death and extends the timeframe until resurrection. May conflict with other mods that adjust death behavior/events.
DESC: Improves NPC reactions to Second Heart revival so enemies treat V as dead and stop attacking during the revive, with a distinct feign-death animation.

### Visuals and Graphics: Preem Scanner (Customization Options for a Clean Minimal Scanner)
COMPAT: ✅ raw .archive only (verified in zip: single archive/pc/mod/###-PreemScanner-Pure.archive, no .xl/ArchiveXL, no .dll — macOS-safe; Nexus Requirements: only "Clean Voiceovers", recommended-not-required)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/9215
TOTAL DLS: 712,134
FILES: archive-mod/###-PreemScanner-Pure.archive
NOTE: Installed "Preem Scanner - Pure" v1.2.0p (the AIO minimal variant, updated for 2.2). 11 other files on the page are not installed (Vanilla-Style/No-Vignette/Monochrome variants + Pure addons). Caveat: LUT Switcher overrides scanner LUT colors (not installed here). Pairs with Clean Voiceovers (mod 15285).
DESC: Removes the green tint and vignette from the scanner while providing a clean new look, with various options.

### Audio: Clean Voiceovers (while zoomed or scanning)
COMPAT: ✅ raw .archive only (verified in zip: single archive/pc/mod/ZoomVoSfxRemover.archive, no .xl/ArchiveXL, no .dll — macOS-safe; Nexus Requirements: only "Preem Scanner", recommended-not-required)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/15285
TOTAL DLS: 37,704
FILES: archive-mod/ZoomVoSfxRemover.archive
NOTE: Single main file "Clean Voiceovers" r1. Pairs with Preem Scanner (mod 9215).
DESC: Makes voiceovers sound normal instead of robotic while zoomed or scanning.

### Gameplay: Quickhacks sort by slot
COMPAT: ✅ REDscript only (Requirements: redscript; .reds is a single @replaceMethod(RPGManager), no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/11425
TOTAL DLS: 819,478
FILES: r6-scripts/quickhacks-sort-by-slot/quickhacks_sort_by_slot.reds
NOTE: Main file "Quickhacks sort by slot" v0.0.0.3 (uses @replaceMethod rather than wrapMethod for compatibility; tested on game v2.3). Ships r6/scripts/quickhacks_sort_by_slot/quickhacks_sort_by_slot.reds — namespace subfolder renamed to kebab-case quickhacks-sort-by-slot/. The separate Miscellaneous WIP file "keep_quickhacks_slots" is a different feature (keeps quickhack slots when unequipping a cyberdeck), not installed.
DESC: Quickhacks are displayed in slot order, not in reverse order of installation.

### Visuals and Graphics: Nova LUT 4.0 (AgX - New HDR)
COMPAT: ✅ raw .archive only (verified in zip: single archive/pc/mod/###-NovaLUT4.archive, no .xl/ArchiveXL, no .dll — macOS-safe; Nexus Requirements: none listed; author: "not a reshade")
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/11622
TOTAL DLS: 1,621,772
FILES: archive-mod/###-NovaLUT4.archive
NOTE: Main file "Nova LUT 4" v4.0.0 ("LUT ONLY. Contains both SDR and HDR LUTs"). Nova 4 has just one LUT (no variants); the 3 optional LUT-Switcher packs on the page are not installed. NOT compatible with other LUT mods; compatible with weather/lighting mods that use their own LUTs as long as Nova LUT gets load priority (the ### filename prefix sorts it first = loaded last = winner). Caveat: Preem Scanner notes that LUT Switcher overrides scanner LUT colors — plain Nova LUT is fine. Author recommends pairing with Nova City 2 (mod 12490) for the screenshot look.
DESC: Crisp visuals with a natural palette, using AgX tonemapping to bring lifelike luminance and color to Night City with a pop of contrast.

### Gameplay: Toggle Sprint While Scanning
COMPAT: ✅ REDscript only (Requirements: redscript; .reds is pure @wrapMethod, no RED4ext/Codeware/ArchiveXL imports — macOS-safe)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/14646
TOTAL DLS: 32,361
FILES: r6-scripts/toggle-sprint-while-scanning/EnableSprintingWhileScanning.reds
NOTE: Single main file "Toggle Sprint While Scanning" v1.0 (download is named "Enable sprinting while scanning-14646-…zip"; ships a bare .reds with no subfolder — placed in its own subfolder per the collision rule). Author intends it alongside mods that disable the scanner time-dilation effect, e.g. "Scanner Time Dilation Optional 2.01" (mod 9671, not installed); works standalone regardless.
DESC: Scanning no longer restricts you to walking-only mode — you can walk, run, or sprint with full control over movement speed while scanning.

### Visuals and Graphics: Cyberpunk 2077 HD Reworked Project
COMPAT: ✅ raw .archive only (verified in zip: single archive/pc/mod/HD Reworked Project.archive, no .xl/ArchiveXL, no .dll; Nexus Requirements: none listed)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/7652
TOTAL DLS: 1,181,393
FILES: archive-mod/HD Reworked Project.archive
NOTE: Installed the ULTRA QUALITY main file v2.0 (1.07 GB); the other main variant is Balanced Quality. Author install path is exactly archive/pc/mod/HD Reworked Project.archive. No performance hit if VRAM is sufficient; if VRAM runs short, uninstall = delete the one .archive.
DESC: Improves the graphics by reworking game assets to better quality, preserving the original art style and good performance.

### Appearance: NPCs Gone Wild
COMPAT: ✅ raw .archive only (verified in zip: single archive/pc/mod/basegame_00NPC_GM.archive, no .xl/ArchiveXL, no .dll — macOS-safe; Nexus page lists no Requirements section)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/1436
TOTAL DLS: 1,940,308
FILES: archive-mod/basegame_00NPC_GM.archive
NOTE: Installed the MILD variant — main file #2 "NPCs Gone Mild (non-REDMOD)" v2.0 (62.6MB); the mod page itself is v4.3.2, which is the full Wild file. Mild = modifies only NPC base body texture files (base underwear/bra removed) and affects only a small portion of female NPCs. Not installed: #1 "NPCs Gone Wild (non-REDMOD)" v4.3.2 (full version), #3 "Strippers and Prostitutes Only", the REDMOD variants, and a low-res texture patch. PAGE ACCESS: adult-gated → the r.jina.ai digest is empty; read the page in the logged-in browser.
DESC: Modifies female NPC body textures to be more revealing (Mild variant: base underwear and bra removed from base body textures only).

### Gameplay: Custom Progression XP
COMPAT: ✅ REDscript only (locally authored, pure wrap-based .reds — macOS-safe)
STATE: ENABLED
URL: — (custom local mod, not from Nexus)
TOTAL DLS: —
FILES: r6-scripts/custom-progression-xp/CustomProgressionXP.reds
NOTE: CUSTOM MOD authored locally — not a Nexus download, nothing in downloaded/. Wraps PlayerDevelopmentData.AddExperience via @wrapMethod (calls wrappedMethod exactly once): multiplies the XP amount by 0.8x for the five patch-2.x progression skills only (CoolSkill/IntelligenceSkill/ReflexesSkill/StrengthSkill/TechnicalAbilitySkill = Headhunter/Netrunner/Shinobi/Solo/Engineer); character Level and StreetCred XP untouched. Rounding is plain round-half-up with NO minimum-gain floor: awards too small for a rounded 0.8x to move stay exactly vanilla, and a 1 XP award stays 1, so no positive award is ever zeroed. Multiplier editable in the .reds (ProgressionXpMultiplier). STACKING: sibling custom mod Custom Faster XP wraps the SAME method with a global 0.8x, so the wraps chain — the five progression skills land at ~0.64x total (-36%, multiplicative, intended) while everything else gets the plain 0.8x (-20%). ASYMMETRY vs that sibling (deliberate, not a bug): this mod has NO telemetryGainReason/isDebug gate, so it also scales respec/build/debug level-set XP for the five skills. No other installed mod touches AddExperience.
DESC: Cuts skill-proficiency XP to 0.8x (-20%) for the five progression skills — Headhunter, Netrunner, Shinobi, Solo, Engineer — leaving character level and street cred XP vanilla.

### Gameplay: Custom Faster XP
COMPAT: ✅ REDscript only (locally authored, pure wrap-based .reds — macOS-safe)
STATE: ENABLED
URL: — (custom local mod, not from Nexus)
TOTAL DLS: —
FILES: r6-scripts/custom-faster-xp/CustomFasterXP.reds
NOTE: CUSTOM MOD authored locally — not a Nexus download, nothing in downloaded/. Wraps PlayerDevelopmentData.AddExperience via @wrapMethod (calls wrappedMethod exactly once): multiplies ALL organic XP awards by 0.8x (character Level, StreetCred, every skill proficiency), gated to telemetryGainReason == Gameplay && !isDebug so respec/build/debug level-sets stay vanilla. Plain RoundF with NO minimum-gain floor: awards too small for a rounded 0.8x to move stay exactly vanilla, and a 1 XP award rounds back to 1, so nothing is zeroed. Multiplier editable in the .reds (the 0.80 literal). STACKING: sibling custom mod Custom Progression XP wraps the SAME method with 0.8x on the five progression skills, so the wraps chain — those five get ~0.64x total (-36%, multiplicative, intended), everything else this mod's plain 0.8x (-20%). No other installed mod touches AddExperience.
DESC: Cuts all organic XP gains by 20% (0.8x) — character level, street cred, and every skill proficiency — leaving respec and debug XP untouched.

### Gameplay: Custom Switch Speed
COMPAT: ✅ REDscript only (locally authored, pure wrap-based .reds — macOS-safe)
STATE: ENABLED
URL: — (custom local mod, not from Nexus)
TOTAL DLS: —
FILES: r6-scripts/custom-switch-speed/SwitchSpeed.reds
NOTE: CUSTOM MOD authored locally — not a Nexus download, nothing in downloaded/. Effect via transient stat Multiplier modifiers (never rescales return values): EquipDuration/UnequipDuration/EquipDuration_First on the weapon entity + UnequipDuration/WeaponSwapDuration on the player, each x0.2 (≈5x faster draw/holster/swap; WeaponSwapDuration is belt-and-suspenders — no 2.31 script reads it); for THROWABLE melee only (WeaponHasTag "Throwable" — throwing knives/axes) also AimInTime x0.2 (≈5x faster normal-stance→knife-held aim-raise). Applied at most once per entity instance via @addField guards, not saved, cannot stack. Knife switch-in handling (paths that never read EquipDuration): the post-throw redraw keeps its ThrowRecovery pool-refill wait (throw cooldown untouched) but the ~2s TDB Items.MeleeWeapon.minimumReloadTime floor is scaled once the pool is full; automatic FirstEquip flourishes suppressed via HasPlayedFirstEquip→true, so every draw uses the normal scaled equip cycle. Known residual: the plain melee draw clip is an anim-graph asset and may not fully honor the scaled duration (engine-side). Multipliers editable in the .reds (SwitchSpeed.Multiplier(), 0.2 = switch + redraw floor; SwitchSpeed.AimMultiplier(), 0.2 = knife aim raise). COLLISION: wraps 8 methods via @wrapMethod (each calls wrappedMethod exactly once) — EquipmentBaseTransition.HandleWeaponEquip / HandleWeaponUnequip / GetWeaponEquipDuration / GetWeaponUnEquipDuration (weapon-side, also covers the cyberware-arm dispatch path) + MeleeTargetingEvents.OnEnter + MeleeThrowReloadDecisions.ExitCondition + FirstEquipSystem.HasPlayedFirstEquip + PlayerPuppet.OnGameAttached (also wrapped by custom-scanner-suite / custom-enemy-overhaul / street-vendors — wraps chain, benign). No other installed mod touches these equip/unequip/melee transitions or stats.
DESC: Makes weapon draw, holster, and swap ~5x faster for all weapon types (including cyberware arms) by scaling the per-weapon and player switch-duration stats to 1/5; also ~5x faster throwing-knife aim-raise, ~5x shorter post-throw knife redraw floor (throw cooldown untouched), and automatic first-draw flourishes suppressed.

### Gameplay: Better Throwing Knives and Weapons - Redscript
COMPAT: ✅ REDscript only (Requirements: redscript)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/9534
TOTAL DLS: 135,770
FILES: r6-scripts/dont-force-equip-next-weapon/DontForceEquipNextWeapon.reds
NOTE: Installed ONLY the optional file "don't force equip next weapon" v1.0.0.0 (1KB) — stops the game force-equipping the next weapon when the throw button is pressed while the weapon is on recovery cooldown. NOT installed: the main file (adds instant reload of thrown weapons — not wanted) and the optional "better throwing weapons - no recovery circle" addon. Ships a bare .reds with no subfolder — placed in its own subfolder per the collision rule. COLLISION: single @replaceMethod(MeleeThrowReloadEvents) OnUpdate — keeps the vanilla MeleeAttackPressed + weaponSwapOnAttackDelay check but empties the branch that called EquipNextWeapon → RequestNextThrowableWeapon. No other deployed mod touches that method (custom-switch-speed wraps the sibling MeleeThrowReloadDecisions.ExitCondition — different class+method, benign), but because this is a @replaceMethod any future mod replacing it would conflict (last compiled wins) — check here first. Behavior: with the switch suppressed, clicking during recovery does nothing until the ThrowRecovery pool refills — intended, not a bug.
DESC: Throwing weapons reload instantly without picking them up and/or won't force equip your next weapon if you spam throw (only the "don't force equip" optional file is wanted here).

### Gameplay: Custom Scanner Suite
COMPAT: ✅ REDscript only (locally authored, pure wrap-based .reds — macOS-safe)
STATE: ENABLED
URL: — (custom local mod, not from Nexus)
TOTAL DLS: —
FILES: r6-scripts/custom-scanner-suite/ScannerSuite.reds
NOTE: CUSTOM MOD authored locally — not a Nexus download, nothing in downloaded/. Three features, each behind its own toggle(s) in the ScannerSuiteConfig block at the top of the .reds (edit literal + relaunch). (1) LOOT WHILE SCANNING (EnableLootWhileScanning true) — keeps UIGameContext.Scanning off the UI context stack while preserving vanilla bookkeeping (@addField m_lwsScanningSuppressed) so the vanilla loot prompt stays usable with the scanner up; by-design side effect: HUD elements vanilla hides during scanning (minimap, quest tracker, healthbar…) stay visible. (2) AUTO-TAG, ALWAYS-ON + LOS-GATED (EnableAutoTag true) — a self-re-arming DelayCallback sweep loop armed once per load from PlayerPuppet.OnGameAttached (ST_ArmSweep/ST_SweepTick, AutoTagSweepInterval 1.0 s, first tick after AutoTagFirstTickDelay 0.1 s; runs in normal gameplay AND scan mode; re-arm-first, replacer/braindance ticks skipped) tagging loot-bearing COLLECTABLES ONLY (lootable corpses + containers/shards/items — ST_AutoTagCategory None/Other; no enemies/devices/quest/cameras) within AutoTagSweepRange 100 m, ONLY with LINE OF SIGHT (TargetingSystem.IsVisibleTarget on EVERY tag channel — no through-wall tagging; an occluded candidate stays transient, spends no seen-list entry, tags when LOS clears) + camera-forward dot backstop, PLUS a GetEntityList tag pass every AutoTagEntityListInterval 1.0 s catching standalone loot the frustum query is blind to (no TargetingComponent), PLUS the OnScannedObjectChanged hover complement (same LOS gate). QUALITY FLOOR AutoTagQualityFloor = gamedataQuality.Common (tag anything that carries loot incl. quality-less junk/materials; raise to Epic for Tier-4+ only) via an explicit ST_QualityTier switch — deliberately NOT EnumInt (gamedataQuality raw ints are non-monotonic) and NOT RPGManager.ItemQualityEnumToValue. Once per entity via the vanilla TagObject path (seen-list on FocusModeTaggingSystem; a manually untagged target is never re-tagged). (3) AUTO-PICKUP (unified auto-loot) — ONE always-on DelaySystem loop (APS_LootLoopTick, AutoPickupLoopInterval 0.5 s, armed from PlayerPuppet.OnGameAttached = player object = game thread, double-arm guarded) drives up to two channels feeding ONE shared worker (APS_TryAutoPickup on GameObject) + ONE per-entity attempt ledger (m_apsAttempted on PlayerPuppet — no channel double-loots): CURSOR (EnableAutoPickupCursor FALSE; the flag also gates the OnScannedObjectChanged hover pickup — if re-enabled it uses the LOS look-at form GetLookAtObject(this,true,true) + the worker LOS gate) and SURROUNDINGS/RADIUS (EnableConstantAutoLoot TRUE — the live channel): every ConstantAutoLootInterval 0.5 s a 360° GameInstance.GetEntityList pass (raw world entity list — sees standalone containers/drops/shards that every TargetingComponent query is structurally blind to) cheap-distance-rejects (Entity.GetWorldPosition before any cast) then routes survivors through the worker. TWO-TIER RANGE+LOS: OUTER 12 m (AutoPickupMaxDistance — also the worker gate for every channel) REQUIRES line of sight for EVERY loot class via TargetingSystem.IsVisibleTarget — occluded loot in the 4–12 m ring is a TRANSIENT refusal, re-checked each pass, collected the moment LOS clears or the player closes in; INNER 4 m (AutoPickupNoLOSRange, 360° channel only) SKIPS the LOS check — not a through-wall cheat ring but the absorber for IsVisibleTarget's known FALSE NEGATIVES (ragdolled-corpse body-part probes clipping into floor/cover, tiny floor-item volumes, closed container lids). COLLECTABILITY: APS_IsCollectable = DeterminGameplayRole()==Loot UNION the class trio IsContainer/IsShardContainer/IsItem — any object the game treats as loot is collected class-agnostically; bare ItemObject (floor-weapon mesh) redirects to its gameItemDropObject via APS_ResolveLootTarget (GetConnectedItemDrop). QUEST LOOT: hard per-item rule APS_IsQuestItem (item tags Quest/UnequipBlocked — vanilla's own definition), NEVER auto-taken, deliberately not a knob; whole-object IsQuest() deliberately unused (unusable as a loot gate — ShardCaseContainerPS defaults m_markAsQuest=true, so every shard case reports IsQuest). Policy knobs: AutoPickupTakeIconic (true), AutoPickupTakeHeavyWeapons (true), AutoPickupPlaySound (true). Worker semantics: transient-vs-final ledger (alive NPC / locked / disabled / out-of-range / occluded / empty / quest-only contents do NOT spend the attempt); stash + player + locked/disabled containers never touched; replacer/braindance guarded; SNAPSHOT-then-transfer (TransferItem mutates the source inventory backing the live item list, so IDs/quantities are snapshotted first); animated crates play their open animation. COLLISION: wraps 6 methods via @wrapMethod (each calls wrappedMethod exactly once — check here before installing scanner/HUD/player-attach mods) — HUDManager.OnScannerUIVisibleChanged / OnQuickHackUIVisibleChanged / OnQuickHackUIKeepContextChanged (loot-while-scanning) + HUDManager.OnLootDataChanged (debug probe only) + PlayerPuppet.OnGameAttached (arms both always-on loops; also wrapped by custom-switch-speed / custom-enemy-overhaul / street-vendors — wraps chain, benign) + scannerDetailsGameController.OnScannedObjectChanged (auto-tag hover then hover-pickup, FOCUS-gated). No other installed mod wraps or replaces any of these. CRASH-SAFETY CONSTRAINT (keep it this way): all custom work is game-thread (DelaySystem ticks + player-object attach); GetEntityList / IsVisibleTarget / GetLookAtObject only READ engine state; NO per-arbitrary-entity GameObject.OnGameAttached / streaming / entity-lifecycle hook — that is the redDispatcher worker-thread heap-corruption class, structurally excluded (evidence: wikis/modding/scanner-suite-crash-analysis.md). All added state session-transient (never saved). Debug probes DebugProbeLootWhileScanning / DebugProbeAutoPickup / DebugProbeAutoTagSweep (keep false for play). Plans + research dossiers at wikis/modding/: scan-mode-auto-pickup.md, scanner-suite-refinements.md, constant-auto-loot-research.md, plan-unified-auto-loot.md.
DESC: Scan-mode + auto-loot suite — keeps the vanilla loot prompt usable while scanning; auto-tags loot-bearing collectables ALWAYS — normal gameplay and scan mode alike, armed at player attach (sweep within 100 m, LINE OF SIGHT required on every channel — no through-wall tagging, occluded loot tags the moment it is seen; quality floor Common = anything carrying loot, once per entity via the vanilla tag path); and a constant 360° auto-loot vacuum (in and out of scan mode, every 0.5 s, ALL loot classes via GetEntityList) with TWO-TIER reach: within 12 m loot is collected only in LINE OF SIGHT (never through walls — the mod accelerates looting, it does not acquire the inaccessible), and a 4 m inner bubble skips the LOS check purely to absorb its false negatives (clipped corpses, floor items, closed lids); quest items never auto-taken (hard rule), iconic/HMG/sound policy knobs, once-per-entity ledger — each feature independently toggleable in the .reds.

### Gameplay: Custom Enemy Overhaul
COMPAT: ✅ REDscript only (locally authored, pure @wrapMethod/@addMethod/@replaceMethod .reds — no RED4ext/CET/Codeware/ArchiveXL/TweakXL; macOS-safe)
STATE: ENABLED
URL: — (custom local mod, not from Nexus)
TOTAL DLS: —
FILES: r6-scripts/custom-enemy-overhaul/EnemyOverhaul.Common.reds, r6-scripts/custom-enemy-overhaul/EnemyOverhaul.TierUprank.reds, r6-scripts/custom-enemy-overhaul/EnemyOverhaul.Duplication.reds, r6-scripts/custom-enemy-overhaul/EnemyOverhaul.AggroRange.reds
NOTE: CUSTOM MOD authored locally — not a Nexus download, nothing in downloaded/. Four .reds under one slug/module namespace EnemyOverhaul. EnemyOverhaul.Common.reds = shared infra (eligibility composite EO_IsEligibleCombatHuman, once-per-entity FIFO ledgers via @addField on HUDManager, EO_Notify HUD+FTLog funnel — passive, no hooks of its own); the three feature files each own a clearly-marked USER CONFIG block at the top (per-feature toggle + tunables; edit literal + relaunch) with DebugNotify default ON (true). F1 TierUprank: a self-re-arming DelaySystem sweep armed from PlayerPuppet.OnGameAttached rolls 30% to bump one eligible combat-human enemy up one rarity tier (Trash→Weak→Normal→Rare→Officer→Elite; replays the rarity stat block + PowerLevel/Level +2 + health-pool re-sync preserving damage fraction; once per entity per session; badge unchanged by design). F2 Duplication (experimental spawn path, gated on its in-game probe — test plan in sprint/install-report.md): 20% to spawn a same-record transient clone via PreventionSpawnSystem.RequestUnitSpawn on navmesh-validated placement, harvested by requestID ticket match, deferred game-thread hostility wiring; the clone is reward-suppressed (AwardsExperience false, DropHeldItems suppressed, corpse RemoveAllItems + DisableKillReward). F3 AggroRange: clean-room port of Enemy Aggro Improvements (Nexus 19351) — 2 @replaceMethod + 3 @wrapMethod on ReactionManagerComponent/StimBroadcasterComponent/PlayerPuppet widening gunshot/explosion/combat-stim aggro (danger 35 m, gunshot/explosion fallback 50 m, district-aware). COLLISION: F1+F2 both @wrapMethod PlayerPuppet.OnGameAttached (also wrapped by custom-scanner-suite / custom-switch-speed / street-vendors — wraps chain, benign); F3's two @replaceMethod (ReactionManagerComponent.ShouldIgnoreCombatStim 8-arg + ShouldHelpTargetFromSameAttitudeGroup) have no other replacer in the vault — check here before installing enemy-AI/reaction mods. CRASH-SAFETY CONSTRAINT (keep it this way): all per-entity work is game-thread (DelaySystem ticks + player-object attach + GetNPCsAroundObject/GetEntityList enumeration); NO per-arbitrary-entity GameObject.OnGameAttached / streaming hook. All added state session-transient (no persistent, no @addField on PlayerPuppet, no AddSavedModifier). Source + plans + acceptance + research dossiers under sprint/ (impl/custom-enemy-overhaul, plan-*.md, acceptance-*.md).
DESC: Locally-authored enemy combat overhaul — three independently-toggleable REDscript features: ~30% chance an eligible combat enemy upranks one rarity tier (bigger health pool + PowerLevel/Level bump, once per entity), ~20% chance an eligible enemy is duplicated into a reward-suppressed transient clone (no XP, no loot), and a clean-room port of Enemy Aggro Improvements (Nexus 19351) widening gunshot/explosion/combat-stim aggro ranges; per-feature USER CONFIG block in each .reds, debug notifies default on.

### Characters: Judy's Face Beautified - 4K Complexion Makeup and Eyebrows
COMPAT: ✅ raw .archive only (verified in zip: single archive/pc/mod/basegame_coralinekoralina_complexion_judy_02.archive, no .xl/ArchiveXL, no .dll — macOS-safe; Nexus Requirements: none listed)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/2570
TOTAL DLS: 438,843
FILES: archive-mod/basegame_coralinekoralina_complexion_judy_02.archive
NOTE: Installed the "no additional freckles" variant v1.0 (22.3MB, texture-only) — mutually exclusive with the "Judy Beautified" original (added freckles); swap = uninstall + install the other file. 4K only — no 2K file exists, so the standing 2K rule does not apply. Author install path is exactly archive/pc/mod/. Replaces Judy's complexion, makeup, eyebrows + normal maps (both makeup and no-makeup complexions edited). No ### filename prefix → default alphabetical load order. Protected by omission: mod 14999's zz-NPCs-Judy.archive is deliberately not deployed so it cannot overwrite this. Judy Enhanced Body (mod 10150) sorts ahead of this archive but owns BODY mesh/texture only — disjoint asset sets, so the complexion survives.
DESC: Replaces vanilla Judy's complexion, makeup, and eyebrows with 4K custom edits (cleaned variant: no additional freckles).

### Characters: Eyes LOD Fix - No more disappearing eyes
COMPAT: ✅ raw .archive only (verified in zip: single archive/pc/mod/EyesLODFix.archive, no .xl/ArchiveXL, no .dll — macOS-safe; Nexus Requirements: none listed)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/2865
TOTAL DLS: 328,846
FILES: archive-mod/EyesLODFix.archive
NOTE: Single main file v2.2 (58KB, "redone with the files from 2.2"); the page's Old files section still offers v1.6 — not used. Download is a .7z (eyes-lod-fix.7z), extracted with macOS bsdtar/libarchive. Compatible with all eyes mods (Kala's Eyes, Unique Eyes, Heterochromia — none installed here). Also forces the high-quality eye model for V in photomode. A separate variant exists for the Nibbles cat (mod 5664, not installed). Author caveat: the disappearing-eyes issue can still occur with mods that extend camera boundaries (none installed).
DESC: Fixes vanilla eyes disappearing when the camera pulls too far away, so faces keep their eyes at distance and in photomode.

### Characters: High Res Unnamed NPC Faces - MonstrrMagic Texture Series
COMPAT: ✅ raw .archive only (verified in zip: single archive/pc/mod/ZZ-NPCFaces2K.archive, no .xl/ArchiveXL, no .dll, no .reds — macOS-safe; Nexus Requirements: none listed)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/7089
TOTAL DLS: 286,154
FILES: archive-mod/ZZ-NPCFaces2K.archive
NOTE: Installed the 2K MAIN file "High-Res NPC Faces 2K" v1.0 (1.4GB download, 1.36 GB deployed) per the standing 2K-over-4K rule — the only other file is the optional 4K (3.5GB), which the author warns has "a pretty big VRAM hit" given how many unnamed NPCs there are. Download is a .7z (high-res-unnamed-npc-faces.7z). All generic/unnamed NPC faces, AI-upscaled 4x via chaiNNer+ESRGAN. Ships a "ZZ-" filename prefix BY DESIGN so other mods overwrite it (see the archive load-order caution) — do NOT rename it. No REDMod variant exists (the author dropped REDMod after CDPR disabled it for Phantom Liberty / 2.0). Covers UNNAMED NPCs only → no overlap with the named-NPC pack (mod 14999) or Judy's Face Beautified (mod 2570). DOWNLOAD CAVEAT: >500MB → Nexus shows the "Standard download" vs "Resumable download (Beta)" modal after Slow download; click "Standard download".
DESC: AI-upscaled 2K retexture of every generic/unnamed NPC face in the base game.

### Characters: High Res Named NPCs AIO - MonstrrMagic Texture Series
COMPAT: ✅ raw .archive only (verified in zip: 42 files, ALL archive/pc/mod/*.archive, no .xl/ArchiveXL, no .dll, no .reds — macOS-safe; Nexus Requirements: none listed)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/14999
TOTAL DLS: 252,426
FILES: archive-mod/zz-Johnny 2.0.archive, archive-mod/zz-NPC-Panam.archive, archive-mod/zz-NPC-Ripperdoc.archive, archive-mod/zz-NPC-Wakako.archive, archive-mod/zz-NPCs-8ug8ear.archive, archive-mod/zz-NPCs-Alt.archive, archive-mod/zz-NPCs-Clair.archive, archive-mod/zz-NPCs-Dakota.archive, archive-mod/zz-NPCs-Delamain.archive, archive-mod/zz-NPCs-Denny.archive, archive-mod/zz-NPCs-Dex.archive, archive-mod/zz-NPCs-Dino.archive, archive-mod/zz-NPCs-DumDum.archive, archive-mod/zz-NPCs-ElCoyoteBarman.archive, archive-mod/zz-NPCs-Evelyn.archive, archive-mod/zz-NPCs-Fingers.archive, archive-mod/zz-NPCs-Hanako.archive, archive-mod/zz-NPCS-Jackie.archive, archive-mod/zz-NPCs-Josh.archive, archive-mod/zz-NPCs-Karina.archive, archive-mod/zz-NPCs-Kerry.archive, archive-mod/zz-NPCs-Mama.archive, archive-mod/zz-NPCs-Misty.archive, archive-mod/zz-NPCs-Nancy.archive, archive-mod/zz-NPCs-Oda.archive, archive-mod/zz-NPCs-Ozob.archive, archive-mod/zz-NPCs-Placide.archive, archive-mod/zz-NPCs-River.archive, archive-mod/zz-NPCs-Rogue.archive, archive-mod/zz-NPCs-Royce.archive, archive-mod/zz-NPCs-Saburo.archive, archive-mod/zz-NPCs-Saul.archive, archive-mod/zz-NPCs-Sebastian.archive, archive-mod/zz-NPCs-T-Bug.archive, archive-mod/zz-NPCs-Takemura.archive, archive-mod/zz-NPCs-Thiago.archive, archive-mod/zz-NPCs-Thompson.archive, archive-mod/zz-NPCs-Us Cracks.archive, archive-mod/zz-NPCs-Weldon.archive, archive-mod/zz-NPCs-Wilson.archive, archive-mod/zz-NPCs-Yorinobu.archive
NOTE: 41 of the pack's 42 archives deployed — **zz-NPCs-Judy.archive (49.1MB) DELIBERATELY NOT INSTALLED** (user spec: must not erase the Judy texture from mod 2570 Judy's Face Beautified). The pack ships one discrete archive per NPC, so omitting the file is a total guarantee and needs no load-order reasoning; the skipped archive is recoverable from downloaded/high-res-named-npcs-aio.7z if ever wanted. (Backstop, not relied on: the `zz-` prefix means these LOSE conflicts anyway — alphabetically-first loads last and wins, so `basegame_coralinekoralina_complexion_judy_02` would beat `zz-NPCs-Judy` regardless.) FILE CHOICE: the OPTIONAL "Manual Install - Named NPCs AIO 2K" v1.01 (1.3GB) — the author's designated non-mod-manager path; the newer v1.2 MAIN files are FOMOD "Vortex Install" packages (no mod manager on macOS). 2K over 4K per the standing rule (the 4K manual file is 3.7GB). Download is a .7z (high-res-named-npcs-aio.7z); the downloaded filename is "Named NPCs AIO 2K-14999-…" — it does NOT carry the "Manual Install - " page-label prefix (a grab glob of that label times out). No REDMod variant exists. Do NOT rename the zz- prefixes — they exist so other mods win. Named NPCs only → no overlap with mod 7089 (unnamed NPC faces) or mod 1436 (NPC body textures). DOWNLOAD CAVEAT: >500MB → click "Standard download" on the large-file modal.
DESC: AI-upscaled 2K retexture of 42 named base-game NPCs (Johnny, Panam, Jackie, Takemura, Rogue…), installed without the Judy archive so Judy's Face Beautified keeps her complexion.

### Miscellaneous: Panam scar and freckles
COMPAT: ✅ raw .archive only (verified in the downloaded zip: single archive/pc/mod/basegame_panam_noscar.archive, no .xl/ArchiveXL, no .dll, no .reds — macOS-safe; Nexus Requirements: none listed)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/1470
TOTAL DLS: 65,663
FILES: archive-mod/basegame_panam_noscar.archive
NOTE: Installed the OPTIONAL file **"Panam scar cleanup"** v1.1 (10KB): scar removed, FRECKLES KEPT ("Just the scar removal"). Ships a single archive/pc/mod/basegame_panam_noscar.archive (20KB on disk) — note the archive is named `basegame_panam_noscar`, NOT the `basegame_panam_cleanup` that the MAIN file's preview shows. Three mutually-exclusive alternatives remain on the page (all v1.1, all pure `.archive`, so any swap is a one-step uninstall+install): MAIN "Panam cleanup" 1.0MB = scar + freckles + pimples + moles; MAIN "Upscaled cleanup full" 1.0MB = same, with upscaled facial textures; OPTIONAL "Panam face cleanup" 1.0MB = face cleanup only, scar KEPT. LOAD ORDER: `basegame_panam_noscar.archive` sorts BEFORE `zz-NPC-Panam.archive` (mod 14999) → first alphabetically = loaded LAST = winner, so this mod wins; but at 20KB it carries only the scar-removal asset, so the pack's 2K AI-upscaled Panam face survives everywhere the patch does not touch. Mod 10237's `Panam - *` archives sort ahead of this one and beat it. Not asset-inspected inside the .archive — if Panam's face ever looks lower-res, the pack's zz-NPC-Panam.archive is the thing being overridden.
DESC: Removes Panam's bullet scar, along with freckles, pimples and moles on her face.

### Characters: Panam Reimagined
COMPAT: ✅ raw .archive only (verified in BOTH downloaded zips: every option folder ships a ready `archive/pc/mod/*.archive` — no .xl/ArchiveXL, no .dll, no .reds, no TweakXL yaml; only extra files are the fomod/*.xml installer manifest + a readme, both inert on macOS. Nexus Requirements list only "Panam scar and freckles" (mod 1470), itself ✅ raw .archive and now ENABLED, so no ❌ dep.)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/10237
TOTAL DLS: 214,932
FILES: archive-mod/Panam - Prettier Face.archive, archive-mod/Panam - Alternate Hair.archive
NOTE: TWO files downloaded, ONE archive deployed from each (both are plain folder trees, NOT opaque Vortex packages — no FOMOD installer needed on macOS; pick an option folder, drop its .archive). Hard dep = mod 1470 (ENABLED). **(1) FACE+EYES** — from MAIN "Panam Reimagined - FOMOD Compatible" v2.3 (185.6MB): deployed `Panam - Default Faces Eye Colors/Panam - Default Face Brown Eyes/archive/pc/mod/Panam - Prettier Face.archive` (667,648 B, md5 b3c1fc166c70f0ffe693af68df22aca4) = DEFAULT face, BROWN eyes. The eye colours are NOT separate Nexus files — all 12 Default-Face colours (Arasaka Corpo, Blue, Brown, CPU, Green, Grey, Light Blue, Light Green, Lizard, Violet, White, Yellow) are option FOLDERS inside the one 185.6MB file, and the "Panam - Alternate Face Eye Colors" branch (13 more) is the other face. SWAP = one step: drop a different colour folder's `Panam - Prettier Face.archive` over the deployed one. **(2) HAIR** — MAIN "Alternate HairStyles" v1.1 (27.4MB): deployed `[NEW]Panam - Dreads Ponytail (V2)/archive/pc/mod/Panam - Alternate Hair.archive` (5,693,440 B, md5 3e03b9dca651b75b85e40dbb2cf1098e). 15 styles ship inside that one file (DefaultHair, Dreads Ponytail, [NEW] Dreads Ponytail V2, Braided Ponytail (+V2), Long Straight Hair (+V2/Alternate), Long Curly, Parted Curly (Concept Art/V1), Short Curly, Short Straight Hair, Short Straight Ponytail, Side Dreads Undercut) — swap = deploy another folder's archive. NOT installed: MAIN "Concept Art Hair" v1.0, OPTIONAL "Long Straight Hair (Brown)" v1.0, OPTIONAL "Panam Reimagined (Previous Face)" v2.9. The FOMOD zip ALSO bundles the same hair set; both files ship an identically-named `Panam - Alternate Hair.archive` — only one may be deployed. The two deployed archives have DISTINCT filenames (`Panam - Prettier Face` = face mesh + eyes, `Panam - Alternate Hair` = hair) so they coexist with no collision. Author aside: "Nibbles to NPCs 2.0" gives accurate Dreads Ponytail physics in Photomode — an AMM/CET add-on (❌ macOS), cosmetic/photomode-only, NOT a requirement; the hair works without it. LOAD ORDER: both archives start with uppercase `P` (ASCII 80), sorting BEFORE `basegame_panam_noscar.archive` (mod 1470, `b`=98) and `zz-NPC-Panam.archive` (mod 14999, `z`=122) → first alphabetically = loaded LAST = winner, so BOTH beat the pack's 2K upscaled Panam face and 1470's scar patch on any shared asset. Stacking with 1470 is INTENDED by the author (Nexus lists it as a hard requirement), and 1470's archive is only 20KB (scar asset only) vs this mod's 667KB face mesh, so the overlap surface is narrow.
DESC: A variety of new alternate hairstyles and eye colors for Panam, complemented by a subtle modification to her head model (smaller chin, cheekbone and eye edits).

### Visuals and Graphics: Realistic Map
COMPAT: ✅ raw .archive only (verified in the downloaded zip: single archive/pc/mod/RealisticMap4K.archive, no .xl/ArchiveXL, no .dll, no .reds — macOS-safe; Nexus Requirements: none listed)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/17811
TOTAL DLS: 470,422
FILES: archive-mod/RealisticMap4K.archive
NOTE: Installed the MAIN file **"Realistic Map 4K" v1.0.0** (15.3MB) — chosen by the standing RESOLUTION rule, which overrides the most-DLs rule: no 2K file exists, so 4K is the lowest rung on this mod's ladder (the 16K file is the page's most-downloaded, deliberately passed over). The 4 main files are PURE RESOLUTION VARIANTS of one another (all v1.0.0, all including "the fix for specific 50 series driver issues") and MUTUALLY EXCLUSIVE — the author: "**Important**: If you're switching between resolutions, make sure you delete the other ones and only keep the one you want." Alternatives: "Realistic Map 16K" (238.8MB), "Realistic Map 8K" (61.1MB), "Realistic Map 32K" (932.7MB — would also trip the >500MB large-file modal). Author's guidance backs the low pick: "Higher resolutions can add loading times when opening the map." Deployed filename matches the author's documented expectation ("There now should be a file called 'RealisticMap4K.archive'"). Nexus flags "Some files not scanned" on this page. NO CONFLICT with Always Best Quality (mod 12700): that mod's AIO build would also touch the MAP category, but only its Ads-only module is deployed here, so nothing else claims the map. LOAD ORDER: `RealisticMap4K.archive` (`R`=82) sorts after `Always_Best_Quality_Ads` (`A`), `!_Tyger_Claws_*` (`!`) and the `###-` archives, but before every lowercase/`zz-` archive; nothing else in the portal replaces map textures.
DESC: Replaces the default in-game map with a detailed high-res 2D render of the actual map (4K resolution variant installed; 8K/16K/32K also offered).

### Visuals and Graphics: Always Best Quality _ Ads - Map - Hud - Photo Mode - Vending Machines and more
COMPAT: ✅ raw .archive only (verified in the downloaded zip: single archive/pc/mod/Always_Best_Quality_Ads.archive, no .xl/ArchiveXL, no .dll, no .reds — macOS-safe; Nexus Requirements: none listed)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/12700
TOTAL DLS: 776,971
FILES: archive-mod/Always_Best_Quality_Ads.archive
NOTE: Installed the OPTIONAL file **"Always_Best_Quality_Ads For 2.31" v4.0.2.31** (65KB) — author's blurb: "Only ads category." Forces ads to always render at their best quality/LOD (no low-res pop-in). The "For 2.31" build matches this vault's game (v2.3/2.31). THE MAIN AXIS: MAIN "Always_Best_Quality For 2.31" v4.0.2.31 (855KB) is the "All in one archive file" covering the FULL scope the mod title advertises (ads + map + hud + photo mode + vending machines + web sites) and is a strict SUPERSET of the installed Ads-only file — the two are alternatives, do NOT run both. **If the wider map/hud/photo-mode/vending-machine coverage is wanted, this is a one-step swap** — delete Always_Best_Quality_Ads.archive and deploy the AIO's archive instead. Also not installed: OPTIONAL "Always_Best_LOD_Ads_Test" v2.1.0.7 (68.6MB — an explicit test build). MISC REDmod builds all SKIPPED WITH CAUSE ("Always_Best_Quality_REDmod For 2.31", "Always_Best_Quality_Ads_REDmod For 2.31", "Always_Best_LOD_Ads_Test_REDmod"): REDmod packaging needs a REDMod deploy step that the macOS toolchain (launch_modded.sh) does not run — same reason Street Vendors (mod 2894) is pinned to its pre-2.0 redscript-only build. LOAD ORDER: `Always_Best_Quality_Ads.archive` (`A`=65) is the earliest-sorting letter in the portal apart from the `!`/`#`-prefixed ones → first alphabetically = loaded LAST = winner, so it beats the lowercase/`zz-` archives on any shared asset but LOSES to `!_Tyger_Claws_*` (`!`=33) and `###-NovaLUT4`/`###-PreemScanner-Pure` (`#`=35). It targets ad-billboard LOD/quality only, which no other installed mod claims (HD Reworked Project is a general texture overhaul on a lowercase-`H` archive that this one would beat on any overlap).
DESC: Forces ads to always display at their best quality/LOD instead of low-res versions (ads-only module of a mod that can also cover map, HUD, photo mode, vending machines and web sites).

### Visuals and Graphics: Preem Scopes (Remove Tint Glitches Scanlines and 3D Depth Effect - FOMOD)
COMPAT: ✅ raw .archive only (verified in the downloaded zip: single archive/pc/mod/PreemScopes.archive, no .xl/ArchiveXL, no .dll, no .reds — macOS-safe; Nexus Requirements: none listed)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/10021
TOTAL DLS: 1,265,970
FILES: archive-mod/PreemScopes.archive
NOTE: Installed the MAIN file **"Preem Scopes" v0.17.2** (4.0MB) — "Removes clutter and glitch effects from most weapon scopes." Despite the mod TITLE ending in "- FOMOD", this main file is NOT a FOMOD: the zip is a plain single archive/pc/mod/PreemScopes.archive, so no installer/option-picking is involved (the FOMOD build is a separate MISC file). NOT deployed — all optional/misc add-ons, each an independent drop-in that STACKS rather than conflicts (add later by dropping its .archive into archive-mod/): OPTIONAL "Preem Scopes - Smart Weapons" v1.0.0 (smart-weapon background removal); OPTIONAL "Preem Scopes - Binoculars" v1.0.1b (removes vignette/scanlines from the 2.1 viewport/telescope/binocular); OPTIONAL "Preem Scopes - Binoculars with Frame" v1.2.0b (MUTUALLY EXCLUSIVE with the plain Binoculars file — "Added back the frame, fluff, shutter, etc"); MISC "Preem Scopes - FOMOD" v1.0.0 (the option-picking installer build of the same mod, redundant here); MISC "Preem Scopes - No Scope Crosshairs" v1.0.0n. SKIPPED WITH CAUSE: OPTIONAL "Preem Scope - Militech Holosight Compat" v1.0.0 — it "Requires Militech Holosight base mod", a separate Nexus mod not in this vault, so it would be inert/broken; only install it if that base mod is ever added. NO CONFLICT with Preem Scanner (mod 9215, `###-PreemScanner-Pure.archive`): same author, different targets — Scanner = the scan/HUD overlay, Scopes = weapon scope optics — and the filenames are distinct so both coexist. LOAD ORDER: `PreemScopes.archive` (`P`=80) sorts AFTER `###-PreemScanner-Pure.archive` (`#`=35) → the Scanner would win any asset both touched; they do not overlap in practice.
DESC: Removes scope glitches, scanlines, tint, and 3D HUD depth effects from most weapon scopes, and tones down distortion and vignetting.

### Visuals and Graphics: FX Begone (Modular Effects Removal)
COMPAT: ✅ raw .archive only (verified in the downloaded zip: single archive/pc/mod/FXBegone-Inventory.archive, no .xl/ArchiveXL, no .dll, no .reds — macOS-safe; Nexus Requirements: none listed)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/9209
TOTAL DLS: 1,668,368
FILES: archive-mod/FXBegone-Inventory.archive
NOTE: MODULAR MOD — the author ships a MENU of independent per-effect .archive files, NOT mutually-exclusive variants ("I know that there will be others that want to pick and choose the effects they want removed, so I have added separate downloads"). Each module is its own discretely-named archive, so extra modules can be added later as pure drop-ins with no collision and no re-install. Installed OPTIONAL **"FX Begone - Inventory" v1.1.0a** (8KB) — removes inventory and menu glitches. NOT deployed ("not deployed", not "incompatible" — the modules stack; to add any, download it and drop its .archive into archive-mod/): MAIN "FX Begone - Complete" v1.2.1-ALL (497KB) — the all-in-one, but the AUTHOR HIMSELF flags it "Might not be ideal" and lists "time skip, plazma damage, fisheye, fire damage, charge attack, blood spatter, player damage, pain, bleed, dizzy, acid, drugged, electro, poison, npc_sandevistan", i.e. it strips gameplay-relevant damage/health feedback; MAIN "FX Begone - Phantom Liberty DLC" v1.0.0-ALL (52KB — "Separate files, use alongside the main version"; COMPLEMENTARY not exclusive, safe to add if the PL DLC is owned); OPTIONAL Zoom Pixelation v1.0.0g, Fall Blood v1.0.0fb, Holocall v1.0.0f, Damage and Health v1.1.0e, Johnny Glitch v1.1.0b, Cybermask Reduced v1.0.0m, Leeroy Jenkins (Combat Alert Lines) v1.0.0lj, Perks v1.1.0p, Camo v1.0.0camo; MISC Focus Perk v1.0.0, Overclock Perk v1.0.0h. LOAD ORDER: `FXBegone-Inventory.archive` (`F`=70) sorts before every lowercase-named archive and before the `zz-`/`basegame_` ones → first alphabetically = loaded LAST = winner; it targets inventory/menu glitch VFX, which no other installed mod touches.
DESC: Removes a variety of visual effects (Johnny glitches, fall damage, zoom/scope pixelation, drug effects) via modular per-effect archives — the inventory/menu glitch module is the one installed.

### Characters: Immersive NPC Variety - Tyger Claw women - Plus Maiko and Roxanne
COMPAT: ✅ raw .archive only (verified in both zips: base ships single archive/pc/mod/!_Tyger_Claws_gang_NewLook_Females_V1.archive, Maiko add-on ships single archive/pc/mod/!_Tyger_Claws_gang_NewLook_Maiko_V1.archive — no .xl/ArchiveXL, no .dll, no .reds in either — macOS-safe; Nexus Requirements: none listed)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/19217
TOTAL DLS: 198,519
FILES: archive-mod/!_Tyger_Claws_gang_NewLook_Females_V1.archive, archive-mod/!_Tyger_Claws_gang_NewLook_Maiko_V1.archive
NOTE: BASE file "1_Tyger Claws - Unique faces" v1.01 (19.8MB) — the mod's core: 25 NPCs with unique faces + Roxanne Sumner and Taki Kenmochi new looks; explicitly "Does NOT include Maiko". Author install path is exactly archive/pc/mod/. MAIKO ADD-ON: "Maiko New Look - New outfit" v1.02 (10.1MB) = the **high collar shirt + skirt** combo. Its MUTUALLY-EXCLUSIVE alternative is "Maiko New Look - New outfit - Alt version" v1.02 = the **suit jacket + skirt + thigh boots** combo; the page states "ONLY USE ONE OF THE MAIKO VERSIONS", so to swap, delete !_Tyger_Claws_gang_NewLook_Maiko_V1.archive and deploy the Alt file's archive instead (both are Main files, both stamped v1.02 "LOD added"). The add-on is a pure drop-in on top of the base: it ships its OWN discretely-named archive (`..._Maiko_V1` vs the base's `..._Females_V1`), so the two coexist with no filename collision and the base needs no re-install. Author: "Combine with main version (1_Tyger Claws - Unique faces) to use all custom faces the mod offers." LOAD ORDER: the `!_` filename prefix is the author's deliberate choice — `!` (ASCII 33) sorts before `#` and every letter, so first alphabetically = loaded LAST = winner: these archives WIN every texture conflict against all other installed .archive mods. Author's note: "If you want to use texture overhaul mods on these NPCs, just place the texture mod higher in the load order" — i.e. rename with an earlier-sorting prefix. Do NOT rename the `!_` prefix without that intent. Overlap: covers unnamed Tyger Claw females with new custom HEAD meshes, so those heads may not pick up mod 7089's ZZ-NPCFaces2K unnamed-face textures (different asset paths — exactly what the author's load-order note is about); Roxanne/Taki/Maiko are absent from mod 14999's named-NPC pack, so no clash there.
DESC: Replaces the heads used by Tyger Claw female NPCs with 9 new unique custom faces to reduce duplicate faces in Night City, and gives Roxanne Sumner and Taki Kenmochi new looks (plus the Maiko add-on in her high-collar-shirt + skirt outfit).

### Characters: Rogue's New Look
COMPAT: ✅ raw .archive only (verified in the downloaded zip: single archive/pc/mod/BimbosOfNC_Rogue_Younger_Alt.archive (13.8MB), no .xl/ArchiveXL, no .dll, no .reds — macOS-safe; Nexus Requirements: none listed)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/12040
TOTAL DLS: 178,882
FILES: archive-mod/BimbosOfNC_Rogue_Younger_Alt.archive
NOTE: Installed the MAIN file **"Rogue's New Look -YOUNG VERSION-"** v1.00 (13.2MB, custom 4K diffuse map). Every file on the page is stamped "-INSTALL ONLY ONE FILE-", so only this one is deployed; the 3 mutually-exclusive alternatives (all pure `.archive`; any swap = one-step uninstall+install): MAIN "-OLD VERSION-" v1.00 (custom 4K diffuse map); MAIN "-NO CUSTOM TEXTURES-" v1.00 (MESH EDITS ONLY — author: "specifically made for those that really want the OG look of Rogue in terms of her age. This will use the base game textures and will allow you to use ANY custom Rogue texture mod you would like!"); OPTIONAL "-YOUNG- -LIP FILLER VERSION-" v1.01 (a FOMOD offering 7 lip-filler options). The 4K texture is NOT a 2K-vs-4K choice — the mod ships 4K only, so the standing 2K rule does not apply. Scope: only OLD Rogue's visuals change; young Rogue (the Johnny flashbacks) is untouched by design. DOWNLOAD FILENAME CAVEAT: the file lands as "Rogue's New Look -YOUNG--12040-…" — it does NOT carry the page label's "VERSION-" suffix (a grab glob of the full page label would time out). LOAD ORDER: `BimbosOfNC_Rogue_Younger_Alt.archive` sorts BEFORE `zz-NPCs-Rogue.archive` (mod 14999) → first alphabetically = loaded LAST = winner, so this dedicated Rogue mod replaces the pack's 2K AI-upscaled Rogue face — intended (same relationship Misty's New Look has to the pack). Author compatibility: works with mods that change her hair; will NOT work with mods that change anything else about her.
DESC: Changes the face of Rogue along with her head textures, with old and young options (only old Rogue's visuals are affected, not the young flashback Rogue).

### Characters: Misty's New Look  -COLLAB WITH LADYBELLA-
COMPAT: ✅ raw .archive only (verified in zip: single archive/pc/mod/BoNC_Mistys_New_Look.archive, no .xl/ArchiveXL, no .dll, no .reds — macOS-safe; Nexus Requirements: none listed)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/12341
TOTAL DLS: 152,181
FILES: archive-mod/BoNC_Mistys_New_Look.archive
NOTE: Installed the MAIN file "Misty's New Look" v1.01 (13.8MB) — the page's headline file ("integrated the lip makeup into the base texture to fix some clipping issues"). Author install path is exactly archive/pc/mod/. Changes meshes AND textures (custom 4K texture; 4K only — no 2K file exists, so the standing 2K rule does not apply). The alternative main "Misty's New Look No Lipstick" v1.00 is the mutually-exclusive no-black-lipstick take — the black lipstick is the mod's advertised identity ("a more goth look") and the main file matches the page description; TO SWAP: uninstall and install "Misty's New Look No Lipstick". Also not installed: the optional "Misty's New Look -Lip Filler Version-" v1.00 ("identical to the original in all other aspects" — a separate lip-filler taste variant). Author compatibility: WILL work with mods that change her hair & clothes; will NOT work with mods that change her head mesh or textures; lipstick mods will affect her lipstick. LOAD ORDER: `BoNC_Mistys_New_Look.archive` sorts before `zz-NPCs-Misty.archive` (mod 14999) → first alphabetically = loaded LAST = winner, so this dedicated Misty mod replaces the pack's 2K AI-upscaled Misty face — intended. Texture credits: based on Avallonkao's 4K complexion work, custom-edited by LadyBella; mesh work by EKT.
DESC: Gives Misty a more goth look, paler skin, and refines her skin textures with a custom 4K texture (black-lipstick main variant).

### Characters: Misty - Alternate Clothes (and Nudes)
COMPAT: ✅ raw .archive only (ZIP-VERIFIED: 48 entries = 47 × archive/pc/mod/basegame_Misty_*.archive + the dir entry; NO .xl/ArchiveXL, NO .dll, NO .lua, NO fomod/ — macOS-safe. Nexus Requirements: none listed; AMM only OPTIONAL, to lock a look)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/1663
TOTAL DLS: 308,119
FILES: archive-mod/basegame_Misty_Goth.archive
NOTE: Installed v4.0 by Seracen (tagged Sexualised); zip kept at downloaded/misty-alternate-clothes-and-nudes.zip (101MB). **DEPLOYED OUTFIT: `basegame_Misty_Goth.archive` (1.4MB)** — exactly ONE of the zip's 47 mutually-exclusive outfits may be live, per the mod's "PICK ONLY ONE" rule; the other 46 stay in the zip, so a swap is a one-file extract with no re-download. Goth is the coherent partner to the installed companion mod Misty's New Look (mod 12341), which is explicitly "a more goth look" — neither standing rule could pick for us here (the 47 outfits share ONE Nexus DL count, and the zip has NO fomod/ModuleConfig.xml, so the "first-listed plugin" fallback does not exist either). Near-twin `Goth_Strap` (strap variant of the same look) not deployed. THE FULL 47-OPTION MENU (all `basegame_Misty_<name>.archive`): Bomber_Brown, Bomber_Silver, Boxers, Club_Blue, Club_Gold, Club_Gold_v2, Club_Silver, Club_Silver_Bolero, Club_Silver_v2, Dancer_Gold, Dancer_Silver, Dominatrix, Dress_Holo, Goth, Goth_Strap, Guns_Out, Hotpants, Hotpants_Halter, Jeans, Leathers, Lingerie_Corpo, Lingerie_Gold, Lingerie_Hex, Lingerie_Silver, Netrunner_Black, Netrunner_Red, Netrunner_White, Nude, Nude_NoShoes, Pasties, Pasties_Cyberarm, Punk, Raincoat_Bright, Raincoat_Fishnets, Raincoat_Tights_Black, Raincoat_Tights_Silver, Roadie, Solo_Black_Gold, Solo_Blue_Black, Solo_Blue_Gold, Soulkiller, Topless, Trenchoat, Trenchoat_Bootless, Undies, Yoga_Black, Yoga_Blue. TO SWAP: delete archive-mod/basegame_Misty_Goth.archive and extract a different one from the kept zip — never leave two Misty outfit archives live at once. CONFLICT CHECK — CLEAN: no Misty body mod is installed (unlike the sibling Seracen mods 1699/1823, dropped for clashing with the Hyst Panam/Judy BODY mods). The two other live Misty archives are mod 12341 (`BoNC_Mistys_New_Look.archive` = FACE/complexion/lipstick) and mod 14999's `zz-NPCs-Misty.archive` (face texture) — a different asset domain from clothes/body meshes. LOAD ORDER: `basegame_Misty_*` (`b`=98) sorts AFTER `BoNC_Mistys_New_Look` (`B`=66) in raw byte order, so the face mod loads LAST and WINS any overlap — correct, the face mod should keep the face. CAVEAT: without AMM (❌ CET on macOS) a specific look CANNOT be locked — per the sibling Seracen pages, "the look will change naturally throughout the game". PAGE ACCESS: tagged Sexualised → the r.jina.ai digest is empty; read the page in the logged-in browser.
DESC: Replaces Misty's default outfit with one of 47 mutually-exclusive alternatives — clothed (bomber, jeans, netrunner, trenchcoat, yoga, punk…), lingerie, or nude/topless variants; exactly one may be installed at a time.

### Gameplay: No Main Quest Auto-Repin
COMPAT: ✅ REDscript only (locally authored, pure listener-based .reds — macOS-safe)
STATE: ENABLED
URL: — (custom local mod, not from Nexus)
TOTAL DLS: —
FILES: r6-scripts/no-main-quest-auto-repin/NoMainQuestAutoRepin.reds
NOTE: CUSTOM MOD authored locally — not a Nexus download, nothing in downloaded/. Stops the quest tracker from auto-switching (re-pinning) to a MAIN quest after you finish a side quest / gig / NCPD hustle / contract — it clears tracking (goes BLANK) instead, deliberately not restoring the last pin. WHY CUSTOM: the exact-fit Nexus mod "Untrack Quest Ultimate — No Main Quest re-tracking" (mod 6328) requires Cyber Engine Tweaks = ❌ macOS, and no REDscript-only mod does this (the installed Simple Untrack Quest 5177 + Track What You Want 4110 are manual/marker-only). MECHANISM: the auto-repin decision is NATIVE (every scripted JournalManager.TrackEntry caller is UI/user-initiated), so the mod cannot pre-empt it — it REACTS via the journal Tracked listener (JournalManager.RegisterScriptCallback(…, gameJournalListenerType.Tracked)) which fires AFTER the switch, then undoes it with UntrackEntry() DEFERRED to the next game-thread frame via GameInstance.GetDelaySystem().DelayCallbackNextFrame; RunDeferredUntrack re-validates the tracker is STILL a MainQuest before blanking. THE DEFERRAL IS LOAD-BEARING — calling UntrackEntry synchronously inside the Tracked callback is a re-entrant native journal mutation and hard-crashes (the guard flag does not protect against the native re-dispatch); all vanilla Tracked listeners only READ. DISCRIMINATOR (cannot nuke the main quest you're actively on): counters ONLY when the newly-tracked entry resolves to gameJournalQuestType.MainQuest AND the previously-tracked quest was NOT main AND is a DIFFERENT quest AND is now Succeeded/Failed. Main-quest objective advances are the same quest (excluded); main→main handoffs have a main "previous" (excluded); a side quest merely switched-away-from while still Active is not Succeeded/Failed (excluded). Fixers'-Reward auto-track left vanilla; NCPD "blue"/contract tracking untouched; applies everywhere (no prologue/ending exclusion). Known residual false positive (rare, self-healing): manually tracking a main quest in the window after a side quest completed but before the game auto-repins → blanked once; re-tracking sticks. Implementation: @wrapMethod(PlayerPuppet) OnGameAttached (game-thread init, once) + @addField(PlayerPuppet) m_nmqReceiver holding a NoMainQuestAutoRepinWatcher (IScriptable) whose cb OnNMQTrackedChanged does the work + NoMainQuestAutoRepinUntrackCallback extends DelayCallback. CRASH-SAFE: init on the PLAYER object only (no arbitrary-entity OnGameAttached / streaming). Config at top of .reds: NoMainQuestAutoRepinConfig.Enabled() (default true), DebugProbe() (default false). COLLISION: only vanilla quest_tracker.script registers a journal Tracked listener; no other installed mod touches journal tracking. KNOWN GAPS (non-crash, left unfixed for minimal change): (1) Setup() registers but nothing ever UnregisterScriptCallback()s, so orphan watchers accumulate across save-load — harmless (redundant next-frame untracks); a @wrapMethod(PlayerPuppet) OnDetach that unregisters + nulls m_nmqReceiver would close it; (2) a side→blank→main ordering can wipe the cross-callback cache and miss the counter (functional miss only). Research dossier + plan: wikis/modding/quest-tracker-auto-repin-research.md + plan-disable-quest-auto-repin.md.
DESC: Stops the quest tracker from auto-re-pinning to a main quest after you finish a side quest / gig / NCPD hustle / contract — clears tracking (goes blank) instead, so the pin no longer force-jumps to the main story.

### Appearance: Panam Body Enhanced 2.2
COMPAT: ✅ raw .archive only (verified in the downloaded zip: single archive/pc/mod/Panam_Enhanced_Hyst_Body.archive, no .xl/ArchiveXL, no .dll, no .reds, no .asi — macOS-safe; Nexus Requirements: none listed)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/4843
TOTAL DLS: 1,909,715
FILES: archive-mod/Panam_Enhanced_Hyst_Body.archive
NOTE: Installed the SOLE MAIN file **"Panam Enhanced Body" v2.2** (4.9MB) — "UPDATE FOR 2.2+ Game version", matching the installed game; no variant axis exists on this page. NOT installed: OPTIONAL "Panam Surprise Selfie 1.01" — not a variant of the body but a SEPARATE feature (adds a text/photo message during Panam's romance); it can be added later as an independent drop-in, but its page warns it requires uninstalling mod 3941 first (not in this vault). **PARTIAL DEPLOY — the zip ships TWO files, ONE deployed**: (1) `archive/pc/mod/Panam_Enhanced_Hyst_Body.archive` (5,226,496 B) → DEPLOYED, and it alone IS the whole install per the author ("Easy to install: Put 'Panam_Enhanced_Hyst_Body.archive' in Cyberpunk 2077\archive\pc\mod"); (2) `bin/x64/plugins/cyber_engine_tweaks/mods/AppearanceMenuMod/Collabs/Custom Appearances/Panam_Enhanced_Body.lua` → NOT DEPLOYED (Cyber Engine Tweaks / AMM preset; ❌ CET unavailable on macOS, no bin/x64/plugins drop dir exists). AMM is listed under "Compatible mods", NOT requirements, so dropping the lua costs only the optional AMM appearance-preset integration — the body replacer is unaffected. Same pattern as Replace Weapon Mods (mod 15409), which also deploys core-only. Author: "This body is only for Panam! only her is affected!" Scope = body mesh/shape only (big breasts + thicc shape; breast physics in all appearances). If a previous version is ever installed, the author says delete it first. **AUTHOR'S EXPLICIT !!!NOT COMPATIBLE!!! LIST** (verify before installing any of these — all currently ABSENT from this vault): "Custom AMM 4K Texture for Panam" by MaximiliumM, "Panam - Alternate Clothes" by Seracen (mod 1699, dropped), "-KS- UV-NPCs - Panam Unlocked", "Citizen Breast Physics", "Cyber Pink complexion". Other Panam RIG/bodymods are "compatible, but not recommended"; Panam Romanced Enhanced needs its two archives renamed with a `z_` prefix to work alongside this mod (not installed here). NO COLLISION with the 3 other ENABLED Panam mods — this is the only BODY mod; the others own FACE/HAIR: mod 1470 `basegame_panam_noscar.archive` (20KB scar patch), mod 10237 `Panam - Prettier Face.archive` (face mesh + eyes) + `Panam - Alternate Hair.archive`, mod 14999 `zz-NPC-Panam.archive` (2K upscaled face texture). LOAD ORDER: `Panam_Enhanced_Hyst_Body.archive` (`P`=80) sorts BEFORE `basegame_panam_noscar` (`b`=98) and `zz-NPC-Panam` (`z`=122) so it beats both, but AFTER `Panam - Prettier Face`/`Panam - Alternate Hair` (`P`+space(32) < `P`+underscore(95)) so those two beat it — academic, since face/hair/body are disjoint asset sets. PAGE ACCESS CAVEAT: tagged **Sexualised/adult** → `mod-tool.sh info` (r.jina.ai, logged-out) returns an EMPTY digest ("Adult content disabled"); mods/pages/4843-pages.md is nav chrome only. Read the page in the logged-in Claude-in-Chrome browser instead.
DESC: Replaces Panam's body mesh with a curvier custom shape (big breasts, thicc proportions, breast physics in all appearances); affects Panam only, body only — her face and hair are untouched.

### Appearance: Judy Enhanced Body with 4K Texture
COMPAT: ✅ raw .archive only (verified in the downloaded zip: single archive/pc/mod/Judy_Enhanced_Hyst_Body.archive, no .xl/ArchiveXL, no .dll, no .reds, no .asi — macOS-safe; Nexus Requirements: none listed)
STATE: ENABLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/10150
TOTAL DLS: 1,431,720
FILES: archive-mod/Judy_Enhanced_Hyst_Body.archive
NOTE: Installed the SOLE MAIN file **"Judy Enhanced Body with 4K Texture" v1.0.4** (16.7MB) — same author (Hyst / Dr Hysto) and same shape as Panam Body Enhanced (mod 4843); no variant axis, one main file only. **The description's "2 Variants (natural and push up look)" is NOT a deploy-time choice** — the zip contains exactly ONE archive and NO fomod/ModuleConfig.xml and no option folders, so the two looks are selected in-game (via the AMM appearance collab), not by picking a file. RESOLUTION: 4K only — no 2K file exists, so the standing 2K-over-4K rule has nothing lower to take. NOT installed: OPTIONAL "Judy_ADDON_Lingerie_and_nude_after_shower" v0.0.1 — an ADD-ON, not a variant ("MUST BE INSTALLED WITH THE MAIN FILE !!!"): replaces the panties appearance with a lingerie outfit and the after-shower appearance with sexy pantie + topless; it can be added later as an independent drop-in. **PARTIAL DEPLOY — zip ships TWO files, ONE deployed**: (1) `archive/pc/mod/Judy_Enhanced_Hyst_Body.archive` (17,711,104 B) → DEPLOYED, and it alone IS the whole install per the author; (2) `bin/x64/plugins/cyber_engine_tweaks/mods/AppearanceMenuMod/Collabs/Custom Appearances/Judy_Enhanced_Body.lua` → NOT DEPLOYED (CET/AMM preset; ❌ CET unavailable on macOS, no bin/x64/plugins portal exists). AMM is a listed compatibility, NOT a requirement — dropping the lua costs only the AMM preset integration (and plausibly the in-AMM natural/push-up switch), not the body replacer. Identical structure + treatment to mod 4843. Scope: "This body is only for Judy Alvarez! only her is affected!" — unique chest (slightly bigger than vanilla, deliberately not huge to avoid arms-crossed clipping), 4K body texture, 3D genital by xbeabsae, tattoo-decal fixes, vanilla neck-flickering fix. Author: she will NOT be affected by rig-deform/chest mods. Known issue (author, reduced to "unnoticeable"): slight stuttering when outside ~20m from Judy's apartment. **⚠ AUTHOR-DECLARED SOFT CONFLICT WITH AN INSTALLED MOD — "NPCs Gone Wild" (mod 1436) is on this page's "Mods that can make conflict!" list** (full list: citizen_breast_physics, Npcs Gone wild, Judy - Alternate Clothes, Judy Day and Night 73 Appearances for AMM; plus a general "some mods that use judy.app file can conflict"). KEPT ANYWAY — deliberate: (a) the wording is the SOFT "can make conflict", NOT the hard "!!!NOT COMPATIBLE… you have to remove them before using my mod!!!" the same author uses on the Panam page — a texture/asset-override caution, not an incompatibility; (b) the vault runs the tamer **MILD** variant of 1436, which touches only NPC BASE body textures for a small portion of female NPCs, whereas this mod gives Judy a DEDICATED body mesh + her own 4K texture; (c) load order resolves any overlap in this mod's favour. If Judy's body ever renders wrong, mod 1436 is the first suspect. LOAD ORDER (byte order — NOTE macOS default `sort` is case-insensitive and gives the WRONG answer; use `LC_ALL=C sort`): `Judy_Enhanced_Hyst_Body.archive` (`J`=74) sorts BEFORE `basegame_00NPC_GM.archive` (mod 1436, `b`=98) and `basegame_coralinekoralina_complexion_judy_02.archive` (mod 2570, `b`=98) → first alphabetically = loaded LAST = winner, so this mod WINS against both. NO REAL CONTENTION WITH JUDY'S FACE BEAUTIFIED (mod 2570) despite it losing the sort: that mod is texture-only on FACE paths (complexion/makeup/eyebrows + normal maps) while this one owns BODY mesh/texture — disjoint asset sets, so her beautified complexion survives. Mod 14999's `zz-NPCs-Judy.archive` is deliberately not deployed, so it cannot interact. PAGE ACCESS CAVEAT: tagged **Sexualised/Pornographic/adult** → the r.jina.ai digest is EMPTY ("Adult content disabled"); mods/pages/10150-pages.md is nav chrome only. Read the page in the logged-in Claude-in-Chrome browser instead.
DESC: Gives Judy Alvarez a unique custom body — reworked chest slightly larger than vanilla, 4K body texture, tattoo-decal and neck-flicker fixes; affects Judy only, body only, leaving her face untouched.

### Appearance: NPCs Enhancement - Hyst Bodies
COMPAT: ✅ per the compat rule (Nexus Requirements: none listed; author's install is a plain game-folder extract = raw .archive, and the same author's mods 4843/10150 both proved to be pure archive/pc/mod + an inert CET lua). NOT zip-verified — see STATE: the mod was never downloaded, so re-verify the extracted tree before any future deploy.
STATE: NOT INSTALLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/9887
TOTAL DLS: 754,136
FILES: —
NOTE: **DROPPED — deliberately not installed. No decision outstanding.** Mutually-exclusive conflict with NPCs Gone Wild (mod 1436, STATE=ENABLED), settled by the standing most-DLs rule at mod level: **1436 = 1,940,308 total DLs vs this mod's 754,136**, so the already-installed mod wins. TO REVERSE: `/disable` 1436, then `/install` this, and at that point resolve the 5-body-shape axis below. WHY IT IS A REAL BLOCK (whereas the same author's Judy mod 10150 was installed despite also naming 1436): (a) WORDING — 10150 uses the SOFT "Mods that can make conflict!", this page carries the author's HARD banner "**!!! MODS NOT COMPATIBLE OR CAN MAKE CONFLICT !!! (if installed them you have I recommend to remove them before using my mod)**" naming **"Npcs Gone Wild"** (full list: Citizen Breasts physics, Naked Sexworker, Naked Tube Dancer, Npcs Gone Wild, CBP_NPCEHB, "and maybe others.."); (b) SCOPE — this mod and 1436 target the **same asset domain**: generic/unnamed female NPC bodies (this refits body MESHES + clothes; 1436 replaces the base body TEXTURES those NPCs use); (c) load order therefore CANNOT separate them — a Hyst body mesh drawing 1436's altered base-body texture is a mesh/texture mismatch, not a clean win, so no `!`/`##`/`zz-` prefix trick fixes it. PRE-RESOLVED FOR A FUTURE INSTALL: FILE = the SOLE MAIN file **"Hyst_NPCs_Enhancement" v1.0.3** (129.6MB) — no variant axis at file level (the page header still reads 1.0.2). Install = "extract zip file 'Hyst NPCs Enhancement' in your Cyberpunk 2077 game folder"; no >500MB modal at 129.6MB. **UNRESOLVED TASTE AXIS**: the description advertises **5 body variants — Big Breast Push up (EBBP), Big Breast Standard (EBB), Big Breast Natural (EBBN), Big Butt, Vanilla Big breast** — which are NOT separate Nexus files (one download, ONE DL count for the lot), so the most-DLs rule cannot pick; resolve from the author's manifest at install time (fomod/ModuleConfig.xml first-listed plugin in a SelectExactlyOne group, per the method used for Panam Reimagined mod 10237) or ask the user. Breast physics included. Author states FULLY compatible with **Panam Body Enhanced (mod 4843)** and **Judy Enhanced Body (mod 10150)** — both ENABLED here — since those cover main NPCs and this covers the rest; also compatible with AMM (❌ CET on macOS — cosmetic loss only). OVERLAP TO CHECK IF EVER INSTALLED (not blockers): it restyles **Roxanne** and **female gangs**, while the ENABLED Tyger Claw women (mod 19217) gives Roxanne Sumner a new look and owns Tyger Claw females via `!_Tyger_Claws_*.archive`, whose `!_` prefix (ASCII 33) sorts first and WINS unless deliberately re-prefixed. Coverage (Night City): Skye, Rita Wheeler, Roxanne, JigJig Street Joytoy, Luxury Joytoy, prostitutes, dancers, casual NPCs, holograms, female gangs; (Dog Town): 3 random NPCs, 3 prostitutes, 1 bartender, 4 holograms. Page states "WORK ON 2.1+ UPDATE". PAGE ACCESS CAVEAT: tagged **Sexualised/adult** → the r.jina.ai digest is EMPTY; mods/pages/9887-pages.md is nav chrome only. Read the page in the logged-in Claude-in-Chrome browser instead.
DESC: Gives ~20+ Night City and Dog Town NPCs (Joytoys, prostitutes, dancers, holograms, female gangs, Skye, Rita Wheeler, Roxanne) the author's custom body meshes with refitted clothes, plus subtle hair/outfit reworks, in a choice of 5 body shapes.

### Characters: Panam - Alternate Clothes
COMPAT: ✅ per the compat rule (Nexus Requirements: none listed; author's install is "place desired .archive files into Cyberpunk 2077\archive\pc\mod" = raw .archive; AMM is explicitly OPTIONAL, only needed to LOCK one look). NOT zip-verified — never downloaded, see STATE.
STATE: NOT INSTALLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/1699
TOTAL DLS: 406,452
FILES: —
NOTE: **DROPPED — deliberately not installed. No decision outstanding.** Mutually-exclusive conflict with Panam Body Enhanced 2.2 (mod 4843, STATE=ENABLED), settled by the standing most-DLs rule at mod level: **4843 = 1,909,715 total DLs vs this mod's 406,452**, so the already-installed body mod wins. TO REVERSE: `/uninstall` 4843, then `/install` this. **THIRD PATH if Panam's enhanced body AND alternate outfits are both wanted**: install "Alternative Clothes for Panam Body Enhanced" (the same wardrobe concept re-authored FOR the Enhanced body, linked as "NEW!!" under 4843's "Compatible mods") — not in this vault, needs its own `/install`. WHY THEY GENUINELY CANNOT COEXIST: 4843 replaces Panam's BODY MESH and refits her clothing to that new body, while this mod replaces the same clothing meshes built for the VANILLA body — both own Panam's body/clothes mesh assets, so they fight over the same slots and produce clipping/mangled geometry rather than a clean load-order win. Mod 4843's page names this mod on its hard incompatibility banner explicitly and by author ("Panam - Alternate Clothes by Seracen"; verified match — this page's Created-by is Seracen). PRE-RESOLVED FOR A FUTURE INSTALL: FILE = the most-downloaded main file **"Panam - Wardrobe Collection" v4.0** (153.1MB, "Collection of all my Panam outfits"). NOT it: UPDATE "Panam - Alternate Clothes (Experimental)" v5.0 (two experimental archives using "the old method", "USE ONLY ONE ARCHIVE!!!"); MISC LOD patches (All 10x, Cinematic 10x, Cinematic 5x); the many Old per-outfit files (superseded by the Wardrobe Collection). ALSO NOTE the OPTIONAL "Panam - No Scars" v1.0 ("Works stand-alone") would COLLIDE with the ENABLED mod 1470 (both remove Panam's scar) — keep it skipped. **UNRESOLVED TASTE AXIS**: the Wardrobe Collection is ONE 153.1MB download containing MANY outfit .archives with "**PICK ONLY ONE OPTION**" / "ONLY USE ONE OUTFIT AT A TIME! Please remove any unwanted archives!" — one Nexus DL count for the lot, so the most-DLs rule cannot choose an outfit; resolve from the author's manifest at install time or ask the user. Author caveats for that install: without AMM (❌ CET on macOS) a specific look CANNOT be locked — "the look will change naturally throughout the game" (the no-jacket/no-harness variants specifically need AMM to pin); minor clipping possible in some clothes combinations; small variations from the image gallery since update 4.0; Alt Jacket asset provided by "Symmetrical Alt Jacket for femV". PAGE ACCESS CAVEAT: tagged **Sexualised/adult** → the r.jina.ai digest is EMPTY; mods/pages/1699-pages.md is nav chrome only. Read the page in the logged-in Claude-in-Chrome browser instead.
DESC: Offers a wardrobe of alternate outfit options for Panam (rocker, runner, Aldecaldos and more, with jacket/harness variations), one outfit archive at a time.

### Characters: Judy - Alternate Clothes
COMPAT: ✅ per the compat rule (Nexus Requirements: none listed; author's install is "place desired .archive files into Cyberpunk 2077\archive\pc\mod" = raw .archive; AMM is explicitly OPTIONAL, only needed to LOCK one look). NOT zip-verified — never downloaded, see STATE.
STATE: NOT INSTALLED
URL: https://www.nexusmods.com/cyberpunk2077/mods/1823
TOTAL DLS: 379,845
FILES: —
NOTE: **DROPPED — deliberately not installed. No decision outstanding.** Mutually-exclusive conflict with Judy Enhanced Body with 4K Texture (mod 10150, STATE=ENABLED), settled by the standing most-DLs rule at mod level: **10150 = 1,431,720 total DLs vs this mod's 379,845**, so the already-installed body mod wins. Consistent with the sibling decision on mod 1699 — the "Hyst bodies vs Seracen clothes" question is settled once, for both characters, in favour of the bodies. No Judy bridge mod exists (unlike Panam's "Alternative Clothes for Panam Body Enhanced"), so Judy gets the body only. TO REVERSE: `/uninstall` 10150, then `/install` this. WHY THEY CANNOT COEXIST — CONFIRMED BY THIS PAGE'S OWN TEXT, not just 10150's list: under KNOWN BUGS/FIXES the author states "**Partially clothed versions will have a unique body mesh** (thanks to xBaebsae)", i.e. this mod SHIPS ITS OWN JUDY BODY MESH — precisely the asset 10150 replaces. Mesh-vs-mesh on one character: the loser's clothes are cut for the other's body, giving clipping/misfit rather than a clean override, and no `!`/`##`/`zz-` prefix trick fixes that. (10150's list uses the SOFT "can make conflict" — which is what justified installing 10150 over the ENABLED mod 1436 — but the deciding test is ASSET DOMAIN, not wording: 10150-vs-1436 are disjoint (dedicated Judy body mesh vs generic NPC base body TEXTURES), 10150-vs-this are not.) PRE-RESOLVED FOR A FUTURE INSTALL: FILE = the most-downloaded main file **"Judy - Alternate Clothes" v3.0** (140.2MB, "Compilation of all Judy clothes - ONLY PICK ONE FILE AT A TIME!!"; the page header reads 4.0 while the main file is v3.0). NOT it: UPDATE "Judy - Alternate Clothes (Experimental)" v4.0 (two experimental archives using "the old method"); OPTIONAL "Maelstrom Patch Alternate" v1.0 and "Maelstrom Patch for Judy and Rogue" v1.0 — situational glitch patches, and the latter also touches ROGUE's clothes, which would want checking against the ENABLED Rogue's New Look (mod 12040). **UNRESOLVED TASTE AXIS**: the main file is ONE 140.2MB download containing MANY outfit .archives with "PICK ONLY ONE OPTION" — one DL count for the lot, so the most-DLs rule cannot choose; resolve from the author's manifest at install time or ask the user. Author caveats for that install: without AMM (❌ CET on macOS) a specific look CANNOT be locked — "the look will change naturally throughout the game"; most jackets only appear when Judy wears her Braindance, the main options being "Braindance_On"/"Braindance_Off"; some models have diving-suit standard/no-mask variants; partially-clothed versions' unique body mesh "may result in missing feet meshes for her nude models" (use selectively); clothing articles sometimes vanish until save reload (mainly accessories/gloves); Maelstrom gangsters reuse Judy's clothing so they may glitch and Judy may revert to default pants near them (the Maelstrom patches target this); shorter LOD on some clothing causes invisible legs at distance (the LOD patch on the Panam page addresses this globally). Author points at "Judy Modding Essentials - Fixes" by Janecio14 if his patches don't solve a bug. PAGE ACCESS CAVEAT: tagged **Sexualised/adult** → the r.jina.ai digest is EMPTY; mods/pages/1823-pages.md is nav chrome only. Read the page in the logged-in Claude-in-Chrome browser instead.
DESC: Offers a wardrobe of alternate outfit options for Judy Alvarez (braindance-on/off jacket variants, diving-suit and partially-clothed options), one outfit archive at a time.
