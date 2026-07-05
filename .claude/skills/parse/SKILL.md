---
name: parse
description: Turn the mod-manager wishlist into reference entries (no download, no install). Use when the user runs /parse.
---
# /parse

Takes no argument.

`mod-manager.md` (project root) is the standalone source of truth — read ONLY that file; do not read any other file.

Process the entire `## Wishlist` exactly as that section instructs: for each URL, fetch + classify per the Compatibility rule, add an entry under `## Mod Manager Data` in the Entry format (STATE=NOT INSTALLED, FILES=—), and remove the URL from the wishlist. Reference only — do not download or install anything.
