---
name: enable
description: Enable (re-activate) a disabled Cyberpunk 2077 mod, moving its files back into the game. Use when the user runs /enable with a mod name/title or Nexus URL.
argument-hint: <url | mod name>
---
# /enable <url | mod name>

Argument = a mod name/title or Nexus URL.

`mod-manager.md` (project root) is the standalone source of truth — read ONLY that file; do not read any other file.

1. Locate the mod's entry under `## Mod Manager Data`.
2. If its STATE is not DISABLED, there is nothing to move — report the current STATE and stop.
3. Perform the ENABLE procedure defined in `mod-manager.md` (Procedures → ENABLE) exactly. Do not restate or invent steps.
