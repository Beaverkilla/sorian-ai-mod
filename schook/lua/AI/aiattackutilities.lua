do
local SUtils = import('/lua/AI/sorianutilities.lua')

function GetBestThreatTarget(aiBrain, platoon, bSkipPathability)
    
    #---------------------------------------------------------------------------------
    # This is the primary function for determining what to attack on the map
    # This function uses two user-specified types of "threats" to determine what to attack
    
    
    # Specify what types of "threat" to attack
    # Threat isn't just what's threatening, but is a measure of various
    # strengths in the game.  For example, 'Land' threat is a measure of
    # how many mobile land units are in a given threat area
    # Economy is a measure of how many economy-generating units there are
    # in a given threat area
    # Overall is a sum of all the types of threats
    # AntiSurface is a measure of  how much damage the units in an area can
    # do to surface-dwelling units.
    # there are many other types of threat... CATCH THEM ALL
           
    local PrimaryTargetThreatType = 'Land'        
    local SecondaryTargetThreatType = 'Economy'   
    
    
    # These are the values that are used to weight the two types of "threats"
    # primary by default is weighed most heavily, while a secondary threat is
    # weighed less heavily
    local PrimaryThreatWeight = 20
    local SecondaryThreatWeight = 0.5
    
    # After being sorted by those two types of threats, the places to attack are then
    # sorted by distance.  So you don't have to worry about specifying that units go
    # after the closest valid threat - they do this naturally.
    
    # If the platoon we're sending is weaker than a potential target, lower
    # the desirability of choosing that target by this factor
    local WeakAttackThreatWeight = 8 #10
    
    # If the platoon we're sending is stronger than a potential target, raise
    # the desirability of choosing that target by this factor
    local StrongAttackThreatWeight = 8
    
    
    # We can also tune the desirability of a target based on various
    # distance thresholds.  The thresholds are very near, near, mid, far
    # and very far.  The Radius value represents the largest distance considered
    # in a given category; the weight is the multiplicative factor used to increase
    # the desirability for the distance category   

    local VeryNearThreatWeight = 20000
    local VeryNearThreatRadius = 25

    local NearThreatWeight = 2500
    local NearThreatRadius = 75
    
    local MidThreatWeight = 500    
    local MidThreatRadius = 150
 
    local FarThreatWeight = 100
    local FarThreatRadius = 300 
    
    # anything that's farther than the FarThreatRadius is considered VeryFar           
    local VeryFarThreatWeight = 1

    # if the platoon is weaker than this threat level, then ignore stronger targets if they're stronger by
    # the given ratio
    local IgnoreStrongerTargetsIfWeakerThan = 5
    local IgnoreStrongerTargetsRatio = 10.0
    # If the platoon is weaker than the target, and the platoon represents a 
    # larger fraction of the unitcap this this value, then ignore
    # the strength of target - the platoon's death brings more units
    local IgnoreStrongerUnitCap = 0.8
     
    # When true, ignores the commander's strength in determining defenses at target location         
    local IgnoreCommanderStrength = true
     
    # If the combined threat of both primary and secondary threat types
    # is less than this level, then just outright ignore it as a threat
    local IgnoreThreatLessThan = 15
    # if the platoon is stronger than this threat level, then ignore weaker targets if the platoon is stronger
    # by the given ratio
    local IgnoreWeakerTargetsIfStrongerThan = 20
    local IgnoreWeakerTargetsRatio = 5

    # When evaluating threat, how many rings in the threat grid do we look at
    local EnemyThreatRings = 1
    # if we've already chosen an enemy, should this platoon focus on that enemy    
    local TargetCurrentEnemy = true
    
    #---------------------------------------------------------------------------------
        
    local platoonPosition = platoon:GetPlatoonPosition()
    local selectedWeaponArc = 'None'
    
    if not platoonPosition then
        #Platoon no longer exists.
        return false
    end
    
    # get overrides in platoon data
    local ThreatWeights = platoon.PlatoonData.ThreatWeights
    if ThreatWeights then
        PrimaryThreatWeight = ThreatWeights.PrimaryThreatWeight or PrimaryThreatWeight
        SecondaryThreatWeight = ThreatWeights.SecondaryThreatWeight or SecondaryThreatWeight
        WeakAttackThreatWeight = ThreatWeights.WeakAttackThreatWeight or WeakAttackThreatWeight
        StrongAttackThreatWeight = ThreatWeights.StrongAttackThreatWeight or StrongAttackThreatWeight
        FarThreatWeight = ThreatWeights.FarThreatWeight or FarThreatWeight
        NearThreatWeight = ThreatWeights.NearThreatWeight or NearThreatWeight
        NearThreatRadius = ThreatWeights.NearThreatRadius or NearThreatRadius
        IgnoreStrongerTargetsIfWeakerThan = ThreatWeights.IgnoreStrongerTargetsIfWeakerThan or IgnoreStrongerTargetsIfWeakerThan
        IgnoreStrongerTargetsRatio = ThreatWeights.IgnoreStrongerTargetsRatio or IgnoreStrongerTargetsRatio 
        SecondaryTargetThreatType = SecondaryTargetThreatType or ThreatWeights.SecondaryTargetThreatType
        IgnoreCommanderStrength = IgnoreCommanderStrength or ThreatWeights.IgnoreCommanderStrength
        IgnoreWeakerTargetsIfStrongerThan = ThreatWeights.IgnoreWeakerTargetsIfStrongerThan or IgnoreWeakerTargetsIfStrongerThan
        IgnoreWeakerTargetsRatio = ThreatWeights.IgnoreWeakerTargetsRatio or IgnoreWeakerTargetsRatio        
        IgnoreThreatLessThan = ThreatWeights.IgnoreThreatLessThan or IgnoreThreatLessThan
        PrimaryTargetThreatType = ThreatWeights.PrimaryTargetThreatType or PrimaryTargetThreatType
        SecondaryTargetThreatType = ThreatWeights.SecondaryTargetThreatType or SecondaryTargetThreatType
        EnemyThreatRings = ThreatWeights.EnemyThreatRings or EnemyThreatRings
        TargetCurrentEnemy = ThreatWeights.TargetCurrentyEnemy or TargetCurrentEnemy
    end       
    
    # Need to use overall so we can get all the threat points on the map and then filter from there
    # if a specific threat is used, it will only report back threat locations of that type
    local enemyIndex = -1
    if aiBrain:GetCurrentEnemy() and TargetCurrentEnemy then
        enemyIndex = aiBrain:GetCurrentEnemy():GetArmyIndex()
    end
    
    local threatTable = aiBrain:GetThreatsAroundPosition(platoonPosition, 16, true, 'Overall', enemyIndex )
    
    if table.getn(threatTable) == 0 then
        return false
    end
    
    local platoonUnits = platoon:GetPlatoonUnits()
    #eval platoon threat  
    local myThreat = GetThreatOfUnits(platoon)
    local friendlyThreat = aiBrain:GetThreatAtPosition( platoonPosition, 1, true, ThreatTable[platoon.MovementLayer], aiBrain:GetArmyIndex() ) - myThreat
    friendlyThreat = friendlyThreat * -1

    local threatDist
    local curMaxThreat = -99999999
    local curMaxIndex = 1
    local foundPathableThreat = false
    local mapSizeX = ScenarioInfo.size[1]
    local mapSizeZ = ScenarioInfo.size[2]
    local maxMapLengthSq = math.sqrt((mapSizeX * mapSizeX) + (mapSizeZ * mapSizeZ))
    local logCount = 0
    
    local unitCapRatio = GetArmyUnitCostTotal(aiBrain:GetArmyIndex()) / GetArmyUnitCap(aiBrain:GetArmyIndex())
    
    local maxRange = false
	local turretPitch = nil
	local per = ScenarioInfo.ArmySetup[aiBrain.Name].AIPersonality
    if platoon.MovementLayer == 'Water' then
		
		if string.find(per, 'sorian') then
			maxRange, selectedWeaponArc, turretPitch = GetNavalPlatoonMaxRangeSorian(aiBrain, platoon)
		else        
			maxRange, selectedWeaponArc = GetNavalPlatoonMaxRange(aiBrain, platoon)
		end
    end
    
    for tIndex,threat in threatTable do 
        #check if we can path to the position or a position nearby
        if not bSkipPathability then
            if platoon.MovementLayer != 'Water' then
                local success, bestGoalPos = CheckPlatoonPathingEx(platoon, {threat[1], 0, threat[2]})
                logCount = logCount + 1
                if not success then

                    local okThresholdSq = 32 * 32
                    local distSq = (threat[1] - bestGoalPos[1]) * (threat[1] - bestGoalPos[1]) + (threat[2] - bestGoalPos[3]) * (threat[2] - bestGoalPos[3])
                    
                    if distSq < okThresholdSq then
                        threat[1] = bestGoalPos[1]
                        threat[2] = bestGoalPos[3]
                    else
                        continue
                    end
                else
                    threat[1] = bestGoalPos[1]
                    threat[2] = bestGoalPos[3]
                end
            else
				local bestPos
				if string.find(per, 'sorian') then
					bestPos = CheckNavalPathingSorian(aiBrain, platoon, {threat[1], 0, threat[2]}, maxRange, selectedWeaponArc, turretPitch)
				else
					bestPos = CheckNavalPathing(aiBrain, platoon, {threat[1], 0, threat[2]}, maxRange, selectedWeaponArc)
				end
				if not bestPos then
					continue
				end
            end
        end
        
        #threat[3] represents the best target
        
        # calculate new threat
        # for debugging
        ################
        local baseThreat = 0
        local targetThreat = 0
        local distThreat = 0
        
        local primaryThreat = 0
        local secondaryThreat = 0
        #################
        
        # Determine the value of the target
        primaryThreat = aiBrain:GetThreatAtPosition( {threat[1], 0, threat[2]}, 1, true, PrimaryTargetThreatType, enemyIndex )
        secondaryThreat = aiBrain:GetThreatAtPosition( {threat[1], 0, threat[2]}, 1, true, SecondaryTargetThreatType, enemyIndex )
        
        baseThreat = primaryThreat + secondaryThreat
        
        targetThreat = ( primaryThreat or 0 ) * PrimaryThreatWeight + ( secondaryThreat or 0 ) * SecondaryThreatWeight
        threat[3] = targetThreat
        
        # Determine relative strength of platoon compared to enemy threat
        local enemyThreat = aiBrain:GetThreatAtPosition( {threat[1], 0, threat[2]}, EnemyThreatRings, true, ThreatTable[platoon.MovementLayer] or 'AntiSurface')
        if IgnoreCommanderStrength then
            enemyThreat = enemyThreat - aiBrain:GetThreatAtPosition( {threat[1], EnemyThreatRings, threat[2]}, 1, true, 'Commander')
        end
        #defaults to no threat (threat difference is opposite of platoon threat)
        local threatDiff =  myThreat - enemyThreat

        if threatDiff <= 0 then
            # if we have no threat... what happened?  Also don't attack things way stronger than us
            if myThreat <= IgnoreStrongerTargetsIfWeakerThan 
                    and (myThreat == 0 or enemyThreat / (myThreat + friendlyThreat) > IgnoreStrongerTargetsRatio) 
                    and unitCapRatio < IgnoreStrongerUnitCap then
                continue
            end
            # if we're weaker than the enemy... make the target less attractive anyway
            threat[3] = threat[3] + threatDiff * WeakAttackThreatWeight
        else
            # ignore overall threats that are really low, otherwise we want to defeat the enemy wherever they are
            if (baseThreat <= IgnoreThreatLessThan) or (myThreat >= IgnoreWeakerTargetsIfStrongerThan and (enemyThreat == 0 or myThreat / enemyThreat > IgnoreWeakerTargetsRatio)) then
                continue
            end
            threat[3] = threat[3] + threatDiff * StrongAttackThreatWeight
        end
        
        # only add distance if there's a threat at all
        local threatDistNorm = -1
        if targetThreat > 0 then
            threatDist = math.sqrt(VDist2Sq(threat[1], threat[2], platoonPosition[1], platoonPosition[3]))
            #distance is 1-100 of the max map length, distance function weights are split by the distance radius
			
            threatDistNorm = 100 * threatDist / maxMapLengthSq
            if threatDistNorm < 1 then
                threatDistNorm = 1
            end
            # farther away is less threatening, so divide
            if threatDist <= VeryNearThreatRadius then
                threat[3] = threat[3] + VeryNearThreatWeight / threatDistNorm
                distThreat = VeryNearThreatWeight / threatDistNorm
            elseif threatDist <= NearThreatRadius then
                threat[3] = threat[3] + MidThreatWeight / threatDistNorm
                distThreat = MidThreatWeight / threatDistNorm
            elseif threatDist <= MidThreatRadius then
                threat[3] = threat[3] + NearThreatWeight / threatDistNorm
                distThreat = NearThreatWeight / threatDistNorm
            elseif threatDist <= FarThreatRadius then
                threat[3] = threat[3] + FarThreatWeight / threatDistNorm
                distThreat = FarThreatWeight / threatDistNorm
            else
                threat[3] = threat[3] + VeryFarThreatWeight / threatDistNorm
                distThreat = VeryFarThreatWeight / threatDistNorm
            end
            
            # store max value
            if threat[3] > curMaxThreat then
                curMaxThreat = threat[3]
                curMaxIndex = tIndex
            end
            foundPathableThreat = true
       end #ignoreThreat
    end #threatTable loop
    
    #no pathable threat found (or no threats at all)
    if not foundPathableThreat or curMaxThreat == 0 then
        return false
    end
    local x = threatTable[curMaxIndex][1]
    local y = GetTerrainHeight( threatTable[curMaxIndex][1], threatTable[curMaxIndex][2] )
    local z = threatTable[curMaxIndex][2]

    return {x, y, z}
    
end

function CheckNavalPathingSorian(aiBrain, platoon, location, maxRange, selectedWeaponArc, turretPitch)
    local platoonUnits = platoon:GetPlatoonUnits()
	local platoonPosition = platoon:GetPlatoonPosition()
    selectedWeaponArc = selectedWeaponArc or 'none'
    
    local success, bestGoalPos
    local threatTargetPos = location
    local isTech1 = false

    local inWater = GetTerrainHeight(location[1], location[3]) < GetSurfaceHeight(location[1], location[3]) - 2
    
    #if this threat is in the water, see if we can get to it
    if inWater then
        success, bestGoalPos = CheckPlatoonPathingEx(platoon, {location[1], 0, location[3]})
    end
    
    #if it is not in the water or we can't get to it, then see if there is water within weapon range that we can get to
    if not success and maxRange then
        #Check vectors in 8 directions around the threat location at maxRange to see if they are in water.
        local rootSaver = maxRange / 1.4142135623 #For diagonals. X and Z components of the vector will have length maxRange / sqrt(2)
        local vectors = {
            {location[1],             0, location[3] + maxRange},   #up
            {location[1],             0, location[3] - maxRange},   #down
            {location[1] + maxRange,  0, location[3]},              #right
            {location[1] - maxRange,  0, location[3]},              #left
            
            {location[1] + rootSaver,  0, location[3] + rootSaver},   #right-up
            {location[1] + rootSaver,  0, location[3] - rootSaver},   #right-down
            {location[1] - rootSaver,  0, location[3] + rootSaver},   #left-up
            {location[1] - rootSaver,  0, location[3] - rootSaver},   #left-down
        }
        
        #Sort the vectors by their distance to us.
        table.sort(vectors, function(a,b)
            local distA = VDist2Sq(platoonPosition[1], platoonPosition[3], a[1], a[3])
            local distB = VDist2Sq(platoonPosition[1], platoonPosition[3], b[1], b[3])
            
            return distA < distB
        end)
        
        #Iterate through the vector list and check if each is in the water. Use the first one in the water that has enemy structures in range.
        for _,vec in vectors do
            inWater = GetTerrainHeight(vec[1], vec[3]) < GetSurfaceHeight(vec[1], vec[3]) - 2
            
            if inWater then
                success, bestGoalPos = CheckPlatoonPathingEx(platoon, vec)
            end
            
            if success and turretPitch then
                success = not SUtils.CheckBlockingTerrain(bestGoalPos, threatTargetPos, selectedWeaponArc, turretPitch)
            end
            
            if success then 
                #I hate having to do this check, but the influence map doesn't have enough resolution and without it the boats
                #will just get stuck on the shore. The code hits this case about once every 5-10 seconds on a large map with 4 naval AIs
                local numUnits = aiBrain:GetNumUnitsAroundPoint( categories.NAVAL + categories.STRUCTURE, bestGoalPos, maxRange, 'Enemy')
                if numUnits > 0 then
                    break
                else
                    success = false
                end
            end
        end
    end
    
    return bestGoalPos
end

function CheckNavalPathing(aiBrain, platoon, location, maxRange, selectedWeaponArc)    
    local platoonUnits = platoon:GetPlatoonUnits()
	local platoonPosition = platoon:GetPlatoonPosition()
    selectedWeaponArc = selectedWeaponArc or 'none'
    
    local success, bestGoalPos
    local threatTargetPos = location
    local isTech1 = false

    local inWater = GetTerrainHeight(location[1], location[3]) < GetSurfaceHeight(location[1], location[3]) - 2
    
    #if this threat is in the water, see if we can get to it
    if inWater then
        success, bestGoalPos = CheckPlatoonPathingEx(platoon, {location[1], 0, location[3]})
    end
    
    #if it is not in the water or we can't get to it, then see if there is water within weapon range that we can get to
    if not success and maxRange then
        #Check vectors in 8 directions around the threat location at maxRange to see if they are in water.
        local rootSaver = maxRange / 1.4142135623 #For diagonals. X and Z components of the vector will have length maxRange / sqrt(2)
        local vectors = {
            {location[1],             0, location[3] + maxRange},   #up
            {location[1],             0, location[3] - maxRange},   #down
            {location[1] + maxRange,  0, location[3]},              #right
            {location[1] - maxRange,  0, location[3]},              #left
            
            {location[1] + rootSaver,  0, location[3] + rootSaver},   #right-up
            {location[1] + rootSaver,  0, location[3] - rootSaver},   #right-down
            {location[1] - rootSaver,  0, location[3] + rootSaver},   #left-up
            {location[1] - rootSaver,  0, location[3] - rootSaver},   #left-down
        }
        
        #Sort the vectors by their distance to us.
        table.sort(vectors, function(a,b)
            local distA = VDist2Sq(platoonPosition[1], platoonPosition[3], a[1], a[3])
            local distB = VDist2Sq(platoonPosition[1], platoonPosition[3], b[1], b[3])
            
            return distA < distB
        end)
        
        #Iterate through the vector list and check if each is in the water. Use the first one in the water that has enemy structures in range.
        for _,vec in vectors do
            inWater = GetTerrainHeight(vec[1], vec[3]) < GetSurfaceHeight(vec[1], vec[3]) - 2
            
            if inWater then
                success, bestGoalPos = CheckPlatoonPathingEx(platoon, vec)
            end
            
            if success then
                success = not aiBrain:CheckBlockingTerrain(bestGoalPos, threatTargetPos, selectedWeaponArc)
            end
            
            if success then 
                #I hate having to do this check, but the influence map doesn't have enough resolution and without it the boats
                #will just get stuck on the shore. The code hits this case about once every 5-10 seconds on a large map with 4 naval AIs
                local numUnits = aiBrain:GetNumUnitsAroundPoint( categories.NAVAL + categories.STRUCTURE, bestGoalPos, maxRange, 'Enemy')
                if numUnits > 0 then
                    break
                else
                    success = false
                end
            end
        end
    end
    
    return bestGoalPos
end

function GetNavalPlatoonMaxRangeSorian(aiBrain, platoon)
    local maxRange = 0
	local selectedWeaponArc = 'none'
	local turretPitch = nil
    local platoonUnits = platoon:GetPlatoonUnits()
    for _,unit in platoonUnits do
        if unit:IsDead() then
            continue
        end
        
        for _,weapon in unit:GetBlueprint().Weapon do
            if not weapon.FireTargetLayerCapsTable or not weapon.FireTargetLayerCapsTable.Water then
                continue
            end
        
            #Check if the weapon can hit land from water
            local AttackAir = string.find(weapon.FireTargetLayerCapsTable.Water, 'Air', 1, true)
            
            if not AttackAir and weapon.MaxRadius > maxRange then 
                if weapon.BallisticArc == 'RULEUBA_LowArc' then
                    selectedWeaponArc = 'low'
					turretPitch = weapon.TurretPitchRange
                elseif weapon.BallisticArc == 'RULEUBA_HighArc' then
                    selectedWeaponArc = 'high'
					turretPitch = weapon.TurretPitchRange
                elseif weapon.BallisticArc == 'RULEUBA_None' and weapon.TurretPitchRange > 0 then
                    selectedWeaponArc = 'none'
					turretPitch = weapon.TurretPitchRange
                elseif weapon.BallisticArc == 'RULEUBA_None' then
                    selectedWeaponArc = 'none'
					turretPitch = nil
				else
					continue
                end
                maxRange = weapon.MaxRadius
            end
        end
    end
    
    if maxRange == 0 then
        return false
    end
	#LOG('*AI DEBUG: GetNavalPlatoonMaxRangeSorian maxRange: '..maxRange..' selectedWeaponArc: '..selectedWeaponArc..' turretPitch: '..turretPitch)
    return maxRange, selectedWeaponArc, turretPitch
end

function GetLandPlatoonMaxRangeSorian(aiBrain, platoon)
    local maxRange = 0
	local selectedWeaponArc = 'none'
	local turretPitch = nil
    local platoonUnits = platoon:GetPlatoonUnits()
    for _,unit in platoonUnits do
        if unit:IsDead() then
            continue
        end
        
        for _,weapon in unit:GetBlueprint().Weapon do
            if not weapon.FireTargetLayerCapsTable or not weapon.FireTargetLayerCapsTable.Land then
                continue
            end
            
            local AttackAir = string.find(weapon.FireTargetLayerCapsTable.Land, 'Air', 1, true)
            
            if not AttackAir and weapon.MaxRadius > maxRange then 
                if weapon.BallisticArc == 'RULEUBA_LowArc' then
                    selectedWeaponArc = 'low'
					turretPitch = weapon.TurretPitchRange
                elseif weapon.BallisticArc == 'RULEUBA_HighArc' then
                    selectedWeaponArc = 'high'
					turretPitch = weapon.TurretPitchRange
                elseif weapon.BallisticArc == 'RULEUBA_None' and weapon.TurretPitchRange > 0 then
                    selectedWeaponArc = 'none'
					turretPitch = weapon.TurretPitchRange
				else
					continue
                end
                maxRange = weapon.MaxRadius
            end
        end
    end
    
    if maxRange == 0 then
        return false
    end
	#LOG('*AI DEBUG: GetLandPlatoonMaxRangeSorian maxRange: '..maxRange..' selectedWeaponArc: '..selectedWeaponArc..' turretPitch: '..turretPitch)
    return maxRange, selectedWeaponArc, turretPitch
end

function GetClosestPathNodeInRadiusByLayerSorian(location, destination, radius, layer)
    
    local maxRadius = radius*radius
    local bestDist = 999999
    local bestMarker = false
    
    local graphTable =  GetPathGraphs()[layer]
    
    if graphTable then
        for name, graph in graphTable do
            for mn, markerInfo in graph do
                local distFromLoc = VDist2Sq(location[1], location[3], markerInfo.position[1], markerInfo.position[3])
                local distFromDest = VDist2Sq(markerInfo.position[1], markerInfo.position[3], destination[1], destination[3])
                    
                if distFromLoc < maxRadius and distFromDest < bestDist then 
                    bestDist = distFromDest
                    bestMarker = markerInfo
                end
            end
        end
    end
    
    return bestMarker
end

function PlatoonGenerateSafePathTo(aiBrain, platoonLayer, start, destination, optThreatWeight, optMaxMarkerDist, testPathDist)   
        
    local location = start
    optMaxMarkerDist = optMaxMarkerDist or 250
    optThreatWeight = optThreatWeight or 1
    local finalPath = {}
	local testPath = false
	
	local per = ScenarioInfo.ArmySetup[aiBrain.Name].AIPersonality

	#If it is a Sorian AI or Duncane AI and not a water unit.
	if (string.find(per, 'sorian') or DiskGetFileInfo('/lua/AI/altaiutilities.lua')) and platoonLayer != "Water" then
		testPath = true
	end
	
	#If we are within 100 units of the destination, don't bother pathing.
	if (VDist2Sq( start[1], start[3], destination[1], destination[3] ) <= 10000 or
		(testPathDist and VDist2Sq( start[1], start[3], destination[1], destination[3] ) <= testPathDist)) and
		testPath then
			table.insert(finalPath, destination)
			return finalPath
	end
	
    --Get the closest path node at the platoon's position
    local startNode
    #if testPath then
    #	startNode = GetClosestPathNodeInRadiusByLayerSorian(location, destination, optMaxMarkerDist, platoonLayer)
    #else
    	startNode = GetClosestPathNodeInRadiusByLayer(location, optMaxMarkerDist, platoonLayer)
    #end
    if not startNode and platoonLayer == 'Amphibious' then
        return PlatoonGenerateSafePathTo(aiBrain, 'Land', start, destination, optThreatWeight, optMaxMarkerDist)
    end
    if not startNode then return false, 'NoStartNode' end
    
    --Get the matching path node at the destiantion
    local endNode = GetClosestPathNodeInRadiusByGraph(destination, optMaxMarkerDist, startNode.graphName)
    if not endNode and platoonLayer == 'Amphibious' then
        return PlatoonGenerateSafePathTo(aiBrain, 'Land', start, destination, optThreatWeight, optMaxMarkerDist)
    end    
    if not endNode then return false, 'NoEndNode' end
    
     --Generate the safest path between the start and destination
    local path = GeneratePath(aiBrain, startNode, endNode, ThreatTable[platoonLayer], optThreatWeight, destination, location, testPath)
    if not path and platoonLayer == 'Amphibious' then
        return PlatoonGenerateSafePathTo(aiBrain, 'Land', start, destination, optThreatWeight, optMaxMarkerDist)
    end    
    if not path then return false, 'NoPath' end
        
    --Insert the path nodes (minus the start node and end nodes, which are close enough to our start and destination) into our command queue.
    #local finalPath = {}
    for i,node in path.path do
        if i > 1 and i < table.getn(path.path) then
              #platoon:MoveToLocation(node.position, false)
              table.insert(finalPath, node.position)
          end
    end

    #platoon:MoveToLocation(destination, false)
    table.insert(finalPath, destination)
    
    return finalPath
end

function GeneratePath(aiBrain, startNode, endNode, threatType, threatWeight, destination, location, testPath)
	if not aiBrain.PathCache then
		#Create path cache table. Paths are stored in this table and saved for 1 minute so
		#any other platoons needing to travel the same route can get the path without the extra work.
		aiBrain.PathCache = {}
	end
	if not aiBrain.PathCache[startNode.name] then
		aiBrain.PathCache[startNode.name] = {}
		aiBrain.PathCache[startNode.name][endNode.name] = {}
	end
	if not aiBrain.PathCache[startNode.name][endNode.name] then
		aiBrain.PathCache[startNode.name][endNode.name] = {}
	end
	
	if aiBrain.PathCache[startNode.name][endNode.name].path and aiBrain.PathCache[startNode.name][endNode.name].path != 'bad'
	and aiBrain.PathCache[startNode.name][endNode.name].settime + 60 > GetGameTimeSeconds() then
		return aiBrain.PathCache[startNode.name][endNode.name].path
	--elseif aiBrain.PathCache[startNode.name][endNode.name].path and aiBrain.PathCache[startNode.name][endNode.name].path == 'bad' then
	--	return false
	end
	
    threatWeight = threatWeight or 1
    
    local graph = GetPathGraphs()[startNode.layer][startNode.graphName]

    local closed = {}

    local queue = {
            path = {startNode, },
    }
	
	if testPath and VDist2Sq(location[1], location[3], startNode.position[1], startNode.position[3]) > 10000 and 
	SUtils.DestinationBetweenPoints(destination, location, startNode.position) then
		local newPath = {
				path = {newNode = {position = destination}, },
		}
		return newPath
	end
	
	local lastNode = startNode
	
	repeat
		if closed[lastNode] then 
			--aiBrain.PathCache[startNode.name][endNode.name] = { settime = 36000 , path = 'bad' }
			return false 
		end
		
		closed[lastNode] = true
		
        local mapSizeX = ScenarioInfo.size[1]
        local mapSizeZ = ScenarioInfo.size[2]
		
		local lowCost = false
		local bestNode = false
			
		for i, adjacentNode in lastNode.adjacent do
		
            local newNode = graph[adjacentNode]
			
			if not newNode or closed[newNode] then
				continue
			end
			
			if testPath and SUtils.DestinationBetweenPoints(destination, lastNode.position, newNode.position) then
				return queue
			end
            
            #local dist = math.sqrt(VDist2Sq(newNode.position[1], newNode.position[3], endNode.position[1], endNode.position[3]))
			local dist = VDist2Sq(newNode.position[1], newNode.position[3], endNode.position[1], endNode.position[3])

            # this brings the dist value from 0 to 100% of the maximum length with can travel on a map
            #dist = 100 * dist / math.sqrt((mapSizeX * mapSizeX) + (mapSizeZ * mapSizeZ))
			dist = 100 * dist / ( mapSizeX + mapSizeZ )
			
            --get threat from current node to adjacent node
            local threat = aiBrain:GetThreatBetweenPositions(newNode.position, lastNode.position, nil, threatType)
            
            --update path stuff
            local cost = dist + threat*threatWeight
			
			if lowCost and cost >= lowCost then
				continue
			end
			
			bestNode = newNode
			lowCost = cost
		end
		if bestNode then
			table.insert(queue.path,bestNode)
			lastNode = bestNode
		end		
	until lastNode == endNode
	
	aiBrain.PathCache[startNode.name][endNode.name] = { settime = GetGameTimeSeconds(), path = queue }
	
	return queue
end

function GeneratePathOld(aiBrain, startNode, endNode, threatType, threatWeight, destination, location, testPath)
	if not aiBrain.PathCache then
		#Create path cache table. Paths are stored in this table and saved for 1 minute so
		#any other platoons needing to travel the same route can get the path without the extra work.
		aiBrain.PathCache = {}
	end
	if not aiBrain.PathCache[startNode.name] then
		aiBrain.PathCache[startNode.name] = {}
		aiBrain.PathCache[startNode.name][endNode.name] = {}
	end
	if not aiBrain.PathCache[startNode.name][endNode.name] then
		aiBrain.PathCache[startNode.name][endNode.name] = {}
	end
	
	if aiBrain.PathCache[startNode.name][endNode.name].path and aiBrain.PathCache[startNode.name][endNode.name].path != 'bad'
	and aiBrain.PathCache[startNode.name][endNode.name].settime + 60 > GetGameTimeSeconds() then
		return aiBrain.PathCache[startNode.name][endNode.name].path
	--elseif aiBrain.PathCache[startNode.name][endNode.name].path and aiBrain.PathCache[startNode.name][endNode.name].path == 'bad' then
	--	return false
	end
    threatWeight = threatWeight or 1
    
    local graph = GetPathGraphs()[startNode.layer][startNode.graphName]
    
    --ZOMG A*
    local closed = {}
    
    --Queue will be sorted such that best path is at the end.
    local queue = { 
        {
            cost = 0, 
            path = {startNode, }, 
            threat = 0
        }
    }
	if testPath and VDist2Sq(location[1], location[3], startNode.position[1], startNode.position[3]) > 10000 and 
	SUtils.DestinationBetweenPoints(destination, location, startNode.position) then
			local newPath = {
				{
					cost = 0,
					path = {newNode = {position = destination}, },
					threat = 0
				}
			}
			return newPath
	end
    
    --I didn't know we had a continue statement when I wrote this, and this was a workaround to avoid using continue. :(
    local AStarLoopBody = function()
        local curPath = table.remove(queue)
        local lastNode = curPath.path[table.getn(curPath.path)]
        
        if closed[lastNode] then return false end
        
		if lastNode == endNode then
			return curPath
		end
		
        closed[lastNode] = true
        
        local mapSizeX = ScenarioInfo.size[1]
        local mapSizeZ = ScenarioInfo.size[2]
        for i, adjacentNode in lastNode.adjacent do
            local fork = {
                cost = curPath.cost, 
                path = {unpack(curPath.path)}, 
                threat = curPath.threat
            }
            
            local newNode = graph[adjacentNode]
            
            if newNode then
				if testPath and SUtils.DestinationBetweenPoints(destination, lastNode.position, newNode.position) then
						return curPath
				end
                --get distance from new node to end node
                local dist = VDist2Sq(newNode.position[1], newNode.position[3], endNode.position[1], endNode.position[3])

                # this brings the dist value from 0 to 100% of the maximum length with can travel on a map
                dist = 100 * dist / ( mapSizeX + mapSizeZ ) #(mapSizeX * mapSizeX  + mapSizeZ * mapSizeZ)
                
                --get threat from current node to adjacent node
                local threat = aiBrain:GetThreatBetweenPositions(newNode.position, lastNode.position, nil, threatType)
                           
                --update path stuff
                fork.cost = fork.cost + dist + threat*threatWeight
                fork.threat = fork.threat + threat
                
                --add the node to the path
                table.insert(fork.path, newNode)
                table.insert(queue,fork)
             end
        end
        
        --sort queue
        table.sort(queue, function(a,b) return a.cost > b.cost end)
		
        return false
    end
    
    --Do A*
    while table.getn(queue) > 0 do
        loopRet = AStarLoopBody()       
        
        if loopRet then
			aiBrain.PathCache[startNode.name][endNode.name] = { settime = GetGameTimeSeconds(), path = loopRet }
            return loopRet     
        end
    end
    
    return false
end

function AIPlatoonSquadAttackVectorSorian( aiBrain, platoon, bAggro )

    --Engine handles whether or not we can occupy our vector now, so this should always be a valid, occupiable spot.
    local attackPos = GetBestThreatTarget(aiBrain, platoon)
    
    local bNeedTransports = false
    # if no pathable attack spot found
    if not attackPos then
        # try skipping pathability
        attackPos = GetBestThreatTarget(aiBrain, platoon, true)
        bNeedTransports = true
        if not attackPos then
            platoon:StopAttack()
            return {}
        end
    end


    # avoid mountains by slowly moving away from higher areas
    GetMostRestrictiveLayer(platoon)
#    if platoon.MovementLayer == 'Land' then
#        local bestPos = attackPos
#        local attackPosHeight = GetTerrainHeight(attackPos[1], attackPos[3])
#        # if we're land
#        if attackPosHeight >= GetSurfaceHeight(attackPos[1], attackPos[3]) then
#            local lookAroundTable = {1,0,-2,-1,2}
#            local squareRadius = (ScenarioInfo.size[1] / 16) / table.getn(lookAroundTable)
#            for ix, offsetX in lookAroundTable do
#                for iz, offsetZ in lookAroundTable do
#                    local surf = GetSurfaceHeight( bestPos[1]+offsetX, bestPos[3]+offsetZ )
#                    local terr = GetTerrainHeight( bestPos[1]+offsetX, bestPos[3]+offsetZ )
#                    # is it lower land... make it our new position to continue searching around
#                    if terr >= surf and terr < attackPosHeight then
#                        bestPos[1] = bestPos[1] + offsetX
#                        bestPos[3] = bestPos[3] + offsetZ
#                        attackPosHeight = terr
#                    end
#                end
#            end
#        end
#        attackPos = bestPos
#    end
        
    local oldPathSize = table.getn(platoon.LastAttackDestination)
    
    # if we don't have an old path or our old destination and new destination are different
    if oldPathSize == 0 or attackPos[1] != platoon.LastAttackDestination[oldPathSize][1] or
    attackPos[3] != platoon.LastAttackDestination[oldPathSize][3] then
        
        GetMostRestrictiveLayer(platoon)
        # check if we can path to here safely... give a large threat weight to sort by threat first
        local path, reason = PlatoonGenerateSafePathTo(aiBrain, platoon.MovementLayer, platoon:GetPlatoonPosition(), attackPos, platoon.PlatoonData.NodeWeight or 10 )
    
        # clear command queue
        platoon:Stop()    
   
        local usedTransports = false
        local position = platoon:GetPlatoonPosition()
		local inBase = false
		local homeBase = aiBrain.BuilderManagers[platoon.PlatoonData.LocationType].Position
		
		if not position then
			return {}
		end
		
		if homeBase and VDist2Sq(position[1], position[3], homeBase[1], homeBase[3]) < 100*100 then
			inBase = true
		end		
        if (not path and reason == 'NoPath') or bNeedTransports then
            usedTransports = SendPlatoonWithTransportsSorian(aiBrain, platoon, attackPos, true, false, true)
        # Require transports over 512 away
        elseif VDist2Sq( position[1], position[3], attackPos[1], attackPos[3] ) > 512*512 and inBase then
            usedTransports = SendPlatoonWithTransportsSorian(aiBrain, platoon, attackPos, true, false, false)
        # use if possible at 256
        elseif VDist2Sq( position[1], position[3], attackPos[1], attackPos[3] ) > 256*256 and inBase then
            usedTransports = SendPlatoonWithTransportsSorian(aiBrain, platoon, attackPos, false, false, false)
        end
        
        if not usedTransports then
            if not path then
                if reason == 'NoStartNode' or reason == 'NoEndNode' then
                    --Couldn't find a valid pathing node. Just use shortest path.
                    platoon:AggressiveMoveToLocation(attackPos)
                end
                # force reevaluation
                platoon.LastAttackDestination = {attackPos}
            else
                local pathSize = table.getn(path)
                # store path
                platoon.LastAttackDestination = path
                # move to new location
                for wpidx,waypointPath in path do
                    if wpidx == pathSize or bAggro then
                        platoon:MoveToLocation(waypointPath, false) #platoon:AggressiveMoveToLocation(waypointPath)
                    else
                        platoon:MoveToLocation(waypointPath, false)
                    end
                end   
            end
        end
    end 
    
    # return current command queue 
    local cmd = {}
    for k,v in platoon:GetPlatoonUnits() do
        if not v:IsDead() then
            local unitCmdQ = v:GetCommandQueue()
            for cmdIdx,cmdVal in unitCmdQ do
                table.insert(cmd, cmdVal)
                break
            end
        end
    end
    return cmd
end

function AIPlatoonNavalAttackVectorSorian( aiBrain, platoon )

    GetMostRestrictiveLayer(platoon)
    --Engine handles whether or not we can occupy our vector now, so this should always be a valid, occupiable spot.
    local attackPos, targetPos = GetBestThreatTarget(aiBrain, platoon)
    
    # if no pathable attack spot found
    if not attackPos then
        return {}
    end
        
    local oldPathSize = table.getn(platoon.LastAttackDestination)
    
    # if we don't have an old path or our old destination and new destination are different
    if oldPathSize == 0 or attackPos[1] != platoon.LastAttackDestination[oldPathSize][1] or
    attackPos[3] != platoon.LastAttackDestination[oldPathSize][3] then
        
        # check if we can path to here safely... give a large threat weight to sort by threat first
        local path, reason = PlatoonGenerateSafePathTo(aiBrain, platoon.MovementLayer, platoon:GetPlatoonPosition(), attackPos, platoon.PlatoonData.NodeWeight or 10 )
    
        # clear command queue
        platoon:Stop()    
           
        if not path then
            path = AINavalPlanB(aiBrain, platoon)
        end
        
        if path then
            local pathSize = table.getn(path)
            # store path
            platoon.LastAttackDestination = path
            # move to new location
            for wpidx,waypointPath in path do
                if wpidx == pathSize then
                    #platoon:AggressiveMoveToLocation(waypointPath)
                    platoon:MoveToLocation(waypointPath, false)
                else
                    #platoon:AggressiveMoveToLocation(waypointPath)
                    platoon:MoveToLocation(waypointPath, false)
                end
            end  
        end
    end 
    
    # return current command queue 
    local cmd = {}
    for k,v in platoon:GetPlatoonUnits() do
        if not v:IsDead() then
            local unitCmdQ = v:GetCommandQueue()
            for cmdIdx,cmdVal in unitCmdQ do
                table.insert(cmd, cmdVal)
                break
            end
        end
    end
    return cmd
end

function SendPlatoonWithTransportsSorian(aiBrain, platoon, destination, bRequired, bSkipLastMove, waitLonger)

    GetMostRestrictiveLayer(platoon)
    
    local units = platoon:GetPlatoonUnits()
    
    
    # only get transports for land (or partial land) movement
    if platoon.MovementLayer == 'Land' or platoon.MovementLayer == 'Amphibious' then
    
        if platoon.MovementLayer == 'Land' then
            # if it's water, this is not valid at all
            local terrain = GetTerrainHeight(destination[1], destination[2])
            local surface = GetSurfaceHeight(destination[1], destination[2])
            if terrain < surface then
                return false
            end
        end
    
        # if we don't *need* transports, then just call GetTransports... 
        if not bRequired then
            #  if it doesn't work, tell the aiBrain we want transports and bail
            if AIUtils.GetTransports(platoon) == false then
                aiBrain.WantTransports = true
                return false
            end
        else
            # we were told that transports are the only way to get where we want to go...
            # ask for a transport every 10 seconds
            local counter = 0
			if not waitLonger then
				counter = 6
			end
            local transportsNeeded = AIUtils.GetNumTransports(units)
            local numTransportsNeeded = math.ceil( ( transportsNeeded.Small + ( transportsNeeded.Medium * 2 ) + ( transportsNeeded.Large * 4 ) ) / 10 )
            if not aiBrain.NeedTransports then
                aiBrain.NeedTransports = 0
            end
            aiBrain.NeedTransports = aiBrain.NeedTransports + numTransportsNeeded
            if aiBrain.NeedTransports > 10 then
                aiBrain.NeedTransports = 10
            end
            local bUsedTransports, overflowSm, overflowMd, overflowLg = AIUtils.GetTransports(platoon) 
            while not bUsedTransports and counter < 12 do
                # if we have overflow, dump the overflow and just send what we can
                if not bUsedTransports and overflowSm + overflowMd + overflowLg > 0 then
                    local goodunits, overflow = AIUtils.SplitTransportOverflow(units, overflowSm, overflowMd, overflowLg)
                    local numOverflow = table.getn(overflow)
                    if table.getn(goodunits) > numOverflow * 2 and numOverflow > 0 then
                        local pool = aiBrain:GetPlatoonUniquelyNamed('ArmyPool')
                        for _,v in overflow do
                            if not v:IsDead() then
                                aiBrain:AssignUnitsToPlatoon( pool, {v}, 'Unassigned', 'None' )
                            end
                        end
                        units = goodunits
                    end
                end
                bUsedTransports, overflowSm, overflowMd, overflowLg = AIUtils.GetTransports(platoon)
                if bUsedTransports then 
                    break 
                end
                counter = counter + 1
                WaitSeconds(Random(10,15))
                if not aiBrain:PlatoonExists(platoon) then
                    aiBrain.NeedTransports = aiBrain.NeedTransports - numTransportsNeeded
                    if aiBrain.NeedTransports < 0 then
                        aiBrain.NeedTransports = 0
                    end
                    return false
                end
                
                local survivors = {}
                for _,v in units do
                    if not v:IsDead() then
                        table.insert(survivors, v)
                    end
                end
                units = survivors
                
            end
            
            aiBrain.NeedTransports = aiBrain.NeedTransports - numTransportsNeeded
            if aiBrain.NeedTransports < 0 then
                aiBrain.NeedTransports = 0
            end
           
            # couldn't use transports...
            if bUsedTransports == false then
				return false
            end  
        end
        # presumably, if we're here, we've gotten transports
		
		local transportLocation = false

		# Try the destination directly if it is an engineer - based on Duncane's idea
		if bSkipLastMove then
			transportLocation = destination
		end
		
		# if not an engineer try a near by land path node
		if not transportLocation then
			transportLocation = AIUtils.AIGetClosestThreatMarkerLoc(aiBrain, 'Land Path Node', destination[1], destination[3], -100000, 6, 0, 'AntiAir')
			# What if it is a water map with no Land Pathing Nodes?
			if not transportLocation then
				transportLocation = AIUtils.AIGetClosestThreatMarkerLoc(aiBrain, 'Amphibious Path Node', destination[1], destination[3], -100000, 6, 0, 'AntiAir')				
				# If we have not found a spot yet find an appropriate transport marker if it's on the map
				if not transportLocation then
					transportLocation = AIUtils.AIGetClosestMarkerLocation(aiBrain, 'Transport Marker', destination[1], destination[3])
				end
			end
		end
		
        local useGraph = 'Land'
        if not transportLocation then
            # go directly to destination, do not pass go.  This move might kill you, fyi.
            transportLocation = platoon:GetPlatoonPosition()
            useGraph = 'Air'
        end
        
	    if not aiBrain:PlatoonExists(platoon) then
	        return false
	    end
        
		if transportLocation then
		    local minThreat = aiBrain:GetThreatAtPosition( transportLocation, 0, true, 'AntiAir' )
			local pos = platoon:GetPlatoonPosition()
			if not pos then
				return false
			end
			local closest = VDist2Sq(pos[1], pos[3], transportLocation[1], transportLocation[3])
		    if minThreat > 0 then
		        local threatTable = aiBrain:GetThreatsAroundPosition(transportLocation, 1, true, 'AntiAir' )
		        for threatIdx,threatEntry in threatTable do		
					local distance = VDist2Sq(pos[1], pos[3], threatEntry[1], threatEntry[2])
		            if threatEntry[3] < minThreat then
                        # if it's land...
                        local terrain = GetTerrainHeight(threatEntry[1], threatEntry[2])
                        local surface = GetSurfaceHeight(threatEntry[1], threatEntry[2])
                        if terrain >= surface then
                           minThreat = threatEntry[3]
                           transportLocation = {threatEntry[1], 0, threatEntry[2]}
						   closest = distance
						end
					elseif threatEntry[3] == minThreat and distance < closest then
                        local terrain = GetTerrainHeight(threatEntry[1], threatEntry[2])
                        local surface = GetSurfaceHeight(threatEntry[1], threatEntry[2])
                        if terrain >= surface then
                           minThreat = threatEntry[3]
                           transportLocation = {threatEntry[1], 0, threatEntry[2]}
						   closest = distance
						end
                    end
                end
            end
        end
		    
		# path from transport drop off to end location
		local path, reason = PlatoonGenerateSafePathTo(aiBrain, useGraph, transportLocation, destination, 200)
		# use the transport!
        AIUtils.UseTransports( units, platoon:GetSquadUnits('Scout'), transportLocation, platoon )
	    
	    # just in case we're still landing...
        for _,v in units do
            if not v:IsDead() then
                if v:IsUnitState( 'Attached' ) then
                   WaitSeconds(2)
                end
            end
        end
        
	    # check to see we're still around
	    if not platoon or not aiBrain:PlatoonExists(platoon) then
	        return false
	    end
		
		# then go to attack location
		if not path then
		    # directly
		    if not bSkipLastMove then
                platoon:AggressiveMoveToLocation(destination)
                platoon.LastAttackDestination = {destination}
            end
		else
		    # or indirectly
            # store path for future comparison
            platoon.LastAttackDestination = path

            local pathSize = table.getn(path)
            #move to destination afterwards
            for wpidx,waypointPath in path do
                if wpidx == pathSize then
                    if not bSkipLastMove then
                        platoon:AggressiveMoveToLocation(waypointPath)
                    end
                else
                    platoon:MoveToLocation(waypointPath, false)
                end
            end  		
		end
	else
		return false
    end
    
    return true
end

function SendPlatoonWithTransports(aiBrain, platoon, destination, bRequired, bSkipLastMove, waitLonger)

    GetMostRestrictiveLayer(platoon)
    
    local units = platoon:GetPlatoonUnits()
    
    
    # only get transports for land (or partial land) movement
    if platoon.MovementLayer == 'Land' or platoon.MovementLayer == 'Amphibious' then
    
        if platoon.MovementLayer == 'Land' then
            # if it's water, this is not valid at all
            local terrain = GetTerrainHeight(destination[1], destination[2])
            local surface = GetSurfaceHeight(destination[1], destination[2])
            if terrain < surface then
                return false
            end
        end
    
        # if we don't *need* transports, then just call GetTransports... 
        if not bRequired then
            #  if it doesn't work, tell the aiBrain we want transports and bail
            if AIUtils.GetTransports(platoon) == false then
                aiBrain.WantTransports = true
                return false
            end
        else
            # we were told that transports are the only way to get where we want to go...
            # ask for a transport every 10 seconds
            local counter = 0
			if waitLonger then
				counter = -6
			end
            local transportsNeeded = AIUtils.GetNumTransports(units)
            local numTransportsNeeded = math.ceil( ( transportsNeeded.Small + ( transportsNeeded.Medium * 2 ) + ( transportsNeeded.Large * 4 ) ) / 10 )
            if not aiBrain.NeedTransports then
                aiBrain.NeedTransports = 0
            end
            aiBrain.NeedTransports = aiBrain.NeedTransports + numTransportsNeeded
            if aiBrain.NeedTransports > 10 then
                aiBrain.NeedTransports = 10
            end
            local bUsedTransports, overflowSm, overflowMd, overflowLg = AIUtils.GetTransports(platoon) 
            while not bUsedTransports and counter < 6 do
                # if we have overflow, dump the overflow and just send what we can
                if not bUsedTransports and overflowSm + overflowMd + overflowLg > 0 then
                    local goodunits, overflow = AIUtils.SplitTransportOverflow(units, overflowSm, overflowMd, overflowLg)
                    local numOverflow = table.getn(overflow)
                    if table.getn(goodunits) > numOverflow and numOverflow > 0 then
                        local pool = aiBrain:GetPlatoonUniquelyNamed('ArmyPool')
                        for _,v in overflow do
                            if not v:IsDead() then
                                aiBrain:AssignUnitsToPlatoon( pool, {v}, 'Unassigned', 'None' )
                            end
                        end
                        units = goodunits
                    end
                end
                bUsedTransports, overflowSm, overflowMd, overflowLg = AIUtils.GetTransports(platoon)
                if bUsedTransports then 
                    break 
                end
                counter = counter + 1				
                WaitSeconds(10)
                if not aiBrain:PlatoonExists(platoon) then
                    aiBrain.NeedTransports = aiBrain.NeedTransports - numTransportsNeeded
                    if aiBrain.NeedTransports < 0 then
                        aiBrain.NeedTransports = 0
                    end
                    return false
                end
                
                local survivors = {}
                for _,v in units do
                    if not v:IsDead() then
                        table.insert(survivors, v)
                    end
                end
                units = survivors
                
            end
            
            aiBrain.NeedTransports = aiBrain.NeedTransports - numTransportsNeeded
            if aiBrain.NeedTransports < 0 then
                aiBrain.NeedTransports = 0
            end
           
            # couldn't use transports...
            if bUsedTransports == false then
				return false
            end  
        end
        # presumably, if we're here, we've gotten transports
        # find an appropriate transport marker if it's on the map
        local transportLocation = AIUtils.AIGetClosestMarkerLocation(aiBrain, 'Transport Marker', destination[1], destination[3])
        local useGraph = 'Land'
        if not transportLocation then
            # go directly to destination, do not pass go.  This move might kill you, fyi.
            transportLocation = platoon:GetPlatoonPosition()
            useGraph = 'Air'
        end
        
		if transportLocation then
		    local minThreat = aiBrain:GetThreatAtPosition( transportLocation, 0, true )
		    if minThreat > 0 then
		        local threatTable = aiBrain:GetThreatsAroundPosition(transportLocation, 1, true, 'Overall' )
		        for threatIdx,threatEntry in threatTable do
		            if threatEntry[3] < minThreat then
                        # if it's land...
                        local terrain = GetTerrainHeight(threatEntry[1], threatEntry[2])
                        local surface = GetSurfaceHeight(threatEntry[1], threatEntry[2])
                        if terrain >= surface then
                           minThreat = threatEntry[3]
                           transportLocation = {threatEntry[1], 0, threatEntry[2]}
                       end
                    end
                end
            end
        end
		    
		# path from transport drop off to end location
		local path, reason = PlatoonGenerateSafePathTo(aiBrain, useGraph, transportLocation, destination, 200)
		# use the transport!
        AIUtils.UseTransports( units, platoon:GetSquadUnits('Scout'), transportLocation, platoon )
	    
	    # just in case we're still landing...
        for _,v in units do
            if not v:IsDead() then
                if v:IsUnitState( 'Attached' ) then
                   WaitSeconds(2)
                end
            end
        end
        
	    # check to see we're still around
	    if not platoon or not aiBrain:PlatoonExists(platoon) then
	        return false
	    end
		
		# then go to attack location
		if not path then
		    # directly
		    if not bSkipLastMove then
                platoon:AggressiveMoveToLocation(destination)
                platoon.LastAttackDestination = {destination}
            end
		else
		    # or indirectly
            # store path for future comparison
            platoon.LastAttackDestination = path

            local pathSize = table.getn(path)
            #move to destination afterwards
            for wpidx,waypointPath in path do
                if wpidx == pathSize then
                    if not bSkipLastMove then
                        platoon:AggressiveMoveToLocation(waypointPath)
                    end
                else
                    platoon:MoveToLocation(waypointPath, false)
                end
            end  		
		end
	else
		return false
    end
    
    return true
end

function InWaterCheck(platoon)
	GetMostRestrictiveLayer(platoon)
	if platoon.MovementLayer == 'Air' then return false end
	local platPos = platoon:GetPlatoonPosition()
	local inWater = GetTerrainHeight(platPos[1], platPos[3]) < GetSurfaceHeight(platPos[1], platPos[3])
	return inWater
end

function AIPlatoonSquadAttackVector( aiBrain, platoon, bAggro )

    --Engine handles whether or not we can occupy our vector now, so this should always be a valid, occupiable spot.
    local attackPos = GetBestThreatTarget(aiBrain, platoon)
    
    local bNeedTransports = false
    # if no pathable attack spot found
    if not attackPos then
        # try skipping pathability
        attackPos = GetBestThreatTarget(aiBrain, platoon, true)
        bNeedTransports = true
        if not attackPos then
            platoon:StopAttack()
            return {}
        end
    end


    # avoid mountains by slowly moving away from higher areas
    GetMostRestrictiveLayer(platoon)
    if platoon.MovementLayer == 'Land' then
        local bestPos = attackPos
        local attackPosHeight = GetTerrainHeight(attackPos[1], attackPos[3])
        # if we're land
        if attackPosHeight >= GetSurfaceHeight(attackPos[1], attackPos[3]) then
            local lookAroundTable = {1,0,-2,-1,2}
            local squareRadius = (ScenarioInfo.size[1] / 16) / table.getn(lookAroundTable)
            for ix, offsetX in lookAroundTable do
                for iz, offsetZ in lookAroundTable do
                    local surf = GetSurfaceHeight( bestPos[1]+offsetX, bestPos[3]+offsetZ )
                    local terr = GetTerrainHeight( bestPos[1]+offsetX, bestPos[3]+offsetZ )
                    # is it lower land... make it our new position to continue searching around
                    if terr >= surf and terr < attackPosHeight then
                        bestPos[1] = bestPos[1] + offsetX
                        bestPos[3] = bestPos[3] + offsetZ
                        attackPosHeight = terr
                    end
                end
            end
        end
        attackPos = bestPos
    end
        
    local oldPathSize = table.getn(platoon.LastAttackDestination)
    
    # if we don't have an old path or our old destination and new destination are different
    if oldPathSize == 0 or attackPos[1] != platoon.LastAttackDestination[oldPathSize][1] or
    attackPos[3] != platoon.LastAttackDestination[oldPathSize][3] then
        
        GetMostRestrictiveLayer(platoon)
        # check if we can path to here safely... give a large threat weight to sort by threat first
        local path, reason = PlatoonGenerateSafePathTo(aiBrain, platoon.MovementLayer, platoon:GetPlatoonPosition(), attackPos, platoon.PlatoonData.NodeWeight or 10 )
    
        # clear command queue
        platoon:Stop()    
   
        local usedTransports = false
        local position = platoon:GetPlatoonPosition()
        if (not path and reason == 'NoPath') or bNeedTransports then
            usedTransports = SendPlatoonWithTransports(aiBrain, platoon, attackPos, true)
        # Require transports over 500 away
        elseif VDist2Sq( position[1], position[3], attackPos[1], attackPos[3] ) > 512*512 then
            usedTransports = SendPlatoonWithTransports(aiBrain, platoon, attackPos, true)
        # use if possible at 250
        elseif VDist2Sq( position[1], position[3], attackPos[1], attackPos[3] ) > 256*256 then
            usedTransports = SendPlatoonWithTransports(aiBrain, platoon, attackPos, false)
        end
        
        if not usedTransports then
            if not path then
                if reason == 'NoStartNode' or reason == 'NoEndNode' then
                    --Couldn't find a valid pathing node. Just use shortest path.
                    platoon:AggressiveMoveToLocation(attackPos)
                end
                # force reevaluation
                platoon.LastAttackDestination = {attackPos}
            else
                local pathSize = table.getn(path)
                # store path
                platoon.LastAttackDestination = path
                # move to new location
                for wpidx,waypointPath in path do
                    if wpidx == pathSize or bAggro then
                        platoon:AggressiveMoveToLocation(waypointPath)
                    else
                        platoon:MoveToLocation(waypointPath, false)
                    end
                end   
            end
        end
    end 
    
    # return current command queue 
    local cmd = {}
    for k,v in platoon:GetPlatoonUnits() do
        if not v:IsDead() then
            local unitCmdQ = v:GetCommandQueue()
            for cmdIdx,cmdVal in unitCmdQ do
                table.insert(cmd, cmdVal)
                break
            end
        end
    end
    return cmd
end

end