module("util", package.seeall)

local minX, minY, maxX, maxY = unpack(GetWorldBounds())

runes = {
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

function ClosestBuilding(pos, types)
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

function GetCheapestItem(unit)
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

-- utilities
function ArgMax(arr, left, right)
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

function RemapX(val)
	return (val + minX)/(maxX - minX) + 1
end

function RemapY(val)
	return (val + minY)/(maxY - minY) + 1
end

function InvertX(val)
	return (val - 1) * (maxX - minX) - minX
end

function InvertY(val)
	return (val - 1) * (maxY - minY) - minY
end

local move_msg_template = [[
Time: %f
Health: %d
Mana: %d
Level: %f
Lane status: %f
Ally loc 1: (%f, %f)
Ally loc 2: (%f, %f)
Ally loc 3: (%f, %f)
Ally loc 4: (%f, %f)
Ally loc 5: (%f, %f)
Enemy loc 1: (%f, %f)
Enemy loc 2: (%f, %f)
Enemy loc 3: (%f, %f)
Enemy loc 4: (%f, %f)
Enemy loc 5: (%f, %f)
]]

if true then -- swizzle debug functions (change this to false to disable)
	function Debug(msg)
		if debug_on then
			local bot = GetBot()

			if bot then
				Msg("[dota2_nn] " .. bot:GetUnitName() .. " " .. msg .. "\n")
			else
				Msg("[dota2_nn] anon-e-moose " .. msg .. "\n")
			end
		end
	end

	function DebugMove(input)
		if debug_on then
			Debug("Move input:")
			Debug(string.format(move_msg_template, unpack(input)))
		end
	end
else
	function Debug(_) end
	function DebugMove(_) end
end