# Cyberpunk 2077 Workspace

AI-piloted Obsidian vault for everything about **Cyberpunk 2077** on **macOS (Steam)**. Two jobs:

1. **Mod management (primary)** — an AI installs / enables / disables / uninstalls game mods. All mod operations go through the `/install`, `/enable`, `/disable`, `/uninstall`, and `/parse` skills, which read **only** `mod-manager.md` — the standalone single source of truth for mod state and procedures. Do not manage mods by any other path.
2. **Game knowledge (secondary)** — Cyberpunk 2077 info (build guides, tutorials, game facts) is collected and saved under `wikis/` for later reference.

## File index
mod-manager.md: Standalone state file plus procedures; single source of truth for mod install/enable/disable/uninstall, including the macOS compatibility rule, folder layout, wishlist, and the Mod Manager Data registry.
docs/enable-mods-on-macbook.md: One-time REDscript + input-loader toolchain setup guide for macOS, with launch, troubleshooting, and vanilla-restore steps.
script/launch_modded.sh: Symlink to the game-folder launcher that compiles REDscript, merges input mods, and starts the modded game (Steam must be running).
mods/: Mod storage root.
mods/downloaded/: Original mod zips (`<slug>.zip`); audit-only, never loaded by the game.
mods/enabled/: Fixed symlink portals INTO the game drop dirs (r6-scripts, r6-input, archive-mod, engine-config); files placed here are live in-game.
mods/disabled/: Real directories holding deactivated mod files moved out of the game, mirroring the enabled/ portal layout under `disabled/<slug>/`.
wikis/: Saved Cyberpunk 2077 knowledge (build guides, tutorials, game info); designated place for game-knowledge notes.
wikis/modding/: Modding research dossiers + implementation plans for locally-authored custom mods (one plan + one research file per feature).
.claude/CLAUDE.md: This project memory and file index.
.claude/skills/install/SKILL.md: `/install <url|mod name>` skill; installs/enables a mod per mod-manager.md.
.claude/skills/enable/SKILL.md: `/enable <url|mod name>` skill; re-activates a DISABLED mod (moves files back into the game, STATE=ENABLED) per mod-manager.md.
.claude/skills/disable/SKILL.md: `/disable <url|mod name>` skill; deactivates an ENABLED mod (moves files out to disabled/, STATE=DISABLED) per mod-manager.md.
.claude/skills/uninstall/SKILL.md: `/uninstall <url|mod name>` skill; fully deletes a mod (files + zip + entry) per mod-manager.md.
.claude/skills/parse/SKILL.md: `/parse` skill; formats the mod-manager.md wishlist into classified mod references.
.obsidian/: Obsidian vault configuration.
