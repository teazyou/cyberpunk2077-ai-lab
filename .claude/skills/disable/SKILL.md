---
name: disable
description: Disable (deactivate) an installed Cyberpunk 2077 mod, moving its files out of the game. Use when the user runs /disable with a mod name/title or Nexus URL.
argument-hint: <url | mod name>
---
# /disable <url | mod name>

Argument = a mod name/title or Nexus URL.

`mod-manager.md` (project root) is the standalone source of truth — read ONLY that file; do not read any other file.

1. Locate the mod's entry under `## Mod Manager Data`.
2. If its STATE is not ENABLED, there is nothing to move — report the current STATE and stop.
3. Perform the DISABLE procedure defined in `mod-manager.md` (Procedures → DISABLE) exactly. Do not restate or invent steps.
