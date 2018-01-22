module("nn_items", package.seeall)

local json = require "game/dkjson"
require "bots/data/ability_data"
require "bots/dota2_nn/util"

-- initialize courier queue if we're the first bot
if not _G.courier_queue then
	_G.courier_queue = {{head=nil, tail=nil}, {head=nil, tail=nil}}
end

-- get this team's courier queue
function GetCourierQueue()
	return _G.courier_queue[GetTeam() - 1]
end

-- pop the top task from the queue
function PopCourierQueue()
	local courier_queue = GetCourierQueue()

	if courier_queue.tail.prev then
		courier_queue.tail.prev.next = nil
	end

	courier_queue.tail = courier_queue.tail.prev
end

-- push a task (coroutine) onto the queue. The top coroutine will run everytime the courier is idle until it's done.
function PushCourierQueue(task)
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

local function QueryItemsNN(input)
	util.Debug("querying items NN")
	
	local me = GetBot()
	local request = string.format(":1414/query?type=item&hero=%s&team=%d&tensor=%s", me:GetUnitName(), GetTeam(), json.encode(input))

	CreateHTTPRequest(request):Send(function(result)
		if result.StatusCode == 0 then
			me.callback_err = "The dota2_nn server is either not running or otherwise cannot be connected to."
		elseif result.StatusCode == 200 then
			me.itemResult = json.decode(result.Body)
		elseif result.StatusCode == 404 then
			me.callback_err = "The dota2_nn server returned a 404 error when " .. me:GetUnitName() .. " attempted a move. This means that there is no training data available for it."
		else
			me.callback_err = "The dota2_nn server returned an unexpected " .. result.StatusCode .. " error. This either some other program is running on port 1414 or there's a serious bug."
		end

		util.Debug(result.StatusCode .. " on move NN request: " .. request)
	end)
end

function StartItemThink()
	-- query NN to buy items and apply upgrades
	util.Debug("building")

	local me = GetBot()
	local input = {}

	input[1] = DotaTime() / 3600
	input[2] = me:GetGold() / 10000

	local items

	if ability_data.items[unit:GetUnitName()] ~= nil then
		items = ability_data.items[unit:GetUnitName()][GetTeam()] or {}
	else
		items = {}
	end

	for i, item in ipairs(items) do
		slot = unit:FindItemSlot(item)

		if slot ~= -1 then
			newInput[i + 2] = 1.0
		else
			newInput[i + 2] = 0.0
		end
	end

	QueryItemsNN(input)

	me.itemTimer = 2000
end

function FinishItemThink()
	local me = GetBot()

	--local _, nextAbility = itemsResult:sub(1, #abilities):max(1)

	--me:ActionImmediate_LevelAbility(abilities[nextAbility])

	for nextItem, activation in ipairs(me.itemsResult) do
		if activation >= .5 then
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
	end
end