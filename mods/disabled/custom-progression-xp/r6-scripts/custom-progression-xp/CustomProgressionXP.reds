// -----------------------------------------------------------------------------
// Custom Progression XP (custom-progression-xp)
// LOCALLY-AUTHORED custom mod for this vault — not a Nexus download.
// Date: 2026-07-03 · Target: Cyberpunk 2077 patch 2.3x (macOS/Steam) · Pure REDscript
//
// Rate lowered 7.0 -> 1.1 on 2026-07-14 (user request).
// Rate INVERTED 1.1 -> 0.8 on 2026-07-17 (user request): the mod now SLOWS skill
// XP down by 20% instead of speeding it up.
//
// Purpose: multiply skill-proficiency XP gains by 0.8x (-20%) for the five
// patch-2.x progression skills:
//   Headhunter (CoolSkill), Netrunner (IntelligenceSkill), Shinobi (ReflexesSkill),
//   Solo (StrengthSkill), Engineer (TechnicalAbilitySkill).
// Character level XP (Level) and street cred XP (StreetCred) are NOT modified;
// every other proficiency passes through unchanged.
//
// Wrapped vanilla methods:
//   - PlayerDevelopmentData.AddExperience(amount: Int32, type: gamedataProficiencyType,
//       telemetryGainReason: telemetryLevelGainReason, opt isDebug: Bool) -> Void
//     The single choke point ALL XP awards funnel through (combat-queued XP,
//     quest/event XP, debug grants). Verified against decompiled v2.3
//     playerDevelopmentSystem.script line 659.
//
// Compatibility: uses @wrapMethod and calls wrappedMethod exactly once, so it
// chains with other wraps of the same method — custom-faster-xp applies a global
// 0.6x, so with both enabled the five skills land at ~0.48x total (-52%,
// multiplicative, intended); everything else gets the plain 0.6x.
// -----------------------------------------------------------------------------
module CustomProgressionXP

// Multiplier for the five progression skills. Kept as Float so a future manual
// edit to a fractional value (e.g. 2.5) still rounds sensibly in the wrap below.
func ProgressionXpMultiplier() -> Float {
  return 0.8;
}

// True only for the five patch-2.x progression skills.
func IsProgressionSkillXp(type: gamedataProficiencyType) -> Bool {
  return Equals(type, gamedataProficiencyType.CoolSkill)                // Headhunter
      || Equals(type, gamedataProficiencyType.IntelligenceSkill)        // Netrunner
      || Equals(type, gamedataProficiencyType.ReflexesSkill)            // Shinobi
      || Equals(type, gamedataProficiencyType.StrengthSkill)            // Solo (Body)
      || Equals(type, gamedataProficiencyType.TechnicalAbilitySkill);   // Engineer
}

@wrapMethod(PlayerDevelopmentData)
public final const func AddExperience(amount: Int32, type: gamedataProficiencyType, telemetryGainReason: telemetryLevelGainReason, opt isDebug: Bool) -> Void {
  if IsProgressionSkillXp(type) && amount > 0 {
    // Float multiply + round-half-up, then back to Int32. NO minimum-gain floor
    // (never had one, and none wanted — user spec 2026-07-14): at the 0.8x rate,
    // awards too small for the rounding to move stay exactly vanilla, by design.
    // A 1 XP award stays 1 (1*0.8+0.5 = 1.3 -> 1), so nothing is zeroed out.
    // The `amount > 0` guard keeps the rounding well-defined (awards are never
    // negative in practice).
    amount = Cast<Int32>(Cast<Float>(amount) * ProgressionXpMultiplier() + 0.5);
  }
  wrappedMethod(amount, type, telemetryGainReason, isDebug);
}
