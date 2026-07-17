module SecondHeartFix

private func DeathVanish( scriptInterface : ref<StateGameScriptInterface> )
{
	let owner : ref<PlayerPuppet> = scriptInterface.owner as PlayerPuppet;
	let exitCombatDelay : Float = TweakDBInterface.GetFloat( t"Items.AdvancedOpticalCamoCommon.exitCombatDelay", 1.5 );
	let enableVisiblityDelay : Float = GameInstance.GetStatsSystem( owner.GetGame() ).GetStatValue( Cast<StatsObjectID>( owner.GetEntityID() ), gamedataStatType.OpticalCamoDuration );
	let hostileTargets : array<TrackedLocation> = owner.GetTargetTrackerComponent().GetHostileThreats( false );
	let hostileTarget : wref<GameObject>;
	let hostileTargetPuppet : wref<ScriptedPuppet>;
    let j : Int32 = 0;
	let vanishEvt : ref<ExitCombatOnOpticalCamoActivatedEvent>;
	owner.SetInvisible( true );
    while j < ArraySize( hostileTargets )
	{
		hostileTarget = hostileTargets[j].entity as GameObject;
		hostileTargetPuppet = hostileTarget as ScriptedPuppet;
		if IsDefined( hostileTargetPuppet )
		{
			hostileTargetPuppet.GetTargetTrackerComponent().DeactivateThreat( owner );
		}
		vanishEvt = new ExitCombatOnOpticalCamoActivatedEvent();
		vanishEvt.npc = hostileTarget;
		GameInstance.GetDelaySystem( owner.GetGame() ).DelayEvent( owner, vanishEvt, 0.1 );
		j += 1;
	}
}

@wrapMethod(ResurrectEvents)
protected func OnExit(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void 
{
	let owner : ref<PlayerPuppet> = scriptInterface.owner as PlayerPuppet;
    let enableVisibilityEvt : ref<EnablePlayerVisibilityEvent> = new EnablePlayerVisibilityEvent();
	wrappedMethod( stateContext, scriptInterface );
    GameInstance.GetDelaySystem( owner.GetGame() ).DelayEvent( owner, enableVisibilityEvt, 0.1 );
}

@wrapMethod(HighLevelTransition)
protected final func StartDeathEffects(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void
{
	DeathVanish( scriptInterface );
	wrappedMethod( stateContext, scriptInterface );
}

@wrapMethod(HighLevelTransition)
protected final func EvaluateSettingCustomDeathAnimation(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void 
{
	if ( this.HasSecondHeart( scriptInterface ) )
	{
    	this.SetPlayerDeathAnimFeatureData(stateContext, scriptInterface, 1);
		return;
	}
	wrappedMethod( stateContext, scriptInterface );
}

@wrapMethod(DeathEvents)
protected final func OnEnter(stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Void
{
	if ( this.HasSecondHeart( scriptInterface ) )
	{
		GameInstance.GetTimeSystem( scriptInterface.GetGame() ).UnsetTimeDilation( n"" );
		GameInstance.GetTimeSystem( scriptInterface.GetGame() ).UnsetTimeDilationOnLocalPlayerZero( n"" );
		stateContext.SetTemporaryBoolParameter( n"requestSandevistanDeactivation", true, true );
		stateContext.SetTemporaryBoolParameter( n"requestKerenzikovDeactivation", true, true );		
		GameInstance.GetRazerChromaEffectsSystem( scriptInterface.GetGame() ).StopAnimation( n"SlowMotion" );
		this.StartDeathEffects( stateContext, scriptInterface );
		this.isDyingEffectPlaying = false;
		super.OnEnter ( stateContext, scriptInterface );
		this.ForceDisableToggleWalk( stateContext );
		return;
	}
	wrappedMethod ( stateContext, scriptInterface );
}

@replaceMethod(DeathDecisionsWithResurrection)
protected func ToResurrect( stateContext: ref<StateContext>, scriptInterface: ref<StateGameScriptInterface>) -> Bool
{
	if( this.IsResurrectionAllowed( stateContext, scriptInterface ) )
	{
		if( this.GetInStateTime() >= this.GetStaticFloatParameterDefault( "stateDuration", 8.0 ) )
		{
			return true;
		}
	}
	return false;
}