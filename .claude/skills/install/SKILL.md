---
name: install
description: Install a Cyberpunk 2077 mod into the game. Use when the user runs /install with a Nexus mod URL or a mod name/title.
argument-hint: <url | mod name>
---
# /install <url | mod name>

Argument = a Nexus mod URL or a mod name/title.

`mod-manager.md` (project root) is the standalone source of truth for the install procedure and mod state — among project files, read ONLY it. You MUST also read the mod's Nexus page (step 2). Do not read other project files.

## 1. Resolve the mod
- URL not already under `## Mod Manager Data` → add a reference first: classify per the Compatibility rule and add an entry (Entry format, STATE=NOT INSTALLED). If the URL is in `## Wishlist`, remove it from there.
- Name → locate its entry under `## Mod Manager Data`.

## 2. Read the mod page + re-verify (every install)
- Run `script/mod-tool.sh info <mod-id>` FIRST — it prints a compact digest (title, category, stats, description, Nexus requirements) and saves the full page at `mods/pages/<mod-id>-pages.md`. Do NOT curl r.jina.ai yourself; the tool replaces that.
- Read the saved `mods/pages/<mod-id>-pages.md` (or the page in the browser) only if the digest is not enough — e.g. you need Files-tab details or the full description.
- Double-check compatibility from the actual mod info against `mod-manager.md`'s Compatibility rule; do NOT trust the stored COMPAT blindly. If it resolves to ❌, stop: set STATE=NOT INSTALLED with the reason and tell me.
- If the description has any specificity (special install step, required load order, config, conflict, caveat), record it in that entry's `NOTE:` line in `mod-manager.md`.

## 3. Choose the variation
- If variants differ by TYPE (e.g. a REDscript version vs an archive version), default to the **REDscript** version — no need to ask (best macOS compatibility).
- If variants are a preference the default can't settle (e.g. 2x vs 3x multiplier, optional/patch versions) and I have not already told you which, ASK me before continuing.
- If there is only one file, use it. Record the chosen variant in the entry's `NOTE:`.

## 4. Download via the browser
- Download using the Chrome browser available in this session (my Nexus account is already logged in). Do NOT use curl/WebFetch — Nexus blocks them and downloads require login.
- On the file's Nexus page choose **"Manual Download"** (never "Mod Manager Download"/Vortex — there is no mod manager on macOS).
- On the next screen choose **"Slow download"** (I have no paid Nexus subscription).
- Right after clicking "Slow download", run `script/mod-tool.sh grab <slug> "<downloads-glob>"` (glob matching the download's filename, e.g. `"Preem Scanner - Pure*"`). It waits for the download to finish, moves the archive to `mods/downloaded/<slug>.<ext>`, extracts it into `mods/staging/<slug>/`, and prints the extracted file list — just wait for it to exit.

## 5. Deploy
- The archive is now in `downloaded/` and its extracted contents in `mods/staging/<slug>/`, with the file list already printed by `grab`. Finish the INSTALL procedure in `mod-manager.md` from the inspect step onward: inspect that printed file list for the compat check, move the files from `mods/staging/<slug>/` into the matching `mods/enabled/` portal(s) per mod-manager.md, delete the emptied `mods/staging/<slug>/` folder, and set the entry's STATE=ENABLED + FILES. Follow it exactly; do not invent steps.
