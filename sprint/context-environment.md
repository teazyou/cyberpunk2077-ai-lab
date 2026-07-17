# Environment & Ground Rules — read FIRST, binding for every agent

## Paths
- REPO (cwd): `/Users/teazyou/dev/tmp-claude/cyberpunk`
- SPRINT: `<REPO>/sprint` — all sprint artifacts live here
- GAME: `/Users/teazyou/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077`
- VANILLA SOURCES (decompiled game scripts, game v2.3): `sprint/vanilla-scripts/` — grep here to verify EVERY engine API
- STYLE + PATTERN REFERENCE (locally-authored, in-game-proven mod): `mods/enabled/r6-scripts/custom-scanner-suite/ScannerSuite.reds`
- ORIGINAL AGGRO MOD (dissected reference): `sprint/reference-aggro/`
- IMPLEMENTATION TARGET: `sprint/impl/custom-enemy-overhaul/*.reds`
- STAGING COMPILE COPY: `sprint/staging/r6/{scripts,cache}` — full copy of game scripts incl. all currently-enabled mods; compiles NEVER touch the live game

## Hard platform constraints (macOS, Steam)
- ONLY pure REDscript (+ .archive + input-loader XML) runs on macOS.
- NOT AVAILABLE — never propose or use: Cyber Engine Tweaks (CET/Lua), RED4ext, TweakXL, ArchiveXL, Codeware, Mod Settings menu. Any API that exists only via those does NOT exist here.
- TweakDB is READ-ONLY at runtime from REDscript (`TweakDBInterface.Get*`). No record/flat writes.
- Game version 2.3.

## REDscript hard rules (each learned the hard way; violations = compile fail or heap-corruption crash)
1. NO `continue` / `break` keywords — they don't exist (UNRESOLVED_REF). Skip iterations with an if-wrapper.
2. NEVER hook/mutate shared state from per-entity `GameObject.OnGameAttached` — entity streaming runs on WORKER THREADS → heap corruption. The PLAYER-object `PlayerPuppet.OnGameAttached` is game-thread and safe. Per-entity work runs on game-thread ticks: DelaySystem self-re-arming loop + enumeration (`GetEntitiesAroundObject` / `GameInstance.GetEntityList` / TargetingSystem queries).
3. NEVER mutate engine state synchronously inside its own listener callback (re-entrancy corrupts the native dispatcher). Defer via `GameInstance.GetDelaySystem(...).DelayCallbackNextFrame(...)` or queue a flag consumed by the tick loop.
4. EVERY API used or cited MUST be verified against `sprint/vanilla-scripts` (grep; cite file:line) or already used by ScannerSuite.reds. NO predicted/guessed APIs — the user rejects them categorically. APIs documented only in Codeware/CET/NativeDB do not count as verified.
5. `@addMethod(Class)` counts as a member: it can read that class's private/protected fields and call its private methods. Cross-class private access → add a public shim via @addMethod on the owning class.
6. Prefer `@wrapMethod` over `@replaceMethod` when both work (mod compat; multiple wraps chain fine).
7. Compile validation: ONLY via `sprint/bin/scc-serial.sh` (global lock serializes scc; refreshes staging from sprint/impl; compiles the FULL staging set). Success = exit 0 + "Output successfully saved". NEVER run scc directly, NEVER compile the live GAME dir, NEVER touch `GAME/r6/cache`, NEVER launch the game.

## Mod shape (fixed decisions)
- One mod: slug `custom-enemy-overhaul`, module namespace `EnemyOverhaul`.
- Files (each unit strictly owns its file; nobody edits a file they don't own):
  - `EnemyOverhaul.Common.reds` — shared infra: eligibility filters, once-per-entity seen-sets/registry, RNG helper, debug notify, enumeration/loop utilities.
  - `EnemyOverhaul.TierUprank.reds`
  - `EnemyOverhaul.Duplication.reds`
  - `EnemyOverhaul.AggroRange.reds`
- All tunables live in a clearly-marked USER CONFIG block at top of each file (percentages, ranges, caps, `DebugNotify` default ON = true).
- Feature files may @wrapMethod/@addMethod anything and import `EnemyOverhaul.Common.*`. If Common lacks something, implement it locally in YOUR file — do not edit Common.

## Web research etiquette
- NexusMods pages 403 on direct fetch — use `curl -s "https://r.jina.ai/<full-url>"` (markdown mirror; pages/metadata only, never file downloads).
- Good sources: wiki.redmodding.org, nativedb.red4ext.com (existence hints only), jac3km4/redscript GitHub wiki, GitHub code search for `.reds` usages, mod source repos (shallow-clone small public repos into `sprint/.scratch/` if needed).
- Chrome MCP tools exist but drive the user's shared browser — LAST resort (JS-only pages); create your own tab, close it when done. Prefer curl/r.jina/WebFetch/WebSearch.

## Debug conventions
- Debug notify = HUD one-liner + `FTLog(...)`, gated per-feature by `DebugNotify` consts (default true). Use a vanilla-verified HUD message API (planner picks it from research).
