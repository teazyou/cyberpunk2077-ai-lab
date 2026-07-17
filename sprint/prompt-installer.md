# Role: Installer (opus-max) — deploy custom-enemy-overhaul

`mod-manager.md` is the single source of truth for mod operations. Steps:

1. Read `/Users/teazyou/dev/tmp-claude/cyberpunk/mod-manager.md` FULLY (Env, Folders, Portal invariant, State model, Procedures, Cautions, Entry format) and study the existing `custom-*` entries (e.g. custom-scanner-suite) as the precedent for locally-authored mods.
2. Preconditions — abort with installed=false if any fails:
   - All four `sprint/acceptance-*.md` static checklists fully `[x]`.
   - Refresh the staging baseline from the live game, then compile clean:
     `rsync -a --delete --exclude 'custom-enemy-overhaul' "/Users/teazyou/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077/r6/scripts/" /Users/teazyou/dev/tmp-claude/cyberpunk/sprint/staging/r6/scripts/`
     then `sprint/bin/scc-serial.sh` → exit 0.
3. Install: create `mods/enabled/r6-scripts/custom-enemy-overhaul/` (through the portal) and copy the four `.reds` from `sprint/impl/custom-enemy-overhaul/`. Canonical source stays in sprint/impl; the portal copies are the deployment.
4. Register: add the mod's entry to `mod-manager.md` per its Entry format, mirroring the custom-scanner-suite precedent (custom/local, no Nexus URL, STATE ENABLED, note: "AI-built via sprint 2026-07-17; source sprint/impl/custom-enemy-overhaul; features: 30% tier-uprank, 20% enemy duplication, aggro-range clean-room port of Nexus 19351").
5. NEVER: launch the game, run raw scc against the GAME dir, touch `GAME/r6/cache`, modify other mods' files or entries.
6. Write `sprint/install-report.md`: files placed where, registry entry added, compile evidence, and the consolidated MANUAL TEST PLAN (copy the "Manual in-game test plan" sections from the three feature acceptance files) — the user runs these next launch (`launch_modded.sh` recompiles automatically at startup).

Return: installed, files_placed, registry_updated, compile_clean, notes.
