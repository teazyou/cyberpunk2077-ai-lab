# Instant Breach on Device Connect — research dossier + implementation

**Feature:** jacking into an access point / backdoor device (and device remote breach) succeeds instantly — no breach-protocol screen, no cell click. Implemented 2026-07-11 as a **local extension inside the deployed Nexus mod file** `r6-scripts/hacking-gets-tedious/HackingGetsTedious.reds` (Hacking Gets Tedious hotfix, Nexus 15084 — its one-click pre-solved board is kept for every minigame that still opens).

**Constraint honored:** every function/field/event used was verified to exist in the game v2.3 sources before use (no predicted APIs). Source of truth: https://github.com/CDPR-Modding-Documentation/Cyberpunk-Scripts (main @ fce9ab7, July 2025 = game 2.3 era), local clone in the session scratchpad.

## Why the minigame cannot be auto-completed from script

- The breach board/completion logic is native. `HackingMinigameGameController` (hackingMinigameUtils.script:116) exposes NO import to end the game — only grid/program setup calls (`AddUnlockableProgram`, `PauseTheTimer`, …).
- The Nexus mod's trick (set `UnlockableProgram.isFulfilled = true` in the generation rules) still requires the native controller to see one cell click before it ends the game and publishes results.
- Therefore: intercept **before the UI opens** and publish the success ourselves.

## Vanilla flow trace (v2.3 sources, file:line)

Physical jack-in ("Breach Protocol" on an access point / backdoor device):

1. Personal-link connect completes → `ScriptableDeviceComponentPS.ResolvePersonalLinkConnection` (scriptableDeviceBasePS.script:4590) → executes `ActionToggleNetrunnerDive(false, evt.m_shouldSkipMiniGame)` — only when `HasNetworkBackdoor()` and `!WasHackingMinigameSucceeded()` (:4608).
2. `ScriptableDeviceComponentPS.OnToggleNetrunnerDive` (:4759):
   - terminate → `DisconnectPersonalLink`;
   - link CONNECTED (or `evt.m_isRemote`): if `m_shouldSkipNetrunnerMinigame || evt.m_skipMinigame` → vanilla quest-skip (`ResolveDive(false)` + disconnect — no daemons, no loot); **else → `return SendThisEventToEntity` — THE branch that opens the UI.**
3. Entity side `Device.OnToggleNetrunnerDive` (deviceBase.script:3401) → sets `NetworkBlackboard.RemoteBreach` → `PerformDive` → `DisplayConnectionWindowOnPlayerHUD(true)` (:3432) → writes `NetworkBlackboard` (DevicesCount/OfficerBreach=false/**NetworkName signal**/MinigameDef/Attempt/DeviceID) — the NetworkName signal is what raises the native breach screen.
4. Native minigame runs; on end it queues **`AccessPointMiniGameStatus { minigameState }`** (import event, deviceBase.script:73) to the breached entity. Script precedent constructing + sending this very event: `accessPointGameController.script:305-320` (`CloseGame`: `new AccessPointMiniGameStatus; evt.minigameState = HackingMinigameState.Succeeded; QueueEventForEntityID(deviceID, evt)`).
5. `Device.OnAccessPointMiniGameStatus` (deviceBase.script:3466) → `GetDevicePS().HackingMinigameEnded(state)` (+ objective succeed, proximity mappin re-eval, quickhack-menu refresh).
6. `HackingMinigameEnded` (scriptableDeviceBasePS.script:4826) → `SetMinigameState` (:4832 — link still connected + Succeeded ⇒ `TurnAuthorizationModuleOFF`, hacking skillcheck passed) → `FinalizeNetrunnerDive` (:4855) → Succeeded ⇒ `ResolveDive(!HasNetworkBackdoor())` (:4784) → `SetExposeQuickHacks` to `GetBackdoorAccessPoint()`; then queues `ActionToggleNetrunnerDive(true)` = personal-link auto-disconnect.
7. `AccessPointControllerPS.OnSetExposeQuickHacks` (accessPointController.script:1164) → `RefreshSlaves_Event` → `RefreshSlaves` (:416): reads **`HackingMinigame.ActivePrograms`** → datamine money/materials/quickhack-shard rewards, `ProcessMinigameNetworkActions` per slave (camera/turret/etc. daemons, reads **ActiveTraps** too — must be clean), `ActionSetExposeQuickHacks` on every slave, `RPGManager.GiveReward(RPGActionRewards.Hacking)`.

Key insight: **everything after step 4 is driven by one script-constructible event + one blackboard variant.** Publishing `ActivePrograms` and queueing `AccessPointMiniGameStatus(Succeeded)` to the jacked entity replays the entire vanilla success chain with zero UI.

## Where the daemon list comes from (outside the minigame)

- Player's programs live script-side: `PlayerPuppetPS.m_availablePrograms` (player.script:99, persistent), granted via `UnlockMinigameProgramEffector` (cyberdeck/perks). Public accessor: **`PlayerPuppet.GetMinigamePrograms()`** (player.script:7009). The native controller's `GetPlayerPrograms()` mirrors this same list via the `HackingMinigame.PlayerPrograms` blackboard (player.script:189, :7032).
- Board filter replicated 1:1 from `MinigameGenerationRuleScalingPrograms.FilterPlayerPrograms` (hackingMinigameUtils.script:875-926):
  - drop invalid/`'None'` program names;
  - `VendingMachine` entity ⇒ drop `MinigameAction.NetworkDataMineLootAllMaster`;
  - physical breach ⇒ keep ONLY `gamedataMinigameActionType.AccessPoint` programs; remote breach ⇒ drop AccessPoint ones;
  - `CameraAccess` / `TurretAccess` categories and `NPC` type gated on `CheckMasterConnectedClassTypes()` (SharedGameplayPS, deviceComponentBase.script:293 — aggregates `AccessPointControllerPS.CheckConnectedClassTypes` over `GetAccessPoints()`);
  - deduped (vanilla `tempPrograms` pass, hackingMinigameUtils.script:866).

## Implementation (in HackingGetsTedious.reds)

- `HGTInstantBreachConfig` — `EnableInstantBreach()` (default true), `DebugProbeInstantBreach()` (default false, HUD activity log).
- `@addMethod(ScriptableDeviceComponentPS) HGT_ShouldInstantBreach(evt)` — mirrors the vanilla branch conditions (`!ShouldTerminate`, link CONNECTED or `m_isRemote`, no vanilla skip flags, player resolvable) **plus a quest-board guard**: if `GetMinigameDefinition()` is a valid record with `GetOverrideProgramsListCount() > 0 || GetGridSymbolsCount() > 0` (Minigame_Def_Record imports, tweakDBRecords.script:5931/5951) → NOT instant (VR netrunning tutorial, story boards keep the real UI; quest logic may watch it).
- `@addMethod ... HGT_CollectBoardPrograms(isRemote)` — the filter above over `GetMinigamePrograms()`.
- `@addMethod ... HGT_InstantBreach(evt)` — `SetVariant(HackingMinigame.ActivePrograms, programs)`; `SetVariant(HackingMinigame.ActiveTraps, [])` (stale-trap guard: `ProcessMinigameNetworkActions` reads ActiveTraps — a leftover `MinigameTraps.IncreaseAwareness` from a previous real board would set a 10× detection multiplier); `SetBool(NetworkBlackboard.RemoteBreach, evt.m_isRemote)` (what the skipped entity handler would have written, read back by `ResolveDive` :4792); `GetPersistencySystem().QueueEntityEvent(PersistentID.ExtractEntityID(GetID()), AccessPointMiniGameStatus(Succeeded))` (PersistentState imports, varDBSystem.script:70-77; same pattern as accessPointController.script:1160).
- `@wrapMethod(ScriptableDeviceComponentPS) OnToggleNetrunnerDive` — instant path returns `DoNotNotifyEntity` (entity handler never runs ⇒ no connection window, no breach screen); every other branch → `wrappedMethod(evt)`. The later terminate action queued by `FinalizeNetrunnerDive` re-enters the wrap with `ShouldTerminate()==true` → falls through to vanilla disconnect. No recursion, no double `RefreshSlaves`.

## Scope decisions

- **Covered:** physical jack-in on any backdoor device (AP, computer, terminal, vending machine), device `RemoteBreach` action (scriptableDeviceBasePS.script:4674).
- **Not covered (one-click board still opens):** NPC "officer" breach + suicide breach (puppet `AccessBreach` action, puppetActions.script:132 — separate path, touches PSM nanowire state; skipping it needs its own research), shard/item breach (`triggerHackingMinigameEffector`), quest-designed boards (guard above), devices vanilla already auto-skips.
- Re-connecting after success does not re-run the dive (vanilla `!WasHackingMinigameSucceeded()` gate :4608) — no reward farming beyond vanilla. Money stays gated by `m_moneyAwarded`/`ShouldRewardMoney` on the master AP.

## Safety notes

- Game-thread only: runs inside a PS action handler; no streaming/attach hooks (see [[redscript-ongameattached-worker-crash]] class of bugs — not applicable here).
- No other deployed mod wraps/replaces `OnToggleNetrunnerDive`, `FinalizeNetrunnerDive`, `ResolveDive`, `HackingMinigameEnded`, or `OnAccessPointMiniGameStatus` (grep-verified 2026-07-11).
- `scc -compile` clean 2026-07-11 (no warnings for this file).

## Pending in-game tests

1. World access point: jack in → instant "breached" (no screen), datamine eddies/materials/shard rewards land, quickhacks exposed network-wide, link auto-disconnects.
2. Camera/turret network: camera-type daemons apply only where such devices are connected.
3. Quest board regression: VR netrunning tutorial still opens its real (pre-solved) board.
4. NPC officer breach + Militech shard: unchanged (one-click board).
5. Probe (`DebugProbeInstantBreach=true`): daemon count logged matches the board a real minigame would show.
