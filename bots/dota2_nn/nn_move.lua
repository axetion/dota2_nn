module("nn_move", package.seeall)

require "bots/data/ability_data"
require "bots/dota2_nn/util"

local json = require "game/dkjson"

local function ShouldAct(newInput, lastInput)
	-- check to see if we should bother asking the NN about the latest game state
	if lastInput == nil then
		util.Debug("first move")
		return true
	elseif math.abs(lastInput[1] - newInput[1]) >= 10/3600 then
		util.Debug("it's been more than 10 seconds")
		return true
	elseif newInput[2] < lastInput[2] then
		util.Debug("taken damage")
		return true
	elseif math.abs(newInput[5] - lastInput[5]) >= 0.05 then
		util.Debug("creep front advanced")
		return true
	else
		for i = 6, 24 do
			if math.sqrt((newInput[i] - lastInput[i])^2 + (newInput[i + 1] - lastInput[i + 1])^2) >= 0.02 then
				util.Debug("player moved ~300 or more units")
				return true
			end
		end
	end

	return false
end

local function QueryMoveNN(input, unit)
	util.Debug("querying move NN")

	util.DebugMove(input)

	local me = GetBot()
	local request = string.format(":1414/query?type=move&hero=%s&team=%d&tensor=%s", unit:GetUnitName(), GetTeam(), json.encode(input))

	CreateHTTPRequest(request):Send(function(result)
		if result.StatusCode == 0 then
			me.callback_err = "The dota2_nn server is either not running or otherwise cannot be connected to."
		elseif result.StatusCode == 200 then
			unit.moveResult = json.decode(result.Body)
		elseif result.StatusCode == 404 then
			me.callback_err = "The dota2_nn server returned a 404 error when " .. me:GetUnitName() .. " attempted a move. This means that there is no training data available for it."
		else
			me.callback_err = "The dota2_nn server returned an unexpected " .. result.StatusCode .. " error when retrieving a move result. This either some other program is running on port 1414 or there's a serious bug."
		end

		util.Debug(result.StatusCode .. " on move NN result: " .. request)
	end)
end

function StartMoveThink(unit)
	local newInput = {} -- move NN input

	newInput[1] = DotaTime() / 3600

	newInput[2] = unit:GetHealth() / unit:GetMaxHealth()
	newInput[3] = unit:GetMana() / unit:GetMaxMana()
	newInput[4] = unit:GetLevel() / 25

	-- creep position of closest lane
	newInput[5] = GetLaneFrontAmount(GetTeam(), unit:GetAssignedLane(), true)

	-- our location
	newInput[6] = util.RemapX(unit:GetLocation().x)
	newInput[7] = util.RemapY(unit:GetLocation().y)

	local i = 1
	for _, ally in ipairs(GetTeamPlayers(GetTeam())) do
		if ally ~= unit:GetPlayerID() then
			-- get ally location
			local pos = GetHeroLastSeenInfo(ally)[1]

			if pos == nil or pos.time_since_seen > 5 then
				pos = GetShopLocation(GetTeam(), SHOP_HOME)
			else
				pos = pos.location
			end

			newInput[2 * (i - 1) + 8] = util.RemapX(pos.x)
			newInput[2 * (i - 1) + 9] = util.RemapY(pos.y)
			i = i + 1
		end
	end

	for index, enemy in ipairs(GetTeamPlayers(bit.bxor(GetTeam(), 1))) do
		-- get enemy location
		local pos = GetHeroLastSeenInfo(enemy)[1]

		if pos == nill or pos.time_since_seen > 5 then
			pos = GetShopLocation(bit.bxor(GetTeam(), 1), SHOP_HOME)
		else
			pos = pos.location
		end

		newInput[2 * (index - 1) + 16] = util.RemapX(pos.x)
		newInput[2 * (index - 1) + 17] = util.RemapY(pos.y)
	end

	local items
	local abilities

	if ability_data.items[unit:GetUnitName()] ~= nil then
		items = ability_data.items[unit:GetUnitName()][GetTeam()] or {}
	else
		items = {}
	end

	if ability_data.abilities[unit:GetUnitName()] ~= nil then
		abilities = ability_data.abilities[unit:GetUnitName()][GetTeam()] or {}
	else
		abilities = {}
	end

	for i, ability in ipairs(abilities) do
		-- ability cooldowns
		local handle = unit:GetAbilityByName(ability)

		if handle ~= nil and handle:GetLevel() > 0 then
			newInput[i + 25] = handle:GetCooldownTimeRemaining() / 360
		else
			newInput[i + 25] = 1.0
		end
	end

	for i, item in ipairs(items) do
		-- inventory
		slot = unit:FindItemSlot(item)

		if slot ~= -1 then
			newInput[i + 25 + #abilities] = 1.0
		else
			newInput[i + 25 + #abilities] = 0.0
		end
	end

	if ShouldAct(newInput, unit.lastInput) then -- did something happen?
		unit.moveResult = nil
		unit.doAttack = false
		unit.lastInput = newInput

		QueryMoveNN(newInput, unit) -- query NN
		return true
	else
		return false
	end
end

function FinishMoveThink(unit)
	-- a pending move NN query just finished, execute move
	local pos

	if unit.movePos == nil then
		pos = Vector(util.InvertX(unit.moveResult[2]), util.InvertY(unit.moveResult[3]), 0) -- move to...
		unit.movePos = pos
	else
		pos = unit.movePos
	end

	if unit.doAttack == nil then
		unit.doAttack = unit.moveResult[1] >= .5 -- if activated attack anything at this point
	end	

	if unit.doAttack then
		util.Debug("attacking")

		local abilities = ability_data.activeAbilities[unit:GetUnitName()][GetTeam()]
		local items = ability_data.activeItems[unit:GetUnitName()][GetTeam()]

		local _, target = ArgMax(unit.moveResult, 4, 11)
		local _, ability = ArgMax(unit.moveResult, 12, #abilities + 12)
		local _, item = ArgMax(unit.moveResult, #abilities + 13, #items + #abilities + 13)

		local targetUnit

		if target == 1 then -- tower
			targetUnit = ClosestBuilding(pos, {towers})
		elseif target == 2 then -- other buildings
			targetUnit = ClosestBuilding(pos, {barracks, shrines, ancients})
		elseif target == 3 then -- self
			targetUnit = unit
		elseif target == 4 then -- tree
			targetUnit = unit:GetNearbyTrees(1600)[1]
		elseif target == 5 then -- jungle creeps
			targetUnit = unit:GetNearbyNeutralCreeps(1600)[1]
		elseif target == 6 then
			targetUnit = unit:GetNearbyLaneCreeps(1600)[1]	
		elseif target == 7 then -- enemy hero
			targetUnit = unit:GetNearbyHeroes(1600, true)[1]
		elseif target == 8 then -- friendly hero
			targetUnit = unit:GetNearbyHeroes(1600, false)[1]
		end

		if targetUnit then
			unit.doAttack = nil
			unit.moveResult = nil
			unit.movePos = nil

			if ability ~= 1 then
				unit:ActionQueue_UseAbilityOnEntity(unit:GetAbilityByName(ability_data.activeAbilities[unit:GetUnitName()][GetTeam()][ability - 1]), targetUnit)
			end
			
			if item ~= 1 then
				local slot = unit:FindItemSlot(ability_data.activeItems[unit:GetUnitName()][GetTeam()][item - 1])

				if slot > 5 then
					unit:ActionImmediate_SwapItems(item, util.GetCheapestItem(unit))
					unit:ActionQueue_Delay(6)
				end

				unit:ActionQueue_UseAbilityOnEntity(unit:GetItemInSlot(slot), targetUnit)
			else
				unit:ActionQueue_AttackUnit(targetUnit, false)
			end
		end
	else
		unit.doAttack = nil
		unit.moveResult = nil
		unit.movePos = nil

		unit:Action_MoveToLocation(pos)
	end
end