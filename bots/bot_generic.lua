require "bots/ability_data"
require "bots/debug_log"

local json = require "game/dkjson"

local minX, minY, maxX, maxY = unpack(GetWorldBounds())

local runes = {
	RUNE_POWERUP_1,
	RUNE_POWERUP_2,
	RUNE_BOUNTY_1,
	RUNE_BOUNTY_2,
	RUNE_BOUNTY_3,
	RUNE_BOUNTY_4
}

-- Data for buildings so that we can get handles for them even if they're in fog of war
local towers = {
	{GetTower(GetTeam(), TOWER_TOP_1), GetTower(bit.bxor(GetTeam(), 1), TOWER_TOP_1)},
	{GetTower(GetTeam(), TOWER_TOP_2), GetTower(bit.bxor(GetTeam(), 1), TOWER_TOP_2)},
	{GetTower(GetTeam(), TOWER_TOP_3), GetTower(bit.bxor(GetTeam(), 1), TOWER_TOP_3)},
	{GetTower(GetTeam(), TOWER_MID_1), GetTower(bit.bxor(GetTeam(), 1), TOWER_MID_1)},
	{GetTower(GetTeam(), TOWER_MID_2), GetTower(bit.bxor(GetTeam(), 1), TOWER_MID_2)},
	{GetTower(GetTeam(), TOWER_MID_3), GetTower(bit.bxor(GetTeam(), 1), TOWER_MID_3)},
	{GetTower(GetTeam(), TOWER_BOT_1), GetTower(bit.bxor(GetTeam(), 1), TOWER_BOT_1)},
	{GetTower(GetTeam(), TOWER_BOT_2), GetTower(bit.bxor(GetTeam(), 1), TOWER_BOT_2)},
	{GetTower(GetTeam(), TOWER_BOT_3), GetTower(bit.bxor(GetTeam(), 1), TOWER_BOT_3)},
	{GetTower(GetTeam(), TOWER_BASE_1), GetTower(bit.bxor(GetTeam(), 1), TOWER_BASE_1)},
	{GetTower(GetTeam(), TOWER_BASE_2), GetTower(bit.bxor(GetTeam(), 1), TOWER_BASE_2)}
}

local barracks = {
	{GetBarracks(GetTeam(), BARRACKS_TOP_MELEE), GetBarracks(bit.bxor(GetTeam(), 1), BARRACKS_TOP_MELEE)},
	{GetBarracks(GetTeam(), BARRACKS_TOP_RANGED), GetBarracks(bit.bxor(GetTeam(), 1), BARRACKS_TOP_RANGED)},
	{GetBarracks(GetTeam(), BARRACKS_MID_MELEE), GetBarracks(bit.bxor(GetTeam(), 1), BARRACKS_MID_MELEE)},
	{GetBarracks(GetTeam(), BARRACKS_MID_RANGED), GetBarracks(bit.bxor(GetTeam(), 1), BARRACKS_MID_RANGED)},
	{GetBarracks(GetTeam(), BARRACKS_BOT_MELEE), GetBarracks(bit.bxor(GetTeam(), 1), BARRACKS_BOT_MELEE)},
	{GetBarracks(GetTeam(), BARRACKS_BOT_RANGED), GetBarracks(bit.bxor(GetTeam(), 1), BARRACKS_BOT_RANGED)}
}

local shrines = {
	{GetShrine(GetTeam(), SHRINE_BASE_1), GetShrine(bit.bxor(GetTeam(), 1), SHRINE_BASE_1)},
	{GetShrine(GetTeam(), SHRINE_BASE_2), GetShrine(bit.bxor(GetTeam(), 1), SHRINE_BASE_2)},
	{GetShrine(GetTeam(), SHRINE_BASE_3), GetShrine(bit.bxor(GetTeam(), 1), SHRINE_BASE_3)},
	{GetShrine(GetTeam(), SHRINE_JUNGLE_1), GetShrine(bit.bxor(GetTeam(), 1), SHRINE_JUNGLE_1)},
	{GetShrine(GetTeam(), SHRINE_JUNGLE_2), GetShrine(bit.bxor(GetTeam(), 1), SHRINE_JUNGLE_2)}
}

local ancients = {
	{GetAncient(GetTeam()), GetAncient(bit.bxor(GetTeam(), 1))}
}

local function ClosestBuilding(pos, types)
	local closestBuilding = nil
	local currentDistance = 0

	for _, buildings in ipairs(types) do
		for i, building in ipairs(buildings) do
			local allyBuilding = building[1]
			local enemyBuilding = building[2]

			local allyDistance = GetUnitToLocationDistance(allyBuilding, pos)
			local enemyDistance = GetUnitToLocationDistance(enemyBuilding, pos)

			if allyDistance < enemyDistance then
				if not closestBuilding or allyDistance < currentDistance then
					closestBuilding = allyBuilding
					currentDistance = allyDistance
				end
			else
				if not closestBuilding or enemyDistance < currentDistance then
					closestBuilding = enemyBuilding
					currentDistance = enemyDistance
				end
			end
		end
	end

	return closestBuilding
end

-- initialize courier queue if we're the first bot
if not _G.courier_queue then
	_G.courier_queue = {{head=nil, tail=nil}, {head=nil, tail=nil}}
end

-- get this team's courier queue
local function GetCourierQueue()
	return _G.courier_queue[GetTeam() - 1]
end

-- pop the top task from the queue
local function PopCourierQueue()
	local courier_queue = GetCourierQueue()

	if courier_queue.tail.prev then
		courier_queue.tail.prev.next = nil
	end

	courier_queue.tail = courier_queue.tail.prev
end

-- push a task (coroutine) onto the queue. The top coroutine will run everytime the courier is idle until it's done.
local function PushCourierQueue(task)
	local courier_queue = GetCourierQueue()
	
	local coro = coroutine.create(task, GetCourier(1))

	local node = {next=courier_queue.head, prev=nil, data=coro}
	
	if not courier_queue.head then
		courier_queue.head = node
		courier_queue.tail = node
	else
		courier_queue.head.prev = node
		courier_queue.head = node
	end
end

-- utilities
local function ArgMax(arr, left, right)
	local max
	local maxIndex = -1

	for i = left, right do
		if max == nil or arr[i] > max then
			max = arr[i]
			maxIndex = i
		end
	end

	return max, maxIndex - left
end

local function RemapX(val)
	return (val + minX)/(maxX - minX) + 1
end

local function RemapY(val)
	return (val + minY)/(maxY - minY) + 1
end

local function InvertX(val)
	return (val - 1) * (maxX - minX) - minX
end

local function InvertY(val)
	return (val - 1) * (maxY - minY) - minY
end

local function GetCheapestItem(unit)
	local max = 0
	local max_price = 0

	for i = 1,9 do
		local item = unit:GetItemInSlot(i)
		local price = GetItemCost(item:GetName())

		if price > max_price then
			max = i
			price = max_price
		end
	end

	return max
end

-- nn query functions
local function RetrieveMoveResult(unit)
	local request = ":1414/move_result?id=" .. unit.moveID

	local me = GetBot()

	CreateHTTPRequest(request):Send(function(result)
		if result.StatusCode == 0 then
			me.callback_err = "The dota2_nn server is either not running or otherwise cannot be connected to."
		elseif result.StatusCode == 200 then
			unit.moveResult = json.decode(result.Body)
		elseif result.StatusCode == 202 then
			unit.movePoll = 10
		else
			me.callback_err = "The dota2_nn server returned an unexpected " .. result.StatusCode .. " error when retrieving a move result. This either some other program is running on port 1414 or there's a serious bug."
		end

		unit.moveID = nil
		debug_log.Debug(result.StatusCode .. " on move NN result: " .. request)
	end)
end

local function QueryMoveNN(input, unit)
	debug_log.Debug("querying move NN")

	debug_log.DebugMove(input)

	local me = GetBot()
	local request = string.format(":1414/move?hero=%s&team=%d&tensor=%s", unit:GetUnitName(), GetTeam(), json.encode(input))

	CreateHTTPRequest(request):Send(function(result)
		if result.StatusCode == 0 then
			me.callback_err = "The dota2_nn server is either not running or otherwise cannot be connected to."
		elseif result.StatusCode == 201 then
			unit.moveID = result.Body
			unit.movePoll = 10
		elseif result.StatusCode == 404 then
			me.callback_err = "The dota2_nn server returned a 404 error when " .. unit:GetUnitName() .. " attempted a move. This means that there is no training data available for it."
		else
			me.callback_err = "The dota2_nn server returned an unexpected " .. result.StatusCode .. " error when submitting a move. This either some other program is running on port 1414 or there's a serious bug."
		end

		debug_log.Debug(result.StatusCode .. " on move NN request: " .. request)
	end)
end

local function QueryItemsNN(input)
	debug_log.Debug("querying items NN")
	
	local me = GetBot()
	local request = string.format(":1414/items?hero=%s&team=%d&tensor=%s", me:GetUnitName(), GetTeam(), json.encode(input))

	CreateHTTPRequest(request):Send(function(result)
		if result.StatusCode == 0 then
			me.callback_err = "The dota2_nn server is either not running or otherwise cannot be connected to."
		elseif result.StatusCode == 201 then
			me.itemID = result.Body
			me.itemPoll = 10
		elseif result.StatusCode == 404 then
			me.callback_err = "The dota2_nn server returned a 404 error when " .. me:GetUnitName() .. " attempted a move. This means that there is no training data available for it."
		else
			me.callback_err = "The dota2_nn server returned an unexpected " .. result.StatusCode .. " error. This either some other program is running on port 1414 or there's a serious bug."
		end

		debug_log.Debug(result.StatusCode .. " on move NN request: " .. request)
	end)
end

local function DoBuybackThink()
	-- check to see if we should buyback
	local me = GetBot()

	if me:HasBuyBack() and me:GetRespawnTime() >= 25 then
		for i = 1,11 do
			local tower = GetTower(GetTeam(), i)

			if tower:WasRecentlyDamagedByAnyHero(10) and tower:GetHealth() <= tower:GetHealth() / 2.5 then
				me:ActionImmediate_Buyback()
			end
		end
	end
end

local function ShouldAct(newInput, lastInput)
	-- check to see if we should bother asking the NN about the latest game state
	if lastInput == nil then
		debug_log.Debug("first move")
		return true
	elseif math.abs(lastInput[1] - newInput[1]) >= 10/3600 then
		debug_log.Debug("it's been more than 10 seconds")
		return true
	elseif newInput[2] < lastInput[2] then
		debug_log.Debug("taken damage")
		return true
	elseif math.abs(newInput[5] - lastInput[5]) >= 0.05 then
		debug_log.Debug("creep front advanced")
		return true
	else
		for i = 6, 24 do
			if math.sqrt((newInput[i] - lastInput[i])^2 + (newInput[i + 1] - lastInput[i + 1])^2) >= 0.02 then
				debug_log.Debug("player moved ~300 or more units")
				return true
			end
		end
	end

	return false
end

local function StartMoveThink(unit)
	local newInput = {} -- move NN input

	newInput[1] = DotaTime() / 3600

	newInput[2] = unit:GetHealth() / unit:GetMaxHealth()
	newInput[3] = unit:GetMana() / unit:GetMaxMana()
	newInput[4] = unit:GetLevel() / 25

	-- creep position of closest lane
	newInput[5] = GetLaneFrontAmount(GetTeam(), unit:GetAssignedLane(), true)

	-- our location
	newInput[6] = RemapX(unit:GetLocation().x)
	newInput[7] = RemapY(unit:GetLocation().y)

	local i = 1
	for _, ally in ipairs(GetTeamPlayers(GetTeam())) do
		if ally ~= unit:GetPlayerID() then
			-- get ally location
			local pos, time = unpack(GetHeroLastSeenInfo(ally))

			if pos == nil then
				pos = GetShopLocation(GetTeam(), SHOP_HOME)
			end

			newInput[2 * (i - 1) + 8] = RemapX(pos.x)
			newInput[2 * (i - 1) + 9] = RemapY(pos.y)
			i = i + 1
		end	
	end

	for index, enemy in ipairs(GetTeamPlayers(bit.bxor(GetTeam(), 1))) do
		-- get enemy location
		local pos, time = unpack(GetHeroLastSeenInfo(enemy))

		if pos == nil then
			pos = GetShopLocation(bit.bxor(GetTeam(), 1), SHOP_HOME)
		end

		newInput[2 * (index - 1) + 16] = RemapX(pos.x)
		newInput[2 * (index - 1) + 17] = RemapY(pos.y)
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
		local handle = unit:GetAbilityByName(ability)

		if handle ~= nil and handle:GetLevel() > 0 then
			newInput[i + 25] = handle:GetCooldownTimeRemaining() / 360
		else
			newInput[i + 25] = 1.0
		end
	end

	for i, item in ipairs(items) do
		-- item cooldowns
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

local function FinishMoveThink(unit)
	-- a pending move NN query just finished, execute move
	local pos

	if unit.movePos == nil then
		pos = Vector(InvertX(unit.moveResult[2]), InvertY(unit.moveResult[3]), 0) -- move to...
		unit.movePos = pos
	else
		pos = unit.movePos
	end

	if unit.doAttack == nil then
		unit.doAttack = unit.moveResult[1] >= .5 -- if activated attack anything at this point
	end	

	if unit.doAttack then
		debug_log.Debug("attacking")
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
			targetUnit = unit:GetNearbyTrees(1600)[0]
		elseif target == 5 then -- jungle creeps
			targetUnit = unit:GetNearbyNeutralCreeps(1600)[0]
		elseif target == 6 then
			targetUnit = unit:GetNearbyLaneCreeps(1600)[0]	
		elseif target == 7 then -- enemy hero
			targetUnit = unit:GetNearbyHeroes(1600, true)[0]
		elseif target == 8 then -- friendly hero
			targetUnit = unit:GetNearbyHeroes(1600, false)[0]
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
					unit:ActionImmediate_SwapItems(item, GetCheapestItem(unit))
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

local function StartItemThink()
	-- query NN to buy items and apply upgrades
	debug_log.Debug("building")

	local input = {}

	--QueryItemsNN()

	GetBot().itemTimer = 2000
end

local function FinishItemThink()
	local me = GetBot()

	local _, nextAbility = itemsResult:sub(1, #abilities):max(1)

	me:ActionImmediate_LevelAbility(abilities[nextAbility])

	itemsResults:sub(#abilities + 1, #items):map(torch.range(1, #items), function(t, item)
		if t >= .5 then
			local result = me:ActionImmediate_PurchaseItem(items[item])

			if result == PURCHASE_ITEM_SUCCESS then
				if DistanceFromFountain() > 1200 then
					PushCourierQueue(function(courier)
						if me:IsAlive() then
							me:ActionImmediate_Courier(courier, COURIER_ACTION_TAKE_AND_TRANSFER_ITEMS)
							coroutine.yield()
							me:ActionImmediate_Courier(courier, COURIER_ACTION_RETURN)
						end
					end)
				end
			elseif result == PURCHASE_ITEM_NOT_AT_SECRET_SHOP then
				if DistanceFromSecretShop() > 1200 then
					PushCourierQueue(function(courier)
						me:ActionImmediate_Courier(courier, COURIER_ACTION_SECRET_SHOP)
						coroutine.yield()

						me:ActionImmediate_PurchaseItem(items[nextItem])

						while not me:IsAlive() do
							coroutine.yield()
						end

						me:ActionImmediate_Courier(courier, COURIER_ACTION_TAKE_AND_TRANSFER_ITEMS)
						coroutine.yield()
						me:ActionImmediate_Courier(courier, COURIER_ACTION_RETURN)
					end)
				end
			end
		end
	end)
end

local function DoLastHitThink(creeps, unit)
	-- do laning/last hit/deny
	for _, creep in ipairs(creeps) do
		if creep:GetHealth() < unit:GetAttackDamage() and (creep:GetTeam() == bit.bxor(GetTeam(), 1) or #creep:GetNearbyHeroes(1300, true)) then
			unit.lastInput[1] = DotaTime() / 3600

			unit:ActionPush_MoveToLocation(creep:GetLocation())
			unit:ActionPush_AttackUnit(creep, true)
		end
	end
end

local function DoRuneThink(unit)
	-- check to see if there are any runes nearby
	-- if so pick them up

	for _, rune in ipairs(runes) do
		if GetUnitToLocationDistance(unit, GetRuneSpawnLocation(rune)) <= 800 and GetRuneStatus(rune) == RUNE_STATUS_AVAILABLE then
			debug_log.Debug("picking up rune " .. rune)

			unit:ActionPush_PickUpRune(rune)
			return true
		end
	end

	return false
end

local function DoMainThink(unit)
	unit.fountainBuy = false -- we've left the fountain

	if DoRuneThink(unit) then -- check for nearby runes
		return
	end

	if unit.moveResult ~= nil then -- we got a response from the move NN
		unit.moveID = nil
		FinishMoveThink(unit)
	elseif unit.moveID ~= nil and unit.movePoll == 0 then -- waiting for a response
		debug_log.Debug("checking move")
		RetrieveMoveResult(unit)
		unit.movePoll = -1
	elseif unit.movePoll ~= nil and unit.movePoll > 0 then -- sleeping before checking for a response again
		debug_log.Debug(unit.movePoll)
		unit.movePoll = unit.movePoll - 1
	elseif not StartMoveThink(unit) then -- do move think, returns false if it's not going to move
		creeps = unit:GetNearbyLaneCreeps(1600, true)

		if #creeps > 0 then -- do laning
			debug_log.Debug("laning")
			DoLastHitThink(creeps, unit)
		end
	end
end

-- Hero think entry point
function Think(unit)
	if GetBot().itemTimer == nil then -- init item timer
		GetBot().itemTimer = 0
	end

	local me = unit or GetBot()

	if me.callback_err ~= nil then
		me:ActionImmediate_Chat(me.callback_err, true)
		me.callback_err = nil
	end

	if not me:IsAlive() then
		DoBuybackThink() -- dead; see if we should buyback
	elseif me:DistanceFromFountain() < 1200 and (me:GetHealth() ~= me:GetMaxHealth() or me:GetMana() ~= me:GetMaxMana()) then -- wait for regen at fountain
		-- force item think if we haven't yet
		if not me.fountainBuy then
			StartItemThink()
			me.fountainBuy = true
		end
	else
		DoMainThink(me) -- actual thinking
	end
	 
	if me.itemTimer ~= nil then -- check item timer
		if me.itemTimer == 0 then -- item timer is done, get items
			StartItemThink()
		else
			me.itemTimer = me.itemTimer - 1

			if me.itemsResult ~= nil then
				FinishItemThink()
			end
		end
	end

	-- run any courier tasks
	local courier_queue = GetCourierQueue()

	if GetCourierState(GetCourier(1)) == COURIER_STATE_IDLE and courier_queue.head then
		next_user = courier_queue.tail.data

		if IsCourierAvailable() then
			coroutine.resume(next_user)

			if coroutine.status(next_user) == "dead" then
				PopCourierQueue()
			end
		end
	end
end

function MinionThink(minion)
	if minion:GetUnitName() ~= "npc_dota_hero_wisp_spirit" then
		Think(minion)
	end	
end
