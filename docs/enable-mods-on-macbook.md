# Enabling Mods (REDscript) for Cyberpunk 2077 on macOS

Complete record of the mod-toolchain install performed on **2026-07-01**, plus how to
launch, add mods, troubleshoot, and fully restore vanilla.

---

## 1. System context (what this was installed on)

| Item | Value |
|------|-------|
| Machine | Apple Silicon (`arm64`), macOS (Darwin 25.x) |
| Game | Cyberpunk 2077 **v2.31** + Phantom Liberty (ep1) |
| Store | **Steam** (app id `1091500`) |
| Game folder | `~/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077` |
| Game binary | `Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077` |
| System Perl | `/usr/bin/perl` 5.34.1 with `XML::LibXML` 2.0110 (required by input loader) |

> On macOS only **REDscript-only mods** and **input-remap mods** work. Frameworks that
> need native code — RED4ext, Cyber Engine Tweaks (CET), ArchiveXL, TweakXL, Codeware —
> do **not** work on Mac. Avoid mods that list those as requirements.

Official guide followed:
https://wiki.redmodding.org/cyberpunk-2077-modding/for-mod-users/users-modding-cyberpunk-2077/modding-on-macos
Secondary guide + mod list compatible:
https://www.nexusmods.com/cyberpunk2077/articles/1936

---

## 2. Components installed (versions + exact download URLs)

| Component | Version | Download URL |
|-----------|---------|--------------|
| REDscript (macOS build, **not** the CLI) | **0.5.31** | <https://github.com/jac3km4/redscript/releases/download/v0.5.31/redscript-v0.5.31-macos.zip> |
| Input Loader for macOS | **1.0** | <https://github.com/risner/cyberpunk2077-input-loader-mac/releases/download/v1.0/input-loader-mac-v1.0.zip> |
| **Fixed** `inputloader.pl` (crash fix) | **1.1** | <https://github.com/user-attachments/files/23583775/inputloader.pl.zip> |

Release/reference pages:
- REDscript releases: <https://github.com/jac3km4/redscript/releases>
- Input Loader releases: <https://github.com/risner/cyberpunk2077-input-loader-mac/releases>
- **Crash-fix issue** (source of the v1.1 loader): <https://github.com/risner/cyberpunk2077-input-loader-mac/issues/1>

### Why the fixed loader matters
The default `input-loader-mac-v1.0` (`inputloader.pl` v1.0) **crashes the game at the
"press any button" screen when no mods are loaded**. The v1.1 file from issue #1 fixes an
undefined-variable bug in the XML merge, replaces a broken `continue;` with `next;`, loads
configs via absolute paths, and gracefully handles the no-mods case. We install v1.1 over
the v1.0 file.

---

## 3. What each archive contains

```
redscript-v0.5.31-macos.zip
├── engine/tools/scc                 # the compiler (native arm64, ad-hoc signed)
├── engine/tools/libscc_lib.dylib    # compiler library
└── launch_modded.sh                 # basic launcher (gets overwritten below)

input-loader-mac-v1.0.zip
├── engine/tools/inputloader.pl                        # v1.0 (buggy — replaced by v1.1)
├── engine/config/platform/mac/input_loader.ini        # points game at merged input cache
├── launch_modded.sh                                   # superset launcher (THIS is the one kept)
└── r6/input/                                          # where input mods go

inputloader.pl.zip  (from issue #1)
└── inputloader.pl                   # v1.1 fixed loader
```

The **kept** `launch_modded.sh` (from the input-loader zip) does, on every run:
```bash
#!/usr/bin/env bash
game_dir=$(dirname "$(readlink -f "$0")")
"$game_dir/engine/tools/scc" -compile "$game_dir/r6/scripts"   # compile REDscript mods
"$game_dir/engine/tools/inputloader.pl"                        # merge input mods
"$game_dir/Cyberpunk2077.app/Contents/MacOS/Cyberpunk2077"     # launch the game
```
Its paths already match the Steam layout, so no editing was needed.

---

## 4. Exact steps performed (reproducible)

Everything below is safe to re-run (e.g. after a game update). It only **adds** files to
the game folder; it never overwrites vanilla game data.

```bash
# ---- 0. Paths --------------------------------------------------------------
GAME="$HOME/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077"
STAGE="$HOME/cp2077-mod-staging"          # scratch download folder (can delete after)
mkdir -p "$STAGE" && cd "$STAGE"

# ---- 1. (Prereq check) input loader needs Perl XML::LibXML -----------------
/usr/bin/perl -MXML::LibXML -e 'print "XML::LibXML OK\n"'   # macOS system perl already has it

# ---- 2. Download the three components --------------------------------------
curl -L -o redscript.zip         "https://github.com/jac3km4/redscript/releases/download/v0.5.31/redscript-v0.5.31-macos.zip"
curl -L -o inputloader-v1.0.zip  "https://github.com/risner/cyberpunk2077-input-loader-mac/releases/download/v1.0/input-loader-mac-v1.0.zip"
curl -L -o inputloader-fixed.zip "https://github.com/user-attachments/files/23583775/inputloader.pl.zip"

# ---- 3. Install REDscript, then input loader (its launch script wins) ------
unzip -o redscript.zip        -d "$GAME"
unzip -o inputloader-v1.0.zip -d "$GAME"

# ---- 4. Apply the v1.1 crash fix (overwrite the v1.0 loader) ---------------
unzip -o inputloader-fixed.zip -d "$STAGE/fixed"
cp -f "$STAGE/fixed/inputloader.pl" "$GAME/engine/tools/inputloader.pl"

# ---- 5. Unblock Gatekeeper quarantine on the tools (harmless if none) ------
xattr -r -d com.apple.quarantine "$GAME/engine/tools/" 2>/dev/null || true

# ---- 6. Create the mod-scripts dir + make scripts executable ---------------
mkdir -p "$GAME/r6/scripts"
chmod +x "$GAME/launch_modded.sh"
chmod +x "$GAME/engine/tools/inputloader.pl"
```

### Notes / gotchas verified during install
- `scc` + `libscc_lib.dylib` are **native arm64** with a valid **ad-hoc (linker-signed)**
  signature → macOS runs them without a Gatekeeper kill. No re-signing needed.
- `curl` downloads are **not** quarantined, so step 5 usually finds nothing to remove —
  it's kept as a safety net (e.g. if you download via a browser instead).
- The v1.1 loader resolves the game dir from its own path and uses **absolute** paths for
  both reading base configs (`r6/config/inputContexts_mac.xml`, `r6/config/inputUserMappings.xml`)
  and writing merged output (`r6/cache/inputContexts.xml`, `r6/cache/inputUserMappings.xml`),
  so it works regardless of the current working directory.

---

## 5. Post-install verification (all passed)

```bash
# REDscript compiles cleanly:
"$GAME/engine/tools/scc" -compile "$GAME/r6/scripts"
#   -> "Compilation complete"
#   -> "Output successfully saved to .../r6/cache/final.redscripts"
#   -> also creates r6/cache/final.redscripts.bk  (pristine vanilla backup)

# Input loader runs without the crash, even with no mods:
"$GAME/engine/tools/inputloader.pl"
#   -> "[InputLoader] Starting up Input Loader (version 1.1)"
#   -> "No mod input XML files found ... (this can be normal)"
#   -> writes r6/cache/inputContexts.xml + r6/cache/inputUserMappings.xml (well-formed XML)
```

Resulting files in `engine/tools/`: `scc`, `libscc_lib.dylib`, `inputloader.pl` (8431 bytes = v1.1).

---

## 6. How to launch the modded game

**Steam must be running** (ownership/DRM check). Then, in Terminal:

```bash
cd "$HOME/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077" && ./launch_modded.sh
```

The script recompiles scripts, merges input mods, and launches the game every time.

> Steam's normal **Play** button launches **vanilla** (it does not run the script).
> Always use `launch_modded.sh` to play with mods.

Optional convenience: make a double-clickable launcher on the Desktop
```bash
cat > "$HOME/Desktop/Cyberpunk 2077 (Modded).command" <<'EOF'
#!/usr/bin/env bash
cd "$HOME/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077" && ./launch_modded.sh
EOF
chmod +x "$HOME/Desktop/Cyberpunk 2077 (Modded).command"
```

---

## 7. How to add mods

Only **REDscript** and **input-remap** mods work on macOS (see the framework warning at top).

- **REDscript mod** (`.reds` files): unzip so the files land under `r6/scripts/`
  (most mod archives already contain the `r6/scripts/...` structure — just unzip into the
  game folder: `unzip mod.zip -d "$GAME"`).
- **Input-remap mod** (`.xml` files): put them in `r6/input/`.
- Then run `./launch_modded.sh` — it recompiles and re-merges automatically.

Finding compatible mods on Nexus: pick ones tagged/described as **REDscript** that do **not**
require RED4ext / CET / ArchiveXL / TweakXL / Codeware.

---

## 8. Troubleshooting

| Symptom | Fix |
|---------|-----|
| Game crashes at "press any button" | Ensure `engine/tools/inputloader.pl` is the **v1.1** file (8431 bytes). Re-apply step 4. |
| `Can't locate XML/LibXML.pm` when loader runs | `XML::LibXML` missing from Perl. macOS system perl normally has it; otherwise install (e.g. `sudo cpan XML::LibXML`). |
| `scc` "killed" / "cannot be opened" | Re-run step 5; if still blocked: `codesign --force -s - "$GAME/engine/tools/scc" "$GAME/engine/tools/libscc_lib.dylib"`. |
| Game won't start from the script | Make sure **Steam is running** first. |
| Mods stopped working after a Steam update | Re-run the whole **Section 4** (updates can wipe `engine/tools/`). |
| `launch_modded.sh: permission denied` | `chmod +x "$GAME/launch_modded.sh"`. |
| "no such file or directory" in Terminal | Path is wrong — the game folder name contains a space; keep the quotes. |

> ⚠️ **Do NOT use Steam → Properties → Installed Files → "Verify integrity of game files."**
> It deletes the added mod files and reverts `final.redscripts`. If you ever do, re-run Section 4.

---

## 9. Restore / revert to vanilla

### A. Quick revert (undo script changes, keep tools installed)
Restore the pristine compiled scripts that `scc` backed up automatically:
```bash
GAME="$HOME/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077"
cp "$GAME/r6/cache/final.redscripts.bk" "$GAME/r6/cache/final.redscripts"
```
(Launching via Steam's normal Play button is then fully vanilla.)

### B. Full uninstall (remove the entire mod toolchain)
```bash
GAME="$HOME/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077"

# tools
rm -f "$GAME/engine/tools/scc" "$GAME/engine/tools/libscc_lib.dylib" "$GAME/engine/tools/inputloader.pl"
# input loader config
rm -f "$GAME/engine/config/platform/mac/input_loader.ini"
# launcher
rm -f "$GAME/launch_modded.sh"
# restore vanilla script cache, remove redscript/loader-generated files
cp "$GAME/r6/cache/final.redscripts.bk" "$GAME/r6/cache/final.redscripts"
rm -f "$GAME/r6/cache/final.redscripts.bk" "$GAME/r6/cache/final.redscripts.ts"
rm -f "$GAME/r6/cache/inputContexts.xml" "$GAME/r6/cache/inputUserMappings.xml"
# optional: remove mod folders (only if empty / you want them gone)
rmdir "$GAME/r6/scripts" "$GAME/r6/input" 2>/dev/null || true

# nuclear option instead of the above: Steam -> Verify integrity of game files
```

### Backups that exist after install
- `r6/cache/final.redscripts.bk` — pristine vanilla script cache (made automatically by `scc`).
- A second copy was saved during setup to the session scratchpad staging folder
  (`.../scratchpad/staging/final.redscripts.ORIGINAL.bak`) — temporary, may be cleaned by the OS.

---

## 10. Quick reference

```bash
GAME="$HOME/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077"

# Launch modded (Steam running):
cd "$GAME" && ./launch_modded.sh

# Add a REDscript mod:
unzip yourmod.zip -d "$GAME"      # lands in r6/scripts/...
cd "$GAME" && ./launch_modded.sh

# Revert to vanilla scripts:
cp "$GAME/r6/cache/final.redscripts.bk" "$GAME/r6/cache/final.redscripts"
```
