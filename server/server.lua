require "json"
require "nn"
require "paths"
require "torch"

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
			response.status(400)
			response.send("")
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

	response.setStatus(201)
	response.send(id)
end

local function GetMoveResult(params, response)
	pool:synchronize()

	local id = params.id

	local query = nn_queries[params.id]

	if query == nil then
		response.status(404)
		response.send("")
	elseif not query.done then
		response.status(202)
		response.send("")
	else
		if query.err_msg ~= nil or query.result == nil then
			response.status(500)
			response.send(query.err_msg)
			print(query.err_msg)
		else
			response.status(200)
			response.send(json.encode(torch.totable(query.result)))
		end

		nn_queries[params.id] = nil
	end
end

local app = require "waffle"

app.post("^/move$", function(request, response)
	if request.ip ~= "127.0.0.1" then
		response.status(403)
		response.send("")
		return
	end

	local ok, msg = pcall(AddMove, request.url.args, response)

	if not ok then
		response.status(500)
		response.send(msg)
	end
end)

app.post("^/move_result$", function(request, response)
	if request.ip ~= "127.0.0.1" then
		response.status(403)
		response.send("")
		return
	end

	local ok, msg = pcall(GetMoveResult, request.url.args, response)

	if not ok then
		response.status(500)
		response.send(msg)
	end
end)

app.listen { port = 1414 }
