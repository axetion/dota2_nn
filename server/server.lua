require "json"
require "nn"
require "paths"
require "torch"

local pegasus = require "pegasus"
local threads = require "threads"
local uuid = require "uuid"

local nns = {}
local nn_queries = {}
local pool = threads.Threads(8, function()
	require "torch"
	require "nn"
end)

uuid.seed()
pool:specific(false)

local function LoadNNs(hero)
	local path = "data/" .. hero .. "/nets/"

	if not paths.dirp(path) then
		return false
	end	

	for net in paths.iterfiles(path) do
		local parts = net:gmatch("[^_]+")

		local team = tonumber(parts())
		local type = parts()

		if nns[hero] == nil then
			nns[hero] = {nil, {}, {}}
		end

		nns[hero][team][type] = torch.load(path .. net, "ascii")
	end

	return true
end

local function AddMove(params, response)
	local hero = params.hero
	local team = tonumber(params.team)
	local input = torch.Tensor(json.decode(params.tensor))

	if nns[hero] == nil then
		if not LoadNNs(hero) then
			response:statusCode(404)
			response:write(hero .. " not found")
			return
		end
	end

	local net = nns[hero][team].move

	local id = uuid.new()

	nn_queries[id] = {
		done = false,
		result = nil,
		err_msg = nil,
	}

	pool:addjob(function() return pcall(net.forward, net, input) end, function(ok, result)
		if not ok then
			nn_queries[id].err_msg = result
		else
			nn_queries[id].result = result
		end

		nn_queries[id].done = true
	end)

	response:statusCode(201)
	response:write(id)
end

local function GetMoveResult(params, response)
	pool:synchronize()

	local id = params.id

	local query = nn_queries[params.id]

	if query == nil then
		response:writeDefaultErrorMessage(404)
	elseif not query.done then
		response:writeDefaultErrorMessage(202)
	else
		if query.err_msg ~= nil or query.result == nil then
			response:statusCode(500)
			response:write(query.err_msg)
			print(query.err_msg)
		else
			response:statusCode(200)
			response:write(json.encode(torch.totable(query.result)))
		end

		nn_queries[params.id] = nil
	end
end

local function ServerEntry(request, response)
	if request.ip ~= "127.0.0.1" then
		response:writeDefaultErrorMessage(403)
	elseif request:path() == "/move" then
		local ok, msg = pcall(AddMove, request:params(), response)

		if not ok then
			response:statusCode(500)
			response:write(msg)
		end
	elseif request:path() == "/move_result" then
		local ok, msg = pcall(GetMoveResult, request:params(), response) 

		if not ok then
			response:statusCode(500)
			response:write(msg)
		end
	else
		response:writeDefaultErrorMessage(410)
	end

	response:close()
end


local server = pegasus:new { port = 1414 }

server:start(ServerEntry)
