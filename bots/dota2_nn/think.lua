module("think", package.seeall)

require "bots/dota2_nn/nn_items"
require "bots/dota2_nn/nn_move"
require "bots/dota2_nn/util"

local function DoLastHitThink(creeps, unit)
	-- do laning/last hit/deny
	for _, creep in ipairs(creeps) do
		if creep:GetHealth() < unit:GetAttackDamage() and (creep:GetTeam() == bit.bxor(GetTeam(), 1) 
				or #creep:GetNearbyHeroes(1300, true)) then
			unit.lastInput[1] = DotaTime() / 3600

			unit:ActionPush_MoveToLocation(creep:GetLocation())
			unit:ActionPush_AttackUnit(creep, true)
		end
	end
end

local function DoRuneThink(unit)
	-- check to see if there are any runes nearby
	-- if so pick them up
	for _, rune in ipairs(util.runes) do
		if GetUnitToLocationDistance(unit, GetRuneSpawnLocation(rune)) <= 800 
				and GetRuneStatus(rune) == RUNE_STATUS_AVAILABLE then
			util.Debug("picking up rune " .. rune)

			unit:ActionPush_PickUpRune(rune)
			return true
		end
	end

	return false
end

local function DoMoveThink(unit)
	unit.fountainBuy = false -- we're leaving the fountain

	if DoRuneThink(unit) then -- check for nearby runes (returns true if we're fetching one)
		return
	end

	if unit.moveResult ~= nil then -- we got a response from a previous NN query
		nn_move.FinishMoveThink(unit)
	elseif not nn_move.StartMoveThink(unit) then -- do move think, returns false if it's not going to move
		creeps = unit:GetNearbyLaneCreeps(1600, true)

		if #creeps > 0 then -- do laning
			util.Debug("laning")
			DoLastHitThink(creeps, unit)
		end
	end
end

-- Hero think entry point
function Entry(unit)
	local me = unit or GetBot() -- unit is nil if we came from Think

	if me:GetUnitName() == "npc_dota_hero_wisp_spirit" then
		return
	end

	if GetBot().itemTimer == nil then -- init item timer if we haven't already
		GetBot().itemTimer = 0
	end

	-- error message from a thread doing an HTTP request?
	if me.callback_err ~= nil then
		me:ActionImmediate_Chat(me.callback_err, true) -- post it in chat so we can see the unit too
		me.callback_err = nil
	end

	if not me:IsAlive() then
		DoBuybackThink() -- dead; see if we should buyback
	elseif me:DistanceFromFountain() < 1200 and 
			(me:GetHealth() ~= me:GetMaxHealth() or me:GetMana() ~= me:GetMaxMana()) then
		-- wait for regen at fountain
		if not me.fountainBuy then
			nn_items.StartItemThink() -- force item think if we haven't yet
			me.fountainBuy = true
		end
	else
		DoMoveThink(me) -- actual thinking
	end
	 
	if me.itemTimer ~= nil then -- check item timer
		if me.itemTimer == 0 then -- item timer is done, get items
			nn_items.StartItemThink()
		else
			me.itemTimer = me.itemTimer - 1

			if me.itemsResult ~= nil then
				nn_items.FinishItemThink()
			end
		end
	end

	-- run any courier tasks
	local courier_queue = nn_items.GetCourierQueue()

	if GetCourierState(GetCourier(1)) == COURIER_STATE_IDLE and courier_queue.head then
		local next_user = courier_queue.tail.data

		if IsCourierAvailable() then
			coroutine.resume(next_user)

			if coroutine.status(next_user) == "dead" then
				nn_items.PopCourierQueue()
			end
		end
	end
end