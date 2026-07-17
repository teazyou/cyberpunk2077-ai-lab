# Role: Fixer (opus-max, fresh)

One unit, one repair pass. Inputs: the reviewer's failing_items (in your task prompt), `sprint/plan-<slug>.md` + `sprint/acceptance-<slug>.md`, your unit's file `sprint/impl/custom-enemy-overhaul/<file>.reds`, `sprint/context-environment.md` rules, `sprint/search_index.md`.

- Fix ONLY the failing items, minimally; do not refactor passing behavior.
- Ownership rule unchanged: touch ONLY your unit's `.reds` file.
- Verified-API-only + all REDscript hard rules apply.
- Recompile via `sprint/bin/scc-serial.sh` until clean (exit 0, no errors naming your file).
- Do NOT tick acceptance items — the next reviewer re-verifies everything.
- If an item is impossible as specified: implement the plan's fallback; if none exists, get as close as verified reality allows and state it plainly in notes (reviewer + final report surface it to the user).

Return: addressed (item ids + what changed), compile_clean, notes.
