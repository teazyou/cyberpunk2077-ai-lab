# Cyberpunk 2077 AI Lab

An AI-piloted mod-management workspace for **Cyberpunk 2077 on macOS (Steam)** — a platform with no mod manager, no Cyber Engine Tweaks, and no RED4ext. An AI agent (Claude Code) installs, enables, disables, and uninstalls Nexus mods end-to-end, and when no compatible mod exists for a feature, it researches the game's decompiled sources and **writes its own pure-REDscript mods**. The repo doubles as an Obsidian vault holding the game knowledge and research the agent accumulates along the way.

This is a personal lab and a working record, not a mod pack. But if you're curious what "an AI as your mod manager" looks like in practice, everything is here: the state file it maintains, the skills that constrain it, and the research-to-implementation pipeline behind the custom mods.

## Why macOS makes this interesting

The Mac build of Cyberpunk 2077 (v2.3x) cannot load native-code frameworks: **RED4ext, CET, ArchiveXL, TweakXL, and Codeware are all impossible** — they inject compiled Windows DLLs. What *does* work:

- **REDscript** (`.reds`) — script patches compiled into the game's script blob at launch
- **Input Loader XML** (`.xml`) — keybind additions, via a macOS port of the input loader
- **Raw `.archive`** files — textures/meshes, as long as they don't need ArchiveXL
- **Engine-config `.ini`** overrides (redirected to `platform/mac/` — the Mac build has no `pc/` dir)

Every mod is classified against this compatibility rule before anything is downloaded. Anything requiring a forbidden framework is recorded as incompatible and never installed. The one-time toolchain setup (REDscript compiler + patched input loader, with troubleshooting and full vanilla-restore steps) is documented in [`docs/enable-mods-on-macbook.md`](docs/enable-mods-on-macbook.md).

## How it works

### One state file, five skills

[`mod-manager.md`](mod-manager.md) is the single source of truth: the macOS compatibility rule, the folder layout, the install/enable/disable/uninstall procedures, and a registry entry for every managed mod (state, Nexus URL, exact file manifest, install notes). It's written to be machine-operable — an agent can run any procedure from that one file alone.

All mutations go through Claude Code skills, never ad hoc:

| Skill | Effect |
|---|---|
| `/install <url\|name>` | Verify compatibility, download via browser, deploy files, update registry |
| `/enable <name>` | Move a disabled mod's files back into the game |
| `/disable <name>` | Move an enabled mod's files out to `mods/disabled/` |
| `/uninstall <name>` | Delete files, archive, and registry entry |
| `/parse` | Classify wishlist URLs into registry references (no install) |

### The symlink-portal trick

There's no mod manager to deploy files, so the repo *is* the deployment mechanism:

- `mods/enabled/` contains four fixed symlinks — `r6-scripts`, `r6-input`, `archive-mod`, `engine-config` — pointing **directly into the live game directories**. Placing a file in a portal puts it in the game; there is no separate "deploy" step.
- `mods/disabled/` holds real directories: a disabled mod's files are physically moved out of the game into `disabled/<slug>/`, mirroring the portal layout.
- `mods/downloaded/` keeps the original Nexus archives for audit; the game never reads them.

Every mod is in exactly one of three states — `ENABLED`, `DISABLED`, or `NOT INSTALLED` — and its registry entry lists the exact portal paths it owns.

### Compile and launch

`script/launch_modded.sh` (a symlink to the launcher in the game folder) recompiles all `.reds` with the REDscript compiler, merges input XMLs, and starts the game. Steam's normal Play button launches vanilla; the script is the modded entry point.

## What's in the repo

| Path | Contents |
|---|---|
| `mod-manager.md` | State file + procedures — the whole system in one document |
| `.claude/skills/` | The five skill definitions (`install`, `enable`, `disable`, `uninstall`, `parse`) |
| `.claude/CLAUDE.md` | Project charter and file index for the agent |
| `docs/enable-mods-on-macbook.md` | macOS REDscript + Input Loader toolchain setup, reproducible step by step |
| `script/` | `mod-tool.sh` (Nexus page fetcher + download grabber) and the launcher symlink |
| `mods/` | `downloaded/`, `enabled/` (portals), `disabled/`, `staging/`, `pages/` (cached Nexus metadata) |
| `wikis/` | Game-knowledge notes (cyberware tiers, gig completion, melee stats…) |
| `wikis/modding/` | Research dossiers and implementation plans for the custom mods |

### The managed mods

The registry currently tracks **48 mods: 44 from Nexus and 4 locally authored** (46 enabled, 1 disabled, 1 referenced but not installed). The Nexus set skews toward quality-of-life and bug fixes that survive the REDscript-only filter — for example:

- **HD Reworked Project** — the well-known asset overhaul, as a single raw `.archive`
- **Nova LUT 4.0** — AgX color grading, also framework-free
- **Fast Travel from Anywhere / Better Fast Travel Map** — map QoL in pure REDscript
- **Vehicle Exit Fix, Stamina Consumption Fix, Second Heart Fix** — patch-2.3x bug fixes
- **Talk to Me, Street Vendors, Real Vendor Names** — world/immersion tweaks

Each entry records which file variant was chosen and why, plus caveats discovered at install time.

### The custom mods

When a wanted feature had no macOS-compatible mod, the agent wrote one. All four are pure `@wrapMethod` REDscript (each wrap calls the vanilla method exactly once), with config literals editable at the top of the file:

- **Custom Faster XP** — multiplies all organic XP gains by 1.2x, gated so respec and debug XP stay vanilla.
- **Custom Progression XP** — multiplies skill-proficiency XP by 7x for the five progression skills (Headhunter, Netrunner, Shinobi, Solo, Engineer), leaving level and street cred alone; stacks multiplicatively with Faster XP by design.
- **Custom Switch Speed** — makes weapon draw/holster/swap ~5x faster via transient stat modifiers across eight wrapped methods, including throwing-knife aim-raise and post-throw redraw, with first-draw flourishes suppressed.
- **Custom Scanner Suite** — the flagship: three independent scan-mode features behind individual toggles. *Loot while scanning* keeps the vanilla loot prompt usable with the scanner up (UI-context-stack compensation). *Auto-tag* runs a periodic frustum sweep (through walls, 50 m, plus a hover fallback) that tags targets from a five-category whitelist — no-police-heat enemies, collectables, quest elements, un-breached access points, working cameras/turrets — once per entity via the vanilla tag path. *Auto-pickup* collects hovered lootables within 12 m and line of sight, filtering quest/iconic items.

### The research methodology

Custom mods don't start with code. Each feature goes through a pipeline archived in `wikis/modding/`:

1. **Research dossier** (e.g. `scan-mode-looting.md`) — sub-agents sweep Nexus, Reddit, GitHub script dumps, and the decompiled 2.3x vanilla sources; every load-bearing claim is tagged VERIFIED (read in source) or SPECULATED.
2. **Implementation plan** (e.g. `plan-loot-while-scanning.md`) — a difficulty-gated design (rated 1–5, only validated plans proceed), with a primary path, a guaranteed-shippable fallback, and cheap in-game probes for the unknowns.
3. **Implementation** — the `.reds`, written against the plan, then adversarially reviewed before deployment.

Follow-up work gets its own dossier (`scanner-suite-refinements.md` reworked auto-tag from hover-based to the frustum sweep).

## Caveats, honestly

- **The symlinks only resolve on the owning machine.** `mods/enabled/*` and `script/launch_modded.sh` point into a local Steam install, so on a fresh clone they dangle — meaning the deployed custom-mod source (including `ScannerSuite.reds`) lives in the game folder and is *not* fully versioned in this repo. The registry's FILES manifests and the research plans are the durable record.
- **One archive is missing:** the 1 GB HD Reworked Project zip exceeds GitHub's file limit and is gitignored; re-download from Nexus if needed.
- **This is not a redistributable mod pack.** The downloaded archives belong to their Nexus authors — install their mods from Nexus, not from here. The custom `.reds` are written for game v2.3x and wrap version-specific methods; they may break on any patch.
- Some registry notes reference session-scratchpad paths from the authoring machine that don't exist anywhere else.

## Orientation for the curious

Start with [`mod-manager.md`](mod-manager.md) — it's the whole system in one read. Then skim a research dossier and its plan in `wikis/modding/` to see how a custom mod earns its way into the game.
