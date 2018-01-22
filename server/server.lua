require "json"
require "nn"
require "paths"
require "torch"

local models = {}

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

local function DoQuery(params, response)
	local hero = params.hero
	local type = params.type

	local team = tonumber(params.team)
	local input = torch.Tensor(json.decode(params.tensor))

	if nns[hero] == nil then
		if not LoadNNs(hero) then
			response.status(400)
			response.send("")
			return
		end
	end

	local net = nns[hero][team][type]

	ok, result = pcall(net.forward, net, input)

	if ok then
		result = json.encode(torch.totable(result))

		response.setStatus(200)
		response.send(result)
	else
		response.status(500)
		response.send(result)
		print(result)
	end
end


local app = require "waffle"

app.post("^/query$", function(request, response)
	if request.ip ~= "127.0.0.1" then
		response.status(403)
		response.send("")
		return
	end

	local ok, msg = pcall(DoQuery, request.url.args, response)

	if not ok then
		response.status(500)
		response.send(msg)
	end
end)

app.listen { port = 1414 }
