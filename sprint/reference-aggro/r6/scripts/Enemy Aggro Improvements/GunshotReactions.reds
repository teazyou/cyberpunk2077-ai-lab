@replaceMethod(ReactionManagerComponent)
public func ShouldIgnoreCombatStim( stimType : gamedataStimType, instigator : wref< ScriptedPuppet >, source : wref< ScriptedPuppet >, sourcePos : Vector4, canDelay : Bool, out canIgnoreOnlyDueToDelay : Bool, out canIgnorePlayerCombatStim : Bool, log : Bool ) -> Bool
{
	let puppet : ref<ScriptedPuppet>;
	let playerPuppet : ref<PlayerPuppet>;
	let otherPuppet : ref<ScriptedPuppet>;
	let isNPCInCombat : Bool;
	let isPlayerInCombat : Bool;
	let inDangerRange : Bool;
	let squadMates : array< wref< Entity > >;
	if !( IsDefined( instigator ) )
	{
		return false;
	}
	if !( IsDefined( source ) )
	{
		source = instigator;
	}
	if( !( IsDefined( source ) ) || !( source.IsPlayer() ) )
	{
		return false;
	}
	if( !( StimFilters.CanBeIgnoredInCombat( stimType ) ) )
	{
		return false;
	}
	isNPCInCombat = this.HasCombatTarget();
	playerPuppet = source as PlayerPuppet;
	isPlayerInCombat = playerPuppet.IsInCombat();
	if( ( !( isNPCInCombat ) && !( isPlayerInCombat ) ) && this.CombatGracePeriodPassed( playerPuppet ) )
	{
		if( canDelay )
		{
			canIgnoreOnlyDueToDelay = true;
		}
		else
		{
			return false;
		}
	}
	puppet = this.GetOwnerPuppet();
	if( NPCPuppet.IsInCombatWithTarget( puppet, source ) )
	{
		return false;
	}
	canIgnorePlayerCombatStim = true;
	if( StimFilters.IsProjectile( stimType ) && this.IsTargetPositionClose( sourcePos, 4.0 ) )
	{
		if( log )
		{
			this.LogInfo( "can't be ignored - projectile hit nearby" );
		}
		return false;
	}
	inDangerRange = this.IsTargetPositionClose( sourcePos, 35.0 ); // was 12.0
	if( Equals( stimType, gamedataStimType.Explosion ) ) //&& inDangerRange )
	{
		if( log )
		{
			this.LogInfo( "can't be ignored - explosion nearby" );
		}
		return false;
	}
	if( StimFilters.IsGunshot( stimType ) )
	{
		if( inDangerRange )
		{
			if( log )
			{
				this.LogInfo( "can't be ignored - gunshot nearby" );
			}
			return false;
		}
		if( ReactionManagerComponent.InGunshotCone( source, puppet ) )
		{
			if( log )
			{
				this.LogInfo( "can't be ignored - gunshot at owner" );
			}
			return false;
		}
	}
	//if( ( StimFilters.IsIllegal( stimType ) && inDangerRange ) && ReactionManagerComponent.InGunshotCone( source, puppet ) )
	if( StimFilters.IsIllegal( stimType ) && ReactionManagerComponent.InGunshotCone( source, puppet ) )
	{
		if( log )
		{
			this.LogInfo( "can't be ignored - nearby illegal action directed at owner" );
		}
		return false;
	}
	if( this.IsTargetVeryClose( source ) )
	{
		if( log )
		{
			this.LogInfo( "can't be ignored - player very close to owner" );
		}
		return false;
	}
	if( puppet.IsConnectedToSecuritySystem() )
	{
		if( puppet.IsTargetTresspassingMyZone( source ) )
		{
			if( log )
			{
				this.LogInfo( "can't be ignored - player trespassing security zone" );
			}
			return false;
		}
	}
	AISquadHelper.GetSquadmates( puppet, squadMates );
	//for( i = 0; i < squadMates.Size(); i += 1 )
	for squadMate in squadMates
	{
		otherPuppet = squadMate as ScriptedPuppet;
		if( IsDefined( otherPuppet ) && NPCPuppet.IsInCombatWithTarget( otherPuppet, source ) )
		{
			if( log )
			{
				this.LogInfo( "can't be ignored - squadmate in combat with player" );
			}
			return false;
		}
	}
	return true;
}


@replaceMethod(ReactionManagerComponent)
private func ShouldHelpTargetFromSameAttitudeGroup( target : wref< GameObject >, targetOfTarget : wref< GameObject > ) -> Bool
{
	let ownerPuppet : ref<ScriptedPuppet>;
	let targetPuppet : ref<ScriptedPuppet>;
	let preventionSys : ref<PreventionSystem>;
	let affiliation1 : wref<Affiliation_Record>;
	let affiliation2 : wref<Affiliation_Record>;

	ownerPuppet = this.GetOwnerPuppet();
	targetPuppet = targetOfTarget as ScriptedPuppet;
	if( IsDefined( ownerPuppet) && IsDefined( targetPuppet ) )
	{
		affiliation1 = TweakDBInterface.GetCharacterRecord( ownerPuppet.GetRecordID() ).Affiliation();
		affiliation2 = TweakDBInterface.GetCharacterRecord( targetPuppet.GetRecordID() ).Affiliation();

		if( NotEquals( affiliation1, affiliation2 ) && NotEquals( ownerPuppet.GetAttitudeAgent().GetAttitudeGroup(), target.GetAttitudeAgent().GetAttitudeGroup() ) )
		{
			return false;
		}
	}
	else if( NotEquals( ownerPuppet.GetAttitudeAgent().GetAttitudeGroup(), target.GetAttitudeAgent().GetAttitudeGroup() ) )
	{
		return false;
	}
	if( IsDefined( targetOfTarget ) ) //&& !( targetOfTarget.IsPlayer() ) )
	{
		return true;
	}
	preventionSys = ownerPuppet.GetPreventionSystem();
	if( ( ( preventionSys.IsChasingPlayer() && target.IsPrevention() ) && ownerPuppet.IsPrevention() ) && preventionSys.ShouldWorkSpotPoliceJoinChase( ownerPuppet ) )
	{
		return true;
	}
	return false;
}